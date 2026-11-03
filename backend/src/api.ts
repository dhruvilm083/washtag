// The Washtag API routes, shared by the Cloudflare Worker (index.ts, for the iPhone app)
// and the Vercel function (api/washtag.ts, for the web app). Each host does its own
// auth and rate limiting, then hands the request here.

import { DIGITS_PROMPT, LABEL_PROMPT, appliancePrompt, enrichPrompt, suggestPrompt, webSearchPrompt } from "./prompts";

export interface AIEnv {
  GEMINI_API_KEY: string;
  GEMINI_MODEL?: string;
}

// Free-tier Gemini model that accepts images. Override with the GEMINI_MODEL variable
// (e.g. "gemini-3.5-flash-lite" if you hit the daily free limit).
const DEFAULT_MODEL = "gemini-3.8-flash";
const MAX_IMAGE_B64 = 6_000_000;

export class HttpError extends Error {
  constructor(public status: number, public code: string, message: string) {
    super(message);
  }
}

/** Runs one endpoint ("/v1/label" etc.) and returns its JSON answer. */
export async function route(method: string, path: string, req: Request, env: AIEnv): Promise<unknown> {
  if (method !== "POST") throw new HttpError(404, "not_found", "No such endpoint.");
  switch (path) {
    case "/v1/label": {
      const { image } = await body<{ image: string }>(req);
      return gemini(env, LABEL_PROMPT, checkImage(image), 6000);
    }
    case "/v1/digits": {
      const { image } = await body<{ image: string }>(req);
      return gemini(env, DIGITS_PROMPT, checkImage(image), 500);
    }
    case "/v1/enrich": {
      const b = await body<{ product?: Record<string, unknown>; context?: string | null }>(req);
      if (!b.product || typeof b.product !== "object") throw new HttpError(400, "bad_request", "Send the product record as \"product\".");
      return gemini(env, enrichPrompt(b.product, b.context ? String(b.context).slice(0, 300) : null), null, 1500);
    }
    case "/v1/suggest": {
      const b = await body<{ structured?: unknown; needs?: string[]; fibres?: string | null; type?: string | null }>(req);
      const prompt = suggestPrompt(b.structured, (b.needs || []).slice(0, 12), b.fibres ?? null, b.type ?? null);
      return gemini(env, prompt, null, 3000);
    }
    case "/v1/appliance": {
      const b = await body<{ kind?: string; brand?: string; model?: string }>(req);
      if (b.kind !== "washer" && b.kind !== "dryer") throw new HttpError(400, "bad_request", "\"kind\" must be washer or dryer.");
      const brand = String(b.brand ?? "").trim().slice(0, 60);
      const model = String(b.model ?? "").trim().slice(0, 60);
      if (!brand && !model) throw new HttpError(400, "bad_request", "Send a brand or model number.");
      return gemini(env, appliancePrompt(b.kind, brand, model), null, 2000);
    }
    case "/v1/websearch": {
      // A number seen on a tag or package that no free barcode database knows: ask Gemini
      // to search the web for it (Google Search grounding, included in the free tier).
      const b = await body<{ code?: string; hint?: string | null }>(req);
      // A barcode or item number, or a brand and product name read off packaging.
      const code = String(b.code ?? "").replace(/[^\p{L}\p{N} .&'/-]/gu, "").replace(/\s+/g, " ").trim().slice(0, 80);
      if (code.length < 3) throw new HttpError(400, "bad_request", "Send the number or name as \"code\".");
      const hint = b.hint ? String(b.hint).slice(0, 200) : null;
      return webSearch(env, code, hint);
    }
  }
  throw new HttpError(404, "not_found", "No such endpoint.");
}

/* ---------- Gemini ---------- */

type GeminiResponse = {
  candidates?: {
    content?: { parts?: { text?: string; thought?: boolean }[] };
    finishReason?: string;
    groundingMetadata?: { groundingChunks?: { web?: { uri?: string; title?: string } }[] };
  }[];
  promptFeedback?: { blockReason?: string };
};

async function gemini(env: AIEnv, prompt: string, imageB64: string | null, maxTokens: number): Promise<unknown> {
  const data = await callGemini(env, prompt, imageB64, maxTokens, false);
  return parseJson(answerText(data));
}

async function webSearch(env: AIEnv, code: string, hint: string | null): Promise<unknown> {
  const data = await callGemini(env, webSearchPrompt(code, hint), null, 2500, true);
  let answer: Record<string, unknown>;
  try {
    answer = parseJson(answerText(data)) as Record<string, unknown>;
  } catch {
    answer = { found: false, confidence: 0, basis: "The web search didn't give a clear answer." };
  }
  const seen = new Set<string>();
  const sources: { title: string; url: string }[] = [];
  for (const c of data.candidates?.[0]?.groundingMetadata?.groundingChunks || []) {
    const url = c.web?.uri;
    if (!url || seen.has(url) || sources.length >= 5) continue;
    seen.add(url);
    sources.push({ title: c.web?.title || "Source", url });
  }
  return { ...answer, sources };
}

function answerText(data: GeminiResponse): string {
  return (data.candidates?.[0]?.content?.parts || []).filter((p) => !p.thought).map((p) => p.text || "").join("");
}

async function callGemini(env: AIEnv, prompt: string, imageB64: string | null, maxTokens: number, search: boolean): Promise<GeminiResponse> {
  if (!env.GEMINI_API_KEY) throw new HttpError(503, "ai_key", "The AI isn't set up yet (no Gemini key on the server).");
  const model = env.GEMINI_MODEL || DEFAULT_MODEL;
  const parts: Record<string, unknown>[] = [];
  if (imageB64) parts.push({ inline_data: { mime_type: "image/jpeg", data: imageB64 } });
  parts.push({ text: prompt });

  const res = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`, {
    method: "POST",
    headers: { "content-type": "application/json", "x-goog-api-key": env.GEMINI_API_KEY },
    // JSON mode can't be combined with the search tool, so search answers are parsed from plain text.
    body: JSON.stringify(
      search
        ? { contents: [{ role: "user", parts }], tools: [{ google_search: {} }], generationConfig: { maxOutputTokens: maxTokens, temperature: 0 } }
        : { contents: [{ role: "user", parts }], generationConfig: { responseMimeType: "application/json", maxOutputTokens: maxTokens, temperature: 0 } },
    ),
  });

  if (res.status === 429) throw new HttpError(429, "rate_limited", "The free AI limit was reached. Try again in a minute, or tomorrow if the daily limit is used up.");
  if (res.status === 400 && search) throw new HttpError(502, "search_unavailable", "Web search isn't available right now.");
  if (res.status === 400) throw new HttpError(400, "image_rejected", "That photo couldn't be read. Try a JPEG under 5 MB.");
  if (res.status === 401 || res.status === 403) throw new HttpError(502, "ai_key", "The AI isn't set up correctly (Gemini key).");
  if (!res.ok) throw new HttpError(502, "upstream", `The reader had a problem (${res.status}). Try again.`);

  const data = (await res.json()) as GeminiResponse;
  if (data.promptFeedback?.blockReason) throw new HttpError(422, "refused", "Couldn't read that image. Try a clearer photo of just the label.");
  return data;
}

function parseJson(text: string): unknown {
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start < 0 || end <= start) throw new HttpError(502, "invalid_json", "The answer came back garbled. Try again.");
  try {
    return JSON.parse(text.slice(start, end + 1));
  } catch {
    throw new HttpError(502, "invalid_json", "The answer came back garbled. Try again.");
  }
}

/* ---------- helpers ---------- */

function checkImage(image: unknown): string {
  if (typeof image !== "string" || image.length < 100) throw new HttpError(400, "bad_request", "Send the photo as base64 JPEG in \"image\".");
  if (image.length > MAX_IMAGE_B64) throw new HttpError(413, "too_large", "That photo is too large.");
  return image.replace(/^data:image\/\w+;base64,/, "");
}

async function body<T>(req: Request): Promise<T> {
  try {
    return (await req.json()) as T;
  } catch {
    throw new HttpError(400, "bad_request", "Body must be JSON.");
  }
}

export function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json" } });
}
