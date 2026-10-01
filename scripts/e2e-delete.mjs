// Browser walkthrough for in-app account deletion (#8): Profile → Delete account, the typed street name that unlocks
// the button, deleting, landing back on sign-in, the old login no longer working, and another player's activity line
// about them showing "A deleted player".
// Usage (local stack running): node scripts/e2e-delete.mjs [--shots dir]
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
let step = 0
let lastPage = null
async function snap(page, name) { if (shots) await page.screenshot({ path: `${shots}/${String(++step).padStart(2, '0')}-${name}.png`, fullPage: true }) }
const one = async (sql, args = []) => (await db.query(sql, args)).rows[0]
const count = async (sql, args = []) => Number((await one(sql, args)).n)

async function newPlayer(name, email) {
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
  await page.getByLabel('Email').fill(email)
  await page.getByLabel('Password').fill('secret123')
  await page.getByRole('button', { name: 'Enter the City' }).click()
  await page.locator('.topbar').waitFor()
  return page
}

try {
  const name = `Goner${RUN}`
  const email = `goner${RUN}-${Date.now()}@test.local`
  const w = await newPlayer(`Witness${RUN}`, `witness${RUN}-${Date.now()}@test.local`)
  const p = await newPlayer(name, email)
  const id = (await one('select id from profiles where name = $1', [name])).id
  const wId = (await one('select id from profiles where name = $1', [`Witness${RUN}`])).id
  // the goner hit the witness once (the insert writes the witness's activity line, as attack() does)
  await db.query('insert into fights (attacker_id, defender_id, attacker_dmg, defender_dmg, cash_taken, winner_id) values ($1, $2, 30, 10, 0, $2)', [id, wId])
  const tally = await count('select count(*) as n from deleted_accounts')

  // Profile → Delete account: the button stays off until the street name is typed (any case)
  await p.goto(`${BASE}/profile`)
  await p.getByRole('button', { name: 'Delete account' }).click()
  const modal = p.locator('.modal')
  await modal.getByRole('heading', { name: 'Delete your account' }).waitFor()
  await modal.getByText("Purchases can't be refunded").waitFor()
  await modal.getByText("Deleting your account doesn't cancel the Daily Drop").waitFor()
  const confirmBox = modal.getByLabel('Type your street name to confirm')
  const del = modal.getByRole('button', { name: 'Delete forever' })
  if (!(await del.isDisabled())) throw new Error('Delete forever starts disabled')
  await confirmBox.fill('Somebody Else')
  if (!(await del.isDisabled())) throw new Error('a wrong name keeps it disabled')
  await snap(p, 'delete-modal')
  await confirmBox.fill(` ${name.toLowerCase()} `)
  if (await del.isDisabled()) throw new Error('the right name, in any case, unlocks it')
  await del.click()

  // Back on the sign-in screen, and the account is gone
  await p.getByRole('button', { name: 'Sign In' }).waitFor()
  await p.getByText('Your account is deleted').waitFor()
  await snap(p, 'signed-out')
  if (await one('select 1 from profiles where id = $1', [id])) throw new Error('profile deleted')
  if (await one('select 1 from auth.users where id = $1', [id])) throw new Error('auth user deleted')
  if (await count('select count(*) as n from deleted_accounts') !== tally + 1) throw new Error('one row in deleted_accounts')

  // The old login doesn't work any more
  await p.getByLabel('Email').fill(email)
  await p.getByLabel('Password').fill('secret123')
  await p.getByRole('button', { name: 'Sign In' }).click()
  await p.getByText('Invalid login credentials').waitFor()
  await p.waitForTimeout(500)
  if (await p.locator('.topbar').count()) throw new Error('no way back in')
  await snap(p, 'sign-in-fails')

  // The witness's activity line about them stays, nameless
  await w.goto(`${BASE}/activity`)
  await w.locator('.activity', { hasText: 'A deleted player attacked you' }).waitFor()
  await snap(w, 'witness-activity')

  console.log('E2E DELETE PASSED')
} catch (e) {
  console.error('E2E DELETE FAILED:', e.message)
  if (shots && lastPage) await lastPage.screenshot({ path: `${shots}/FAIL.png`, fullPage: true }).catch(() => {})
  process.exitCode = 1
} finally {
  if (errors.length) { console.error('Page errors:\n' + errors.join('\n')); process.exitCode = 1 }
  await browser.close()
  await db.end()
}
