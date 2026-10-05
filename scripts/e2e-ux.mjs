// Browser walkthrough for Phase 3 (UX): a new player's Home leads with the next step; Next up gathers what's waiting
// (trips back, full grow houses, crates, the hospital) and each is done right there; the shop buys and sells five at a
// time; Do It buttons are named for their job and say what happened; Sign out takes one tap; chat loads older lines
// without losing your place; at a casino table toasts drop in under the top bar, clear of the bet bar.
// Usage (local stack running): node scripts/e2e-ux.mjs
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
  // no dialog handler on purpose: a window.confirm that turns up where none should is dismissed, and the step fails
  await p.goto(BASE)
  await p.getByRole('button', { name: 'New Player' }).click()
  await p.getByLabel('Street name').fill(N('Ux'))
  await p.getByLabel('Email').fill(`ux${RUN}-${Date.now()}@test.local`)
  await p.getByLabel('Password').fill('secret123')
  await p.getByRole('button', { name: 'Enter the City' }).click()
  await p.locator('.topbar').waitFor()
  const me = (await one('select id from profiles where name = $1', [N('Ux')])).id

  // 1. a new player's Home: Getting started is the first card, showing just the next step; the rest open under it
  const gs = p.locator('.getting-started')
  await gs.waitFor()
  if (!(await p.locator('.page > *').first().evaluate(el => el.classList.contains('getting-started')))) throw new Error('Getting started leads Home')
  await gs.getByText('0 of 6 done').waitFor()
  if (await gs.locator('a.row').count() !== 1) throw new Error('one step showing')
  await gs.locator('a.row.next', { hasText: 'Run an Action' }).waitFor()
  if (await p.locator('.next-up').count()) throw new Error('nothing waiting: no Next up card')
  await gs.getByRole('button', { name: 'See all 6 steps' }).click()
  if (await gs.locator('a.row').count() !== 6) throw new Error('all six once opened')
  await gs.getByRole('button', { name: 'Just the next step' }).click()
  await gs.locator('a.row.next').click()
  await p.waitForURL(/\/actions$/)

  // 2. Actions: Do It is named for the job, and the result is read out
  const first = p.getByRole('button', { name: /^Do It: / }).first()
  const job = (await first.getAttribute('aria-label')).replace('Do It: ', '')
  await first.click()
  await p.locator('[role="status"]', { hasText: new RegExp(`^${job.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}: plus`) }).waitFor()
  await p.goto(BASE)
  await gs.getByText('1 of 6 done').waitFor()
  await gs.locator('a.row.next', { hasText: 'Arm your Offensive setup' }).waitFor()

  // 3. Next up: a trip back, a full grow house and a crate, each handled in place
  await db.query(`insert into hustlers (player_id, commodity, count, units, cash_due, departs_at, returns_at) values ($1, 'herb', 1, 10, 777, now() - interval '5 hours', now() - interval '1 minute')`, [me])
  await db.query(`insert into grow_houses (player_id, commodity, level, running, started_at) values ($1, 'herb', 1, true, now() - interval '30 days')`, [me])
  await db.query('update profiles set drop_crates = 1 where id = $1', [me])
  await p.reload()
  const next = p.locator('.next-up')
  await next.waitFor()
  if (!(await p.locator('.page > *').first().evaluate(el => el.classList.contains('next-up')))) throw new Error('Next up leads Home')
  await next.locator('[data-next="hustlers"]').getByText('$777 to collect').waitFor()
  await next.locator('[data-next="hustlers"]').getByRole('button', { name: 'Collect' }).click()
  await p.locator('.toast', { hasText: 'Collected $777' }).waitFor()
  await next.locator('[data-next="hustlers"]').waitFor({ state: 'detached' })
  await next.locator('[data-next="grow"]').getByRole('button', { name: 'Collect' }).click()
  await p.locator('.toast', { hasText: /^Collected [\d,]+ Herb/ }).waitFor()
  await next.locator('[data-next="grow"]').waitFor({ state: 'detached' })
  await next.locator('[data-next="crates"]').getByRole('button', { name: 'Open' }).click()
  await p.locator('.modal .drop-prize .name').waitFor()
  await p.locator('.modal').getByRole('button', { name: 'Close' }).last().click()
  await p.locator('.next-up').waitFor({ state: 'detached' })

  // 4. in the hospital: Heal to Full right on Home
  await db.query('update profiles set health = 5, in_hospital = true, cash = 1000000 where id = $1', [me])
  await p.reload()
  const hosp = p.locator('.next-up [data-next="hospital"]')
  await hosp.getByText("You're in the hospital").waitFor()
  await hosp.getByRole('button', { name: /^Heal to Full/ }).click()
  await p.locator('.toast', { hasText: /^Healed to full for/ }).waitFor()
  await hosp.waitFor({ state: 'detached' })

  // 5. the shop: ×5 buys five and equips what fits; Sell takes the loose ones five at a time
  await db.query('update profiles set cash = 1000000 where id = $1', [me])
  await p.goto(`${BASE}/items?tab=shop`)
  await p.getByText('$1,000,000 on hand').waitFor()
  await p.getByRole('button', { name: '×5', exact: true }).click()
  const knuckles = p.locator('.row', { hasText: 'Brass Knuckles' })
  await knuckles.getByRole('button', { name: /^5 · \$/ }).click()
  await p.locator('.toast', { hasText: /^Bought 5 Brass Knuckles and equipped them/ }).waitFor()
  const inv = await one('select qty from inventory where player_id = $1 and item_id = 1', [me])
  if (inv?.qty !== 5) throw new Error('five bought: ' + JSON.stringify(inv))
  const eq = await one(`select max(qty) as q from setup_items where player_id = $1 and item_id = 1`, [me])
  if (eq.q !== 5) throw new Error('all five equipped (six slots free): ' + JSON.stringify(eq))
  await knuckles.getByRole('button', { name: /^5 · \$/ }).click()
  // the first toast may still be up: wait on the server for the second five (one more fits each setup)
  for (let i = 0; ; i++) {
    if ((await one(`select max(qty) as q from setup_items where player_id = $1 and item_id = 1`, [me])).q === 6) break
    if (i > 50) throw new Error('the second five: one more equipped in each setup')
    await p.waitForTimeout(200)
  }
  // ten owned, at most six equipped in any one setup: four loose, so Sell offers four
  await p.reload()
  await knuckles.getByRole('button', { name: /^Sell 4 / }).waitFor()
  p.once('dialog', d => d.accept())   // selling asks first (window.confirm under automation)
  await knuckles.getByRole('button', { name: /^Sell 4 / }).click()
  await p.locator('.toast', { hasText: /^Sold 4 for \$/ }).waitFor()
  if ((await one('select qty from inventory where player_id = $1 and item_id = 1', [me])).qty !== 6) throw new Error('six left')

  // 6. chat: Load older brings 50 more and leaves you where you were reading
  await db.query(`insert into messages (channel, sender_id, sender_name, body, created_at) select 'global', $1, $2, 'ux line ' || g, now() - make_interval(secs => (120 - g) / 10.0) from generate_series(1, 120) g`, [me, N('Ux')])
  await p.goto(`${BASE}/chat`)
  const log = p.locator('.chat .log')
  await log.locator('.msg', { hasText: 'ux line 120' }).waitFor()
  if (await log.locator('.msg').count() !== 50) throw new Error('fifty lines to start')
  await log.evaluate(el => { el.scrollTop = 0 })
  const topLine = await log.locator('.msg').first().innerText()
  await log.getByRole('button', { name: 'Load older messages' }).click()
  await log.locator('.msg').nth(99).waitFor()
  const box = await log.boundingBox()
  const stillThere = await log.locator('.msg', { hasText: topLine.split('\n')[1] ?? topLine }).first().boundingBox()
  if (!stillThere || stillThere.y < box.y - 5 || stillThere.y > box.y + box.height) throw new Error('the line you were reading stays in view')

  // 7. at a casino table, a toast drops in under the top bar, clear of the bet bar
  await p.goto(`${BASE}/casino/slots`)
  await p.locator('.table-bar').waitFor()
  await p.route('**/rpc/slots_spin', route => route.fulfill({ status: 400, contentType: 'application/json', body: '{"message":"Table is closed"}' }))
  await p.getByRole('button', { name: /^Spin for / }).click()
  const toast = p.locator('.toast', { hasText: 'Table is closed' })
  await toast.waitFor()
  const tb = await toast.boundingBox(), bar = await p.locator('.table-bar').boundingBox()
  if (tb.y + tb.height > bar.y) throw new Error(`toast over the bet bar: toast ends ${tb.y + tb.height}, bar starts ${bar.y}`)
  await p.unroute('**/rpc/slots_spin')

  // 8. Sign out: one tap, no "are you sure"
  await p.goto(`${BASE}/profile`)
  await p.getByRole('button', { name: 'Sign out' }).click()
  await p.getByRole('button', { name: 'New Player' }).waitFor()

  if (errors.length) throw new Error(errors.join('\n'))
  console.log('e2e-ux PASSED: Home leads with the next step, Next up done in place, named Do It with a spoken result, shop ×5, chat load older, toasts clear of the table, one-tap sign out')
} catch (e) {
  console.error('e2e-ux FAILED:', e.message)
  process.exitCode = 1
} finally {
  await browser.close()
  await db.end()
}
