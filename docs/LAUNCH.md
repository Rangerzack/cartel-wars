# App Store launch checklist

The persistent checklist for getting Thug Empire 1.0 onto the App Store. Update it at every milestone. **Status
words mean what they say:** *done* has evidence next to it; *unverified* means nobody has checked yet; *needs Zack*
means it takes an Apple, GitHub or RevenueCat login, a device, or a decision.

Started 2026-11-25. State checked that day against the repo, the live database (Supabase `cartel-wars`, read-only
queries) and Apple's published requirements.

## Shortest path to the first TestFlight build

1. **[done, on `staging`]** Workflow moved to `.github/workflows/ios.yml`.
2. **[needs Zack]** Promote it to `main`. "Run workflow" only appears for workflows on the default branch. (A pushed
   `ios-v*` tag also triggers it from any branch.)
3. **[needs Zack]** Apple setup, all in a browser (steps are in the comment at the top of `ios.yml`):
   1. Register the bundle ID `io.rangelab.cartelwars`.
   2. Create the app record "Thug Empire", SKU `cartel-wars`.
   3. Create an App Store Connect API key (Admin access).
4. **[needs Zack]** Create the private `Rangerzack/cartel-wars-certs` repo and a fine-grained token for it.
5. **[needs Zack]** Add six repository secrets: `ASC_KEY_ID`, `ASC_ISSUER_ID`, `ASC_KEY_P8`, `MATCH_GIT_URL`,
   `MATCH_GIT_AUTH`, `MATCH_PASSWORD`. Add them in GitHub → repo Settings → Secrets and variables → Actions. Never
   paste them into a chat.
6. Run **Actions → iOS to TestFlight → Run workflow**. *Evidence:* a green run, and build 1 visible under TestFlight
   in App Store Connect.

The build works without RevenueCat. Without `REVENUECAT_IOS_KEY`, the Store says "Purchases aren't available in this
build", which is fine for a first TestFlight build but not for submission.

## Confirmed blockers

| # | Blocker | Evidence it's real | Status | Evidence needed to close it |
|---|---|---|---|---|
| B1 | iOS workflow parked in `docs/`, so no build can run | File was at `docs/ios-workflow.yml`; repo has no `ios-v*` tags; no iOS run has ever happened | Moved on `staging`; needs promoting to `main` | First green "iOS to TestFlight" run |
| B2 | Player and thug fights cost no stamina | Deployed `attack()` checks `stamina < 2` but never subtracts (function source identical to `20261002000001_combos_jail.sql`). `fight_preview` tells players a fight "costs ⚡2" | Fixed in `20261125000029_launch_fixes.sql`, tested (`scripts/launch-test.sql`) and race-checked locally. **Not applied to the live database yet** | Migration applied; a live fight drops stamina by 2 |
| B3 | Sandbox (free) purchases would credit real diamonds into the live economy | `iap_apply` credited regardless of `environment`; `docs/ops.md` said so | Fixed in the same migration: sandbox credits only `iap_tester` accounts and admins. Store tests updated | Migration applied; a sandbox buy on a non-tester account is recorded as ignored, and one on the demo account is credited |
| B4 | App Store screenshots are out of date | `docs/app-store/screenshots-6.7` last changed 2026-10-04, before the Border Night redesign and the rename | Open | New 6.7"/6.9" set from the current build, uploaded in App Store Connect |
| B5 | Purchases not set up | No RevenueCat key in the build; the webhook secret and products are not configured (`iap_grants` is empty) | Needs Zack (see below) | A sandbox pack bought on TestFlight lands on the demo account within seconds |
| B6 | Submission metadata incomplete | Review notes have blank demo credentials; the age rating questionnaire now has two new required questions (see below) | Open | App Store Connect shows no missing fields |

## Unverified concerns

| Concern | What's known | How to settle it |
|---|---|---|
| "⚡2 job refused at exactly 2" | The server check is correct (`do_action` refuses only `stamina < cost`; tested at exactly 2 for fights too). Likely a stale stamina number in the app (the bar shows the last `get_me`) | Reproduce on TestFlight. If the server says "Not enough stamina" at the displayed 2, capture the time and check `server_time` against `next_tick` |
| fastlane/match first run | The Fastfile and Matchfile read correctly, but they've never run | The first workflow run |
| `UIRequiredDeviceCapabilities` | Was `armv7`, from the old Capacitor template, on an arm64-only iOS 15+ app. Changed to `arm64` on `staging` | Upload passes App Store Connect validation |
| RevenueCat privacy disclosure | The listing says to check whether the SDK sends a device ID | Read RevenueCat's App Store privacy guide when the SDK is configured; update App Privacy |
| Rights | The app and the Profile page say it's an unofficial fan project and name *Cartel Wars*. The renamed title avoids the *Narcos: Cartel Wars* clash. All art is drawn in-repo (`scripts/brand-assets.mjs`, `scripts/app-art.mjs`) | Zack decides whether naming *Cartel Wars* in the app is wanted (guideline 5.2: naming someone else's trademark can draw a rejection). Check that item names and descriptions weren't copied word for word from the original |
| Bribe vs bail | Bribes cost $40 per heat point; bail is a flat $8,000. With heat upgrades past 200, bribing down costs more than getting busted | Balance decision for Zack (proposal: cap a full bribe at the bail price). Not a launch blocker |
| Economy loops, duplicate rewards, abuse | The existing suites cover duplicate IAP events, refunds, out-of-order subscription events, mission claims and casino edge cases. There's no server-side rate limiting except on the forum | Next milestone: a server-enforced per-player limit on high-value RPCs (transfers, market, casino), plus an admin pause switch per feature |
| Fresh-account campaign, disconnects, season rollover | Covered by `scripts/e2e-seasons.mjs` and `season-test.sql` (SQL suite passes) | Run the Playwright suites; then a device pass on TestFlight |
| Polish branch `design-skills-pass` | One commit, CSS and copy only, CI green | Review, merge into `staging`, run the full suites and e2e, look at it on a phone |

## Done (with evidence)

- **2026-11-25:** full SQL suite (27 files, `scripts/local-db.sh test`) passes on `staging` with the launch fixes.
  New `scripts/launch-test.sql` checks four things:
  - a fight takes 2 stamina and still goes through at exactly 2
  - at 1 stamina the fight is refused and nothing is taken
  - sandbox purchases credit only testers and admins, and production purchases credit anyone
  - only an admin can mark a tester
- **2026-11-25:** concurrency check. Two simultaneous attacks on 3 stamina: one went through, one was refused, and 1
  stamina was left (`_tick` locks the profile row).
- **2026-11-25:** the App Review demo-account seed in `docs/app-store/listing.md` now sets `iap_tester = true`. The
  review notes ask App Review to buy on the demo account.

## Needs Zack: accounts

Never paste keys, passwords or tokens into a chat. Each one goes straight into the setting named here.

- **Apple Developer:** register the bundle ID; App Store Connect: create the app; create an API key (Admin). Under
  Agreements, Tax, and Banking, sign the Paid Apps agreement. Without it, products can't be sold, not even in the
  sandbox.
- **GitHub:**
  - Create the private `cartel-wars-certs` repo and a fine-grained token for it.
  - Add the six Actions secrets.
  - Add the `REVENUECAT_IOS_KEY` Actions variable.
- **RevenueCat:**
  - Create the project and iOS app, and add the In-App Purchase key.
  - Turn on App Store Server Notifications (v2, production and sandbox).
  - Point the webhook at `iap-webhook` with an Authorization header you make up.
  - Steps are in `docs/ops.md` → Purchases.
- **Supabase:**
  - Set `REVENUECAT_WEBHOOK_AUTH` (Dashboard → Edge Functions → Secrets).
  - Deploy `iap-webhook` with `--no-verify-jwt`.
- **App Store Connect products:** the consumable diamond packs from `store_packs` (and the subscription, if decision
  D3 says so).
- **Demo account:** create `appreview@rangelab.io` and run the seed in `docs/app-store/listing.md`. Fill the
  credentials into App Store Connect → App Review Information. Never put them in the repo.

## Needs Zack: decisions

| # | Decision | Recommendation |
|---|---|---|
| D1 | Apply `20261125000029_launch_fixes.sql` to the live database (shared by live and staging) | **Yes.** All 294 players' fights start costing the 2 stamina the game already quotes, effective immediately. The sandbox gate changes nothing today because no purchases exist. Rollback: re-run the old `attack()` and `iap_apply()` (named in the migration header) |
| D2 | Bundle ID: keep `io.rangelab.cartelwars` or switch to e.g. `io.rangelab.thugempire` before the first upload | **Keep.** Players never see it. It becomes permanent at the first upload, so this is the last free moment to change it, and renaming means editing `capacitor.config.ts`, the Xcode project, `Appfile` and `Matchfile` |
| D3 | Ship the Daily Drop subscription in 1.0, or launch with diamond packs only and keep the Drop free | **Packs only for 1.0.** A paid Drop needs subscription review (3.1.2), a delivery model that doesn't lose paid days (crates stack to 7, then a day is lost), and the paid random-prize disclosures. Keeping it free keeps every player's current benefit. Ship it in 1.1 |
| D4 | Sandbox purchases: credit testers only (built), or also brand-new accounts so App Review can buy on an account it makes itself | **Testers only**, with review notes pointing App Review to the demo account. Crediting new accounts lets any TestFlight tester mint diamonds |
| D5 | Age rating answers | Frequent simulated gambling → 18+ (already the plan). Also answer the two descriptors Apple added on 2026-11-16, required by 2027-01-12: Shared Location **No**, Dating and Relationships **No** |

## Device checks (TestFlight, Zack's iPhone)

Not automatable from here; tick each when done:

- [ ] Sign up, sign in, sign out, password reset email
- [ ] Keyboard over chat and forum inputs; safe areas on a notched phone; status bar
- [ ] Background the app, then resume; airplane mode mid-action ("Can't reach the city", then recovery)
- [ ] Marcus campaign on a fresh account: tabs unlock in order
- [ ] Buy a pack on the demo account (credited), and on a non-tester account (not credited, shown as "on its way")
- [ ] Restore purchases; delete account from Profile; reinstall and sign in
