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
  // diamonds come from milestones (own card since 0017): the repeating steps with progress, and the lifetime ladders
  const ms = a.locator('#milestones')
  await ms.locator('.milestone-row', { hasText: 'Every 250 actions' }).getByText(/next at 250/).waitFor()
  await ms.locator('.milestone-row', { hasText: 'Every $10,000,000 wagered at the casino' }).getByText('💎 30').waitFor()
  await ms.getByText('Lifetime milestones, once each').click()
  await ms.getByText('100,000 → 💎 250').waitFor()
  await ms.getByText('$1,000,000,000 → 💎 250').waitFor()
  await snap(a, 'slots')

  // Heat: 💎30 a time for +50 max heat, and the red line moves up with it
  const heatRow = up.locator('.row', { hasText: 'Max heat +50' })
  await heatRow.getByText('100 max · red from 75').waitFor()
  await a.locator('#police').getByText('Red (75+)').waitFor()
  await heatRow.getByRole('button', { name: '💎 30' }).click()
  await heatRow.getByText('150 max · red from 125').waitFor()
  await a.locator('#police').getByText('Red (125+) risks a bust').waitFor()
  await a.locator('#police').getByText('Your heat upgrades moved it up from 75').waitFor()
  const ph = await one('select heat_max, diamonds from profiles where id = $1', [aId])
  if (ph.heat_max !== 150 || ph.diamonds !== 169) throw new Error('heat upgrade: ' + JSON.stringify(ph))
  await snap(a, 'heat')

  // at 130 the button gives way to "Maxed"
  await db.query('update profiles set inventory_slots = 130 where id = $1', [aId])
  await a.reload()
  await up.locator('.row', { hasText: 'Setup slot +1' }).getByText('130/130 slots').waitFor()
  await up.locator('.row', { hasText: 'Setup slot +1' }).locator('.pill', { hasText: 'Maxed' }).waitFor()
  await db.query('update profiles set inventory_slots = 7 where id = $1', [aId])
  // max stamina at 150: "Maxed" too, not a dead "💎 10"
  await db.query('update profiles set stamina_max = 150 where id = $1', [aId])
  await a.reload()
  await up.locator('.row', { hasText: 'Max stamina +5' }).locator('.pill', { hasText: 'Maxed' }).waitFor()
  if (await up.locator('.row', { hasText: 'Max stamina +5' }).getByRole('button').count()) throw new Error('no upgrade button at 150')
  await db.query('update profiles set stamina_max = 25, stamina = 25 where id = $1', [aId])

  // Refills: nothing to refill shows one disabled "Full", not price buttons that do nothing
  await a.reload()
  const staminaRefill = a.locator('#refills .row', { hasText: 'Stamina' })
  await staminaRefill.getByRole('button', { name: 'Full' }).waitFor()
  if (!(await staminaRefill.getByRole('button', { name: 'Full' }).isDisabled())) throw new Error('Full is disabled')
  if (await staminaRefill.getByRole('button').count() !== 1) throw new Error('only Full at full stamina')
  await db.query('update profiles set stamina = 5 where id = $1', [aId])
  await a.reload()
  await staminaRefill.getByRole('button', { name: /💎/ }).waitFor()
  if (await staminaRefill.getByRole('button', { name: 'Full' }).count()) throw new Error('refills come back once stamina is missing')

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
  if (p2.boost_side !== 'attack' || !p2.ok || p2.diamonds !== 119) throw new Error('boost: ' + JSON.stringify(p2))
  await snap(a, 'boost')
  await a.goto(`${BASE}/items?setup=offense`)
  await a.getByText('⚡ Includes your +50 attack boost').waitFor()
  await a.getByText(/Attack 98 · Defense 20/).waitFor()   // 20 + 7×4 knuckles + 50
  await a.locator('.seg button', { hasText: 'Defensive' }).click()
  // the setup is in the URL now (a router navigation), so wait for the switch to land before looking
  await a.locator('.seg button[aria-pressed="true"]', { hasText: 'Defensive' }).waitFor()
  await a.getByText(/^Attack \d+ · Defense \d+$/).waitFor()
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

  // Go to jail for 💎50: no stamina — and you're in until you post bail
  await db.query('update profiles set diamonds = 100, stamina = 0, cash = 10000 where id = $1', [aId])
  await a.goto(`${BASE}/services?focus=police`)
  const police = a.locator('#police')
  await police.getByText('You stay until you post bail ($8,000)').waitFor()
  await police.getByRole('button', { name: 'Go to Jail · 💎 50' }).click()
  await a.getByText("You're in County Jail — jail setup is active").waitFor()
  const jailCard = a.locator('.card', { has: a.locator('.hd', { hasText: 'County Jail' }) })
  await jailCard.getByText('until you post bail').first().waitFor()
  await a.locator('.status-strip').getByText('🔒 In jail · until bail').waitFor()
  // the top bar's heat corner says Jail while you're inside
  await a.locator('.topbar .jail-tag', { hasText: 'Jail' }).waitFor()
  if (await a.locator('.topbar .bar.heat').count()) throw new Error('no heat bar in the top bar while jailed')
  if (await police.getByRole('button', { name: /Go to Jail/ }).count()) throw new Error('no second trip while inside')
  const pj = await one(`select diamonds, jail_until = 'infinity' as ok, heat = heat_max as maxed from profiles where id = $1`, [aId])
  if (pj.diamonds !== 50 || !pj.ok || !pj.maxed) throw new Error('jailed for diamonds, heat maxed: ' + JSON.stringify(pj))
  await jailCard.getByText('bail walks you out with zero heat').waitFor()
  await police.getByText('posting bail clears your heat to 0').waitFor()
  await snap(a, 'jail')
  // Services puts jail first while you're inside
  await a.goto(`${BASE}/services?focus=jail`)
  await a.locator('#jail.focused').waitFor()
  if ((await a.locator('.svc-nav a').first().textContent()) !== 'Jail') throw new Error('Jail is the first chip')
  if ((await a.locator('.page > .card').first().getAttribute('id')) !== 'jail') throw new Error('the jail card comes first')
  // Home leads with it too, and bail is paid right there (Phase 3: Next up)
  await a.goto(BASE)
  const jailRow = a.locator('.next-up .row[data-next="jail"]')
  await jailRow.getByText("You're locked up").waitFor()
  await jailRow.getByRole('button', { name: 'Post Bail · $8,000' }).click()
  await a.getByText('Bailed out for $8,000 · heat back to 0').waitFor()
  await jailRow.waitFor({ state: 'detached' })
  await a.goto(`${BASE}/services`)
  const out = await one('select jail_until, heat from profiles where id = $1', [aId])
  if (out.jail_until !== null || out.heat !== 0) throw new Error('out on bail with zero heat: ' + JSON.stringify(out))
  await a.locator('.topbar .bar.heat').waitFor()
  if (await a.locator('.topbar .jail-tag').count()) throw new Error('the Jail tag goes once you bail')
  // out and unhurt: Bank leads again
  await a.locator('#jail').waitFor({ state: 'detached' })
  if ((await a.locator('.page > .card').first().getAttribute('id')) !== 'bank') throw new Error('Bank comes first once out')

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
