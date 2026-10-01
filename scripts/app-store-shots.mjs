// App Store screenshots (#24): the 6.9" set Apple requires (1320×2868) and the 6.7" set (1290×2796), as PNGs in
// docs/app-store/screenshots/ and docs/app-store/screenshots-6.7/. Each screen is one phone screen, not a full page.
// Needs the local stack with the demo world: scripts/local-db.sh reset, then demo; dev-server.mjs; vite.
// Before each set it dresses bot01 up as "Domino" (cash, a producer's grow houses, gear, fights, activity, stripes) and
// swaps the demo world's names for made-up ones, so it only ever runs against the local demo database.
// Usage: node scripts/app-store-shots.mjs   (env BASE, PGPORT; SETS=6.9 for just the required set)
import { chromium } from 'playwright'
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import pg from 'pg'

const BASE = process.env.BASE || 'http://127.0.0.1:5173'
const ROOT = fileURLToPath(new URL('..', import.meta.url))
const db = new pg.Pool({ host: 'localhost', port: Number(process.env.PGPORT || 54329), user: 'postgres', database: 'cartel' })
const SETS = [
  { name: '6.9', dir: 'docs/app-store/screenshots', viewport: { width: 440, height: 956 } },
  { name: '6.7', dir: 'docs/app-store/screenshots-6.7', viewport: { width: 430, height: 932 } },
].filter(s => !process.env.SETS || process.env.SETS.split(',').includes(s.name))

// The seed borrows real cartel and TV names; store metadata can't (guideline 5.2), so the screenshots use these.
const NAMES = ['Domino', 'Marisol', 'Santi', 'Calloway', 'Brixton', 'Paz', 'Rook', 'Vandal', 'Kestrel', 'Halcon', 'Ferro', 'Dutch',
  'Sable', 'Juniper', 'Corvo', 'Tejada', 'Okoro', 'Blanca', 'Quill', 'Rocco', 'Lupe', 'Wren', 'Mako', 'Delacroix']

const POLISH = `
do $$
declare
  hero uuid := (select id from auth.users where email = 'bot01@demo.local');
  rook uuid := (select id from auth.users where email = 'bot07@demo.local');
  crew_a uuid; crew_b uuid; crew_c uuid; mates uuid[];
begin
  if hero is null then raise exception 'No demo world: run scripts/local-db.sh demo first'; end if;
  update profiles p set name = n.name, bio = case when p.bio = 'Plata o plomo.' then 'Pay on time.' else p.bio end
    from auth.users u, unnest('{${NAMES.join(',')}}'::text[]) with ordinality n(name, i)
   where u.id = p.id and u.email = format('bot%s@demo.local', lpad(n.i::text, 2, '0'));
  select id into crew_a from crews where capo_id = hero;
  select id into crew_b from crews where capo_id = rook;
  select id into crew_c from crews where capo_id = (select id from auth.users where email = 'bot13@demo.local');
  update crews set name = 'Los Halcones', emblem = '🦅', description = 'Harbor Row is ours. Producers welcome.' where id = crew_a;
  update crews set name = 'Hilltop Kings', emblem = '👑', description = 'We run the hill.' where id = crew_b;
  update crews set name = 'Costa Verde', emblem = '🌵', description = 'Recruiting. Producers welcome.' where id = crew_c;
  update cartels set name = 'Del Norte' where don_id = hero;
  select array_agg(id order by name) into mates from profiles where crew_id = crew_a and id <> hero;

  -- the hero: a settled producer mid-session, stats green, nothing pending that would put a prompt on screen
  update profiles set avatar = '🐺', bio = 'Harbor Row is ours. Buying dust, paying street.', cash = 1284500, bank = 8420000,
    diamonds = 145, stamina_max = 150, stamina = 138, health_max = 300, health = 300, heat = 34, heat_max = 100,
    reputation = 60, rep_earned = 160, path = 'producer', path_chosen_at = now() - interval '20 days',
    actions_done = 4210, fights_won = 612, fights_lost = 148, imports = 18400, market_volume = 6250000,
    storage_cap = 1500, inventory_slots = 8, in_hospital = false, jail_until = null, muted_until = null, rename_pending = false,
    last_tick = now(), stamina_tick = now(), health_tick = now(), last_seen = now(), daily_day = (now() at time zone 'utc')::date,
    drop_since = now() - interval '12 days', drop_until = null, drop_day = (now() at time zone 'utc')::date, drop_crates = 2,
    boost_side = null, boost_until = null, created_at = now() - interval '58 days'
   where id = hero;
  -- three-digit storage: Profile's Storage stat clips at 430 px wide once both numbers are in the thousands
  update storage set qty = case commodity when 'herb' then 610 when 'dust' then 280 else 74 end where player_id = hero;
  delete from grow_houses where player_id = hero;
  insert into grow_houses (player_id, commodity, level, running, started_at) values
    (hero, 'herb', 8, true, now() - interval '6 hours'), (hero, 'dust', 6, true, now() - interval '4 hours'),
    (hero, 'pills', 4, true, now() - interval '3 hours');
  delete from hustlers where player_id = hero;
  delete from setup_items where player_id = hero;
  delete from setup_combos where player_id = hero;
  delete from inventory where player_id = hero;
  insert into inventory (player_id, item_id, qty) select hero, id, 1 from item_defs
   where name in ('AK-47', 'M4 Carbine', 'Sniper Rifle', 'Body Armor', 'Kevlar Jacket', 'Bulletproof Plate', 'Armored SUV', 'Cargo Truck', 'Cell Block Pipe', 'Helmet');
  insert into setup_items (player_id, setup, item_id, qty) select hero, 'offense', id, 1 from item_defs
   where name in ('AK-47', 'M4 Carbine', 'Sniper Rifle', 'Body Armor', 'Kevlar Jacket', 'Armored SUV');
  insert into setup_items (player_id, setup, item_id, qty) select hero, 'defense', id, 1 from item_defs
   where name in ('Bulletproof Plate', 'Body Armor', 'Kevlar Jacket', 'M4 Carbine', 'Sniper Rifle', 'Armored SUV');
  insert into setup_items (player_id, setup, item_id, qty) select hero, 'jail', id, 1 from item_defs where name in ('Cell Block Pipe', 'Helmet');
  -- milestones already earned, so the first job doesn't pay out a pile of diamonds mid-run
  delete from milestones where player_id = hero;
  insert into milestones (player_id, key) select hero, key from milestone_defs
   where (kind = 'actions' and n <= 4300) or (kind = 'wins' and n <= 612);

  -- the matchup: Rook, a healthy rival with a little less cash and heat, so both sides show edges, geared to be close
  update profiles set cash = 412000, heat = 18, health = health_max, in_hospital = false, jail_until = null, avatar = '🐍',
    bio = 'We run the hill.', last_seen = now() - interval '6 minutes', last_tick = now(), health_tick = now(), inventory_slots = 8 where id = rook;
  delete from setup_items where player_id = rook;
  delete from setup_combos where player_id = rook;
  delete from inventory where player_id = rook;
  insert into inventory (player_id, item_id, qty) select rook, id, 1 from item_defs
   where name in ('RPG', 'Sniper Rifle', 'Bulletproof Plate', 'Body Armor', 'Armored SUV', 'Shank');
  insert into setup_items (player_id, setup, item_id, qty) select rook, s, id, 1 from item_defs, unnest(array['offense', 'defense']::setup_kind[]) s
   where name in ('RPG', 'Sniper Rifle', 'Bulletproof Plate', 'Body Armor', 'Armored SUV');
  insert into setup_items (player_id, setup, item_id, qty) select rook, 'jail', id, 1 from item_defs where name = 'Shank';

  -- latest fights on Home: three wins from the last couple of hours (none on Rook, so the preview has no hits this hour)
  delete from fights where (attacker_id = hero or defender_id = hero or attacker_id = rook or defender_id = rook) and created_at > now() - interval '3 hours';
  insert into fights (attacker_id, defender_id, attacker_dmg, defender_dmg, cash_taken, winner_id, created_at) values
    (hero, (select id from auth.users where email = 'bot04@demo.local'), 34, 9, 28650, hero, now() - interval '9 minutes'),
    ((select id from auth.users where email = 'bot20@demo.local'), hero, 7, 31, 12400, hero, now() - interval '48 minutes'),
    (hero, (select id from auth.users where email = 'bot15@demo.local'), 29, 11, 19800, hero, now() - interval '2 hours');

  -- the crew page's fight record
  delete from crew_fights where attacker_crew = crew_a or defender_crew = crew_a;
  insert into crew_fights (attacker_crew, defender_crew, started_by, attack_power, defense_power, won, cash_taken, created_at) values
    (crew_a, crew_b, hero, 1120, 910, true, 38400, now() - interval '5 hours'),
    (crew_a, crew_c, mates[2], 1085, 1010, true, 21900, now() - interval '1 day'),
    (crew_b, crew_a, rook, 960, 1004, false, 31050, now() - interval '2 days'),
    (crew_a, crew_b, mates[1], 990, 1060, false, 0, now() - interval '3 days');

  -- "While you were away"
  delete from activity where player_id = hero;
  insert into activity (player_id, kind, actor_id, crew_id, block_id, data, seen, created_at, updated_at) values
    (hero, 'attacked', (select id from auth.users where email = 'bot20@demo.local'), null, null, '{"n":1,"held":1,"cash_won":12400}', false, now() - interval '48 minutes', now() - interval '48 minutes'),
    (hero, 'sold', (select id from auth.users where email = 'bot23@demo.local'), null, null, '{"units":150,"commodity":"dust","cash":30450}', false, now() - interval '70 minutes', now() - interval '70 minutes'),
    (hero, 'block_taken', mates[1], crew_b, (select b.id from blocks b join hoods h on h.id = b.hood_id where h.gy = 1 and h.gx = 3 and b.slot = 2), '{}', false, now() - interval '3 hours', now() - interval '3 hours');

  -- last week's boards: gold stripes on Fights and Turf
  delete from accolade_events where player_id = hero and created_at < date_trunc('week', now() at time zone 'utc') at time zone 'utc';
  insert into accolade_events (player_id, kind, amount, created_at)
    select hero, 'fight_win', 1, date_trunc('week', now() at time zone 'utc') at time zone 'utc' - interval '3 days' from generate_series(1, 400);
  insert into accolade_events (player_id, kind, amount, created_at)
    select hero, 'turf', 1, date_trunc('week', now() at time zone 'utc') at time zone 'utc' - interval '4 days' from generate_series(1, 9);

  -- a market with prices, trades and buy orders from other players
  delete from buy_orders where buyer_id <> hero;
  insert into buy_orders (buyer_id, commodity, qty, unit_price, expires_at) values
    ((select id from auth.users where email = 'bot13@demo.local'), 'pills', 120, 640, now() + interval '31 hours'),
    ((select id from auth.users where email = 'bot09@demo.local'), 'dust', 600, 205, now() + interval '20 hours'),
    ((select id from auth.users where email = 'bot22@demo.local'), 'herb', 2000, 58, now() + interval '9 hours');
  delete from market_trades;
  insert into market_trades (commodity, units, unit_price, buyer_id, seller_id, via, created_at)
    select c, 25 * (1 + (g % 7)), (case c when 'herb' then 60 when 'dust' then 200 else 600 end * (0.9 + (g % 5) * 0.05))::int,
           (select id from auth.users where email = format('bot%s@demo.local', lpad((2 + g % 22)::text, 2, '0'))), hero, 'listing',
           now() - (g * interval '47 minutes')
      from generate_series(1, 27) g, lateral (select (array['herb', 'dust', 'pills'])[1 + g % 3] c) x;
end $$;`

/** Width, height and colour type straight from the PNG's IHDR chunk. */
function pngInfo(file) {
  const b = fs.readFileSync(file)
  if (b.toString('latin1', 1, 4) !== 'PNG' || b.toString('latin1', 12, 16) !== 'IHDR') throw new Error(`${file} is not a PNG`)
  return { width: b.readUInt32BE(16), height: b.readUInt32BE(20), colorType: b[25] }
}

const browser = await chromium.launch({ executablePath: process.env.CHROME || '/opt/pw-browsers/chromium' })
const errors = []
try {
  for (const set of SETS) {
    await db.query(POLISH)
    const { rows: [ids] } = await db.query(`select (select id from auth.users where email = 'bot07@demo.local') rook,
      (select crew_id from profiles p join auth.users u on u.id = p.id where u.email = 'bot01@demo.local') crew`)
    fs.mkdirSync(path.join(ROOT, set.dir), { recursive: true })
    const ctx = await browser.newContext({ viewport: set.viewport, deviceScaleFactor: 3, isMobile: true, hasTouch: true })
    const p = await ctx.newPage()
    p.on('pageerror', e => errors.push(`${set.name}: ${e.message}`))
    p.on('dialog', d => d.dismiss())
    await p.goto(BASE)
    await p.getByLabel('Email').fill('bot01@demo.local')
    await p.getByLabel('Password').fill('secret123')
    await p.getByRole('button', { name: 'Sign In' }).click()
    await p.locator('.topbar').waitFor()

    const screens = [
      { file: '01-home', path: '/', ready: '.away .row' },
      { file: '02-actions', path: '/actions', ready: '.row.action',
        // the reputation jobs (the cash ladder's names lean on crime, and store screenshots have to pass for 4+, guideline 2.3.8),
        // after a cash job and a reputation job, so the session tally and a result on the row show the way they do mid-session
        prep: async () => {
          await p.locator('.row.action .doit').first().click()
          await p.locator('.action-result').waitFor()
          await p.getByRole('button', { name: 'Reputation' }).click()
          await p.locator('.row.action .doit').first().click()
          await p.locator('.action-result').waitFor()
        } },
      { file: '03-economy', path: '/economy', ready: '.card .fill' },
      // Browse opens on prices and the offers, so no scrolling needed any more
      { file: '04-market', path: '/economy?tab=market', ready: '.order-row' },
      { file: '05-fight', path: `/player/${ids.rook}`, ready: '.odds-box' },
      { file: '06-territory', path: '/territory', ready: '.hoodgrid' },
      { file: '07-crew', path: `/crew/${ids.crew}`, ready: '.stat' },
      { file: '08-profile', path: '/profile', ready: '.row.link' },
    ]
    for (const s of screens) {
      await p.goto(BASE + s.path)
      await p.locator('.topbar').waitFor()
      await p.locator(s.ready).first().waitFor()
      // nothing still loading and no toast over the screen
      await p.waitForFunction(() => !document.querySelector('.spin, .toast'))
      if (s.prep) await s.prep()
      await p.waitForTimeout(400)
      const file = `${set.dir}/${s.file}.png`
      await p.screenshot({ path: path.join(ROOT, file) })
      const { width, height, colorType } = pngInfo(path.join(ROOT, file))
      const want = [set.viewport.width * 3, set.viewport.height * 3]
      if (width !== want[0] || height !== want[1]) errors.push(`${file} is ${width}×${height}, want ${want.join('×')}`)
      // App Store Connect turns down screenshots with an alpha channel
      if (colorType !== 2) errors.push(`${file} is PNG colour type ${colorType}, want 2 (RGB, no alpha)`)
      console.log(`${file} ${width}×${height}${colorType === 2 ? ' RGB' : ''}`)
    }
    await ctx.close()
  }
} finally {
  await browser.close()
  await db.end()
}
if (errors.length) { console.error(errors.join('\n')); process.exitCode = 1 }
