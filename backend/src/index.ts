// Washtag API proxy (Cloudflare Worker).
// The iPhone app talks to this Worker for anything that needs the AI model.
// The Gemini API key lives here as a Worker secret and never ships inside the app.
// Product (barcode) lookup happens in the app itself against free databases.

import { DIGITS_PROMPT, LABEL_PROMPT, enrichPrompt, suggestPrompt } from "./prompts";

export interface Env {
  GEMINI_API_KEY: string;
  APP_TOKEN: string;
  GEMINI_MODEL?: string;
  LIMITER?: { limit(opts: { key: string }): Promise<{ success: boolean }> };
}

// Free-tier Gemini model that accepts images. Override with the GEMINI_MODEL variable
// (e.g. "gemini-3.5-flash-lite" if you hit the daily free limit).
const DEFAULT_MODEL = "gemini-3.8-flash";
const MAX_IMAGE_B64 = 6_000_000;

class HttpError extends Error {
  constructor(public status: number, public code: string, message: string) {
    super(message);
  }
}

export default {
  async fetch(req: Request, env: Env): Promise<Response> {
    try {
      const url = new URL(req.url);
      if (url.pathname === "/health") return json({ ok: true });

      if (!env.APP_TOKEN || req.headers.get("x-washtag-token") !== env.APP_TOKEN) {
        throw new HttpError(401, "unauthorized", "Missing or wrong app token.");
      }
      if (env.LIMITER) {
        const key = req.headers.get("x-washtag-install") || req.headers.get("cf-connecting-ip") || "anon";
        const { success } = await env.LIMITER.limit({ key });
        if (!success) throw new HttpError(429, "rate_limited", "Too many requests. Wait a moment and try again.");
      }

      if (req.method === "POST" && url.pathname === "/v1/label") {
        const { image } = await body<{ image: string }>(req);
        return json(await gemini(env, LABEL_PROMPT, checkImage(image), 6000));
      }
      if (req.method === "POST" && url.pathname === "/v1/digits") {
        const { image } = await body<{ image: string }>(req);
        return json(await gemini(env, DIGITS_PROMPT, checkImage(image), 500));
      }
      if (req.method === "POST" && url.pathname === "/v1/enrich") {
        const b = await body<{ product?: Record<string, unknown>; context?: string | null }>(req);
        if (!b.product || typeof b.product !== "object") throw new HttpError(400, "bad_request", "Send the product record as \"product\".");
        return json(await gemini(env, enrichPrompt(b.product, b.context ? String(b.context).slice(0, 300) : null), null, 1500));
      }
      if (req.method === "POST" && url.pathname === "/v1/suggest") {
        const b = await body<{ structured?: unknown; needs?: string[]; fibres?: string | null; type?: string | null }>(req);
        const prompt = suggestPrompt(b.structured, (b.needs || []).slice(0, 12), b.fibres ?? null, b.type ?? null);
        return json(await gemini(env, prompt, null, 3000));
      }
      throw new HttpError(404, "not_found", "No such endpoint.");
    } catch (e) {
      if (e instanceof HttpError) return json({ error: { code: e.code, message: e.message } }, e.status);
      console.error(e);
      return json({ error: { code: "server", message: "Something went wrong." } }, 500);
    }
  },
};

/* ---------- Gemini ---------- */

type GeminiResponse = {
  candidates?: { content?: { parts?: { text?: string; thought?: boolean }[] }; finishReason?: string }[];
  promptFeedback?: { blockReason?: string };
};

async function gemini(env: Env, prompt: string, imageB64: string | null, maxTokens: number): Promise<unknown> {
  const model = env.GEMINI_MODEL || DEFAULT_MODEL;
  const parts: Record<string, unknown>[] = [];
  if (imageB64) parts.push({ inline_data: { mime_type: "image/jpeg", data: imageB64 } });
  parts.push({ text: prompt });

  const res = await fetch(`https://generativelanguage.googleapis.com/v1beta/models/${encodeURIComponent(model)}:generateContent`, {
    method: "POST",
    headers: { "content-type": "application/json", "x-goog-api-key": env.GEMINI_API_KEY },
    body: JSON.stringify({
      contents: [{ role: "user", parts }],
      generationConfig: { responseMimeType: "application/json", maxOutputTokens: maxTokens, temperature: 0.2 },
    }),
  });

  if (res.status === 429) throw new HttpError(429, "rate_limited", "The free AI limit was reached. Try again in a minute, or tomorrow if the daily limit is used up.");
  if (res.status === 400) throw new HttpError(400, "image_rejected", "That photo couldn't be read. Try a JPEG under 5 MB.");
  if (res.status === 401 || res.status === 403) throw new HttpError(502, "ai_key", "The AI isn't set up correctly (Gemini key).");
  if (!res.ok) throw new HttpError(502, "upstream", `The reader had a problem (${res.status}). Try again.`);

  const data = (await res.json()) as GeminiResponse;
  if (data.promptFeedback?.blockReason) throw new HttpError(422, "refused", "Couldn't read that image. Try a clearer photo of just the label.");
  const text = (data.candidates?.[0]?.content?.parts || []).filter((p) => !p.thought).map((p) => p.text || "").join("");
  return parseJson(text);
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

function json(data: unknown, status = 200): Response {
  return new Response(JSON.stringify(data), { status, headers: { "content-type": "application/json" } });
}
