// Browser walkthrough for businesses: the map filter, business tiles and the full-hood badge, the block panel,
// the Crew perks card, and discounted prices on the Services, Items and Economy pages.
// Usage (local stack running): node scripts/e2e-business.mjs [--shots dir]
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
const money = (n) => '$' + Math.round(n).toLocaleString('en-US')

try {
  const a = await newPlayer(N('Gus'))
  const aId = (await one('select id from profiles where name = $1', [N('Gus')])).id

  // Found a crew in the UI, then hand it the whole center hood plus three outer Gyms and an outer Pawn Shop
  await a.goto(`${BASE}/crew`)
  await a.getByLabel('Name').fill(N('Pollos'))
  await a.getByRole('button', { name: 'Found It' }).click()
  await a.getByText('Your crew is on the map').waitFor()
  const crewId = (await one('select crew_id from profiles where id = $1', [aId])).crew_id
  const center = (await one('select id from hoods where gx = 5 and gy = 5')).id
  await db.query(`update blocks set owner_crew_id = $1, bonus_at = now() + interval '1 day'
                   where hood_id = $2
                      or id in (select b.id from blocks b join hoods h on h.id = b.hood_id
                                 where b.business = 'gym' and greatest(abs(h.gx - 5), abs(h.gy - 5)) = 4 and b.owner_crew_id is null
                                 order by b.id limit 3)
                      or id in (select b.id from blocks b join hoods h on h.id = b.hood_id
                                 where b.business = 'pawn_shop' and greatest(abs(h.gx - 5), abs(h.gy - 5)) = 4 and b.owner_crew_id is null
                                 order by b.id limit 1)`, [crewId, center])
  const perks = (await one(`select _crew_perks($1) p`, [crewId])).p
  if (!(perks.gym > 0) || !(perks.pawn_shop > 0)) throw new Error('expected gym and pawn perks: ' + JSON.stringify(perks))
  await db.query('update profiles set cash = 5000000 where id = $1', [aId])

  // The map: filter to Gyms; the matching hoods light up and the rest dim
  await a.goto(`${BASE}/territory`)
  await a.getByLabel('Show a business').selectOption('gym')
  await a.locator('.hcell.biz-hit').first().waitFor()
  const hits = await a.locator('.hcell.biz-hit').count()
  const gymHoods = Number((await one(`select count(distinct hood_id) n from blocks where business = 'gym'`)).n)
  if (hits !== gymHoods) throw new Error(`gym filter lit ${hits} hoods, expected ${gymHoods}`)
  await a.locator('.legend', { hasText: 'Gym' }).waitFor()
  await snap(a, 'map-gym-filter')

  // The center hood: six business tiles and the full-hood badge
  await a.goto(`${BASE}/territory?hood=${center}`)
  await a.locator('.blocks6 .biz-name').nth(5).waitFor()
  if (await a.locator('.blocks6 .biz-name').count() !== 6) throw new Error('six business tiles')
  await a.getByText('★ Full hood').waitFor()
  await snap(a, 'center-hood')
  // open the Muscle block (slot D): the business panel shows its values and our crew's take
  await a.locator('.blocks6 .block').nth(3).click()
  const panel = a.locator('.biz-panel')
  await panel.waitFor()
  await panel.getByText('This block').waitFor()
  await panel.getByText(/Your crew gets .+ from it \(full hood\)/).waitFor()
  await snap(a, 'block-panel')
  await a.getByRole('button', { name: 'Close' }).click()

  // Crew page: the perks card, one row per business
  await a.goto(`${BASE}/crew/${crewId}`)
  const card = a.locator('.card', { hasText: 'Crew perks' })
  await card.waitFor()
  const rows = await card.locator('.row.link').count()
  if (rows !== Object.keys(perks).length) throw new Error(`perk rows ${rows} vs ${Object.keys(perks).length}`)
  await card.locator('.row.link', { hasText: 'Gym' }).getByText(/3 blocks/).waitFor()
  await snap(a, 'crew-perks')

  // Services: thugs show the Gym tag, and the button price is what the server charges
  await a.goto(`${BASE}/services?focus=hoodlums`)
  const hood = a.locator('#hoodlums')
  await hood.locator('.perk-tag', { hasText: 'Gym' }).waitFor()
  const btn = hood.getByRole('button', { name: /Hire · / })
  const shown = (await btn.textContent()).replace(/^.*Hire · /, '')
  await btn.click()
  await a.getByText(`Hired for ${shown}`).waitFor()
  await snap(a, 'services-gym')

  // Items: weapons show the Pawn Shop tag and a struck-through full price; buying charges the discounted one
  await a.goto(`${BASE}/items?tab=shop&cat=weapon`)
  await a.locator('.perk-tag', { hasText: 'Pawn Shop' }).waitFor()
  const bat = a.locator('.row', { hasText: 'Baseball Bat' })
  const cost = Math.round(2000 * (1 - perks.pawn_shop))
  await bat.getByRole('button', { name: `${money(2000)}${money(cost)}` }).click()
  await a.getByText(/Bought Baseball Bat/).waitFor()
  const paid = 5000000 - Number((await one('select cash from profiles where id = $1', [aId])).cash)
  if (paid < cost) throw new Error(`paid ${paid} for a ${money(cost)} bat (plus thugs)`)
  await snap(a, 'items-pawn')

  // Economy: the center hood's Night Club shows on the hustler card with the shorter trip
  const nightlife = (await one(`select business from blocks where hood_id = $1 and slot = 3`, [center])).business
  await a.goto(`${BASE}/economy?tab=hustlers`)
  const label = { strip_club: 'Strip Club', night_club: 'Night Club', dispensary: 'Dispensary' }[nightlife]
  await a.locator('.perk-tag', { hasText: label }).waitFor()
  await snap(a, 'economy-hustlers')

  // a player outside the crew sees no perks and full prices
  const b = await newPlayer(N('Lyle'))
  await b.goto(`${BASE}/items?tab=shop&cat=weapon`)
  await b.locator('.row', { hasText: 'Baseball Bat' }).getByRole('button', { name: money(2000), exact: true }).waitFor()
  if (await b.locator('.perk-tag').count() !== 0) throw new Error('no perks outside the crew')

  console.log('E2E BUSINESS PASSED')
} catch (e) {
  console.error('E2E BUSINESS FAILED:', e.message)
  if (shots && lastPage) await lastPage.screenshot({ path: `${shots}/FAIL.png`, fullPage: true }).catch(() => {})
  process.exitCode = 1
} finally {
  if (errors.length) { console.error('Page errors:\n' + errors.join('\n')); process.exitCode = 1 }
  await browser.close()
  await db.end()
}
