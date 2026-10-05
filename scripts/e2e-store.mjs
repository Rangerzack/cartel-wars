// Browser walkthrough for the store on the web build (#15, #16, #17): the packs with no prices and the "sold in the iPhone
// app" line, the Daily Drop's odds (adding up to 100%) above Subscribe with Terms and Privacy, the free plan still
// subscribing on the web, and what the webhook does as the player sees it: a pack credited (activity line), purchased
// diamonds refused as a gift, a paid plan with Manage subscription in place of Cancel, and a refund.
// The webhook itself isn't running here; the script calls iap_apply in the database the way the edge function does.
// Usage (local stack running): node scripts/e2e-store.mjs [--shots dir]
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
  // Manage subscription opens Apple's page; answer it here instead of going out to the internet
  await ctx.route('https://apps.apple.com/**', r => r.fulfill({ status: 200, contentType: 'text/html', body: '<title>Subscriptions</title>' }))
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
const iap = (event, tx, product, player, days = null, raw = {}) => one(
  `select iap_apply('revenuecat', $1, $2, $3, $4, case when $5::int is null then null else now() + make_interval(days => $5::int) end, $6) as r`,
  [event, tx, product, player, days, raw])
const PACK = 'io.rangelab.cartelwars.diamonds.550', DROP = 'io.rangelab.cartelwars.drop.monthly'

try {
  const b = await newPlayer(N('Recv'))
  const bId = (await one('select id from profiles where name = $1', [N('Recv')])).id
  await b.context().close()
  const a = await newPlayer(N('Buyer'))
  const aId = (await one('select id from profiles where name = $1', [N('Buyer')])).id

  // Home's quick grid → the store: on the web the Diamonds card says where they're sold (and that they can be earned),
  // with no pack list at all: a list with no prices and no buttons was a dead end
  await a.locator('.quick').getByRole('link', { name: 'Store' }).click()
  await a.waitForURL(/\/store$/)
  const packs = a.locator('#diamonds')
  const notice = packs.getByText(/Diamonds are sold in the iPhone app\. Everything they buy can also be earned/)
  await notice.waitFor()
  const rows = packs.locator('.store-pack')
  if (await rows.count() !== 0) throw new Error(`no pack list on the web, got ${await rows.count()}`)
  if (await packs.getByRole('button').count() !== 0) throw new Error('no buy buttons on the web')
  if (/\$\s?\d/.test(await packs.innerText())) throw new Error('no prices on the web')
  if (await a.getByRole('button', { name: 'Restore purchases' }).count() !== 0) throw new Error('no restore on the web')
  await packs.getByText('Only diamonds you earn in the game can be sent').waitFor()

  // The Daily Drop below it: the odds before Subscribe, adding up to 100%; free, no price anywhere
  const card = a.locator('#drop')
  await card.getByText('FREE', { exact: true }).waitFor()
  const odds = card.locator('.drop-odds .row:has(.ico)')
  await odds.nth(10).waitFor()
  if (await odds.count() !== 11) throw new Error(`odds rows ${await odds.count()}`)
  const pcts = (await odds.locator('b.tabular').allTextContents()).map(s => Number(s.replace('%', '')))
  const sum = Math.round(pcts.reduce((s, x) => s + x, 0) * 10) / 10
  if (sum !== 100) throw new Error(`odds add up to ${sum}%: ${pcts.join(', ')}`)
  const sub = card.getByRole('button', { name: 'Subscribe — Free for Now' })
  const oddsBox = await card.locator('.drop-odds').boundingBox(), subBox = await sub.boundingBox()
  if (!(oddsBox.y + oddsBox.height <= subBox.y)) throw new Error('the odds sit above Subscribe')
  await card.getByText('In the iPhone app it will be a monthly subscription.').waitFor()
  if (/\$\d+\.\d\d|\/mo\b|a month once/.test(await card.innerText())) throw new Error('no subscription price on the web')
  for (const [label, file] of [['Terms of service', 'terms.html'], ['Privacy policy', 'privacy.html']]) {
    const href = await card.getByRole('link', { name: label }).getAttribute('href')
    if (!href?.endsWith(file)) throw new Error(`${label} → ${href}`)
  }
  await snap(a, 'store-web')

  // The free plan still works on the web
  await sub.click()
  await a.getByText('Subscribed — your first crate is here').waitFor()
  await card.getByText('1/7 crates').waitFor()
  await card.getByText(/free plan/).waitFor()
  await card.getByRole('button', { name: 'Cancel' }).waitFor()

  // The webhook credits a pack: the diamonds land, with an activity line
  let r = (await iap('NON_RENEWING_PURCHASE', `e2e-${RUN}-1`, PACK, aId)).r
  if (r.credited !== 550) throw new Error('credit: ' + JSON.stringify(r))
  await a.reload()
  await packs.getByText('💎 575').waitFor()
  await a.goto(`${BASE}/activity`)
  await a.getByText('You bought 550 diamonds').waitFor()
  await snap(a, 'bought')

  // Bought diamonds stay with the buyer: only the 25 earned can go
  await a.goto(`${BASE}/player/${bId}`)
  const dia = a.getByPlaceholder('Diamonds')
  await dia.fill('26')
  await a.getByRole('button', { name: 'Send 💎' }).click()
  await a.getByText('You can only send diamonds you earned in the game').waitFor()
  await dia.fill('25')
  await a.getByRole('button', { name: 'Send 💎' }).click()
  await a.getByText(`Sent 💎 25 to ${N('Recv')}`).waitFor()
  const after = await one('select diamonds, diamonds_bought_unspent from profiles where id = $1', [aId])
  if (after.diamonds !== 550 || Number(after.diamonds_bought_unspent) !== 550) throw new Error('after the gift: ' + JSON.stringify(after))
  await snap(a, 'gift')

  // A paid plan (bought in the app): Manage subscription instead of Cancel, and it opens Apple's page
  r = (await iap('INITIAL_PURCHASE', `e2e-${RUN}-sub`, DROP, aId, 30)).r
  if (!r.subscribed) throw new Error('subscribe: ' + JSON.stringify(r))
  await a.goto(`${BASE}/store`)
  await card.getByText(/paid through/).waitFor()
  if (await card.getByRole('button', { name: 'Cancel' }).count() !== 0) throw new Error('no Cancel on a paid plan')
  const [apple] = await Promise.all([a.context().waitForEvent('page'), card.getByRole('button', { name: 'Manage subscription' }).click()])
  await apple.waitForLoadState()
  if (apple.url() !== 'https://apps.apple.com/account/subscriptions') throw new Error('manage → ' + apple.url())
  await apple.close()
  await snap(a, 'paid-plan')

  // Apple refunds the pack: the diamonds go back, with an activity line
  r = (await iap('CANCELLATION', `e2e-${RUN}-1`, PACK, aId, null, { cancel_reason: 'CUSTOMER_SUPPORT' })).r
  if (r.revoked !== 550) throw new Error('refund: ' + JSON.stringify(r))
  await a.goto(`${BASE}/activity`)
  await a.getByText('Apple refunded a 550-diamond purchase, so 550 diamonds were taken back').waitFor()
  if ((await one('select diamonds from profiles where id = $1', [aId])).diamonds !== 0) throw new Error('refunded down to 0')
  await snap(a, 'refunded')

  console.log('E2E STORE PASSED')
} catch (e) {
  console.error('E2E STORE FAILED:', e.message)
  if (shots && lastPage) await lastPage.screenshot({ path: `${shots}/FAIL.png`, fullPage: true }).catch(() => {})
  process.exitCode = 1
} finally {
  if (errors.length) { console.error('Page errors:\n' + errors.join('\n')); process.exitCode = 1 }
  await browser.close()
  await db.end()
}
