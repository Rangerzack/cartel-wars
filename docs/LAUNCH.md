# App Store launch checklist

The persistent checklist for getting Thug Empire 1.0 onto the App Store. Update it at every milestone. **Status
words mean what they say:** *done* has evidence next to it; *unverified* means nobody has checked yet; *needs Zack*
means it takes an Apple, GitHub or RevenueCat login, a device, or a decision.

Started 2026-11-25. State checked that day against the repo, the live database (Supabase `cartel-wars`, read-only
queries) and Apple's published requirements.

## Shortest path to the first TestFlight build

1. **[done]** Workflow moved to `.github/workflows/ios.yml`.
2. **[done 2026-11-25]** Promoted to `main`, so "Run workflow" is available.
3. **[needs Zack]** Apple setup, all in a browser (steps are in the comment at the top of `ios.yml`):
   1. Register the bundle ID `io.github.rangerzack.thugempire`.
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
| B1 | iOS workflow parked in `docs/`, so no build can run | File was at `docs/ios-workflow.yml`; repo has no `ios-v*` tags; no iOS run has ever happened | Moved and live on `main` (2026-11-25) | First green "iOS to TestFlight" run |
| B2 | Fights checked for 2 stamina, never took it, and the app said they cost 2 | Deployed `attack()` refused below 2 and took nothing; `fight_preview` and the Player page quoted ⚡2. SPEC called "not consumed" intended | **Decided (Zack, 2026-11-25): fights cost no stamina.** Check removed, preview says 0, app wording updated (`20261125000029_launch_fixes.sql`, `launch-test.sql`). **Applied to the live database and promoted 2026-11-25** | Live fight at 0 stamina works; Player page shows no stamina cost |
| B3 | Sandbox (free) purchases would credit real diamonds into the live economy | `iap_apply` credited regardless of `environment`; `docs/ops.md` said so | Fixed in the same migration, applied live 2026-11-25: sandbox credits only `iap_tester` accounts and admins | A sandbox buy on a non-tester account is recorded as ignored; one on the demo account is credited |
| B4 | App Store screenshots are out of date | `docs/app-store/screenshots-6.7` last changed 2026-10-04, before the Border Night redesign and the rename | Open | New 6.7"/6.9" set from the current build, uploaded in App Store Connect |
| B5 | Purchases not set up | No RevenueCat key in the build; the webhook secret and products are not configured (`iap_grants` is empty) | Needs Zack (see below) | A sandbox pack bought on TestFlight lands on the demo account within seconds |
| B7 | Password reset and other auth emails don't reach players | Custom SMTP is off, so Supabase only emails its own team, at 2 an hour. The Site URL was `http://localhost:3000` with no redirect URLs allowed | URLs fixed 2026-11-25 (Site URL `https://rangerzack.github.io/cartel-wars/`, redirect `https://rangerzack.github.io/cartel-wars/**`). SMTP needs Zack: a provider account and a sender address, entered in Authentication → Emails → SMTP Settings | A reset email sent to a non-team address arrives and its link opens the game's new-password screen, on the web and from the iPhone app |
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

- **2026-11-25:** `20261125000029_launch_fixes.sql` applied to the live project by Zack in the SQL editor. A read-only check
  afterwards confirmed:
  - `attack()` has no stamina check, and `fight_preview` quotes 0
  - `iap_apply` has the sandbox gate and players can't call it
  - `drop_paused` = 1; 11 subscriptions saved in `drop_pause_backup`, 0 still active
  - store packs are on `io.github.rangerzack.thugempire.*`
  - main promoted (`5cef922`); CI and the Pages deploy passed
- Note: this migration was run in the SQL editor, so it isn't recorded in `supabase_migrations.schema_migrations`.
  Don't `supabase db push` this repo against the live project without checking what's recorded there first.

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
- **App Store Connect products:** the six consumable diamond packs from `store_packs` (ids above). No subscription in 1.0.
- **Demo account:** create `appreview@rangelab.io` and run the seed in `docs/app-store/listing.md`. Fill the
  credentials into App Store Connect → App Review Information. Never put them in the repo.

## Decisions

| # | Decision | Outcome |
|---|---|---|
| D1 | Fight stamina | **Zero** (Zack, 2026-11-25). Fights against players and thugs cost no stamina. Crew fights, turf wars and Personal Hood fights keep their costs |
| D2 | Bundle ID | **`io.github.rangerzack.thugempire`** (Zack, 2026-11-25: private project, no Range Lab). Product ids follow it: `io.github.rangerzack.thugempire.diamonds.100` … `.15000`. Permanent after the first upload |
| D3 | Daily Drop in 1.0 | **Paused until 1.1** (Zack, 2026-11-25). Nobody can subscribe; the free subscriptions running at the pause stopped and are saved in `drop_pause_backup`; crates and credits already earned still work. 1.0 sells diamond packs only, so don't create the subscription product in App Store Connect yet |
| D4 | Sandbox purchases | **Testers only** (recommended; built). App Review buys on the demo account |
| D5 | Age rating answers | Frequent simulated gambling → 18+. The two descriptors Apple added on 2026-11-16 (required by 2027-01-12): Shared Location **No**, Dating and Relationships **No** |

## Open questions for Zack

- **Repo visibility.** `Rangerzack/cartel-wars` is public. Making it private takes the GitHub Pages site down on a free
  plan, and macOS build minutes stop being free.

- **Legal pages and support email:** done 2026-11-25. The operator is "the independent developer" and the contact is
  `Zack@apheleia.me`. Use the same address as the Support email in App Store Connect. Add your name to the privacy policy if
  you want a named data controller.
- **Apple Developer account type.** A private project ships under your individual account; the seller name on the
  store is then your legal name.

## Device checks (TestFlight, Zack's iPhone)

Not automatable from here; tick each when done:

- [ ] Sign up, sign in, sign out, password reset email
- [ ] Keyboard over chat and forum inputs; safe areas on a notched phone; status bar
- [ ] Background the app, then resume; airplane mode mid-action ("Can't reach the city", then recovery)
- [ ] Marcus campaign on a fresh account: tabs unlock in order
- [ ] Buy a pack on the demo account (credited), and on a non-tester account (not credited, shown as "on its way")
- [ ] Delete account from Profile; reinstall and sign in
- [ ] Daily Drop card says paused; a player with crates left can still open them
