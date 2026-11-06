// Browser walkthrough of Your Hood on the Territory page (Season 1, components/HoodPanel.tsx): the grid with its
// garrisons, the attack form's verdict, a force too small to fight, a lost fight that bleeds both sides, a won one,
// cash piling up and collected, an upgrade, Collect All, the greyed blocks ahead, the boss after six, and the Home
// tile and Next Up line that point here. Runs as an established demo player and starts its own season with small
// garrisons ($1k of muscle on every block, $2k on the boss), ended after.
// Usage (local stack with the demo world): node scripts/e2e-hood.mjs
import { chromium } from 'playwright'
import pg from 'pg'
const db = new pg.Pool({ host: 'localhost', port: Number(process.env.PGPORT || 54329), user: 'postgres', database: 'cartel' })

const BASE = process.env.BASE || 'http://127.0.0.1:5173'
const SHOTS = process.env.SHOTS || '/tmp/claude-0/shots'
const browser = await chromium.launch({ executablePath: process.env.CHROME || '/opt/pw-browsers/chromium' })
const errors = []
const one = async (sql, args = []) => (await db.query(sql, args)).rows[0]

// $1,000 of muscle = 1 thug and 1 enforcer, resistance 70; the boss at $2,000 = 2 and 1, resistance 80
const season = (await one(`insert into seasons (name, starts_at, ends_at, home_businesses, home_defenders)
  values ('E2E Hood', now(), now() + interval '1 day', (select array_agg(code) from (select code from business_defs order by random() limit 6) x), array[1000, 1000, 1000, 1000, 1000, 1000, 2000]) returning id`)).id
const me = (await one(`select id from auth.users where email = 'bot03@demo.local'`)).id
await db.query(`update profiles set stamina = stamina_max, health = 100, health_tick = now(), in_hospital = false, jail_until = null, cash = 200000 where id = $1`, [me])
await db.query(`insert into player_hoodlums (player_id, code, qty) values ($1, 'thug', 20), ($1, 'mercenary', 0) on conflict (player_id, code) do update set qty = excluded.qty`, [me])
try {
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 })
  const p = await ctx.newPage()
  p.on('pageerror', e => errors.push(e.message))
  p.on('dialog', d => d.accept())
  await p.goto(BASE)
  await p.getByLabel('Email').fill('bot03@demo.local')
  await p.getByLabel('Password').fill('secret123')
  await p.getByRole('button', { name: 'Sign In' }).click()
  await p.locator('.topbar').waitFor()

  // the Home tile lands on the hood inside Territory: six held tiles with their garrisons, the first one next
  await p.locator('.quick a[href="/territory?focus=hood"]').click()
  await p.locator('.hood-grid').waitFor()
  if ((await p.locator('.hood-grid .block').count()) !== 6) throw new Error('six tiles')
  await p.getByRole('button', { name: /^Block 1, .*held by 1 thug and 1 enforcer, resistance 70, next/ }).waitFor()
  await p.getByRole('button', { name: /^Block 3, .*held by 1 thug and 1 enforcer, resistance 70$/ }).waitFor()
  await p.getByText('You have 20 thugs and 0 mercs').waitFor()
  await p.screenshot({ path: `${SHOTS}/hood-locked.png` })

  // the form: "Just enough" picks 8 thugs (80 × 0.9 = 72 > 70); one thug is too small to get a fight; 3 thugs lose
  await p.getByRole('button', { name: 'Just enough' }).click()
  if ((await p.getByLabel('Thugs to send').inputValue()) !== '8') throw new Error('just enough is 8 thugs: ' + await p.getByLabel('Thugs to send').inputValue())
  await p.getByText('Takes the block, whatever the roll.').waitFor()
  await p.getByLabel('Thugs to send').fill('1')
  await p.getByText(/Too small to get a fight/).waitFor()
  if (!(await p.getByRole('button', { name: /^Attack · 10 vs 70/ }).isDisabled())) throw new Error('too small: no attack')
  await p.getByLabel('Thugs to send').fill('3')
  await p.getByText('They hold, but you bleed the garrison for next time.').waitFor()
  await p.getByRole('button', { name: /^Attack · 30 vs 70 · 3 stamina/ }).click()
  await p.locator('.attack-result', { hasText: /Lost/ }).waitFor()
  await p.locator('.attack-result', { hasText: 'They held' }).waitFor()
  const after = await one(`select stamina, (select qty from player_hoodlums where player_id = $1 and code = 'thug') thugs, (select thugs + enforcers from home_blocks where player_id = $1 and season_id = $2 and slot = 1) garrison from profiles where id = $1`, [me, season])
  if (after.thugs !== 19) throw new Error('a lost fight at 30 vs 70 costs 1 thug (half of 3, rounded down): ' + JSON.stringify(after))
  if (after.garrison !== 2) throw new Error('two guards can\'t lose a fraction of one: ' + JSON.stringify(after))
  await p.locator('.attack-result').getByRole('button', { name: 'Dismiss' }).click()
  await p.locator('.attack-result').waitFor({ state: 'detached' })

  // a win: everything you have (19 thugs, 190) against what's left; the tile turns, the panel moves to block 2, the hood pays
  await p.getByRole('button', { name: 'Everything' }).click()
  await p.getByRole('button', { name: /^Attack · 190 vs \d+ · 3 stamina/ }).click()
  await p.locator('.attack-result', { hasText: 'Block 1 is ours.' }).waitFor()
  await p.getByRole('button', { name: /^Block 1, .*yours, level 1/ }).waitFor()
  await p.locator('.card .hd', { hasText: 'Block 2 ·' }).waitFor()
  await p.getByText('$1,500/day').first().waitFor()
  const left = (await one(`select qty from player_hoodlums where player_id = $1 and code = 'thug'`, [me])).qty
  if (left < 14 || left > 17) throw new Error('a won fight at 190 vs ~70 costs about a fifth of the force: ' + left)

  // cash piles up by the hour and stops at 48: six hours waiting is a quarter day
  await db.query(`update home_blocks set collected_at = now() - interval '6 hours' where player_id = $1 and season_id = $2 and slot = 1`, [me, season])
  await p.reload(); await p.locator('.hood-grid').waitFor()
  await p.getByRole('button', { name: /^Block 1, / }).click()
  await p.getByRole('button', { name: /^Collect · \$375/ }).click()
  await p.locator('.toast', { hasText: 'Collected $375' }).waitFor()
  await p.getByRole('button', { name: /^Collect$/ }).waitFor()
  if (!(await p.getByRole('button', { name: /^Collect$/ }).isDisabled())) throw new Error('nothing to collect right after collecting')

  // an upgrade: level 2 pays double; the price came off the cash
  const cash0 = Number((await one('select cash from profiles where id = $1', [me])).cash)
  await p.getByRole('button', { name: 'Upgrade to level 2 for $5,000' }).click()
  await p.locator('.toast', { hasText: 'is level 2' }).waitFor()
  await p.getByText('$3,000/day').first().waitFor()
  const cash1 = Number((await one('select cash from profiles where id = $1', [me])).cash)
  if (cash1 !== cash0 - 5000) throw new Error(`upgrade cost $5,000: ${cash0} -> ${cash1}`)

  // the rest of the blocks with mercs (10 mercs = 600, a sure thing), Collect All with two waiting, then the boss
  await db.query(`update player_hoodlums set qty = 100 where player_id = $1 and code = 'mercenary'`, [me])
  await p.reload(); await p.locator('.hood-grid').waitFor()
  for (let slot = 2; slot <= 6; slot++) {
    await p.getByRole('button', { name: new RegExp(`^Block ${slot}, `) }).click()
    await p.getByLabel('Thugs to send').fill('0')
    await p.getByLabel('Mercenaries to send').fill('10')
    await p.getByRole('button', { name: /^Attack · 600 vs \d+ · 3 stamina/ }).click()
    await p.locator('.attack-result', { hasText: `Block ${slot} is ours.` }).waitFor()
    await p.locator('.attack-result').getByRole('button', { name: 'Dismiss' }).click()
  }
  await db.query(`update home_blocks set collected_at = now() - interval '12 hours' where player_id = $1 and season_id = $2 and slot in (2, 3)`, [me, season])
  await p.reload(); await p.locator('.hood-grid').waitFor()
  await p.getByRole('button', { name: /^Collect All · \$1,500/ }).click()
  await p.locator('.toast', { hasText: 'Collected $1,500' }).waitFor()
  await p.getByRole('button', { name: /^The boss, held by 2 thugs and 1 enforcer, resistance 80/ }).waitFor()
  await p.screenshot({ path: `${SHOTS}/hood-boss.png` })
  await p.getByRole('button', { name: /^The boss, / }).click()
  await p.getByLabel('Thugs to send').fill('0')
  await p.getByLabel('Mercenaries to send').fill('10')
  await p.getByRole('button', { name: /^Attack the Boss · 600 vs 80/ }).click()
  await p.locator('.attack-result', { hasText: 'The boss is down.' }).waitFor()
  await p.locator('.hood-plate').waitFor()
  await p.getByText('$4,500/day').first().waitFor()   // level 2 at +50%
  const income = (await one(`select sum(case when level = 2 then 4500 else 2250 end)::int n from home_blocks where player_id = $1 and season_id = $2`, [me, season])).n
  await p.getByText(`$${income.toLocaleString('en-US')}/day`).first().waitFor()
  await p.screenshot({ path: `${SHOTS}/hood-done.png`, fullPage: true })

  // Next Up on Home says there's cash waiting once there's enough of it
  await db.query(`update home_blocks set collected_at = now() - interval '12 hours' where player_id = $1 and season_id = $2`, [me, season])
  await p.goto(BASE)
  await p.locator('.next-up [data-next="hood"]').waitFor()
  await p.locator('.next-up [data-next="hood"]').getByRole('button', { name: 'Collect' }).click()
  await p.locator('.toast', { hasText: /^Collected \$/ }).waitFor()
  await p.locator('.next-up [data-next="hood"]').waitFor({ state: 'detached' })

  // the old address still lands on the hood
  await p.goto(`${BASE}/hood`)
  await p.locator('.hood-grid').waitFor()
  if (!p.url().includes('/territory?focus=hood')) throw new Error('/hood redirects into Territory: ' + p.url())

  if (errors.length) throw new Error(errors.join('\n'))
  console.log('e2e-hood PASSED: tiles and garrisons, the form and its verdicts, a loss that bleeds both sides, wins, hourly cash and the cap, upgrade, Collect All, the boss, Next Up, the old link')
} catch (e) {
  console.error('e2e-hood FAILED:', e.message)
  process.exitCode = 1
} finally {
  await browser.close()
  await db.query('delete from seasons where id = $1', [season]).catch(() => {})
  await db.end()
}
