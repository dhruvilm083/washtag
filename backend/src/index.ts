// Washtag API proxy (Cloudflare Worker).
// The iPhone app talks to this Worker for anything that needs the AI model.
// The Gemini API key lives here as a Worker secret and never ships inside the app.
// Product (barcode) lookup happens in the app itself against free databases.
// The routes themselves are in api.ts, shared with the web app's Vercel function.

import { HttpError, json, route, type AIEnv } from "./api";

export interface Env extends AIEnv {
  APP_TOKEN: string;
  LIMITER?: { limit(opts: { key: string }): Promise<{ success: boolean }> };
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

      return json(await route(req.method, url.pathname, req, env));
    } catch (e) {
      if (e instanceof HttpError) return json({ error: { code: e.code, message: e.message } }, e.status);
      console.error(e);
      return json({ error: { code: "server", message: "Something went wrong." } }, 500);
    }
  },
};
