# Moderation routine

Apple wants "timely responses to concerns" (guideline 1.2). You're the only admin, so the game tells you when a
report comes in, and you check the queue once a day either way.

## How you hear about reports

1. A player files a report (🚩 Report on a profile, a forum thread or reply, or from the ⋯ on a chat line). The
   `profile_reports_notify` trigger runs `_report_notify()`.
2. If `notify_url` is set, the trigger claims the 10-minute slot (it writes `sent_at` in `notify_state`, key `report`),
   then queues a call to the `report-notify` edge function through pg_net, with the shared secret in `x-report-secret`.
3. The function checks the secret and sends one message: to Discord if `DISCORD_WEBHOOK_URL` is set, otherwise an
   email through Resend if `RESEND_API_KEY` and `REPORT_EMAIL_TO` are set.

   > 🚩 **2 players** with open reports (3 reports). Latest: *name* on **Rude Dude** by Tattler — "rude".
   > Review: https://rangerzack.github.io/cartel-wars/admin

- **One message per 10 minutes at most.** Reports inside the window don't send their own; the next message after it
  carries the counts. Ten reports in a minute is one message. A report that comes in inside the window and isn't
  followed by another only shows in the counts of the next message and on the Admin page, which is what the daily
  check is for.
- **Best-effort.** If the call fails (function down, Discord down, wrong secret), the report still goes in. Nothing
  retries; the next report after 10 minutes tries again.
- **Off** while `notify_url` is empty: the default, and always the case on local databases, which don't have pg_net
  anyway.

## Setup (once)

### 1. Pick where messages go

- **Discord** (instant push to your phone): in a channel only you can read, Edit Channel → Integrations → Webhooks →
  New Webhook → Copy Webhook URL. Anyone with that URL can post to the channel, so treat it as a secret.
- **Email**: a [Resend](https://resend.com) account and API key. Verify `rangelab.io` under Domains so mail from
  `noreply@rangelab.io` gets delivered, or set `REPORT_EMAIL_FROM` to an address on a domain you have verified.

If both are set, Discord wins.

### 2. Set the function's secrets

| Secret | What it is |
|---|---|
| `REPORT_SECRET` | A random string the database sends and the function checks (`openssl rand -hex 32`). Required. |
| `DISCORD_WEBHOOK_URL` | The webhook URL (Discord). |
| `RESEND_API_KEY` | The Resend API key (email). |
| `REPORT_EMAIL_TO` | Where to send the email; separate several addresses with commas (email). |
| `REPORT_EMAIL_FROM` | Optional sender, default `Cartel Wars <noreply@rangelab.io>` (email). |

```sh
npx supabase login
npx supabase link --project-ref bghoornhtsgzlebrbdoh
npx supabase secrets set REPORT_SECRET=<random> DISCORD_WEBHOOK_URL=<webhook URL>
# or, for email:
npx supabase secrets set REPORT_SECRET=<random> RESEND_API_KEY=<key> REPORT_EMAIL_TO=zack@rangelab.io
```

Or set them in the dashboard under Edge Functions → Secrets. Changing a secret doesn't need a redeploy.

### 3. Deploy the function

```sh
npx supabase functions deploy report-notify --no-verify-jwt
```

`--no-verify-jwt` because the database calls it with the shared secret, not a signed-in player's token.
`supabase/config.toml` says the same for `report-notify`, so a deploy without the flag keeps it off. Redeploy after
changing `supabase/functions/report-notify/index.ts`.

### 4. Point the database at it

In the SQL editor:

```sql
update app_text set value = 'https://bghoornhtsgzlebrbdoh.supabase.co/functions/v1/report-notify' where key = 'notify_url';
update app_text set value = '<the same REPORT_SECRET>' where key = 'notify_secret';
select extname from pg_extension where extname = 'pg_net';   -- one row; if none, turn on pg_net under Database → Extensions
```

The migration turns pg_net on where it can, so the last line is a check.

### 5. Try it

```sh
curl -i -X POST https://bghoornhtsgzlebrbdoh.supabase.co/functions/v1/report-notify \
  -H 'Content-Type: application/json' -H 'x-report-secret: <REPORT_SECRET>' \
  -d '{"kind":"report","open_targets":1,"open_reports":1,"latest":{"reason":"other","note":"test","target":"Nobody","reporter":"Zack"}}'
```

| Answer | Meaning |
|---|---|
| 200 `{"sent":"discord"}` or `{"sent":"resend"}` | Working. |
| 200 `{"skipped":"no channel configured"}` | No Discord URL, and not both Resend secrets. |
| 401 | The secret in the header isn't `REPORT_SECRET`. |
| 502 | Discord or Resend refused or couldn't be reached; the body says which and why. |

Then a real one: report a player from a second account. If no message comes:

```sql
select * from notify_state;   -- sent_at moves when a call is queued
-- what the calls got back (pg_net keeps them a few hours)
select created, status_code, error_msg, content from net._http_response order by created desc limit 5;
```

and the function's logs (dashboard: Edge Functions → report-notify → Logs). A 401 there means `notify_secret` and
`REPORT_SECRET` differ.

- Test again inside the 10 minutes: `update notify_state set sent_at = null where key = 'report';`
- Pause notifications: `update app_text set value = '' where key = 'notify_url';`
- New secret: `secrets set REPORT_SECRET=…`, then the same value into `notify_secret`.

## The daily check

Once a day, message or not:

1. Open the game → Profile → 🛡 Admin (Home shows a notice while reports are open). The Reports tab lists players
   with open reports, most recently reported first.
2. For each player, compare the snapshot (what the profile said when it was reported) with what it says now; a report
   of a message, thread or reply shows the reported text and where it was. Act, or dismiss. Delete closes the reports
   on that message or post; mutes, resets and Dismiss close all of that player's open reports (Unmute closes none).
   Every action goes in the Log tab and tells the player.
3. Nothing should stay open longer than a day.

## Escalation ladder

| What you see | What you do |
|---|---|
| Rude but within the rules: trash talk, swearing the filter lets through | Dismiss |
| An offensive name, avatar or bio | Reset the name or avatar, or clear the bio |
| Hate or threats | Delete it, mute them for 7 days |
| The same player again | Reset the name, mute them for 30 days |

- **Keep the log.** Never delete `mod_log` rows; it's the record if Apple or a player asks what happened.
- A word that keeps getting through goes on the Word Filter tab.

## Adding a second admin

Admins are the emails in the `admins` table; `profiles.is_admin` is set from it when someone signs up.

```sql
insert into admins (email) values ('them@example.com');
-- already signed up? flag them now
update profiles p set is_admin = true from auth.users u where u.id = p.id and lower(u.email) = lower('them@example.com');
```

They get the Admin page the next time the game refreshes. Messages go to the channel, not to admins: add them to the
Discord channel, or add their address to `REPORT_EMAIL_TO`.

To remove one:

```sql
delete from admins where lower(email) = lower('them@example.com');
update profiles p set is_admin = false from auth.users u where u.id = p.id and lower(u.email) = lower('them@example.com');
```

# Purchases

Diamond packs and the Daily Drop subscription are sold through Apple in the iOS app. RevenueCat runs the purchase on
the phone and tells the game through a webhook. Nothing is sold on the web. Rules: SPEC.md, "Store".

## How a purchase reaches the game

1. The app signs RevenueCat in as the player (their Supabase user id) when they sign in, and out when they sign out.
2. The player taps a pack in the Store (Home → Diamonds) or Subscribe on the Daily Drop. StoreKit shows Apple's sheet
   and takes the payment. The price on the button is StoreKit's, in the player's currency.
3. RevenueCat posts the event to the `iap-webhook` edge function with the Authorization header you set in RevenueCat.
4. The function checks the header and calls `iap_apply(...)` with the service key (players can't call it). That
   credits the pack, claws back a refund, or moves the Daily Drop's paid-through date, and writes one `iap_grants` row.
5. The app sees the diamonds in `get_me` (it checks every 1.5 s for 20 s, then says they're on their way).

- **Retries are safe.** RevenueCat retries anything but a 2xx. `iap_grants` is unique on (provider, transaction, event),
  so a repeat answers `{"duplicate":true}` and changes nothing. Events the game doesn't use still get 200, recorded as
  `{"ignored": …}`; only a database error answers 500, so RevenueCat tries again.
- **Sandbox counts.** TestFlight and App Review purchases are sandbox purchases: free, and the webhook credits them
  like real ones (App Review has to see the diamonds arrive). Anyone with a TestFlight build can get free diamonds,
  so only invite testers you trust. `raw->>'environment'` says which it was.
- **Refunds.** Players ask Apple (reportaproblem.apple.com). RevenueCat reports a refund as a `CANCELLATION` with
  `cancel_reason` `CUSTOMER_SUPPORT`: a pack's diamonds come back off the balance (never below 0), a subscription ends
  at once. A plain `CANCELLATION` of the subscription is the player turning off renewal: it runs to its paid-through
  date and `EXPIRATION` ends it.

## Setup (once)

### 1. App Store Connect

1. **Business → Agreements**: the Paid Apps agreement has to be active, with bank and tax details. Nothing can be
   sold without it, not even in the sandbox.
2. **Apps → Cartel Wars → Monetization → In-App Purchases → "+"**, type **Consumable**, one per row of `store_packs`,
   with exactly these product ids:

   | Product id | Diamonds |
   |---|---|
   | `io.rangelab.cartelwars.diamonds.100` | 100 |
   | `io.rangelab.cartelwars.diamonds.550` | 550 |
   | `io.rangelab.cartelwars.diamonds.1200` | 1,200 |
   | `io.rangelab.cartelwars.diamonds.2600` | 2,600 |
   | `io.rangelab.cartelwars.diamonds.7000` | 7,000 |
   | `io.rangelab.cartelwars.diamonds.15000` | 15,000 |

   Pick the price, a display name like "1,200 Diamonds" (it's on Apple's payment sheet) and a review screenshot of
   the Store.
3. **Subscriptions → "+"**: a group "Daily Drop", then an auto-renewable subscription `io.rangelab.cartelwars.drop.monthly`,
   duration 1 month, with its price and a screenshot of the Daily Drop card.
4. **Users and Access → Integrations → In-App Purchase → "+"**: an In-App Purchase key for RevenueCat. Download the
   `.p8` (offered once).
5. Submit the products with the next build (the first in-app purchases go to review together with an app version).

### 2. RevenueCat

1. Create a project "Cartel Wars" and add an **App Store** app: bundle id `io.rangelab.cartelwars`, the In-App
   Purchase key from above (with its key id and your issuer id).
2. The app's page shows an **Apple Server Notification URL**. Paste it into App Store Connect → Cartel Wars → App
   Information → App Store Server Notifications (production and sandbox, version 2). Refunds reach RevenueCat this way.
3. **Product catalog → Products**: add the seven product ids. An entitlement or an Offering isn't needed: the app asks
   StoreKit for the ids in `store_packs` and `app_text`.
4. **Project settings → General → Restore behavior**: *Keep with original App User ID*. A restore on another Cartel
   Wars account can't move a subscription to it; the app says "Those purchases belong to another Cartel Wars account".
5. **API keys**: copy the App Store app's public key (`appl_…`) into a GitHub repository variable
   `REVENUECAT_IOS_KEY` (Settings → Secrets and variables → Actions → Variables). The iOS workflow builds with it as
   `VITE_REVENUECAT_IOS_KEY`. It's a public key, meant to ship inside the app. A build without it shows the Store
   with "Purchases aren't available in this build".
6. **Integrations → Webhooks → "+"**:
   - URL: `https://bghoornhtsgzlebrbdoh.supabase.co/functions/v1/iap-webhook`
   - Authorization header value: a random string, e.g. `Bearer ` followed by `openssl rand -hex 32`
   - Environments: production and sandbox; events: all.

### 3. Set the function's secret

| Secret | What it is |
|---|---|
| `REVENUECAT_WEBHOOK_AUTH` | The Authorization header value from RevenueCat, exactly (`Bearer …` included). Required: without it every call gets 401. |
| `SUPABASE_URL` | The project URL. Supabase gives it to every edge function; don't set it. |
| `SUPABASE_SERVICE_ROLE_KEY` | The service key the function calls `iap_apply` with. Also given by Supabase; don't set it. |

```sh
npx supabase secrets set REVENUECAT_WEBHOOK_AUTH='Bearer <the random string>'
```

### 4. Deploy the function

```sh
npx supabase functions deploy iap-webhook --no-verify-jwt
```

`--no-verify-jwt` because RevenueCat sends its own Authorization header, not a signed-in player's token.
`supabase/config.toml` says the same for `iap-webhook`. Redeploy after changing `supabase/functions/iap-webhook/index.ts`.
The tables and `iap_apply` come with migration `20261004000012_store.sql`.

### 5. Try it

In RevenueCat, the webhook's **Send test event**, or:

```sh
curl -i -X POST https://bghoornhtsgzlebrbdoh.supabase.co/functions/v1/iap-webhook \
  -H 'Content-Type: application/json' -H 'Authorization: Bearer <the random string>' \
  -d '{"event":{"type":"TEST","id":"test-1","app_user_id":"nobody","product_id":"test_product"}}'
```

| Answer | Meaning |
|---|---|
| 200 `{"ignored":"unknown product"}` | Working (a test event names no real product). |
| 200 `{"credited":550}`, `{"subscribed":…}`, `{"revoked":…}`, `{"lapsed":true}`, `{"ended":true}` | A real event did its job. |
| 200 `{"ignored":"unknown player"}` | The app_user_id isn't a player's id: the purchase was made signed out, or by a deleted account. |
| 200 `{"duplicate":true}` | That event was already applied. |
| 401 | The header isn't `REVENUECAT_WEBHOOK_AUTH`. |
| 400 | Not JSON, or no event in it. |
| 500 | The database call failed; the body says why. RevenueCat retries. |

Then a real one: in App Store Connect → Users and Access → Sandbox, make a test account, sign in to it on the iPhone
(Settings → App Store → Sandbox Account), and buy 100 diamonds in a TestFlight build. Within seconds the diamonds land
and Activity says "You bought 100 diamonds".

```sql
-- what the webhook did lately
select created_at, event, product_id, transaction_id, diamonds, player_id, raw->>'environment' as env
  from iap_grants order by id desc limit 20;
-- purchases that found no player
select * from iap_grants where player_id is null and event in ('INITIAL_PURCHASE', 'NON_RENEWING_PURCHASE') order by id desc;
```

To credit one by hand (a purchase that found no player, after checking it in RevenueCat), go through `iap_apply` so
it's on the record. The `manual` provider keeps it apart from RevenueCat's own events:

```sql
select iap_apply('manual', 'NON_RENEWING_PURCHASE', '<Apple transaction id>', 'io.rangelab.cartelwars.diamonds.550',
                 '<player id>', null, '{"note": "credited by hand"}');
```

## Changing packs

Packs are rows in `store_packs`; the price lives only in App Store Connect. The app reads the list when it starts.

```sql
-- a new pack: create the product in App Store Connect first, with the same id
insert into store_packs (id, diamonds, sort) values ('io.rangelab.cartelwars.diamonds.30000', 30000, 7);
-- what a pack gives (purchases already made keep what they got; a refund takes back what that purchase gave)
update store_packs set diamonds = 1300 where id = 'io.rangelab.cartelwars.diamonds.1200';
-- stop selling one (a purchase of it still pays out)
update store_packs set active = false where id = 'io.rangelab.cartelwars.diamonds.15000';
```

Keep the display name in App Store Connect in step with the diamonds. In the app the Store shows only packs the App
Store returns, so a row whose product isn't live yet stays hidden there.

## Turning the Daily Drop's paid plan on

`drop_free` is a constant in `_cfg`, so it changes with a migration: copy the newest `create or replace function _cfg`
(the latest migration that has one) into a new migration, change `drop_free` from 1 to 0, and ship it. From then on
`subscribe_drop` refuses ("Subscribe through the store"), the app's Subscribe button is the App Store purchase, and the
web says it's an iPhone subscription. Before that, the subscription product has to be approved and live.

Players already on the free plan keep it, open-ended, until they cancel. To end them at the switch instead (their
unopened crates stay), add to the same migration:

```sql
update profiles set drop_since = null where drop_since is not null and drop_until is null;
```
