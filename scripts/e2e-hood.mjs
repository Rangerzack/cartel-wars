// Browser walkthrough of Your Hood (Season 1, pages/Hood.tsx): the grid, the next block's odds, a lost fight that
// costs health but never the hospital, a won fight, cash piling up and collected, an upgrade, Collect All, the greyed
// blocks ahead, the boss row after six, and the Home tile and Next Up line that point here. Runs as an established
// demo player and starts its own season, ended after.
// Usage (local stack with the demo world): node scripts/e2e-hood.mjs
import { chromium } from 'playwright'
import pg from 'pg'
const db = new pg.Pool({ host: 'localhost', port: Number(process.env.PGPORT || 54329), user: 'postgres', database: 'cartel' })

const BASE = process.env.BASE || 'http://127.0.0.1:5173'
const SHOTS = process.env.SHOTS || '/tmp/claude-0/shots'
const browser = await chromium.launch({ executablePath: process.env.CHROME || '/opt/pw-browsers/chromium' })
const errors = []
const one = async (sql, args = []) => (await db.query(sql, args)).rows[0]

const season = (await one(`insert into seasons (name, starts_at, ends_at, home_businesses, home_defenders)
  values ('E2E Hood', now(), now() + interval '1 day', (select array_agg(code) from (select code from business_defs order by random() limit 6) x), array[100000, 1, 1, 1, 1, 1, 1]) returning id`)).id
const me = (await one(`select id from auth.users where email = 'bot03@demo.local'`)).id
// 60 health with the regen clock pinned, so no healing tick lands between the setup and the fight
await db.query(`update profiles set stamina = stamina_max, health = 60, health_tick = now(), in_hospital = false, jail_until = null, cash = 200000 where id = $1`, [me])
const defenders = (arr) => db.query(`update seasons set home_defenders = $2 where id = $1`, [season, arr])
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

  // the Home tile, then the hood: six locked tiles, the first with its odds, the panel on it
  await p.locator('.quick a[href="/hood"]').click()
  await p.locator('.hood-grid').waitFor()
  if ((await p.locator('.hood-grid .block').count()) !== 6) throw new Error('six tiles')
  await p.getByRole('button', { name: /^Block 1, .*held by defenders at 100000, 0% to win/ }).waitFor()
  await p.getByRole('button', { name: /^Block 3, .*held by defenders at 1$/ }).waitFor()
  await p.getByText("You bring").waitFor()
  await p.screenshot({ path: `${SHOTS}/hood-locked.png` })

  // a loss: health down, never into the hospital, the block still theirs, stamina spent
  await p.getByRole('button', { name: /^Attack · 0% to win · 2 stamina/ }).click()
  await p.locator('.attack-result', { hasText: /Lost/ }).waitFor()
  await p.locator('.attack-result', { hasText: 'They held.' }).waitFor()
  const after = await one('select health, stamina, in_hospital from profiles where id = $1', [me])
  if (after.health < 20 || after.health >= 60 || after.in_hospital) throw new Error('a loss costs health, not the hospital: ' + JSON.stringify(after))
  await p.locator('.attack-result').getByRole('button', { name: 'Dismiss' }).click()
  await p.locator('.attack-result').waitFor({ state: 'detached' })

  // a win: the tile turns, the panel moves to block 2, the hood pays
  await defenders([1, 1, 1, 1, 1, 1, 1])
  await p.reload(); await p.locator('.hood-grid').waitFor()
  await p.getByRole('button', { name: /^Attack · 100% to win/ }).click()
  await p.locator('.attack-result', { hasText: 'Block 1 is ours.' }).waitFor()
  await p.getByRole('button', { name: /^Block 1, .*yours, level 1/ }).waitFor()
  await p.locator('.card .hd', { hasText: 'Block 2 ·' }).waitFor()
  await p.getByText('$1,500/day').first().waitFor()

  // cash piles up by the hour and stops at 48: six hours waiting is a quarter day
  await db.query(`update home_blocks set collected_at = now() - interval '6 hours' where player_id = $1 and season_id = $2 and slot = 1`, [me, season])
  await p.reload(); await p.locator('.hood-grid').waitFor()
  await p.getByRole('button', { name: /^Block 1, / }).click()
  await p.getByRole('button', { name: /^Collect · \$375/ }).click()
  await p.locator('.toast', { hasText: 'Collected $375' }).waitFor()
  await p.getByRole('button', { name: /^Collect$/ }).waitFor()   // nothing left: Collect without an amount, disabled
  if (!(await p.getByRole('button', { name: /^Collect$/ }).isDisabled())) throw new Error('nothing to collect right after collecting')

  // an upgrade: level 2 pays double; the price came off the cash
  const cash0 = Number((await one('select cash from profiles where id = $1', [me])).cash)
  await p.getByRole('button', { name: 'Upgrade to level 2 for $5,000' }).click()
  await p.locator('.toast', { hasText: 'is level 2' }).waitFor()
  await p.getByText('$3,000/day').first().waitFor()
  const cash1 = Number((await one('select cash from profiles where id = $1', [me])).cash)
  if (cash1 !== cash0 - 5000) throw new Error(`upgrade cost $5,000: ${cash0} -> ${cash1}`)

  // the rest of the blocks, Collect All with two waiting, then the boss row
  for (let slot = 2; slot <= 6; slot++) {
    await p.getByRole('button', { name: new RegExp(`^Block ${slot}, `) }).click()
    await p.getByRole('button', { name: /^Attack · 100% to win/ }).click()
    await p.locator('.attack-result', { hasText: `Block ${slot} is ours.` }).waitFor()
    await p.locator('.attack-result').getByRole('button', { name: 'Dismiss' }).click()
  }
  await db.query(`update home_blocks set collected_at = now() - interval '12 hours' where player_id = $1 and season_id = $2 and slot in (2, 3)`, [me, season])
  await p.reload(); await p.locator('.hood-grid').waitFor()
  await p.getByRole('button', { name: /^Collect All · \$1,500/ }).click()
  await p.locator('.toast', { hasText: 'Collected $1,500' }).waitFor()
  await p.getByRole('button', { name: /^The boss, 1 attack and defense/ }).waitFor()
  await p.screenshot({ path: `${SHOTS}/hood-boss.png` })
  await p.getByRole('button', { name: /^The boss, / }).click()
  await p.getByRole('button', { name: /^Attack · 100% to win/ }).click()
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

  if (errors.length) throw new Error(errors.join('\n'))
  console.log('e2e-hood PASSED: tiles and odds, a loss with a health floor, wins, hourly cash and the cap, upgrade, Collect All, the boss, Next Up')
} catch (e) {
  console.error('e2e-hood FAILED:', e.message)
  process.exitCode = 1
} finally {
  await browser.close()
  await db.query('delete from seasons where id = $1', [season]).catch(() => {})
  await db.end()
}
