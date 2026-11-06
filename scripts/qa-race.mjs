// Phase 6 QA: the same spend fired many times at once, the way a double tap, a retried request or two open tabs
// would send it. Each case gives the player exactly enough for one, fires 12 copies on 12 connections at the same
// moment, and checks that one went through (or as many as the stake allows) and nothing went negative or appeared
// from nowhere. Needs the local database (scripts/local-db.sh reset); makes its own two players.
// Usage: node scripts/qa-race.mjs
import pg from 'pg'

const N = 12
const ONE = 'f6f6f6f6-0006-4000-8000-000000000001'
const TWO = 'f6f6f6f6-0006-4000-8000-000000000002'
const db = new pg.Pool({ host: process.env.PGHOST || 'localhost', port: Number(process.env.PGPORT || 54329), user: 'postgres', database: 'cartel', max: N + 2 })
const q = async (sql, args) => (await db.query(sql, args)).rows

await q(`insert into auth.users (id, raw_user_meta_data) values ($1, '{"name":"QaOne"}'), ($2, '{"name":"QaTwo"}') on conflict do nothing`, [ONE, TWO])

// put both players back to a known state, then apply the case's own stake
async function reset(extra = '') {
  await q(`update profiles set cash = 0, bank = 0, diamonds = 0, heat = 0, stamina = stamina_max, health = health_max,
            in_hospital = false, jail_until = null, immune_until = now() - interval '1 day', drop_crates = 0 ${extra} where id in ($1, $2)`, [ONE, TWO])
  await q(`delete from inventory where player_id in ($1, $2)`, [ONE, TWO])
  await q(`delete from hustlers where player_id in ($1, $2)`, [ONE, TWO])
}

// N copies of one call as `who`, each on its own connection, released together
async function fire(who, call) {
  const clients = await Promise.all(Array.from({ length: N }, () => db.connect()))
  try {
    await Promise.all(clients.map(c => c.query(`select set_config('request.jwt.claims', $1, false)`, [JSON.stringify({ sub: who, role: 'authenticated' })])))
    const res = await Promise.allSettled(clients.map(c => c.query(`select ${call} as r`)))
    return { ok: res.filter(r => r.status === 'fulfilled').length, errors: [...new Set(res.filter(r => r.status === 'rejected').map(r => r.reason.message))] }
  } finally { clients.forEach(c => c.release()) }
}

const state = async () => (await q(`select id, cash, bank, diamonds, drop_crates from profiles where id in ($1, $2) order by id`, [ONE, TWO]))
  .reduce((m, r) => ({ ...m, [r.id === ONE ? 'one' : 'two']: { cash: +r.cash, bank: +r.bank, diamonds: +r.diamonds, crates: r.drop_crates } }), {})

const cases = [
  { name: 'withdraw the whole bank', stake: `bank = 1000`, call: `bank_withdraw(1000)`, max: 1,
    check: s => s.one.bank === 0 && s.one.cash === 1000 },
  { name: 'deposit all the cash', stake: `cash = 1000`, call: `bank_deposit(1000)`, max: 1,
    check: s => s.one.cash === 0 && s.one.bank > 0 && s.one.bank <= 1000 },
  { name: 'send all the cash', stake: `cash = 1000`, call: `send_cash('${TWO}', 1000)`, max: 1,
    check: s => s.one.cash >= 0 && s.two.cash <= 1000 && s.one.cash + s.two.cash <= 1000 },
  { name: 'send all the diamonds', stake: `diamonds = 10`, call: `send_diamonds('${TWO}', 10)`, max: 1,
    check: s => s.one.diamonds === 0 && s.two.diamonds === 10 },
  { name: 'buy one item with exactly enough', stake: `cash = (select price from item_defs where id = 1)`, call: `buy_item(1, 1)`, max: 1,
    check: async s => s.one.cash === 0 && (await q(`select coalesce(sum(qty), 0)::int n from inventory where player_id = $1`, [ONE]))[0].n === 1 },
  { name: 'sell the only item', stake: '', setup: () => q(`insert into inventory (player_id, item_id, qty) values ($1, 1, 1)`, [ONE]), call: `sell_item(1, 1)`, max: 1,
    check: async s => (await q(`select coalesce(sum(qty), 0)::int n from inventory where player_id = $1`, [ONE]))[0].n === 0 && s.one.cash <= (await q(`select price from item_defs where id = 1`))[0].price },
  // a win pays for the next spin, so more than one can go through; each one that did is in the ledger, and the cash
  // left is the $100 plus what those rounds paid minus what they cost
  { name: 'spin the slots with one bet on hand', stake: `cash = 100`, call: `slots_spin(100)`, max: N,
    setup: () => q(`delete from casino_bets where player_id = $1`, [ONE]),
    check: async (s, _b, r) => { const l = (await q(`select count(*)::int n, coalesce(sum(payout - wager), 0)::int net from casino_bets where player_id = $1`, [ONE]))[0]
      return l.n === r.ok && s.one.cash === 100 + l.net } },
  { name: 'refill stamina with exactly enough diamonds', stake: `diamonds = 10, stamina = 0`, call: `refill('stamina', 'diamonds')`, max: 1,
    check: s => s.one.diamonds >= 0 },
  { name: 'open the only crate', stake: `drop_crates = 1`, call: `open_crate()`, max: 1,
    check: s => s.one.crates === 0 },
  // the Personal Hood: one block's cash collected 12 times at once pays once; 12 attacks on the next block with 2
  // stamina clear it once and cost 2 stamina (the rest are refused for stamina or "already yours")
  { name: 'collect the hood 12 times', stake: `cash = 0`, call: `home_collect()`, max: 1,
    setup: async () => { await q(`update seasons set home_defenders = array[1,1,1,1,1,1,1]`)
      await q(`insert into home_hoods (player_id, season_id) select $1, id from seasons on conflict do nothing`, [ONE])
      await q(`insert into home_blocks (player_id, season_id, slot, business, cleared_at, collected_at) select $1, s.id, 1, s.home_businesses[1], now(), now() - interval '24 hours' from seasons s on conflict (player_id, season_id, slot) do update set cleared_at = now(), collected_at = now() - interval '24 hours', level = 1`, [ONE]) },
    check: async s => s.one.cash === 1500 && (await q(`select collects from home_hoods where player_id = $1`, [ONE]))[0].collects === 1 },
  { name: 'attack the next block 12 times', stake: `stamina = 2, health = 100`, call: `home_attack(2)`, max: 1,
    check: async () => { const r = (await q(`select stamina, (select count(*)::int from home_blocks where player_id = $1 and cleared_at is not null) n from profiles where id = $1`, [ONE]))[0]; return r.stamina === 0 && r.n === 2 } },
  { name: 'collect one trip of hustlers', stake: '', call: `collect_hustlers()`, max: N,
    setup: () => q(`insert into hustlers (player_id, commodity, count, units, cash_due, departs_at, returns_at) values ($1, 'herb', 1, 10, 777, now() - interval '2 hours', now() - interval '1 minute')`, [ONE]),
    check: s => s.one.cash === 777 },
]

// the hood cases need a running season; an admin starts one if there isn't
await q(`update profiles set is_admin = true where id = $1`, [ONE])
if (!(await q(`select 1 from seasons where starts_at <= now() and ends_at > now()`)).length) {
  const c = await db.connect()
  try { await c.query(`select set_config('request.jwt.claims', $1, false)`, [JSON.stringify({ sub: ONE })]); await c.query(`select season_start('Race')`) } finally { c.release() }
}

const failures = []
for (const c of cases) {
  await reset()
  if (c.stake) await q(`update profiles set ${c.stake} where id = $1`, [ONE])
  if (c.setup) await c.setup()
  const before = await state()
  const r = await fire(ONE, c.call)
  const after = await state()
  // collect_hustlers answers fine with nothing to collect, so only the money says whether it paid twice
  const spentOk = c.max === N || r.ok <= c.max
  const neg = Object.values(after).some(p => p.cash < 0 || p.bank < 0 || p.diamonds < 0 || p.crates < 0)
  const good = spentOk && !neg && await c.check(after, before, r)
  console.log(`${good ? 'ok  ' : 'FAIL'} ${c.name.padEnd(44)} ${r.ok}/${N} went through  ${JSON.stringify(after.one)} ${r.errors.slice(0, 2).join(' / ')}`)
  if (!good) failures.push(c.name)
}
await reset()
await db.end()
if (failures.length) { console.error(`QA RACE FAILED: ${failures.join(', ')}`); process.exit(1) }
console.log('QA RACE PASSED')
