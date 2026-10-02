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
  await p.locator('.row.action .action-result').first().waitFor() // results show in place, no pop-up
  await p.locator('.session-tally', { hasText: '1 job' }).waitFor()
  await snap(p, 'action-result')

  // Shop + equip
  await p.goto(BASE + '/items')
  await p.getByRole('button', { name: 'Buy Items' }).click()
  await p.locator('.row', { hasText: 'Brass Knuckles' }).getByRole('button', { name: /\$500/ }).click()
  await toast(p, /Bought Brass Knuckles and equipped it in your Offensive and Defensive setups/)
  await p.getByRole('button', { name: 'Protection' }).click()
  await p.locator('.row', { hasText: 'Leather Jacket' }).getByRole('button', { name: /\$1,000/ }).click()
  await toast(p, /Bought Leather Jacket and equipped it in your Offensive and Defensive setups/)
  await p.getByRole('button', { name: 'Setups' }).click()
  await p.getByText(/Attack 24 · Defense 25/).waitFor()
  await p.locator('.combo-pill', { hasText: 'Back Alley' }).first().waitFor()   // knuckles + jacket: a street combo
  await snap(p, 'setups')

  // Economy: build grow house, hustlers tab, market tab
  await p.goto(BASE + '/economy')
  await p.locator('.row', { hasText: 'Herb grow house' }).getByRole('button', { name: 'Build' }).click()
  await toast(p, /grow house is up/)
  await snap(p, 'economy')
  await p.getByRole('button', { name: 'Hustlers' }).click()
  await p.getByText('No hustlers out').waitFor()
  await p.getByRole('button', { name: 'Marketplace' }).click()
  await p.getByText(/Nothing for sale right now|@ \$/).first().waitFor()
  await snap(p, 'market')

  // Services: bank deposit
  await p.goto(BASE + '/services')
  await p.getByPlaceholder('Amount').first().fill('1000')
  await p.getByRole('button', { name: 'Deposit' }).click()
  await toast(p, /Banked/)
  await snap(p, 'services')

  // Crew
  await p.goto(BASE + '/crew')
  await p.getByRole('button', { name: 'Start a crew' }).click()
  await p.getByLabel('Name').fill(N('Los Pollos '))
  await p.getByRole('button', { name: 'Found It' }).click()
  await toast(p, /on the map/)
  await p.locator('.hd', { hasText: 'Members' }).waitFor()
  await snap(p, 'crew')

  // Territory: hire hoodlums then attack a block (bankroll the player directly in the local DB)
  await db.query(`update profiles set cash = cash + 200000 where name = $1`, [N('Escobar')])
  await p.goto(BASE + '/services')
  await p.locator('.card', { hasText: 'Hoodlums' }).waitFor()
  // a turf attack needs at least 51 thugs
  await p.locator('#hoodlums .qty input').fill('60')
  await p.getByRole('button', { name: /Hire · / }).click()
  await toast(p, /Hired 60 thugs for/)
  // make the first block deterministic: unclaimed, no garrison (resistance 250 vs 51 thugs ≈ 510)
  await db.query(`delete from block_garrison where block_id = (select min(id) from blocks)`)
  await db.query(`delete from block_siege where block_id = (select min(id) from blocks)`)
  await db.query(`update blocks set owner_crew_id = null, taken_at = null, bonus_at = null where id = (select min(id) from blocks)`)
  await db.query(`select _recompute_hood((select min(hood_id) from blocks))`)
  await p.goto(BASE + '/territory')
  await p.locator('.hcell').first().click()
  await p.locator('.blocks6 .block').first().click()
  await p.locator('.modal h2', { hasText: 'Attack with' }).waitFor()
  await p.getByLabel(/Thugs/).fill('51')
  await p.getByRole('button', { name: 'Attack', exact: true }).click()
  await p.locator('.modal', { hasText: /Block taken/ }).waitFor()
  await snap(p, 'territory')
  await p.getByRole('button', { name: 'Close' }).last().click()

  // Chat
  await p.goto(BASE + '/chat')
  await p.getByPlaceholder('Say something…').fill('hola city')
  await p.getByRole('button', { name: 'Send' }).click()
  await p.locator('.msg', { hasText: 'hola city' }).last().waitFor()
  await snap(p, 'chat')

  // Second player can attack straight away (no new-player immunity)
  const q = await newPlayer(N('Lalo'))
  await q.goto(BASE + '/fight')
  await q.locator('.row', { hasText: N('Escobar') }).click()
  await q.getByRole('button', { name: /Attack/ }).waitFor()
  await snap(q, 'player-profile')
  await q.getByRole('button', { name: /Chat/ }).click()
  await q.getByPlaceholder('Say something…').fill('yo')
  await q.getByRole('button', { name: 'Send' }).click()
  await q.locator('.msg', { hasText: 'yo' }).last().waitFor()
  await q.goto(BASE + '/crew')
  await q.locator('.row', { hasText: N('Los Pollos ') }).click()
  await q.getByRole('button', { name: 'Apply to Join' }).click()
  await toast(q, /Applied/)

  await p.goto(BASE + '/crew')
  await p.locator('.row', { hasText: N('Los Pollos ') }).first().click()
  await p.locator('.row', { hasText: N('Lalo') }).getByRole('button', { name: 'Accept' }).click()
  await toast(p, new RegExp(N('Lalo') + ' is in'))
  await p.goto(BASE + '/chat/dms')
  await p.locator('.row', { hasText: N('Lalo') }).click()
  await p.locator('.msg', { hasText: 'yo' }).last().waitFor()

  // Third player founds a rival crew and launches a crew fight
  const t = await newPlayer(N('Tuco'))
  await t.goto(BASE + '/crew')
  await t.getByRole('button', { name: 'Start a crew' }).click()
  await t.getByLabel('Name').fill(N('Salamancas '))
  await t.getByRole('button', { name: 'Found It' }).click()
  await toast(t, /on the map/)
  await t.goto(BASE + '/crew')
  await t.getByPlaceholder('Search crews…').fill('Los Pollos')
  await t.locator('.row', { hasText: N('Los Pollos ') }).click()
  await t.getByRole('button', { name: /Crew Fight/ }).click()
  await t.locator('.modal', { hasText: /took the fight|held the line/ }).waitFor()
  await snap(t, 'crew-fight')
  await t.getByRole('button', { name: 'Close' }).last().click()
  await t.getByRole('button', { name: /Crew Fight · / }).waitFor()   // cooldown shown

  // Back bars: step back when there's history, fall back home when the page was opened directly
  await p.goto(BASE + '/fight')
  await p.locator('.row', { hasText: N('Lalo') }).click()
  await p.waitForURL(/\/player\//)
  await p.getByRole('button', { name: '‹ Back' }).click()
  await p.waitForURL(/\/fight$/)
  await p.goto(BASE + '/items')
  await p.getByRole('button', { name: '‹ Back' }).click()
  await p.waitForURL(u => new URL(u).pathname === '/')

  // Deep links: /services?focus= scrolls to and highlights the card; shop deep link opens the right tab
  await p.goto(BASE + '/services?focus=hoodlums')
  await p.locator('#hoodlums.focused').waitFor()
  await p.goto(BASE + '/items?tab=shop&cat=protection')
  await p.locator('.row', { hasText: 'Leather Jacket' }).waitFor()

  // Disabled buttons say why before the tap
  await p.goto(BASE + '/economy')
  await p.getByRole('button', { name: 'Marketplace' }).click()
  await p.getByRole('button', { name: 'Sell', exact: true }).click()
  await p.locator('.why', { hasText: /in storage to list|need a vehicle/ }).waitFor()
  if (!(await p.getByRole('button', { name: 'List It' }).isDisabled())) throw new Error('List It should be disabled with nothing in storage')

  // Account: change password, sign out, sign back in with the new one; reset link request
  const { rows: [acct] } = await db.query(`select u.email from auth.users u join profiles p on p.id = u.id where p.name = $1`, [N('Escobar')])
  await p.goto(BASE + '/profile')
  await p.getByRole('button', { name: 'Change password' }).click()
  await p.getByLabel('New password', { exact: true }).fill('newsecret9')
  await p.getByLabel('Confirm new password').fill('newsecret9')
  await p.getByRole('button', { name: 'Save new password' }).click()
  await toast(p, /Password updated/)
  await snap(p, 'profile')
  p.once('dialog', d => d.accept())
  await p.getByRole('button', { name: 'Sign out' }).click()
  await p.getByRole('button', { name: 'Existing Account' }).waitFor()
  await p.getByText('Forgot your password?').click()
  await p.getByLabel('Email').fill(acct.email)
  await p.getByRole('button', { name: 'Send reset link' }).click()
  await p.getByText(/a reset link is on its way/).waitFor()
  await snap(p, 'reset-sent')
  await p.getByText('‹ Back to sign in').click()
  await p.getByLabel('Email').fill(acct.email)
  await p.getByLabel('Password').fill('newsecret9')
  await p.getByRole('button', { name: 'Sign In' }).click()
  await p.locator('.topbar').waitFor()
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
