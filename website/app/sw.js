// Washtag web app service worker: keeps the app itself available offline.
// Scans, lookups and suggestions need the network and are never cached.
// Bump VERSION whenever a file in SHELL changes.

const VERSION = "washtag-app-1";
const SHELL = [
  "/app/", "/app/app.css", "/app/manifest.webmanifest",
  "/app/js/app.js", "/app/js/api.js", "/app/js/appliances.js", "/app/js/barcode.js", "/app/js/config.js", "/app/js/gtin.js",
  "/app/js/image.js", "/app/js/lookup.js", "/app/js/planner.js", "/app/js/store.js", "/app/js/symbols.js",
  "/app/vendor/zxing.min.js", "/app/icons/icon-180.png", "/app/icons/icon-192.png", "/app/icons/icon-512.png",
];

self.addEventListener("install", (e) => {
  e.waitUntil(caches.open(VERSION).then((c) => c.addAll(SHELL)).then(() => self.skipWaiting()));
});

self.addEventListener("activate", (e) => {
  e.waitUntil(caches.keys().then((keys) => Promise.all(keys.filter((k) => k !== VERSION).map((k) => caches.delete(k)))).then(() => self.clients.claim()));
});

// App files: network first so updates land straight away, cache when offline.
self.addEventListener("fetch", (e) => {
  const url = new URL(e.request.url);
  if (e.request.method !== "GET" || url.origin !== location.origin || !url.pathname.startsWith("/app/")) return;
  e.respondWith(
    fetch(e.request)
      .then((res) => {
        if (res.ok) { const copy = res.clone(); caches.open(VERSION).then((c) => c.put(e.request, copy)); }
        return res;
      })
      .catch(() => caches.match(e.request, { ignoreSearch: true }).then((hit) => hit || caches.match("/app/")))
  );
});
