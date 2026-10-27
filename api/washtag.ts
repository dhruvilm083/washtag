// Washtag web app API (Vercel Edge Function), served from the same site as the web app.
// It holds the Gemini key as the GEMINI_API_KEY environment variable in Vercel and reuses
// the Worker's routes from backend/src/api.ts. It also relays barcode-database lookups
// for browsers that the databases won't answer directly.
//
//   POST /api/washtag?op=label|digits|enrich|suggest|appliance
//   GET  /api/washtag?op=product&src=upcitemdb|opf|obf|off&code=...
//   GET  /api/washtag?op=health

import { HttpError, json, route } from "../backend/src/api";

export const config = { runtime: "edge" };

declare const process: { env: Record<string, string | undefined> };

const AI_OPS = new Set(["label", "digits", "enrich", "suggest", "appliance"]);
const PRODUCT_SOURCES: Record<string, (code: string) => string> = {
  upcitemdb: (c) => `https://api.upcitemdb.com/prod/trial/lookup?upc=${c}`,
  opf: (c) => `https://world.openproductsfacts.org/api/v2/product/${c}.json?fields=${OFF_FIELDS}`,
  obf: (c) => `https://world.openbeautyfacts.org/api/v2/product/${c}.json?fields=${OFF_FIELDS}`,
  off: (c) => `https://world.openfoodfacts.org/api/v2/product/${c}.json?fields=${OFF_FIELDS}`,
};
const OFF_FIELDS = "product_name,generic_name,brands,categories,image_url,image_front_url,quantity";

export default async function handler(req: Request): Promise<Response> {
  const url = new URL(req.url);
  const op = url.searchParams.get("op") || "";
  try {
    if (op === "health") return json({ ok: true, ai: Boolean(process.env.GEMINI_API_KEY) });
    checkSameSite(req, url);

    if (op === "product" && req.method === "GET") {
      const make = PRODUCT_SOURCES[url.searchParams.get("src") || ""];
      const code = (url.searchParams.get("code") || "").replace(/\D/g, "");
      if (!make || code.length < 6 || code.length > 14) throw new HttpError(400, "bad_request", "Send a source and a 6–14 digit code.");
      const res = await fetch(make(code), { headers: { accept: "application/json", "user-agent": "Washtag-Web/1.0 (washtag-green.vercel.app)" } });
      return new Response(await res.text(), { status: res.status, headers: { "content-type": "application/json" } });
    }

    if (AI_OPS.has(op)) {
      const env = { GEMINI_API_KEY: process.env.GEMINI_API_KEY || "", GEMINI_MODEL: process.env.GEMINI_MODEL };
      return json(await route(req.method, `/v1/${op}`, req, env));
    }
    throw new HttpError(404, "not_found", "No such endpoint.");
  } catch (e) {
    if (e instanceof HttpError) return json({ error: { code: e.code, message: e.message } }, e.status);
    console.error(e);
    return json({ error: { code: "server", message: "Something went wrong." } }, 500);
  }
}

/** Only the Washtag web app's own pages may call this (browsers send these headers; scripts elsewhere are refused). */
function checkSameSite(req: Request, url: URL) {
  const origin = req.headers.get("origin");
  const site = req.headers.get("sec-fetch-site");
  if (origin && hostOf(origin) !== url.host) throw new HttpError(403, "forbidden", "Not allowed from this site.");
  if (site && site !== "same-origin") throw new HttpError(403, "forbidden", "Not allowed from this site.");
  if (!origin && !site) throw new HttpError(403, "forbidden", "Open Washtag in a browser.");
}

function hostOf(origin: string): string {
  try {
    return new URL(origin).host;
  } catch {
    return "";
  }
}
