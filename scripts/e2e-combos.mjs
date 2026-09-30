// Browser walkthrough for combos: completing one from the shop, picking between two, the hidden defense combo in
// the fight preview, the counter showing in the fight result, intel on the next look, the Combos tab (wheel, city
// board, every combo), the defender's log and activity, thugs' combos, and the jail wall.
// Usage (local stack running): node scripts/e2e-combos.mjs [--shots dir]
import { chromium } from 'playwright'
import fs from 'node:fs'
import pg from 'pg'
const db = new pg.Pool({ host: 'localhost', port: Number(process.env.PGPORT || 54329), user: 'postgres', database: 'cartel' })

const BASE = process.env.BASE || 'http://127.0.0.1:5173'
const shots = process.argv.includes('--shots') ? process.argv[process.argv.indexOf('--shots') + 1] : null
if (shots) fs.mkdirSync(shots, { recursive: true })
const browser = await chromium.launch({ executablePath: process.env.CHROME || '/opt/pw-browsers/chromium' })
const errors = []
const RUN = Date.now().toString(36).slice(-4)
const N = (base) => `${base}${RUN}`
let step = 0
let lastPage = null
async function snap(page, name) { if (shots) await page.screenshot({ path: `${shots}/${String(++step).padStart(2, '0')}-${name}.png`, fullPage: true }) }
async function newPlayer(name) {
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 })
  const page = await ctx.newPage()
  lastPage = page
  page.on('pageerror', e => errors.push(`${name}: ${e.message}`))
  page.on('response', r => { if (r.status() === 404) errors.push(`404 ${r.url()}`) })
  page.on('console', m => { if (m.type() === 'error' && !/realtime|websocket|WebSocket|Failed to load resource/i.test(m.text())) errors.push(`${name} console: ${m.text()}`) })
  await page.goto(BASE)
  await page.getByRole('button', { name: 'New Player' }).click()
  await page.getByLabel('Street name').fill(name)
  await page.getByLabel('Email').fill(`${name.toLowerCase()}-${Date.now()}@test.local`)
  await page.getByLabel('Password').fill('secret123')
  await page.getByRole('button', { name: 'Enter the City' }).click()
  await page.locator('.topbar').waitFor()
  return page
}
const one = async (sql, args = []) => (await db.query(sql, args)).rows[0]
async function buy(page, cat, name) {
  await page.goto(`${BASE}/items?tab=shop&cat=${cat}`)
  await page.locator('.row', { has: page.locator('.t', { hasText: new RegExp(`^${name}`) }) }).locator('.btn.gold').click()
  await page.getByText(new RegExp(`Bought ${name}`)).waitFor()
}

try {
  const a = await newPlayer(N('Vince'))
  const aId = (await one('select id from profiles where name = $1', [N('Vince')])).id
  await db.query('update profiles set cash = 2000000 where id = $1', [aId])

  // Uzi + Tactical Vest from the shop (each goes straight into both setups): Spray and Pray
  await buy(a, 'weapon', 'Uzi')
  await a.locator('.row', { hasText: 'Uzi' }).getByText('Spray and Pray').first().waitFor()   // the shop tags the combo
  await buy(a, 'protection', 'Tactical Vest')
  await a.goto(`${BASE}/items?setup=offense`)
  const combo = a.locator('.card', { has: a.locator('.hd', { hasText: /^Combo/ }) })
  await combo.locator('.combo-pill', { hasText: 'Spray and Pray' }).waitFor()
  await combo.getByText(/Blitz.*beats Infantry and Blackout/).waitFor()
  await snap(a, 'setup-combo')

  // add a Sawed-off: the panel says Riot Squad needs a Riot Shield; buy it and pick between the two
  await buy(a, 'weapon', 'Sawed-off Shotgun')
  await a.goto(`${BASE}/items?setup=offense`)
  await combo.getByText('needs a').filter({ hasText: 'Riot Shield' }).waitFor()
  await buy(a, 'protection', 'Riot Shield')
  await a.goto(`${BASE}/items?setup=offense`)
  await combo.getByText('This setup completes 2 combos').waitFor()
  await combo.locator('.combo-pill', { hasText: 'Riot Squad' }).first().waitFor()          // tier 1, first on the list
  await combo.getByRole('button', { name: /Spray and Pray/ }).click()
  await a.getByText('Spray and Pray it is').waitFor()
  if ((await one(`select _active_combo($1, 'offense') c`, [aId])).c !== 'spray_pray') throw new Error('picked combo runs')
  await snap(a, 'setup-pick')

  // the defender: Back Alley (Blackout) on defense — Blitz beats Blackout
  const b = await newPlayer(N('Tuna'))
  const bId = (await one('select id from profiles where name = $1', [N('Tuna')])).id
  await db.query(`insert into inventory (player_id, item_id, qty) select $1, id, 1 from item_defs where name in ('Machete', 'Helmet')`, [bId])
  await db.query(`insert into setup_items (player_id, setup, item_id, qty) select $1, 'defense', id, 1 from item_defs where name in ('Machete', 'Helmet')`, [bId])

  // first look: they run a combo, which one is a secret
  await a.goto(`${BASE}/player/${bId}`)
  const odds = a.locator('.odds-box')
  await odds.locator('.combo-pill.unknown').waitFor()
  await odds.getByText(/you won't know which until you hit them/).waitFor()
  await snap(a, 'preview-unknown')

  // the fight shows both combos and the counter
  await a.getByRole('button', { name: '⚔️ Attack' }).click()
  const modal = a.locator('.modal')
  await modal.locator('.combo-result .combo-pill', { hasText: 'Back Alley' }).waitFor()
  await modal.getByText(/you counter them: your combo rolls 0–10, theirs rolls nothing/).waitFor()
  await snap(a, 'result-counter')
  await modal.getByRole('button', { name: 'Close' }).click()

  // next look: the preview remembers Back Alley
  await a.reload()
  await odds.locator('.combo-pill', { hasText: 'Back Alley' }).waitFor()
  await odds.getByText(/That's what they ran when you hit them/).waitFor()
  await snap(a, 'preview-intel')

  // the Combos tab: the wheel, the city board, and every combo (yours marked)
  await a.goto(`${BASE}/fight?tab=combos`)
  await a.getByText('The counter wheel').waitFor()
  if (await a.locator('.wheel-row').count() !== 5) throw new Error('five styles on the wheel')
  await a.locator('.meta-row').first().waitFor()
  const spray = a.locator('.combo-row', { hasText: 'Spray and Pray' })
  await spray.locator('.pill', { hasText: 'Offense' }).waitFor()
  await spray.locator('.combo-parts .have').first().waitFor()
  const nCombos = Number((await one('select count(*) n from combo_defs')).n)
  if (await a.locator('.combo-row').count() !== nCombos) throw new Error('every combo listed')
  await snap(a, 'combos-tab')

  // the defender sees what hit them: My Fights and Activity
  await b.goto(`${BASE}/fight?tab=log`)
  await b.locator('.combo-vs', { hasText: 'They ran' }).locator('.combo-pill', { hasText: 'Spray and Pray' }).waitFor()
  await b.goto(`${BASE}/activity`)
  await b.getByText(/attacked you with/).first().waitFor()
  await snap(b, 'defender-log')

  // thugs wear their combos openly
  const thug = await one(`select name, _active_combo(id, 'defense') c from profiles where is_bot and _active_combo(id, 'defense') is not null order by bot_level limit 1`)
  if (thug) {
    await a.goto(`${BASE}/fight?tab=thugs`)
    await a.getByRole('button', { name: 'All 200' }).click()
    await a.locator('.thug-row', { has: a.locator('.t', { hasText: new RegExp(`^${thug.name} `) }) }).locator('.combo-pill').waitFor()
  }

  // the jail wall, both ways
  await db.query(`update profiles set jail_until = now() + interval '1 hour' where id = $1`, [aId])
  await a.goto(`${BASE}/player/${bId}`)
  await a.getByText("You're locked up — you can only fight other inmates.").waitFor()
  if (!(await a.getByRole('button', { name: '⚔️ Attack' }).isDisabled())) throw new Error('attack disabled from jail')
  await b.goto(`${BASE}/player/${aId}`)
  await b.getByText("They're locked up — only other inmates can get at them.").waitFor()
  await snap(b, 'jail-wall')
  await db.query('update profiles set jail_until = null where id = $1', [aId])

  console.log('E2E COMBOS PASSED')
} catch (e) {
  console.error('E2E COMBOS FAILED:', e.message)
  if (shots && lastPage) await lastPage.screenshot({ path: `${shots}/FAIL.png`, fullPage: true }).catch(() => {})
  process.exitCode = 1
} finally {
  if (errors.length) { console.error('Page errors:\n' + errors.join('\n')); process.exitCode = 1 }
  await browser.close()
  await db.end()
}
