// Browser walkthrough of the campaign (Season 1, components/Marcus.tsx + lib/gate.ts): a brand-new player sees Marcus
// instead of Getting Started, the city's tabs are locked until his missions open them, and missions 1 to 6 play
// through the card: look at the hood, work three jobs, arm up, bank, grow, fight, move product, hire thugs, take block 1,
// collect. Each claim pays and unlocks.
// Starts its own season and ends it after, so the other suites run with no season (every tab open).
// Usage (local stack running): node scripts/e2e-campaign.mjs
import { chromium } from 'playwright'
import pg from 'pg'
const db = new pg.Pool({ host: 'localhost', port: Number(process.env.PGPORT || 54329), user: 'postgres', database: 'cartel' })

const BASE = process.env.BASE || 'http://127.0.0.1:5173'
const SHOTS = process.env.SHOTS || '/tmp/claude-0/shots'
const browser = await chromium.launch({ executablePath: process.env.CHROME || '/opt/pw-browsers/chromium' })
const errors = []
let page = null
const RUN = Date.now().toString(36).slice(-4)
const N = (base) => `${base}${RUN}`
const one = async (sql, args = []) => (await db.query(sql, args)).rows[0]

// a season of this test's own (deleted at the end; the hood and mission rows go with it)
const season = (await one(`insert into seasons (name, starts_at, ends_at, home_businesses, home_defenders)
  values ('E2E Season', now(), now() + interval '1 day', (select array_agg(code) from (select code from business_defs order by random() limit 6) x), array[1000, 150000, 500000, 1000000, 2500000, 5000000, 10000000]) returning id`)).id
try {
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 })
  const p = await ctx.newPage()
  page = p
  p.on('pageerror', e => errors.push(e.message))
  p.on('dialog', d => d.accept())
  await p.goto(BASE)
  await p.getByRole('button', { name: 'New Player' }).click()
  await p.getByLabel('Street name').fill(N('Rook'))
  await p.getByLabel('Email').fill(`rook${RUN}-${Date.now()}@test.local`)
  await p.getByLabel('Password').fill('secret123')
  await p.getByRole('button', { name: 'Enter the City' }).click()
  await p.locator('.topbar').waitFor()
  const me = (await one('select id from profiles where name = $1', [N('Rook')])).id
  const mission = async () => (await one(`select key from mission_defs d where not exists (select 1 from missions m where m.player_id = $1 and m.key = d.key and m.claimed_at is not null) order by seq limit 1`, [me])).key
  const claim = async (key, pays) => {
    await p.locator(`#mission-${key}.marcus.complete`).waitFor().catch(() => { throw new Error(`${key}: the card never flipped to complete (${p.url()})`) })
    await p.locator(`#mission-${key}`).getByRole('button', { name: /^Claim/ }).click()
    await p.locator('.toast', { hasText: pays }).waitFor()
    await p.locator(`#mission-${key}`).waitFor({ state: 'detached' })   // the next card is in: the claim landed
    const row = await one('select claimed_at from missions where player_id = $1 and key = $2', [me, key])
    if (!row?.claimed_at) throw new Error(`${key} claimed`)
  }

  // 1. Marcus, not the checklist; everything but Home and Chat locked
  await p.locator('.marcus').waitFor()
  if (await p.locator('.getting-started').count()) throw new Error('Getting Started gives way to Marcus')
  await p.getByText('Boss. The city got reset.').waitFor()
  for (const t of ['Actions', 'Economy', 'Fight', 'Services']) await p.getByRole('link', { name: `${t}, locked` }).waitFor()
  await p.screenshot({ path: `${SHOTS}/campaign-1.png` })
  await p.getByRole('link', { name: 'Actions, locked' }).click()
  await p.locator('.toast', { hasText: 'Not yet, boss' }).waitFor()
  if (!p.url().endsWith('/')) throw new Error('a locked tab stays put')
  await p.goto(`${BASE}/items`)
  await p.locator('.locked-screen').waitFor()
  await p.getByRole('link', { name: 'Back to Home' }).click()
  await p.locator('.marcus').waitFor()
  // a profile stays open (it's where chat and the forum lead); only its Attack is locked, with Marcus's line
  const other = (await one('select id from profiles where id <> $1 and not is_bot order by random() limit 1', [me])).id
  await p.goto(`${BASE}/player/${other}`)
  await p.getByRole('button', { name: '⚔️ Attack' }).waitFor()
  if (!(await p.getByRole('button', { name: '⚔️ Attack' }).isDisabled())) throw new Error('Attack is locked until First Blood')
  await p.getByText('Not yet, boss').waitFor()
  await p.getByRole('button', { name: '💬 Chat' }).waitFor()
  await p.goto(BASE)
  await p.locator('.marcus').waitFor()
  await p.getByText('Look at your six blocks').waitFor()   // the objective line, not the button's words
  // the hood sits on Territory, open from the start; looking at it is the mission. Block 1 is held by $1k of muscle
  // (this season's values), and the player has no thugs yet
  await p.getByRole('link', { name: 'Open Your Hood' }).click()
  await p.locator('.hood-grid').waitFor()
  if (!p.url().includes('/territory?focus=hood')) throw new Error('the hood is on Territory: ' + p.url())
  await p.getByRole('button', { name: /^Block 1, .*held by 1 thug and 1 enforcer, resistance 70, next/ }).waitFor()
  await p.getByText('You have 0 thugs and 0 mercs').waitFor()
  await p.getByRole('button', { name: '‹ Back' }).click()
  await claim('six_blocks', '+$500')

  // 2. work: three jobs, the progress on the card; Actions opens with the mission
  if ((await mission()) !== 'work') throw new Error('mission 2 is Work')
  await p.locator('.tabbar a[href="/actions"]:not(.locked)').waitFor()
  await p.getByRole('link', { name: 'Go to Actions' }).click()
  await p.locator('.row.action').first().waitFor()
  for (let i = 0; i < 3; i++) { await p.getByRole('button', { name: 'Do It' }).first().click(); await p.locator('.toast').first().waitFor(); await p.waitForTimeout(600) }
  await p.goto(BASE)
  await claim('work', '+$1,500')

  // 3. get armed: the shop opens, a bat makes 28
  if ((await mission()) !== 'get_armed') throw new Error('mission 3 is Get Armed')
  await p.locator('.quick a[href="/items"]:not(.locked)').waitFor()   // the Home tile unlocked
  await p.getByRole('link', { name: 'Open the Shop' }).click()
  await p.locator('.row', { hasText: 'Baseball Bat' }).waitFor({ timeout: 10000 }).catch(async () => { await p.screenshot({ path: `${SHOTS}/campaign-shop-fail.png` }); throw new Error('the shop opens on weapons: ' + p.url()) })
  await p.locator('.row', { hasText: 'Baseball Bat' }).getByRole('button', { name: /\$2,000/ }).click()
  await p.locator('.toast', { hasText: /Bought .*Baseball Bat and equipped/ }).waitFor()   // a buy equips what fits
  await p.goto(BASE)
  await claim('get_armed', '+$2,000')

  // 4. bank it: a deposit; diamonds as the reward; Services and the Casino open
  if ((await mission()) !== 'bank_it') throw new Error('mission 4 is Bank It')
  await p.getByRole('link', { name: 'Go to Services' }).click()
  await p.getByLabel('Amount to deposit or withdraw').fill('100')
  await p.getByRole('button', { name: 'Deposit' }).click()
  await p.locator('.toast', { hasText: 'Banked' }).waitFor()
  await p.goto(BASE)
  const dia = (await one('select diamonds from profiles where id = $1', [me])).diamonds
  await claim('bank_it', '💎10')
  if ((await one('select diamonds from profiles where id = $1', [me])).diamonds !== dia + 10) throw new Error('ten diamonds')
  await p.locator('.quick a[href="/casino"]:not(.locked)').waitFor()
  await p.getByRole('link', { name: 'Fight, locked' }).waitFor()

  // 5–7 grow, first blood, move product: met from state, claimed in a row
  await db.query(`update profiles set fights_won = greatest(fights_won, 1), imports = greatest(imports, 10) where id = $1`, [me])
  await db.query(`insert into grow_houses (player_id, commodity) select $1, 'herb' where not exists (select 1 from grow_houses where player_id = $1)`, [me]).catch(() => {})
  await p.reload(); await p.locator('.marcus').waitFor()
  if ((await mission()) !== 'grow') throw new Error('mission 5 is Grow')
  await claim('grow', '+$3,000')
  await claim('first_blood', '+$3,000')
  await claim('move_product', '+$4,000')

  // 8. hire muscle: thirty thugs from Services; the card counts them
  if ((await mission()) !== 'hire_muscle') throw new Error('mission 8 is Hire Muscle')
  await p.locator('.marcus:not(.complete)').getByText('0 of 30').waitFor()
  await db.query(`update profiles set cash = greatest(cash, 100000) where id = $1`, [me])
  await p.getByRole('link', { name: 'Go to Services' }).click()
  await p.locator('#hoodlums').waitFor()
  if (!p.url().includes('focus=hoodlums')) throw new Error('the mission lands on the hoodlums card: ' + p.url())
  await db.query(`insert into player_hoodlums (player_id, code, qty) values ($1, 'thug', 30) on conflict (player_id, code) do update set qty = 30`, [me])
  await p.goto(BASE); await p.locator('.marcus').waitFor()
  await claim('hire_muscle', '+$5,000')

  // 9. block one: thirty thugs (300 × 0.9 = 270) against 70; the card flips
  if ((await mission()) !== 'block_one') throw new Error('mission 9 is Block One')
  await p.getByRole('link', { name: 'Open Your Hood' }).click()
  await p.locator('.hood-grid').waitFor()
  await p.getByRole('button', { name: 'Everything' }).click()
  await p.getByRole('button', { name: /^Attack · 300 vs 70 · 3 stamina/ }).click()
  await p.locator('.attack-result', { hasText: 'Block 1 is ours.' }).waitFor()
  await p.getByRole('button', { name: /^Block 1, .*yours, level 1/ }).waitFor()
  await p.screenshot({ path: `${SHOTS}/campaign-2.png` })
  await p.getByRole('button', { name: '‹ Back' }).click()
  await claim('block_one', '+$10,000')

  // 10. open for business: cash waits on the taken block once an hour has passed
  if ((await mission()) !== 'open_for_business') throw new Error('mission 10 is Open for Business')
  await db.query(`update home_blocks set collected_at = now() - interval '6 hours' where player_id = $1 and slot = 1`, [me])
  await p.getByRole('link', { name: 'Open Your Hood' }).click()
  await p.getByRole('button', { name: /^Block 1, /}).click()
  await p.getByRole('button', { name: /^Collect · \$375/ }).click()
  await p.locator('.toast', { hasText: 'Collected $375' }).waitFor()
  await p.getByRole('button', { name: '‹ Back' }).click()
  await claim('open_for_business', '+$2,000')
  // the log shows ten done and the eleventh open; the board has this player on it
  await p.goto(`${BASE}/missions`)
  await p.locator('.mission.now', { hasText: 'Build It Up' }).waitFor()
  if ((await p.locator('.mission.done').count()) !== 10) throw new Error('ten done in the log')
  await p.locator('.season-board .row.me', { hasText: '1 of 6 blocks · 10 of 16' }).waitFor()
  await p.screenshot({ path: `${SHOTS}/campaign-log.png`, fullPage: true })

  if (errors.length) throw new Error(errors.join('\n'))
  console.log('e2e-campaign PASSED: Marcus replaces the checklist, the gate holds and opens, missions 1-10 claim and pay')
} catch (e) {
  console.error('e2e-campaign FAILED:', e.message)
  if (page) await page.screenshot({ path: `${SHOTS}/campaign-fail.png`, fullPage: true }).catch(() => {})
  process.exitCode = 1
} finally {
  await browser.close()
  await db.query('delete from seasons where id = $1', [season]).catch(() => {})
  await db.end()
}
