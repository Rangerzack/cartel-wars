# Cartel Wars

A web reconstruction of SMLSD's *The Cartel* / *Cartel Wars* (iPhone, 2009–2010,
later *Cartel Reloaded* under Roasted Brains): a multiplayer crime-economy game
about producing and moving product, one-on-one fights with equipped gear, Heat
and jail, Crews and Cartels, and turf wars over Hoods and Blocks.

Design notes and every reconstructed number live in [SPEC.md](SPEC.md).

## Stack

- **Backend:** Supabase (Postgres + Auth + Realtime). All game logic is SQL in
  `supabase/migrations/` — every state change is a `security definer` RPC, and
  regen/production/payouts are computed lazily from timestamps. No cron, no
  edge functions.
- **Web:** Vite + React + TypeScript in `web/`, mobile-first, `@supabase/supabase-js`.

## Run it against a Supabase project

1. Create a project at supabase.com, then push the migrations:
   ```sh
   npx supabase login
   npx supabase link --project-ref <your-project-ref>
   npx supabase db push
   ```
   (or paste the three files from `supabase/migrations/` into the SQL editor, in order).
2. In the Supabase dashboard → Authentication → Providers → Email, turn **off**
   "Confirm email" unless you've set up SMTP.
3. Configure and run the web app:
   ```sh
   cd web
   cp .env.example .env      # set VITE_SUPABASE_URL and VITE_SUPABASE_ANON_KEY
   npm install
   npm run dev
   ```
4. Deploy `web/` anywhere static (Vercel, Netlify, Cloudflare Pages). It's a
   single-page app, so route all paths to `index.html` (`web/vercel.json` and
   `web/public/_redirects` are included).

## Run it fully local (no Supabase account, no Docker)

Needs a local Postgres 15+ (`initdb`/`pg_ctl` on PATH) and Node 20+.

```sh
npm install                  # root: installs scripts/ deps
npm run db:reset             # starts a throwaway Postgres on :54329 and applies migrations
npm run dev:api              # tiny GoTrue+PostgREST stand-in on :54321 (see scripts/dev-server.mjs)
cd web && npm install && cp .env.local.example .env.local && npm run dev
```

Optional: populate a demo world (24 bots, three crews, a cartel, held blocks,
listings, chat) so the city looks alive, then sign in as `bot01@demo.local` /
`secret123`:

```sh
npm run db:demo
```

Tests:

```sh
npm run db:test              # SQL smoke test of every RPC (scripts/smoke-test.sql)
npm run e2e                  # Playwright walkthrough of the UI against the local stack
node scripts/tour.mjs out/   # screenshots of every screen as a demo bot
```

`npm run db:*` needs to run as a user that can start Postgres (on Linux:
`sudo -u postgres env PGDATA_DIR=/tmp/cartel-pg npm run db:reset`).

## Layout

```
supabase/migrations/0001_schema.sql     tables, enums, RLS lockdown
supabase/migrations/0002_functions.sql  all game rules (actions, fights, economy, crews, territory, chat)
supabase/migrations/0003_seed.sql       content: commodities, items, actions, hoodlums, hoods/blocks
web/src/lib/api.ts                      typed wrappers for every RPC
web/src/lib/game.tsx                    session + player state (get_me) + toasts
web/src/pages/*                         Home, Actions, Economy, Fight, Player, Services, Items, Crew, Cartel, Territory, Chat, Profile
scripts/                                local Postgres harness, dev API server, smoke test, e2e
```

## Tuning

Game constants are in `_cfg()` at the top of `0002_functions.sql`; content tables
are in `0003_seed.sql`. Change, re-run `npm run db:test`, then `supabase db push`
(new changes go in a new migration file once the project is live).

## Not yet built

Reputation actions with rare weapons (the 2011 "Reputation expansion"), the
Casino (Cartel Reloaded), Diamond purchases, and the "Profession" stat. See
SPEC.md for what's sourced and what's a fill-in.

---

Unofficial fan reconstruction. Not affiliated with SMLSD, Webtouch SRL or Roasted Brains.
