# Washtag website

A single static page (`index.html`) showcasing the Washtag iPhone app. No build step: open it in a browser or host the folder on any static host (GitHub Pages, Cloudflare Pages).

The phone screens are drawn in HTML/CSS from the app's SwiftUI layout with example items, not real device screenshots.

The app isn't on the App Store yet, so every App Store button points at a placeholder listing (`id0000000000`) and shows a "listing not found" notice when clicked. When the app is live, set `STORE_URL` in the script at the bottom of `index.html` to the real listing and remove the click handler and the `#store-err` notice.
