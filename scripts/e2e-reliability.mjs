// Browser walkthrough for the Phase 2 reliability fixes: a failed first load shows Retry (and recovers), chat keeps
// your place and your draft, the casino is fully off while jailed, roulette holds the table max, the quantity field can
// be cleared and retyped, a deleted crew sends you back without a Back loop, Build and Sell only show when the server
// would accept them.
// Usage (local stack running): node scripts/e2e-reliability.mjs
import { chromium } from 'playwright'
import pg from 'pg'
const db = new pg.Pool({ host: 'localhost', port: Number(process.env.PGPORT || 54329), user: 'postgres', database: 'cartel' })

const BASE = process.env.BASE || 'http://127.0.0.1:5173'
const browser = await chromium.launch({ executablePath: process.env.CHROME || '/opt/pw-browsers/chromium' })
const errors = []
const RUN = Date.now().toString(36).slice(-4)
const N = (base) => `${base}${RUN}`
const one = async (sql, args = []) => (await db.query(sql, args)).rows[0]

try {
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 })
  const p = await ctx.newPage()
  p.on('pageerror', e => errors.push(e.message))
  p.on('dialog', d => d.accept())
  await p.goto(BASE)
  await p.getByRole('button', { name: 'New Player' }).click()
  await p.getByLabel('Street name').fill(N('Rel'))
  await p.getByLabel('Email').fill(`rel${RUN}-${Date.now()}@test.local`)
  await p.getByLabel('Password').fill('secret123')
  await p.getByRole('button', { name: 'Enter the City' }).click()
  await p.locator('.topbar').waitFor()
  const me = (await one('select id from profiles where name = $1', [N('Rel')])).id
  await db.query('update profiles set cash = 2000000, diamonds = 0 where id = $1', [me])

  // 1. a failed first load: Retry where the spinner was, and it recovers once the server answers
  let fail = true
  await p.route('**/rpc/find_thugs', route => (fail ? route.fulfill({ status: 500, contentType: 'application/json', body: '{"message":"boom"}' }) : route.continue()))
  await p.goto(`${BASE}/fight?tab=thugs`)
  const retry = p.getByRole('button', { name: 'Try again' })
  await retry.waitFor()
  fail = false
  await retry.click()
  await p.locator('.thug-row').first().waitFor()
  await p.unroute('**/rpc/find_thugs')

  // 2. chat: scrolled up to read, a new line doesn't snap you down; a refused send keeps the draft
  await db.query(`insert into messages (channel, sender_id, sender_name, body) select 'global', $1, $2, 'line ' || g from generate_series(1, 40) g`, [me, N('Rel')])
  await p.goto(`${BASE}/chat`)
  const log = p.locator('.chat .log')
  await log.locator('.msg').nth(39).waitFor()
  await log.evaluate(el => { el.scrollTop = 0 })
  await db.query(`insert into messages (channel, sender_id, sender_name, body) values ('global', $1, $2, 'the newest line')`, [me, N('Rel')])
  await log.locator('.msg', { hasText: 'the newest line' }).waitFor({ timeout: 8000 })
  if (await log.evaluate(el => el.scrollTop) > 40) throw new Error('reading history, the log should stay where it was')
  await p.route('**/rpc/send_message', route => route.fulfill({ status: 400, contentType: 'application/json', body: '{"message":"Easy on the language"}' }))
  const box = p.getByPlaceholder('Say something…')
  await box.fill('keep me')
  await p.getByRole('button', { name: 'Send' }).click()
  await p.locator('.toast', { hasText: 'Easy on the language' }).waitFor()
  if (await box.inputValue() !== 'keep me') throw new Error('a refused send should leave the draft in the box')
  await p.unroute('**/rpc/send_message')

  // 3. jailed, the whole casino is off: no chip, spin, spot or deal takes a tap
  await db.query(`update profiles set jail_until = 'infinity' where id = $1`, [me])
  await p.goto(`${BASE}/casino/roulette`)
  await p.getByText('No gambling from a cell.').waitFor()
  await p.locator('fieldset.lockable:disabled').first().waitFor()
  if (!(await p.locator('.roulette .n').first().isDisabled())) throw new Error('the felt should be off while jailed')
  if (!(await p.locator('.chip').first().isDisabled())) throw new Error('the chips should be off while jailed')
  await db.query(`update profiles set jail_until = null, heat = 0 where id = $1`, [me])

  // 4. roulette: over the table max the spin is off and says why
  await p.goto(`${BASE}/casino/roulette`)
  await p.locator('.roulette .n').first().waitFor()
  await p.locator('.chip', { hasText: '$100k' }).click()
  for (let i = 0; i < 6; i++) await p.locator('.outside.six .o').first().click()
  await p.getByText('Table max is $500,000 a spin').waitFor()
  if (!(await p.getByRole('button', { name: /^Spin · / }).isDisabled())) throw new Error('over the table max, Spin is off')

  // 5. the quantity field: clear it and type 5, and it's 5 (not 15)
  await db.query('update profiles set cash = 2000000 where id = $1', [me])
  await p.goto(`${BASE}/services?focus=hoodlums`)
  const qty = p.locator('#hoodlums .qty input')
  await qty.waitFor()
  await qty.fill('')
  await qty.type('5')
  if (await qty.inputValue() !== '5') throw new Error('cleared and retyped: ' + await qty.inputValue())
  await p.locator('#hoodlums').getByRole('button', { name: /^Hire · / }).waitFor()
  if (!/Hire · \$[\d,]+/.test(await p.locator('#hoodlums').getByRole('button', { name: /^Hire · / }).innerText())) throw new Error('the price follows the count')

  // 6. a crew that doesn't exist: back to the hub, and Back from there leaves the hub (no loop)
  await p.goto(`${BASE}/`)
  await p.goto(`${BASE}/crew/00000000-0000-4000-8000-000000000000`)
  await p.waitForURL(/\/crew$/)
  await p.locator('.toast', { hasText: 'That crew is gone' }).waitFor()
  await p.goBack()
  await p.waitForURL(/\/$/)

  // 7. a second grow house needs diamonds: Build is off and says how many
  await db.query(`update profiles set diamonds = 0, path = 'producer' where id = $1`, [me])
  await p.goto(`${BASE}/economy`)
  const build = p.locator('.row', { hasText: 'grow house' }).getByRole('button', { name: /^Build/ })
  await build.first().waitFor()
  await build.first().click()
  await p.locator('.toast', { hasText: /grow house is up and running/ }).waitFor()
  await p.locator('.row', { hasText: 'grow house' }).getByText(/Need 💎 \d+ more diamonds/).first().waitFor()
  if (!(await build.first().isDisabled())) throw new Error('a second house without the diamonds: Build is off')

  // 8. the shop: Sell shows only for a unit that isn't equipped
  await p.goto(`${BASE}/items?tab=shop`)
  const knuckles = p.locator('.row', { hasText: 'Brass Knuckles' })
  await knuckles.getByRole('button', { name: /^\$/ }).click()
  await p.locator('.toast', { hasText: /Bought Brass Knuckles/ }).waitFor()
  await p.goto(`${BASE}/items?tab=shop`)
  await knuckles.waitFor()
  if (await knuckles.getByRole('button', { name: /^Sell/ }).count()) throw new Error('the only unit is equipped: no Sell')
  // a second one is equipped too (the shop equips what it sells); once a setup lets one go, that unit can be sold
  await knuckles.getByRole('button', { name: /^\$/ }).click()
  await p.locator('.toast', { hasText: /Bought Brass Knuckles/ }).waitFor()
  await p.goto(`${BASE}/items?tab=shop`)
  await knuckles.waitFor()
  if (await knuckles.getByRole('button', { name: /^Sell/ }).count()) throw new Error('both units equipped: still no Sell')
  await db.query(`update setup_items set qty = 1 where player_id = $1 and item_id = 1`, [me])
  await p.goto(`${BASE}/items?tab=shop`)
  await knuckles.getByRole('button', { name: /^Sell/ }).waitFor()

  if (errors.length) throw new Error(errors.join('\n'))
  console.log('e2e-reliability PASSED: retry on a failed load, chat keeps place and draft, casino lock, table max, qty field, gone crew, build and sell guards')
} catch (e) {
  console.error('e2e-reliability FAILED:', e.message)
  process.exitCode = 1
} finally {
  await browser.close()
  await db.end()
}
