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
  Washtag/Services         API client, on-device barcode decoding, storage, load planner
  Washtag/Views            Scan, Index, This load, Household, care tag and symbols
backend/    Cloudflare Worker: holds the Anthropic + Barcode Lookup keys
  src/index.ts             /v1/label, /v1/digits, /v1/product, /v1/suggest
  src/prompts.ts           prompts (Claude Haiku 5.5, claude-haiku-5-5)
```

## Quick start

```bash
# server
cd backend && npm install && npx wrangler login
npx wrangler secret put ANTHROPIC_API_KEY
npx wrangler secret put BARCODE_LOOKUP_API_KEY
npx wrangler secret put APP_TOKEN
npx wrangler deploy

# app (on a Mac)
cd ../ios
cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig   # fill it in
brew install xcodegen && xcodegen generate && open Washtag.xcodeproj
```

Debug builds always use Google's test ads. Never tap your own live ads.
