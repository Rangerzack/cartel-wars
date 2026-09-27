// Browser walkthrough for the week-2 UX work: activity feed, tab badges, unread DMs, fight preview,
// rookie poker table, casino bet defaults, Actions sort, path prompt on Home.
// Usage (local stack running): node scripts/e2e-week2.mjs [--shots dir]
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
const tabBadge = (p, tab) => p.locator('.tabbar a', { hasText: tab }).locator('.tbadge')

try {
  const a = await newPlayer(N('Walt'))
  const b = await newPlayer(N('Jesse'))
  const aId = await idOf(N('Walt'))

  // Fight preview, then the fight
  await b.goto(`${BASE}/player/${aId}`)
  await b.locator('.odds-box', { hasText: /Your odds vs/ }).waitFor()
  await b.getByText(/You'd take \d+–\d+ damage/).waitFor()
  await snap(b, 'fight-preview')
  await b.getByRole('button', { name: /Attack/ }).click()
  await b.locator('.modal', { hasText: /You (won|lost) the fight/ }).waitFor()
  await b.getByRole('button', { name: 'Close' }).click()

  // DM from Jesse
  await b.getByRole('button', { name: /Chat/ }).click()
  await b.getByPlaceholder('Say something…').fill('yo, we need to cook')
  await b.getByRole('button', { name: 'Send' }).click()
  await b.locator('.msg', { hasText: 'we need to cook' }).waitFor()

  // Walt comes back: Home and Chat badges, "while you were away"
  lastPage = a
  await a.goto(BASE + '/')
  await tabBadge(a, 'Home').filter({ hasText: '1' }).waitFor()
  await tabBadge(a, 'Chat').filter({ hasText: '1' }).waitFor()
  if (!/^\(2\) /.test(await a.title())) throw new Error(`title should show 2 unread, got "${await a.title()}"`)
  const away = a.locator('.card.away')
  await away.locator('.row.activity', { hasText: new RegExp(`${N('Jesse')} attacked you`) }).waitFor()
  await snap(a, 'home-away')
  await away.getByRole('button', { name: 'Clear' }).click()
  await away.waitFor({ state: 'detached' })
  await tabBadge(a, 'Home').waitFor({ state: 'detached' })

  // Activity page keeps the history
  await a.goto(BASE + '/activity')
  await a.locator('.row.activity', { hasText: /attacked you/ }).waitFor()
  await a.getByRole('link', { name: N('Jesse') }).first().waitFor()

  // Unread DM: listed as unread, opening it clears the badge
  await a.goto(BASE + '/chat/dms')
  await a.locator('.row.unread', { hasText: N('Jesse') }).waitFor()
  await snap(a, 'dms-unread')
  await a.locator('.row', { hasText: N('Jesse') }).click()
  await a.locator('.msg', { hasText: 'we need to cook' }).waitFor()
  await tabBadge(a, 'Chat').waitFor({ state: 'detached' })
  if (/^\(/.test(await a.title())) throw new Error('title count should clear')

  // Economy badge: a hustler trip that's back
  await db.query(`insert into hustlers (player_id, commodity, count, units, cash_due, departs_at, returns_at) values ($1, 'herb', 1, 10, 500, now() - interval '5 hours', now() - interval '1 minute')`, [aId])
  await a.goto(BASE + '/')
  await tabBadge(a, 'Economy').filter({ hasText: '1' }).waitFor()

  // Actions: stamina-full dot, sort by $ per stamina (remembered)
  await tabBadge(a, 'Actions').waitFor()
  await a.goto(BASE + '/actions')
  await a.getByRole('button', { name: 'Best $ per ⚡' }).click()
  // runnable jobs first (Do It enabled — full stamina), each group sorted by $ per stamina
  const rows = await a.locator('.row.action').evaluateAll(rs => rs.map(r => ({
    rate: Number((r.textContent.match(/~\$([\d,]+)\/⚡/) || [])[1]?.replace(/,/g, '') ?? -1),
    open: !r.querySelector('button.doit').disabled })))
  const sortedGroup = g => g.every((r, i) => r.rate >= 0 && (!i || r.rate <= g[i - 1].rate))
  const firstLocked = rows.findIndex(r => !r.open)
  if (!rows[0].open || (firstLocked >= 0 && rows.slice(firstLocked).some(r => r.open)) || !sortedGroup(rows.filter(r => r.open)) || !sortedGroup(rows.filter(r => !r.open)))
    throw new Error('not sorted runnable-first by $ per stamina: ' + JSON.stringify(rows))
  await a.reload()
  await a.locator('.seg.sm button.on', { hasText: 'Best $ per ⚡' }).waitFor()
  await snap(a, 'actions-sorted')
  await a.getByRole('button', { name: 'Reputation' }).click()
  await a.locator('.row.action', { hasText: /reputation/ }).first().waitFor()

  // Path: teaser past halfway, the choice on Home once it's due, and a nudge on Actions
  await db.query('update profiles set rep_earned = 60 where id = $1', [aId])
  await a.goto(BASE + '/')
  await a.locator('.path-teaser', { hasText: '60/100' }).waitFor()
  await db.query('update profiles set rep_earned = 120 where id = $1', [aId])
  await a.goto(BASE + '/actions')
  await a.locator('.notice', { hasText: 'pick Producer or Trader' }).waitFor()
  await a.getByText('Choose your path →').click()
  await a.locator('.card', { hasText: 'Choose your path' }).waitFor()
  await snap(a, 'home-path')
  a.once('dialog', d => d.accept())
  await a.getByRole('button', { name: 'Be a Trader' }).click()
  await a.locator('.card', { hasText: 'Choose your path' }).waitFor({ state: 'detached' })

  // Casino: bets start at the minimum; the Rookie Room is open to new players, closed to veterans
  await a.goto(BASE + '/casino/slots')
  await a.getByRole('button', { name: 'Spin for $100' }).waitFor()
  await a.goto(BASE + '/casino/poker')
  const rookie = a.locator('.row', { hasText: 'Rookie Room' })
  await rookie.locator('.pill', { hasText: 'Rookies' }).waitFor()
  if (await rookie.getByRole('button', { name: /Open|Join/ }).isDisabled()) throw new Error('new player should be able to sit in the Rookie Room')
  await snap(a, 'poker-lobby')
  await db.query(`update profiles set created_at = now() - interval '30 days' where id = $1`, [aId])
  await a.reload()
  await a.locator('.row', { hasText: 'Rookie Room' }).getByText(/For players in their first 7 days/).waitFor()
  if (!(await a.locator('.row', { hasText: 'Rookie Room' }).getByRole('button', { name: /Open|Join/ }).isDisabled())) throw new Error('veteran should be barred')

  console.log('E2E WEEK 2 PASSED')
} catch (e) {
  console.error('E2E WEEK 2 FAILED:', e.message)
  if (shots && lastPage) await lastPage.screenshot({ path: `${shots}/FAIL.png`, fullPage: true }).catch(() => {})
  process.exitCode = 1
} finally {
  if (errors.length) { console.error('Page errors:\n' + errors.join('\n')); process.exitCode = 1 }
  await browser.close()
  await db.end()
}
