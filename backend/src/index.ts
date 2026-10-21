// Washtag API proxy (Cloudflare Worker).
// The iPhone app talks only to this Worker. The Anthropic and Barcode Lookup
// keys live here as Worker secrets and never ship inside the app.

import Anthropic from "@anthropic-ai/sdk";
import { DIGITS_PROMPT, LABEL_PROMPT, enrichPrompt, suggestPrompt } from "./prompts";

export interface Env {
  ANTHROPIC_API_KEY: string;
  BARCODE_LOOKUP_API_KEY: string;
  APP_TOKEN: string;
  LIMITER?: { limit(opts: { key: string }): Promise<{ success: boolean }> };
}

const MODEL = "claude-haiku-5-5";
const MAX_IMAGE_B64 = 6_000_000; // about 4.5 MB of JPEG; the app sends ~1800px images well under this

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

      const anthropic = new Anthropic({ apiKey: env.ANTHROPIC_API_KEY });

      if (req.method === "POST" && url.pathname === "/v1/label") {
        const { image } = await body<{ image: string }>(req);
        return json(await askWithImage(anthropic, checkImage(image), LABEL_PROMPT, 6000));
      }
      if (req.method === "POST" && url.pathname === "/v1/digits") {
        const { image } = await body<{ image: string }>(req);
        return json(await askWithImage(anthropic, checkImage(image), DIGITS_PROMPT, 1000));
      }
      if (req.method === "GET" && url.pathname === "/v1/product") {
        const code = (url.searchParams.get("code") || "").replace(/\D/g, "");
        if (!code) throw new HttpError(400, "bad_request", "Pass ?code= with the barcode digits.");
        return json(await lookupProduct(anthropic, env, code, url.searchParams.get("context")));
      }
      if (req.method === "POST" && url.pathname === "/v1/suggest") {
        const b = await body<{ structured?: unknown; needs?: string[]; fibres?: string | null; type?: string | null }>(req);
        const prompt = suggestPrompt(b.structured, (b.needs || []).slice(0, 12), b.fibres ?? null, b.type ?? null);
        return json(await askText(anthropic, prompt, 3000));
      }
      throw new HttpError(404, "not_found", "No such endpoint.");
    } catch (e) {
      if (e instanceof HttpError) return json({ error: { code: e.code, message: e.message } }, e.status);
      if (e instanceof Anthropic.RateLimitError) return json({ error: { code: "rate_limited", message: "The reader is busy. Try again shortly." } }, 429);
      if (e instanceof Anthropic.BadRequestError) return json({ error: { code: "image_rejected", message: "That photo couldn't be read. Try a JPEG under 5 MB." } }, 400);
      if (e instanceof Anthropic.APIError) return json({ error: { code: "upstream", message: "The reader had a problem. Try again." } }, 502);
      console.error(e);
      return json({ error: { code: "server", message: "Something went wrong." } }, 500);
    }
  },
};

/* ---------- Claude calls ---------- */

async function askWithImage(client: Anthropic, imageB64: string, prompt: string, maxTokens: number) {
  const msg = await client.messages.create({
    model: MODEL,
    max_tokens: maxTokens,
    output_config: { effort: "low" },
    messages: [
      {
        role: "user",
        content: [
          { type: "image", source: { type: "base64", media_type: "image/jpeg", data: imageB64 } },
          { type: "text", text: prompt },
        ],
      },
    ],
  });
  return parseJsonReply(msg);
}

async function askText(client: Anthropic, prompt: string, maxTokens: number) {
  const msg = await client.messages.create({
    model: MODEL,
    max_tokens: maxTokens,
    output_config: { effort: "low" },
    messages: [{ role: "user", content: prompt }],
  });
  return parseJsonReply(msg);
}

function parseJsonReply(msg: Anthropic.Message): unknown {
  if (msg.stop_reason === "refusal") throw new HttpError(422, "refused", "Couldn't read that image. Try a clearer photo of just the label.");
  const text = msg.content.flatMap((b) => (b.type === "text" ? [b.text] : [])).join("");
  const start = text.indexOf("{");
  const end = text.lastIndexOf("}");
  if (start < 0 || end <= start) throw new HttpError(502, "invalid_json", "The answer came back garbled. Try again.");
  try {
    return JSON.parse(text.slice(start, end + 1));
  } catch {
    throw new HttpError(502, "invalid_json", "The answer came back garbled. Try again.");
  }
}

/* ---------- Barcode Lookup ---------- */

type BLStore = { name?: string; country?: string; currency_symbol?: string; price?: string; link?: string };
type BLProduct = {
  barcode_number?: string; title?: string; brand?: string; manufacturer?: string; category?: string;
  description?: string; color?: string; material?: string; size?: string; images?: string[]; stores?: BLStore[];
};

async function lookupProduct(client: Anthropic, env: Env, code: string, context: string | null) {
  const blUrl = `https://api.barcodelookup.com/v3/products?barcode=${encodeURIComponent(code)}&formatted=y&key=${encodeURIComponent(env.BARCODE_LOOKUP_API_KEY)}`;
  const res = await fetch(blUrl, { headers: { accept: "application/json" } });

  if (res.status === 404) return notFound(code, "Barcode Lookup has no record of this code.");
  if (res.status === 403 || res.status === 401) throw new HttpError(502, "lookup_key", "Product lookup isn't set up correctly (Barcode Lookup key).");
  if (res.status === 429) throw new HttpError(429, "rate_limited", "Product lookup limit reached. Try again later.");
  if (!res.ok) throw new HttpError(502, "upstream", `Product lookup failed (${res.status}).`);

  const data = (await res.json()) as { products?: BLProduct[] };
  const p = data.products?.[0];
  if (!p || !p.title) return notFound(code, "Barcode Lookup returned no product for this code.");

  const record = {
    title: p.title, brand: p.brand || null, manufacturer: p.manufacturer || null, category: p.category || null,
    description: (p.description || "").slice(0, 1200) || null, color: p.color || null, material: p.material || null, size: p.size || null,
  };

  let enrich: { category?: string; careNotes?: string[]; detergentUse?: { isLaundryProduct?: boolean; typicalDoseNote?: string | null } } = {};
  try {
    enrich = (await askText(client, enrichPrompt(record, context), 1500)) as typeof enrich;
  } catch {
    // Care notes are optional; the catalogue data is still useful on its own.
  }

  const exact = (p.barcode_number || "").replace(/\D/g, "") === code;
  return {
    found: true,
    source: "barcodelookup",
    confidence: exact ? 95 : 75,
    basis: exact ? "Exact barcode match in the Barcode Lookup database" : "Close match in the Barcode Lookup database",
    brand: record.brand,
    manufacturer: record.manufacturer,
    productName: record.title,
    category: enrich.category || record.category,
    rawCategory: record.category,
    description: record.description,
    material: record.material,
    color: record.color,
    imageURL: p.images?.[0] || null,
    stores: (p.stores || []).slice(0, 5).map((s) => ({
      name: s.name || "Store", country: s.country || null,
      price: s.price ? `${s.currency_symbol || ""}${s.price}` : null, link: s.link || null,
    })),
    gs1Region: gs1Region(code),
    careNotes: enrich.careNotes || [],
    detergentUse: enrich.detergentUse || { isLaundryProduct: false, typicalDoseNote: null },
  };
}

function notFound(code: string, basis: string) {
  const region = gs1Region(code);
  return { found: false, source: "barcodelookup", confidence: 0, basis, gs1Region: region, careNotes: [], stores: [] };
}

// Rough GS1 prefix → registration region. Prefix says where the company
// registered its barcodes, not where the product was made.
function gs1Region(code: string): string | null {
  const c = code.length === 12 ? "0" + code : code;
  if (c.length !== 13) return null;
  const p = parseInt(c.slice(0, 3), 10);
  const ranges: [number, number, string][] = [
    [0, 19, "USA / Canada"], [30, 39, "USA (restricted)"], [60, 139, "USA / Canada"], [300, 379, "France"], [380, 380, "Bulgaria"],
    [400, 440, "Germany"], [450, 459, "Japan"], [460, 469, "Russia"], [471, 471, "Taiwan"], [480, 480, "Philippines"], [489, 489, "Hong Kong"],
    [490, 499, "Japan"], [500, 509, "United Kingdom"], [520, 521, "Greece"], [540, 549, "Belgium / Luxembourg"], [560, 560, "Portugal"],
    [570, 579, "Denmark"], [590, 590, "Poland"], [600, 601, "South Africa"], [640, 649, "Finland"], [690, 699, "China"], [700, 709, "Norway"],
    [729, 729, "Israel"], [730, 739, "Sweden"], [750, 750, "Mexico"], [760, 769, "Switzerland"], [779, 779, "Argentina"], [789, 790, "Brazil"],
    [800, 839, "Italy"], [840, 849, "Spain"], [858, 858, "Slovakia"], [859, 859, "Czechia"], [868, 869, "Turkey"], [870, 879, "Netherlands"],
    [880, 880, "South Korea"], [885, 885, "Thailand"], [888, 888, "Singapore"], [890, 890, "India"], [893, 893, "Vietnam"], [899, 899, "Indonesia"],
    [900, 919, "Austria"], [930, 939, "Australia"], [940, 949, "New Zealand"], [955, 955, "Malaysia"],
  ];
  return ranges.find(([a, b]) => p >= a && p <= b)?.[2] ?? null;
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
