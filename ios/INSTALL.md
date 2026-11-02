# Install Washtag on your iPhone (free, no Apple Developer Program)

A free Apple ID ("Personal Team") can install Washtag on your own iPhone from Xcode.
The build stops opening after 7 days; plug the phone in and press Run again to renew it.
Debug builds always show Google's test ads.

## One-time setup on the Mac

1. Install **Xcode** from the Mac App Store and open it once so it finishes installing its parts.
2. Xcode → Settings → Accounts → **+** → Apple ID, and sign in. That gives you a Personal Team.
3. Install Homebrew from https://brew.sh, then in Terminal: `brew install xcodegen`
4. Get the code: `git clone https://github.com/dhruvilm083/washtag.git && cd washtag/ios`

## Point the app at its server

The app reads labels through the website's API on Vercel (the same one the web app uses).

1. Make up a random token, letters and numbers only (no `/`), e.g. from `openssl rand -hex 24`.
2. In Vercel → washtag project → Settings → Environment Variables, add `APP_TOKEN` with that value, then redeploy.
3. In Terminal, in `washtag/ios`: `cp Config/Secrets.example.xcconfig Config/Secrets.xcconfig`, then open
   `Config/Secrets.xcconfig` and set:
   - `WASHTAG_BUNDLE_ID` to something unique to you, e.g. `com.dhru.washtag`
   - `WASHTAG_APP_TOKEN` to the same token
   - leave `WASHTAG_API_BASE` and `WASHTAG_PRIVACY_URL` as they are

`Secrets.xcconfig` is git-ignored, so the token never goes to GitHub.

## Build and install

1. `xcodegen generate && open Washtag.xcodeproj`
2. Click **Washtag** at the top of the file list → **Signing & Capabilities** → tick *Automatically manage signing*
   and pick your Personal Team.
3. On the iPhone: Settings → Privacy & Security → **Developer Mode** → on (the phone restarts).
4. Plug the iPhone in with a cable, tap **Trust** on the phone, pick it as the run destination at the top of Xcode,
   and press **Run** (▶). The first build downloads Google's ad packages and takes a few minutes.
5. The first time, the phone says the developer isn't trusted: Settings → General → VPN & Device Management →
   your Apple ID → **Trust**. Then open Washtag.

## Every 7 days

Plug in, open `Washtag.xcodeproj`, press Run. Your saved index stays.

## If the build fails

Copy the first red error from Xcode's Issue navigator (⌘5) into the Washtag thread.
