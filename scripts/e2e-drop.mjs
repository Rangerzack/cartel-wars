// Browser walkthrough for the Daily Drop: the pitch and odds, subscribing, opening a crate with the reveal, a jackpot
// with the Bank button, the free refill and free hustler credits, and cancelling.
// Usage (local stack running): node scripts/e2e-drop.mjs [--shots dir]
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
let rigged = false

try {
  const a = await newPlayer(N('Saul'))
  const aId = (await one('select id from profiles where name = $1', [N('Saul')])).id
  const card = a.locator('#drop')

  // The pitch: free for now, the jackpots, and the odds table
  await card.getByText('FREE', { exact: true }).waitFor()
  await card.getByText(/Jackpots:/).waitFor()
  await card.getByText('What can drop? See the odds').click()
  const odds = card.locator('.drop-odds .row .ico')
  await odds.nth(10).waitFor()
  if (await odds.count() !== 11) throw new Error(`odds rows ${await odds.count()}`)
  await card.locator('.drop-odds .row.jackpot', { hasText: '$1,000,000' }).getByText('3%').waitFor()
  await card.locator('.drop-odds .row', { hasText: '5 Diamonds' }).first().getByText('20%').waitFor()
  await snap(a, 'pitch-odds')

  // Subscribe: today's crate lands straight away
  await card.getByRole('button', { name: 'Subscribe — Free for Now' }).click()
  await a.getByText('Subscribed — your first crate is here').waitFor()
  await a.getByText('A Daily Drop crate is waiting').waitFor()
  await card.getByText('1/7 crates').waitFor()
  if (await card.locator('.crate-stack span.on').count() !== 1) throw new Error('one crate in the stack')
  await snap(a, 'subscribed')

  // Open it: the crate shakes, then the prize shows and the stack is empty
  await card.getByRole('button', { name: 'Open Crate' }).click()
  const modal = a.locator('.modal')
  await modal.locator('.drop-prize .name').waitFor()
  const label = (await modal.locator('.drop-prize .name').textContent()).trim()
  const got = await one(`select z.label from drop_opens o join drop_prizes z on z.code = o.prize where o.player_id = $1`, [aId])
  if (got?.label !== label) throw new Error(`modal shows ${label}, server gave ${got?.label}`)
  await snap(a, 'reveal')
  await modal.getByRole('button', { name: 'Close' }).click()
  await card.getByText(/Next crate in/).waitFor()
  await card.getByText(`Last crate:`).waitFor()
  if (await a.getByText('crate is waiting').count() !== 0) throw new Error('notice gone once opened')

  // A jackpot: rig the table so the $1,000,000 comes up, then open two crates back to back and bank it
  await db.query(`update drop_prizes set weight = case code when 'cash_1m' then 1000000 else 1 end`)
  rigged = true
  await db.query('update profiles set drop_crates = 2, cash = 0 where id = $1', [aId])
  await a.reload()
  await card.getByRole('button', { name: 'Open Crate · 2 waiting' }).click()
  await modal.getByRole('heading', { name: 'Jackpot!' }).waitFor()
  await modal.locator('.drop-prize .name', { hasText: '$1,000,000' }).waitFor()
  await modal.getByRole('button', { name: 'Open Another · 1 left' }).click()
  await modal.getByRole('button', { name: 'Bank $1,000,000' }).waitFor()
  await snap(a, 'jackpot')
  await modal.getByRole('button', { name: 'Bank $1,000,000' }).click()
  await modal.getByText("Banked. It's safe.").waitFor()
  const acct = await one('select cash, bank from profiles where id = $1', [aId])
  if (Number(acct.cash) !== 1000000 || Number(acct.bank) !== 1000000) throw new Error(`cash ${acct.cash} bank ${acct.bank}`)
  await modal.getByRole('button', { name: 'Close' }).click()
  await card.getByText('See the odds').click()
  await card.getByText(`${N('Saul')} hit`).first().waitFor()
  await snap(a, 'latest-jackpots')

  // Credits: a free stamina refill on the Refills card, and free hustlers on the Hustlers page
  await db.query(`insert into storage (player_id, commodity, qty) values ($1, 'herb', 400)
                  on conflict (player_id, commodity) do update set qty = 400`, [aId])
  await db.query('update profiles set free_refills = 2, free_hustlers = 100, stamina = 0, cash = 0 where id = $1', [aId])
  await a.reload()
  await card.getByRole('button', { name: /2 free refills/ }).click()
  await a.waitForURL(/focus=refills/)
  await a.locator('#refills').getByRole('button', { name: '🎁 Free ×2' }).click()
  await a.getByText(/stamina · 1 free left/).waitFor()
  const pr = await one('select stamina, stamina_max, free_refills, refills_used from profiles where id = $1', [aId])
  if (pr.stamina !== pr.stamina_max || pr.free_refills !== 1 || pr.refills_used !== 0) throw new Error('free refill: ' + JSON.stringify(pr))
  await snap(a, 'free-refill')
  await a.goto(`${BASE}/economy?tab=hustlers`)
  await a.getByText('100 free hustlers from the Daily Drop').waitFor()
  await a.getByText('(1 free)').waitFor()
  await a.getByRole('button', { name: 'Send Them Out' }).click()
  await a.getByText(/out the door with .* \(1 free\)/).waitFor()
  if ((await one('select free_hustlers from profiles where id = $1', [aId])).free_hustlers !== 99) throw new Error('one hustler credit used')
  await snap(a, 'free-hustlers')

  // Cancel: crates already left stay openable, and the pitch comes back
  await db.query('update profiles set drop_crates = 1 where id = $1', [aId])
  await a.goto(BASE)
  await card.getByRole('button', { name: 'Cancel' }).click()
  await a.getByText('Daily Drop cancelled').waitFor()
  await card.getByRole('button', { name: 'Subscribe — Free for Now' }).waitFor()
  await card.getByRole('button', { name: 'Open Crate' }).waitFor()
  await snap(a, 'cancelled')

  console.log('E2E DROP PASSED')
} catch (e) {
  console.error('E2E DROP FAILED:', e.message)
  if (shots && lastPage) await lastPage.screenshot({ path: `${shots}/FAIL.png`, fullPage: true }).catch(() => {})
  process.exitCode = 1
} finally {
  if (rigged) {
    await db.query(`update drop_prizes set weight = case code when 'herb_1000' then 100 when 'dust_700' then 100 when 'pills_250' then 100
                      when 'dia_5' then 200 when 'dia_10' then 100 when 'refills_2' then 100 when 'cash_100k' then 100 when 'thugs_1000' then 50
                      when 'hustlers_100' then 50 when 'dia_25' then 70 when 'cash_1m' then 30 end`)
  }
  if (errors.length) { console.error('Page errors:\n' + errors.join('\n')); process.exitCode = 1 }
  await browser.close()
  await db.end()
}
