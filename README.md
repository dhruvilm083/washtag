# Washtag (iPhone)

Reads laundry care labels and product barcodes, turns them into clear Wash / Dry / Care / Do-not
instructions, keeps a saved index labelled by household member, and plans "this load" with detergent amounts.

Full setup and launch guide: https://claude.ai/artifact/PNTGd9fqvLXMViJamzoJN3

## Layout

```
ios/        SwiftUI app (iOS 17+), generated into an Xcode project with XcodeGen
  project.yml              project spec (Google Mobile Ads 13.11, UMP 3.1 via Swift Package Manager)
  Config/                  Debug/Release xcconfig; copy Secrets.example.xcconfig -> Secrets.xcconfig
  Washtag/App              app entry and tab bar
  Washtag/Ads              consent, tracking prompt, App Open launch ad
  Washtag/Models           data types (match the backend JSON)
  Washtag/Services         API client, free product lookup (UPCitemdb + Open Facts), on-device
                           barcode decoding, storage, load planner, laundry sorter (loads + order)
  Washtag/Views            Scan, Index, This load, Household, care tag and symbols
backend/    Cloudflare Worker: holds the Gemini API key (free tier)
  src/index.ts             /v1/label, /v1/digits, /v1/enrich, /v1/suggest, /v1/appliance
  src/prompts.ts           prompts (Gemini, default model gemini-3.8-flash)
```

## Quick start

```bash
# server
cd backend && npm install && npx wrangler login
npx wrangler secret put GEMINI_API_KEY      # free key from aistudio.google.com
npx wrangler secret put APP_TOKEN
npx wrangler deploy

# app (on a Mac)
cd ../ios
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig   # fill it in
brew install xcodegen && xcodegen generate && open Washtag.xcodeproj
```

Everything here runs on free tiers: Gemini API free tier, UPCitemdb free lookups (100 a day),
Open Products/Beauty/Food Facts, Cloudflare Workers free plan, and a free Apple ID ("Personal Team")
for installing on your own iPhone. A free Personal Team build stops opening after 7 days; rebuild
from Xcode to renew it. Publishing to the App Store needs the paid Apple Developer Program.

Debug builds always use Google's test ads. Never tap your own live ads.
