// Browser walkthrough for round 3: fight edges and scores, the Thugs list, rare finds on actions,
// daily cash in the feed, refills coming back at 00:00 UTC.
// Usage (local stack running): node scripts/e2e-round3.mjs [--shots dir]
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
const idOf = async (name) => (await db.query('select id from profiles where name = $1', [name])).rows[0].id

try {
  const a = await newPlayer(N('Saul'))
  const aId = await idOf(N('Saul'))
  const thug1 = await idOf('Thug 1')

  // Fight preview against Thug 1: odds, both sides' edges, and the gear-only scores
  await a.goto(`${BASE}/player/${thug1}`)
  const box = a.locator('.odds-box', { hasText: /Your odds vs Thug 1/ })
  await box.waitFor()
  await box.locator('.edge-col', { hasText: 'Their edges' }).locator('.pill', { hasText: 'Defending' }).waitFor()
  await box.getByText(/Gear alone: your hit 40\.0 vs theirs 20\.0/).waitFor()
  await box.getByText(/Strong favorite/).waitFor()
  await snap(a, 'preview-thug1')
  await a.getByRole('button', { name: /Attack/ }).click()
  const modal = a.locator('.modal', { hasText: /You won the fight/ })
  await modal.waitFor()
  await modal.locator('.scoreline').waitFor()
  await modal.getByText(/your hit landed in full/).waitFor()
  await snap(a, 'fight-result')
  await a.getByRole('button', { name: 'Close' }).click()
  // after a hit you're hotter than the thug: the heat edge flips to you
  await box.locator('.edge-col', { hasText: 'Your edges' }).locator('.pill', { hasText: 'More heat' }).waitFor()

  // Thugs tab: ranked by payday, Thug 1 shows you've hit it once
  await a.goto(`${BASE}/fight?tab=thugs`)
  await a.getByText(/you're favored up to about Thug \d+/).waitFor()
  await a.locator('.thug-row').first().waitFor()
  await a.getByRole('button', { name: 'All 200' }).click()
  await a.locator('.thug-row', { hasText: 'Thug 200' }).getByText('Long shot').waitFor()
  await a.locator('.thug-row').filter({ has: a.locator('.t', { hasText: /^Thug 1$/ }) }).getByText(/hit 1× this hour/).waitFor()
  await a.getByRole('button', { name: 'Best paydays' }).click()
  await snap(a, 'thugs')

  // Actions: every job names its rare find and odds; a find pops the reveal (the roll is faked in the response)
  await a.goto(`${BASE}/actions`)
  const sling = a.locator('.row.action', { hasText: 'Sling on the Corner' })
  await sling.getByText(/Rare find: EOD Bomb Suit · 1 in 6,000/).waitFor()
  await a.locator('.row.action', { hasText: 'Take Down a Rival Don' }).getByText(/TOW Missile · 1 in 500/).waitFor()
  await a.locator('.card', { hasText: 'Rare finds' }).getByText(/Every job can turn up one of four items/).waitFor()
  await a.route('**/rpc/do_action', async route => {
    const res = await route.fetch()
    const body = await res.json()
    body.found = { id: 0, name: 'EOD Bomb Suit', category: 'protection', att: 0, def: 115, owned: 1 }
    await route.fulfill({ response: res, json: body })
  })
  await sling.getByRole('button', { name: 'Do It' }).click()
  const reveal = a.locator('.modal', { hasText: 'Rare find!' })
  await reveal.locator('.name', { hasText: 'EOD Bomb Suit' }).waitFor()
  await reveal.getByText(/def 115 · you own 1/).waitFor()
  await snap(a, 'rare-find')
  await a.unroute('**/rpc/do_action')
  await reveal.getByRole('button', { name: 'Close' }).click()

  // A real find (rolled in the database) shows in the city-wide list and in Items, where it can't be bought
  await db.query(`select _rare_roll($1, a, 0) from action_defs a where name = 'Take Down a Rival Don'`, [aId])
  await a.reload()
  await a.locator('.finds-ticker', { hasText: `${N('Saul')} found a TOW Missile on Take Down a Rival Don` }).waitFor()
  await a.goto(`${BASE}/items?tab=shop&cat=weapon`)
  const tow = a.locator('.row.drop-only', { hasText: 'TOW Missile' })
  await tow.getByText('×1').waitFor()
  await tow.getByRole('button', { name: 'Found on jobs' }).waitFor()
  await snap(a, 'items-finds')

  // Daily cash: a missed rollover pays on the next load and lands in the feed
  await db.query(`update profiles set daily_day = daily_day - 1 where id = $1`, [aId])
  await a.goto(`${BASE}/activity`)
  // the pay happens in get_me's tick; the feed may have loaded first
  if (!(await a.getByText(/Daily cash landed on hand/).isVisible())) { await a.waitForTimeout(800); await a.reload() }
  await a.getByText(/Daily cash landed on hand/).waitFor()
  await a.locator('.row.activity', { hasText: 'Daily cash' }).getByText('+$50,000').waitFor()
  await snap(a, 'daily-cash')

  // Refills: used up yesterday → back after the rollover; used today → countdown to 00:00 UTC
  await db.query(`update profiles set refills_used = 3, refills_reset_at = now() where id = $1`, [aId])
  await a.goto(`${BASE}/services?focus=refills`)
  await a.getByText('3/3 full product refills today').waitFor()
  await a.getByText(/The full ones come back at 00:00 UTC — in \d+h \d+m|The full ones come back at 00:00 UTC — in \d+m/).waitFor()
  await a.locator('#bank').getByText(/Everyone gets \$50,000 on hand at 00:00 UTC/).waitFor()
  await snap(a, 'refills')
  await db.query(`update profiles set refills_reset_at = date_trunc('day', now() at time zone 'utc') at time zone 'utc' - interval '1 hour' where id = $1`, [aId])
  await a.reload()
  await a.getByText('0/3 full product refills today').waitFor()

  console.log('E2E ROUND 3 PASSED')
} catch (e) {
  console.error('E2E ROUND 3 FAILED:', e.message)
  if (shots && lastPage) await lastPage.screenshot({ path: `${shots}/FAIL.png`, fullPage: true }).catch(() => {})
  process.exitCode = 1
} finally {
  if (errors.length) { console.error('Page errors:\n' + errors.join('\n')); process.exitCode = 1 }
  await browser.close()
  await db.end()
}
