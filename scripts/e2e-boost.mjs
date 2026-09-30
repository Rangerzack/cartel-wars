// Browser walkthrough for scaling slot prices and the 24-hour boost: the slot button's diamonds + cash price
// and how it climbs, the full-setup hint on Items, picking a boost side (locked while it runs), the boost in the
// Offense setup's numbers, and extending it.
// Usage (local stack running): node scripts/e2e-boost.mjs [--shots dir]
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

try {
  const a = await newPlayer(N('Juan'))
  const aId = (await one('select id from profiles where name = $1', [N('Juan')])).id

  // Slots: 1💎 + $20,000 for the 7th, and the button needs both
  await db.query('update profiles set diamonds = 200, cash = 10000 where id = $1', [aId])
  await a.goto(`${BASE}/services?focus=upgrades`)
  const up = a.locator('#upgrades')
  const slotBtn = up.locator('.row', { hasText: 'Setup slot +1' }).getByRole('button')
  await slotBtn.getByText('💎 1 + $20,000').waitFor()
  if (!(await slotBtn.isDisabled())) throw new Error('not enough cash on hand: disabled')
  await up.getByText('Slots take cash on hand').waitFor()
  await db.query('update profiles set cash = 1000000 where id = $1', [aId])
  await a.reload()
  await slotBtn.click()
  await a.getByText('Upgraded for 💎 1 + $20,000').waitFor()
  await slotBtn.getByText('💎 1 + $40,000').waitFor()
  const p1 = await one('select inventory_slots, diamonds, cash from profiles where id = $1', [aId])
  if (p1.inventory_slots !== 7 || p1.diamonds !== 199 || Number(p1.cash) !== 980000) throw new Error('charged: ' + JSON.stringify(p1))
  // diamonds come from milestones: the next steps, and the whole ladder
  await up.getByText(/Next: 50 actions → 💎 5 \(\d+\/50\) · 10 fight wins → 💎 5/).waitFor()
  await up.getByText('All milestones').click()
  await up.getByText('100,000 → 💎 250').waitFor()
  await snap(a, 'slots')

  // at 130 the button gives way to "Maxed"
  await db.query('update profiles set inventory_slots = 130 where id = $1', [aId])
  await a.reload()
  await up.locator('.row', { hasText: 'Setup slot +1' }).getByText('130/130 slots').waitFor()
  await up.locator('.row', { hasText: 'Setup slot +1' }).locator('.pill', { hasText: 'Maxed' }).waitFor()
  await db.query('update profiles set inventory_slots = 7 where id = $1', [aId])

  // Items: a full setup points at the next slot's price
  await db.query(`insert into inventory (player_id, item_id, qty) select $1, id, 7 from item_defs where name = 'Brass Knuckles'`, [aId])
  await db.query(`insert into setup_items (player_id, setup, item_id, qty) select $1, 'offense', id, 7 from item_defs where name = 'Brass Knuckles'`, [aId])
  await a.goto(`${BASE}/items?setup=offense`)
  await a.getByText('Setup full. The next slot costs 💎 1 + $40,000').waitFor()

  // Boost: pick a side, then the Offense setup shows +50
  await a.goto(`${BASE}/services?focus=boost`)
  const boost = a.locator('#boost')
  await boost.getByText(/One side at a time/).waitFor()
  await boost.getByRole('button', { name: '+50 Attack · 💎 50' }).click()
  await a.getByText('+50 Attack for 24h').waitFor()
  await boost.getByText(/left/).first().waitFor()
  await boost.getByText('you can switch to defense once this one runs out').waitFor()
  if (await boost.getByRole('button', { name: /Defense/ }).count()) throw new Error('no defense button while attack runs')
  const p2 = await one('select boost_side, boost_until > now() + interval \'23 hours\' as ok, diamonds from profiles where id = $1', [aId])
  if (p2.boost_side !== 'attack' || !p2.ok || p2.diamonds !== 149) throw new Error('boost: ' + JSON.stringify(p2))
  await snap(a, 'boost')
  await a.goto(`${BASE}/items?setup=offense`)
  await a.getByText('⚡ Includes your +50 attack boost').waitFor()
  await a.getByText(/Attack 98 · Defense 20/).waitFor()   // 20 + 7×4 knuckles + 50
  await a.locator('.seg button', { hasText: 'Defensive' }).click()
  if (await a.getByText('Includes your +50').count()) throw new Error('boost only in its own setup')

  // Extend it
  await a.goto(`${BASE}/services?focus=boost`)
  await boost.getByRole('button', { name: 'Extend · 💎 50' }).click()
  await a.getByText('Boost extended another 24h').waitFor()
  const p3 = await one('select boost_until > now() + interval \'47 hours\' as ok from profiles where id = $1', [aId])
  if (!p3.ok) throw new Error('extended by 24h')

  // once it runs out, either side is open again
  await db.query(`update profiles set boost_until = now() - interval '1 second' where id = $1`, [aId])
  await a.reload()
  await boost.getByText('Your last boost was attack.').waitFor()
  await boost.getByRole('button', { name: '+50 Defense · 💎 50' }).click()
  await a.getByText('+50 Defense for 24h').waitFor()
  await boost.getByText('you can switch to attack once this one runs out').waitFor()
  if ((await one('select boost_side from profiles where id = $1', [aId])).boost_side !== 'defense') throw new Error('switched to defense')

  console.log('E2E BOOST PASSED')
} catch (e) {
  console.error('E2E BOOST FAILED:', e.message)
  if (shots && lastPage) await lastPage.screenshot({ path: `${shots}/FAIL.png`, fullPage: true }).catch(() => {})
  process.exitCode = 1
} finally {
  if (errors.length) { console.error('Page errors:\n' + errors.join('\n')); process.exitCode = 1 }
  await browser.close()
  await db.end()
}
