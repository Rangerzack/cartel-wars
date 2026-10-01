// Browser walkthrough for the in-app confirm (components/Confirm.tsx). Players get a sheet, not window.confirm, which
// some browsers and embedded web views mute or answer "no" by themselves: in the Claude desktop app's browser a tap on
// Leave did nothing at all. This script hides navigator.webdriver so the app shows the sheet (under automation it falls
// back to the native dialog, which the other e2e scripts answer), and fails if any native dialog opens.
// Kai founds a crew; Lu joins and is made Co-Capo; Lu taps Leave: Cancel, the ×, Escape and the backdrop all keep him
// in, and Leave takes him out.
// Usage (local stack running): node scripts/e2e-confirm.mjs
import { chromium } from 'playwright'
import pg from 'pg'
const db = new pg.Pool({ host: 'localhost', port: Number(process.env.PGPORT || 54329), user: 'postgres', database: 'cartel' })

const BASE = process.env.BASE || 'http://127.0.0.1:5173'
const browser = await chromium.launch({ executablePath: process.env.CHROME || '/opt/pw-browsers/chromium' })
const errors = []
const RUN = Date.now().toString(36).slice(-4)
const N = (base) => `${base}${RUN}`
async function newPlayer(name) {
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 })
  // what a player's browser reports; the app keeps the native dialog only for automation
  await ctx.addInitScript(() => Object.defineProperty(Navigator.prototype, 'webdriver', { get: () => false }))
  const page = await ctx.newPage()
  page.on('pageerror', e => errors.push(`${name}: ${e.message}`))
  page.on('dialog', d => { errors.push(`${name}: a native ${d.type()} opened: ${d.message()}`); d.dismiss() })
  await page.goto(BASE)
  await page.getByRole('button', { name: 'New Player' }).click()
  await page.getByLabel('Street name').fill(name)
  await page.getByLabel('Email').fill(`${name.toLowerCase().replace(/[^a-z0-9]/g, '')}-${Date.now()}@test.local`)
  await page.getByLabel('Password').fill('secret123')
  await page.getByRole('button', { name: 'Enter the City' }).click()
  await page.locator('.topbar').waitFor()
  return page
}
const one = async (sql, args = []) => (await db.query(sql, args)).rows[0]
const sheet = (p) => p.locator('.modal', { has: p.locator('.confirm-actions') })
async function stillIn(p, crewName, how) {
  await sheet(p).waitFor({ state: 'detached' })
  await p.waitForTimeout(300)
  const r = await one('select c.name from profiles p join crews c on c.id = p.crew_id where p.name = $1', [N('Lu')])
  if (r?.name !== crewName) throw new Error(`${how} should keep Lu in the crew, but he is in ${JSON.stringify(r?.name)}`)
}

try {
  const kai = await newPlayer(N('Kai'))
  const lu = await newPlayer(N('Lu'))
  const crewName = N('Tide ')
  const kaiId = (await one('select id from profiles where name = $1', [N('Kai')])).id
  const luId = (await one('select id from profiles where name = $1', [N('Lu')])).id
  // the crew and Lu's place in it are set up directly; the subject here is the confirm, not joining
  const crew = await one(`insert into crews (name, emblem, capo_id, co_capo_id) values ($1, '🌊', $2, $3) returning id`, [crewName, kaiId, luId])
  await db.query('update profiles set crew_id = $1 where id in ($2, $3)', [crew.id, kaiId, luId])

  await lu.goto(`${BASE}/crew/${crew.id}`)
  const leave = lu.getByRole('button', { name: 'Leave', exact: true })
  await leave.click()
  await sheet(lu).waitFor()
  const title = await sheet(lu).locator('h3').textContent()
  if (title !== `Leave ${crewName}?`) throw new Error('sheet title: ' + title)
  if (!/Co-Capo seat opens up/.test(await sheet(lu).locator('.confirm-msg').textContent())) throw new Error('a Co-Capo is told the seat opens up')
  if (!(await lu.evaluate(() => document.activeElement?.closest('.modal') != null))) throw new Error('focus moves into the sheet')

  await sheet(lu).getByRole('button', { name: 'Cancel' }).click()
  await stillIn(lu, crewName, 'Cancel')
  await leave.click(); await sheet(lu).getByRole('button', { name: 'Close' }).click()   // the ×
  await stillIn(lu, crewName, 'The ×')
  await leave.click(); await sheet(lu).waitFor(); await lu.keyboard.press('Escape')
  await stillIn(lu, crewName, 'Escape')
  await leave.click(); await sheet(lu).waitFor(); await lu.mouse.click(195, 40)       // the backdrop above the sheet
  await stillIn(lu, crewName, 'A tap on the backdrop')

  await leave.click()
  await sheet(lu).locator('.confirm-actions').getByRole('button', { name: 'Leave' }).click()
  await lu.locator('.toast', { hasText: 'You left the crew' }).waitFor()
  await lu.waitForURL(/\/crew$/)
  const after = await one('select crew_id from profiles where id = $1', [luId])
  if (after.crew_id) throw new Error('Leave should take Lu out of the crew')
  const seat = await one('select co_capo_id from crews where id = $1', [crew.id])
  if (seat.co_capo_id) throw new Error('the Co-Capo seat should be empty after Lu leaves')
  await kai.close()

  if (errors.length) throw new Error(errors.join('\n'))
  console.log('e2e-confirm PASSED: the in-app confirm asks, every way out of it is a no, and Leave works (no native dialog opened)')
} catch (e) {
  console.error('e2e-confirm FAILED:', e.message)
  process.exitCode = 1
} finally {
  await browser.close()
  await db.end()
}
