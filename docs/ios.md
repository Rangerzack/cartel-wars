# iOS app

The App Store build is the web app inside a native shell ([Capacitor 8](https://capacitorjs.com)).
`web/ios/` is a normal Xcode project. Its `App/App/public/` folder holds a copy of `web/dist`,
built with `BASE_PATH=/` and copied in by `npx cap sync ios`. That folder is not committed; every build
regenerates it. Native plugins: App, Browser, Haptics, Keyboard, Splash Screen and Status Bar, pulled in
with Swift Package Manager (no CocoaPods).

## How a build gets to TestFlight

`.github/workflows/ios.yml` runs on GitHub's macOS runner (Xcode 26). You don't need a Mac.

1. `npm ci && npm run build:ios` in `web/`: Vite build with the live Supabase URL and key (the same ones as
   `pages.yml`), then `cap sync ios`.
2. `xcodebuild -resolvePackageDependencies` fetches Capacitor's Swift packages.
3. `bundle exec fastlane ios beta` in `web/ios/App` (see `fastlane/Fastfile`):
   - logs in to App Store Connect with the API key;
   - `match` downloads the distribution certificate and App Store profile from the private certs repo.
     On the very first run it creates them with the API key and saves them there, encrypted;
   - sets the build number to the workflow's run number, builds, signs, and uploads to TestFlight.

Start it from **Actions → iOS to TestFlight → Run workflow**, or push a tag like `ios-v1.0.0`. Apple
takes 5–30 minutes to process the build, then it shows up in TestFlight.

## Secrets

The comment at the top of `ios.yml` has the step-by-step version. In short:

| Secret | What it is | Where it comes from |
|---|---|---|
| `ASC_KEY_ID` | App Store Connect API key ID | App Store Connect → Users and Access → Integrations → App Store Connect API → Team Keys → "+" (access: Admin) |
| `ASC_ISSUER_ID` | Your team's issuer ID | The same page, above the key list |
| `ASC_KEY_P8` | The key file, base64 on one line | The `AuthKey_XXXX.p8` download (Apple offers it once) |
| `MATCH_GIT_URL` | Where the signing files live | A new, empty, **private** GitHub repo, e.g. `https://github.com/Rangerzack/cartel-wars-certs.git` |
| `MATCH_GIT_AUTH` | Access to that repo | A fine-grained token for that repo only (Contents: Read and write), stored as base64 of `username:token` |
| `MATCH_PASSWORD` | Encrypts the files in that repo | A passphrase you make up. Keep a copy. |

Before the first run, register the bundle ID `io.rangelab.cartelwars` (developer.apple.com → Identifiers)
and create the app in App Store Connect (Apps → "+" → New App). The API key can't create the app record.

## Versions

- **Version** (what players see, e.g. 1.0.0): `MARKETING_VERSION` in `web/ios/App/App.xcodeproj/project.pbxproj`.
  It appears twice (Debug and Release); change both. Bump it for every App Store release: the last number
  for fixes (1.0.1), the middle one for new features (1.1.0). Then tag the commit `ios-v1.0.1` to build it.
- **Build number**: the workflow's run number, set at build time. Don't edit it. Don't rename `ios.yml`
  either: that restarts the run count, and App Store Connect rejects a build number it has already seen.

## Running it on a Mac (optional)

```sh
cd web
cp .env.example .env              # fill in the Supabase URL and anon key from pages.yml
npm ci
npm run build:ios                 # BASE_PATH=/ vite build, then cap sync ios
npx cap open ios                  # opens Xcode
```

In Xcode, pick your team under App → Signing & Capabilities (automatic signing), then run on a simulator
or a plugged-in iPhone. After changing web code, run `npm run build:ios` again.

## Native settings

- `web/capacitor.config.ts`: app ID, name, splash, status bar and keyboard settings. Run `npm run build:ios`
  after changing it.
- `web/ios/App/App/Info.plist`: portrait only, display name, `ITSAppUsesNonExemptEncryption = NO` (the app
  only uses HTTPS, so TestFlight skips the export-compliance question).
- `project.pbxproj`: iPhone only (`TARGETED_DEVICE_FAMILY = 1`), iOS 15.0 minimum (Capacitor 8's floor),
  version numbers.
- `web/ios/App/App/PrivacyInfo.xcprivacy`: Apple's privacy manifest. No tracking; declares UserDefaults use.
- `cap sync` never touches these files. Adding a Capacitor plugin (`npm install @capacitor/…` and then
  `npm run build:ios`) rewrites `web/ios/App/CapApp-SPM/Package.swift`; commit that change.

## Icon and splash (placeholders)

The current icon and launch screen are **placeholders**: the `web/public/icon.svg` shield on `#121216`.
The final art is #21. To replace it, overwrite the files in `web/assets/`:

- `icon.png`: 1024×1024, square corners (iOS rounds them), **no transparency**. Apple rejects icons
  with an alpha channel.
- `splash.png` and `splash-dark.png`: 2732×2732, the same image twice (the game is dark either way). Phones
  crop the sides, so keep the logo within the middle ~1200 px.

Then, from `web/`:

```sh
npx @capacitor/assets generate --ios --iconBackgroundColor '#121216' --splashBackgroundColor '#121216' --splashBackgroundColorDark '#121216'
```

and commit `web/assets/` and `web/ios/App/App/Assets.xcassets/`.
