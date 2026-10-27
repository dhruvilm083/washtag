# Washtag website

A single static page (`index.html`) showcasing the Washtag iPhone app. No build step: open it in a browser or host the folder on any static host (GitHub Pages, Cloudflare Pages).

Light and dark themes follow the visitor's device setting; the round button in the header switches between them and remembers the choice.

The phone screens are drawn in HTML/CSS from the app's SwiftUI layout with example items, not real device screenshots.

The app isn't on the App Store yet, so every App Store button points at a placeholder listing (`id0000000000`) and shows a "listing not found" notice when clicked. When the app is live, set `STORE_URL` in the script at the bottom of `index.html` to the real listing and remove the click handler and the `#store-err` notice.

## Deploying on Vercel

`vercel.json` at the repo root tells Vercel to serve this folder as-is, with no build step.

1. Sign in at vercel.com with GitHub and choose **Add New → Project**.
2. Import `dhruvilm083/washtag` and keep the defaults (Framework Preset: Other). Deploy.
3. The site goes live at `https://<project-name>.vercel.app`, and every push to `main` redeploys it.

## Web app (`app/`)

`/app/` is Washtag as an installable web app (PWA), so people can use it on any phone without the App Store. It has the same Scan, Index, This load and Household screens as the iPhone app, saves everything in the browser, and works offline apart from scanning. In Safari: Share → Add to Home Screen.

- The AI calls go to `/api/washtag` (`api/washtag.ts` at the repo root, a Vercel Edge Function that reuses the Worker's routes in `backend/src/api.ts`). Set **`GEMINI_API_KEY`** in Vercel → Project → Settings → Environment Variables (optional: `GEMINI_MODEL`), then redeploy.
- Barcodes are decoded on the device (BarcodeDetector, or the bundled ZXing in `app/vendor/`, Apache-2.0). Product lookup uses UPCitemdb and Open Facts straight from the browser, relayed through `/api/washtag` if the browser blocks it.
- Ads: fill in `ADSENSE` in `app/js/config.js` once AdSense approves the site.
- After changing app files, bump `VERSION` in `app/sw.js`.
