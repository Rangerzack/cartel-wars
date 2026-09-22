// Browser walkthrough against the local stack (local-db.sh + dev-server.mjs + vite).
// Usage: node scripts/e2e.mjs [--shots dir]
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
  await page.getByText(name, { exact: false }).first().waitFor()
  return page
}
const toast = (page, re) => page.locator('.toast').filter({ hasText: re }).first().waitFor({ timeout: 8000 })

try {
  const p = await newPlayer(N('Escobar'))
  await snap(p, 'home')

  // Actions
  await p.getByRole('link', { name: /Actions/ }).click()
  await p.getByRole('button', { name: 'Do It' }).first().click()
  await p.locator('.modal').waitFor()
  await snap(p, 'action-result')
  await p.getByRole('button', { name: 'Close' }).click()

  // Shop + equip
  await p.goto(BASE + '/items')
  await p.getByRole('button', { name: 'Buy Items' }).click()
  await p.locator('.row', { hasText: 'Brass Knuckles' }).getByRole('button', { name: /\$500/ }).click()
  await toast(p, /Bought Brass Knuckles/)
  await p.getByRole('button', { name: 'Protection' }).click()
  await p.locator('.row', { hasText: 'Leather Jacket' }).getByRole('button', { name: /\$1,000/ }).click()
  await toast(p, /Bought Leather Jacket/)
  await p.getByRole('button', { name: 'Setups' }).click()
  await p.locator('.row', { hasText: 'Brass Knuckles' }).getByRole('button', { name: '+' }).click()
  await p.locator('.row', { hasText: 'Leather Jacket' }).getByRole('button', { name: '+' }).click()
  await p.getByText(/Attack 24 · Defense 25/).waitFor()
  await p.locator('.gold', { hasText: 'combo bonus' }).waitFor()
  await snap(p, 'setups')

  // Economy: build grow house, hustlers tab, market tab
  await p.goto(BASE + '/economy')
  await p.locator('.row', { hasText: 'Herb grow house' }).getByRole('button', { name: 'Build' }).click()
  await toast(p, /grow house is up/)
  await snap(p, 'economy')
  await p.getByRole('button', { name: 'Hustlers' }).click()
  await p.getByText('No hustlers out').waitFor()
  await p.getByRole('button', { name: 'Marketplace' }).click()
  await p.getByText('Nothing for sale right now.').waitFor()
  await snap(p, 'market')

  // Services: bank deposit
  await p.goto(BASE + '/services')
  await p.getByPlaceholder('Amount').first().fill('1000')
  await p.getByRole('button', { name: 'Deposit' }).click()
  await toast(p, /Banked/)
  await snap(p, 'services')

  // Crew
  await p.goto(BASE + '/crew')
  await p.getByLabel('Name').fill(N('Los Pollos '))
  await p.getByRole('button', { name: 'Found It' }).click()
  await toast(p, /on the map/)
  await p.locator('.hd', { hasText: 'Members' }).waitFor()
  await snap(p, 'crew')

  // Territory: hire hoodlums then attack a block (bankroll the player directly in the local DB)
  await db.query(`update profiles set cash = cash + 100000 where name = $1`, [N('Escobar')])
  await p.goto(BASE + '/services')
  await p.locator('.card', { hasText: 'Hoodlums' }).waitFor()
  // give ourselves cash via the dev API is out of scope; attacking with 10 thugs on cheapest block (resistance 200) will fail but exercise the flow
  await p.locator('.qty input').last().fill('30')
  await p.getByRole('button', { name: /Hire · / }).click()
  await toast(p, /Hired for/)
  await p.goto(BASE + '/territory')
  await p.locator('.block').first().click()
  await p.locator('.modal').waitFor()
  await p.getByLabel(/Thugs/).fill('30')
  await p.getByRole('button', { name: 'Attack', exact: true }).click()
  await p.locator('.modal', { hasText: /Block taken/ }).waitFor()
  await snap(p, 'territory')
  await p.getByRole('button', { name: 'Close' }).click()

  // Chat
  await p.goto(BASE + '/chat')
  await p.getByPlaceholder('Say something…').fill('hola city')
  await p.getByRole('button', { name: 'Send' }).click()
  await p.locator('.msg', { hasText: 'hola city' }).waitFor()
  await snap(p, 'chat')

  // Second player attacks first (needs immunity off — do via API? Immunity blocks it; verify the error toast instead)
  const q = await newPlayer(N('Lalo'))
  await q.goto(BASE + '/fight')
  await q.locator('.row', { hasText: N('Escobar') }).click()
  await q.getByText('New players can\'t be attacked yet.').waitFor()
  await snap(q, 'player-profile')
  await q.getByRole('button', { name: /Chat/ }).click()
  await q.getByPlaceholder('Say something…').fill('yo')
  await q.getByRole('button', { name: 'Send' }).click()
  await q.locator('.msg', { hasText: 'yo' }).waitFor()
  await q.goto(BASE + '/crew')
  await q.locator('.row', { hasText: N('Los Pollos ') }).click()
  await q.getByRole('button', { name: 'Apply to Join' }).click()
  await toast(q, /Applied/)

  await p.goto(BASE + '/crew')
  await p.locator('.row', { hasText: N('Lalo') }).getByRole('button', { name: 'Accept' }).click()
  await toast(p, new RegExp(N('Lalo') + ' is in'))
  await p.goto(BASE + '/chat/dms')
  await p.locator('.row', { hasText: N('Lalo') }).click()
  await p.locator('.msg', { hasText: 'yo' }).waitFor()

  await p.goto(BASE + '/profile')
  await snap(p, 'profile')
  console.log('E2E PASSED')
} catch (e) {
  console.error('E2E FAILED:', e.message)
  if (shots && lastPage) await lastPage.screenshot({ path: `${shots}/FAIL.png`, fullPage: true }).catch(() => {})
  process.exitCode = 1
} finally {
  if (errors.length) { console.error('Page errors:\n' + errors.join('\n')); process.exitCode = 1 }
  await browser.close()
  await db.end()
}
