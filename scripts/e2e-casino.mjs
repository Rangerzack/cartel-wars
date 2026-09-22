// Casino walkthrough against the local stack: house games as one player, then two players at a poker table.
// Usage: node scripts/e2e-casino.mjs [--shots dir]
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
  await db.query(`update profiles set cash = cash + 1000000 where name = $1`, [name])
  await page.reload()
  await page.getByText(name, { exact: false }).first().waitFor()
  return page
}
const toast = (page, re) => page.locator('.toast').filter({ hasText: re }).first().waitFor({ timeout: 8000 })
const sleep = (ms) => new Promise(r => setTimeout(r, ms))

try {
  const a = await newPlayer(N('Ace'))

  // slots
  await a.goto(BASE + '/casino/slots')
  await a.getByRole('button', { name: /Spin for \$1,000/ }).click()
  await a.locator('.reels').locator('.reel.spinning').first().waitFor()
  await a.getByText(/you win|No luck/).waitFor({ timeout: 8000 })
  await snap(a, 'slots')

  // blackjack
  await a.goto(BASE + '/casino/blackjack')
  await a.getByRole('button', { name: /Deal for \$1,000/ }).click()
  for (let i = 0; i < 6; i++) {
    await a.locator('.bjtable .outcome, button:has-text("Hit")').first().waitFor()
    if (await a.locator('.bjtable .outcome').count()) break
    const total = Number((await a.locator('.bjtable .hand').nth(1).locator('.small').innerText()).match(/· (\d+)/)[1])
    if (total < 17) await a.getByRole('button', { name: 'Hit' }).click(); else await a.getByRole('button', { name: 'Stand' }).click()
    await sleep(300)
  }
  await a.locator('.bjtable .outcome').waitFor()
  await snap(a, 'blackjack')
  await a.getByRole('button', { name: /Deal for/ }).waitFor()   // hand over → can deal again

  // craps
  await a.goto(BASE + '/casino/craps')
  await a.getByRole('button', { name: /Pass Line/ }).click()
  await a.getByRole('button', { name: /Roll · \$1,000 in play/ }).click()
  await a.locator('.puck').filter({ hasText: /ON|OFF/ }).waitFor()
  await a.getByText(/settled|bets stay up/).waitFor({ timeout: 8000 })
  await snap(a, 'craps')

  // roulette
  await a.goto(BASE + '/casino/roulette')
  await a.locator('.outside .o.redsq').click()
  await a.locator('.roulette .n', { hasText: /^17/ }).click()
  await a.getByText(/Red \$500/).waitFor()
  await a.getByRole('button', { name: /Spin · \$1,000 on the felt/ }).click()
  await a.getByText(/paid|house takes it/).waitFor({ timeout: 8000 })
  await snap(a, 'roulette')
  await a.locator('.row', { hasText: 'Roulette' }).first().waitFor()   // ledger updated

  // poker: two players (start from an empty room)
  await db.query(`delete from poker_seats`); await db.query(`delete from poker_hands`)
  const b = await newPlayer(N('Bet'))
  await a.goto(BASE + '/casino/poker')
  await a.locator('.row', { hasText: 'Back Room · 1k/2k' }).first().getByRole('button', { name: /Open|Join/ }).click()
  await a.locator('.modal').waitFor()
  await snap(a, 'poker-buyin')
  await a.getByRole('button', { name: /Sit down with/ }).click()
  await toast(a, /Bought in for/)
  await a.locator('.felt').waitFor()
  await a.getByText('Need two players to deal.').waitFor()
  await snap(a, 'poker-alone')

  await b.goto(BASE + '/casino/poker')
  await b.locator('.row', { hasText: 'Back Room · 1k/2k' }).first().getByRole('button', { name: 'Join' }).click()
  await b.getByRole('button', { name: /Sit down with/ }).click()
  await toast(b, /Bought in for/)
  await b.locator('.felt').waitFor()

  // play a hand: whoever's turn it is checks or calls, until the result shows
  const pages = { A: a, B: b }
  let acted = 0
  for (let i = 0; i < 40 && acted < 12; i++) {
    let did = false
    for (const [k, pg] of Object.entries(pages)) {
      const call = pg.getByRole('button', { name: /^Call/ })
      const check = pg.getByRole('button', { name: 'Check' })
      if (await call.count()) { if (acted === 0) await snap(pg, `poker-${k}-to-act`); await call.click(); did = true; acted++ }
      else if (await check.count()) { if (acted === 0) await snap(pg, `poker-${k}-to-act`); await check.click(); did = true; acted++ }
      if (did) { await sleep(500); break }
    }
    if (!did) {
      if (await a.locator('.felt .gold', { hasText: /wins/ }).count()) break
      await sleep(600)
    }
  }
  await a.locator('.felt .gold', { hasText: /wins/ }).waitFor({ timeout: 10000 })
  await snap(a, 'poker-showdown-A')
  await snap(b, 'poker-showdown-B')
  const hands = await db.query(`select count(*)::int as n from poker_hands where finished_at is not null and result->>'fold_out' = 'false'`)
  if (hands.rows[0].n < 1) throw new Error('expected a showdown hand in the DB')

  // next hand starts on its own; raise flow
  await sleep(6500)
  const turn = (await a.getByRole('button', { name: /Raise|^Bet$/ }).count()) ? a : b
  await turn.getByRole('button', { name: /Raise|^Bet$/ }).click()
  await turn.getByRole('button', { name: /^Raise to|^Bet \$/ }).waitFor()
  await snap(turn, 'poker-raise')
  await turn.getByRole('button', { name: /^Raise to|^Bet \$/ }).click()
  const other = turn === a ? b : a
  await other.getByRole('button', { name: /^Call/ }).waitFor({ timeout: 8000 })

  // table chat
  await a.locator('button', { hasText: '💬' }).click()
  await a.getByPlaceholder('Say something…').fill('nice hand')
  await a.getByRole('button', { name: 'Send' }).click()
  await b.locator('button', { hasText: '💬' }).click()
  await b.locator('.msg', { hasText: 'nice hand' }).last().waitFor({ timeout: 8000 })
  await snap(b, 'poker-chat')

  // leave mid-hand
  await a.getByRole('button', { name: 'Leave' }).click()
  await toast(a, /Cashed out/)
  await a.getByText(/No-Limit Hold'em/).waitFor()
  await b.locator('.felt .gold', { hasText: /wins/ }).waitFor({ timeout: 8000 })
  await b.getByRole('button', { name: 'Leave' }).click()
  await toast(b, /Cashed out/)
  const seats = await db.query(`select count(*)::int as n from poker_seats`)
  if (seats.rows[0].n !== 0) throw new Error('seats not empty after both left')

  // accolades board has the gambler category
  await a.goto(BASE + '/accolades')
  await a.getByText('🎰 Gambler').waitFor()
  console.log('E2E CASINO PASSED')
} catch (e) {
  console.error('E2E FAILED:', e.message)
  if (shots && lastPage) await lastPage.screenshot({ path: `${shots}/FAIL.png`, fullPage: true }).catch(() => {})
  process.exitCode = 1
} finally {
  if (errors.length) { console.error('Page errors:\n' + errors.join('\n')); process.exitCode = 1 }
  await browser.close()
  await db.end()
}
