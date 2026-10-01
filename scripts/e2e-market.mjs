// Browser walkthrough for the market overhaul: picking a path early (and the level-5 wall without one), Trader
// hustler terms with the street-price push, the Prices board, the 150% listing cap and 5% fee, posting a buy order,
// filling it from another account, the buyer's feed line, cancelling, and drug refills (3 full each, then half the bar).
// Usage (local stack running): node scripts/e2e-market.mjs [--shots dir]
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
  page.on('dialog', d => d.accept())
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
const money = (n) => '$' + Math.round(n).toLocaleString('en-US')
const stock = (id, com, n) => db.query(`insert into storage as st (player_id, commodity, qty) values ($1, $2, $3)
  on conflict (player_id, commodity) do update set qty = excluded.qty`, [id, com, n])
const truck = (id) => db.query(`insert into inventory (player_id, item_id, qty) select $1, id, 1 from item_defs where name = 'Cargo Truck'
  on conflict (player_id, item_id) do update set qty = 1`, [id])

try {
  // calm street so the numbers are predictable
  await db.query('update street_prices sp set wiggle = 0, pressure = 0, pressure_at = now(), wiggle_at = now(), updated_at = now(), price = c.base_price from commodities c where c.code = sp.commodity')

  const a = await newPlayer(N('Lalo'))
  const aId = (await one('select id from profiles where name = $1', [N('Lalo')])).id
  await db.query('update profiles set cash = 5000000, diamonds = 100 where id = $1', [aId])

  // No path yet: the prompt on Economy, and "Not yet" folds the chooser back up
  await a.goto(`${BASE}/economy`)
  await a.getByText('No path yet: you can run grow houses up to level 5').waitFor()
  await a.getByRole('button', { name: 'Choose a path ›' }).click()
  await a.getByRole('button', { name: 'Be a Trader' }).waitFor()
  await a.getByText('with no hire fee (they keep 10%) and sell 10% over street').waitFor()
  await snap(a, 'path-early')
  await a.getByRole('button', { name: 'Not yet' }).click()
  await a.getByRole('button', { name: 'Choose a path ›' }).waitFor()

  // Grow house at level 5: the upgrade stops there without a path
  await a.getByRole('button', { name: 'Build' }).first().click()
  await a.getByText('grow house is up and running').waitFor()
  await db.query('update grow_houses set level = 5 where player_id = $1', [aId])
  await a.reload()
  await a.getByText('Level 5 is as far as you go without a path').waitFor()
  if (!(await a.getByRole('button', { name: /^Upgrade/ }).isDisabled())) throw new Error('upgrade past 5 should be disabled')
  // a house already past it: the pick is due
  await db.query('update grow_houses set level = 6 where player_id = $1', [aId])
  await a.reload()
  await a.getByText('Your grow houses are past level 5').waitFor()
  await snap(a, 'path-due')
  await a.getByRole('button', { name: 'Be a Trader' }).click()
  await a.getByText("You're a Trader").waitFor()

  // Trader hustlers: no fee, a cut, and the batch's push on street
  await stock(aId, 'herb', 5000)
  await a.goto(`${BASE}/economy?tab=hustlers`)
  await a.getByText('Trader terms: no hire fee').waitFor()
  await a.locator('.qty input').fill('100')
  const preview = a.locator('.small', { hasText: 'brings back about' })
  await preview.getByText(/after their \$[\d,]+ cut/).waitFor()
  await a.getByText(/this batch goes at about \$59 a unit before your markup and leaves street at \$58/).waitFor()
  const shown = Number((await preview.locator('b.gold').innerText()).replace(/[$,]/g, ''))
  await snap(a, 'trader-hustle')
  await a.getByRole('button', { name: 'Send Them Out' }).click()
  await a.getByText('100 hustlers out the door with 1,600 units').waitFor()
  const trip = await one('select cash_due from hustlers where player_id = $1', [aId])
  if (Math.abs(Number(trip.cash_due) - shown) > shown * 0.005) throw new Error(`preview ${shown} vs ${trip.cash_due}`)
  const p = await one(`select price, pressure from street_prices where commodity = 'herb'`)
  if (p.price !== 58 || Number(p.pressure) !== 0.032) throw new Error('street pushed: ' + JSON.stringify(p))
  const cash = await one('select cash from profiles where id = $1', [aId])
  if (Number(cash.cash) !== 5000000 - 5000) throw new Error('no hire fee (only the grow house was paid): ' + cash.cash)
  await a.getByText(/street \$58 −3% · flooded, recovering/).waitFor()

  // Marketplace: the Prices board, the 150% cap and the fee
  await truck(aId)
  await stock(aId, 'dust', 2000)
  await a.goto(`${BASE}/economy?tab=market`)
  await a.locator('.card', { has: a.locator('.hd', { hasText: 'Prices' }) }).locator('.row').nth(2).waitFor()
  // the forms sit under their own tabs of the Marketplace seg
  await a.getByRole('button', { name: 'Sell', exact: true }).click()
  await a.waitForURL(/mtab=sell/)
  const sellCard = a.locator('.card', { has: a.locator('.hd', { hasText: /^Sell/ }) })
  await sellCard.getByRole('button', { name: /Dust/ }).click()
  await sellCard.getByText('Price / unit (up to $300)').waitFor()
  await sellCard.getByLabel(/Price \/ unit/).fill('301')
  await sellCard.getByText('Listings can go up to 150% of street — $300 a unit right now.').waitFor()
  await sellCard.getByLabel(/Units/).fill('100')
  await sellCard.getByLabel(/Price \/ unit/).fill('250')
  await sellCard.getByText('you keep $23,750 after the 5% fee').waitFor()
  await sellCard.getByRole('button', { name: 'List It' }).click()
  await a.getByText('Listed on the marketplace').waitFor()
  await snap(a, 'sell')

  // Someone else posts a buy order for dust ...
  const b = await newPlayer(N('Nacho'))
  const bId = (await one('select id from profiles where name = $1', [N('Nacho')])).id
  await db.query('update profiles set cash = 200000 where id = $1', [bId])
  await b.goto(`${BASE}/economy?tab=market&mtab=order`)
  const orderCard = b.locator('.card', { has: b.locator('.hd', { hasText: 'Buy Order' }) })
  await orderCard.getByRole('button', { name: /Dust/ }).click()
  await orderCard.getByLabel(/Units/).fill('500')
  await orderCard.getByLabel(/Offer/).fill('150')
  await orderCard.getByText('Holds $75,000 of your cash on hand.').waitFor()
  await orderCard.getByRole('button', { name: 'Post Order' }).click()
  await b.getByText('Posted: 500 Dust wanted at $150').waitFor()
  await b.getByRole('button', { name: 'Mine (1)' }).click()
  const mine = b.locator('.card', { has: b.locator('.hd', { hasText: 'Mine' }) })
  await mine.getByText('Wanted 500 Dust @ $150').waitFor()
  await mine.getByText('$75,000 held').waitFor()
  if (Number((await one('select cash from profiles where id = $1', [bId])).cash) !== 125000) throw new Error('cash held')
  await snap(b, 'order-posted')

  // ... and the Trader sells 200 into it (Browse, the Marketplace's first tab)
  await a.goto(`${BASE}/economy?tab=market`)
  const wanted = a.locator('.card', { has: a.locator('.hd', { hasText: 'Wanted' }) })
  const row = wanted.locator('.order-row', { hasText: N('Nacho') })
  await row.locator('input').fill('200')
  await row.getByRole('button', { name: 'Sell $28,500' }).click()
  await a.getByText('Sold 200 for $28,500 (after $1,500 fee)').waitFor()
  await a.locator('.card', { has: a.locator('.hd', { hasText: 'Prices' }) }).getByText('last $150').waitFor()
  await snap(a, 'order-filled')

  // the buyer's feed, then cancelling hands back what's left
  await b.goto(`${BASE}/activity`)
  await b.getByText(/filled your buy order: 200 .* dust for \$30,000/).waitFor()
  await b.goto(`${BASE}/economy?tab=market&mtab=mine`)
  await mine.getByText('200 in so far').waitFor()
  await mine.getByRole('button', { name: 'Cancel' }).click()
  await b.getByText('Order cancelled — $45,000 back on hand').waitFor()
  if ((await one(`select qty from storage where player_id = $1 and commodity = 'dust'`, [bId])).qty !== 200) throw new Error('dust landed')

  // Refills (since 0016): each drug is full 3 times a day, then half the stamina bar; drugs don't refill health
  await db.query(`update profiles set stamina_max = 150, stamina = 0, stamina_tick = now() + interval '5 minutes', health = 10,
                  drug_refills = jsonb_build_object('day', _game_day()::text, 'herb', 2) where id = $1`, [bId])
  await stock(bId, 'herb', 5000)
  await b.goto(`${BASE}/services?focus=refills`)
  const refills = b.locator('#refills')
  await refills.locator('.refill-left .pill', { hasText: '🌿 1/3' }).waitFor()
  if (await refills.locator('.row', { hasText: /^Health/ }).getByRole('button', { name: /🌿|❄️|💊/ }).count()) throw new Error('drugs should not refill health')
  const herb = refills.locator('.row', { hasText: /^Stamina/ }).getByRole('button', { name: /🌿/ })
  await herb.click()
  await b.getByText('+150 stamina · Herb restores half your stamina until 00:00 UTC').waitFor()
  await refills.locator('.refill-left .pill.red', { hasText: '🌿 0/3' }).waitFor()
  await db.query(`update profiles set stamina = 0, stamina_tick = now() + interval '5 minutes' where id = $1`, [bId])
  await b.reload(); await refills.locator('.refill-left').waitFor()
  await herb.click()
  await b.getByText('+75 stamina · Herb restores half your stamina until 00:00 UTC').waitFor()
  await snap(b, 'refills')

  console.log('E2E MARKET PASSED')
} catch (e) {
  console.error('E2E MARKET FAILED:', e.message)
  if (shots && lastPage) await lastPage.screenshot({ path: `${shots}/FAIL.png`, fullPage: true }).catch(() => {})
  process.exitCode = 1
} finally {
  if (errors.length) { console.error('Page errors:\n' + errors.join('\n')); process.exitCode = 1 }
  await browser.close()
  await db.end()
}
