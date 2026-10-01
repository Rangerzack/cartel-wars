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
