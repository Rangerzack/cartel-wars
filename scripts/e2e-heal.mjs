// Browser walkthrough for healing to full where you're hurt (components/Heal.tsx): health is only sold all the way to
// your max, at one price, or you wait till you have it. Actions from a hospital bed and a player's page offer it in
// place; the hospital card has nothing else (no point picker, no partial check-out); short of cash it's off and says why.
// Usage (local stack running): node scripts/e2e-heal.mjs
import { chromium } from 'playwright'
import pg from 'pg'
const db = new pg.Pool({ host: 'localhost', port: Number(process.env.PGPORT || 54329), user: 'postgres', database: 'cartel' })

const BASE = process.env.BASE || 'http://127.0.0.1:5173'
const SHOTS = process.env.SHOTS || '/tmp/claude-0/shots'
const browser = await chromium.launch({ executablePath: process.env.CHROME || '/opt/pw-browsers/chromium' })
const errors = []
const RUN = Date.now().toString(36).slice(-4)
const N = (base) => `${base}${RUN}`
const one = async (sql, args = []) => (await db.query(sql, args)).rows[0]
const dollars = (t) => Number(t.replace(/[^0-9]/g, ''))

try {
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 })
  const p = await ctx.newPage()
  p.on('pageerror', e => errors.push(e.message))
  p.on('dialog', d => d.accept())
  await p.goto(BASE)
  await p.getByRole('button', { name: 'New Player' }).click()
  await p.getByLabel('Street name').fill(N('Doc'))
  await p.getByLabel('Email').fill(`doc${RUN}-${Date.now()}@test.local`)
  await p.getByLabel('Password').fill('secret123')
  await p.getByRole('button', { name: 'Enter the City' }).click()
  await p.locator('.topbar').waitFor()
  const me = (await one('select id from profiles where name = $1', [N('Doc')])).id
  // laid up at 5 health; the clock pinned so no healing tick lands mid-test
  const layUp = (health, cash) => db.query(`update profiles set health = $2, in_hospital = $3, health_tick = now(), cash = $4, health_bought = 0 where id = $1`, [me, health, health < 20, cash])

  // Actions from a hospital bed: Heal to Full right on the page, priced the way the server charges it
  await layUp(5, 50000)
  await p.goto(`${BASE}/actions`)
  await p.locator('.notice', { hasText: "You can't work from a hospital bed" }).waitFor()
  const heal = p.getByRole('button', { name: /^Heal to Full \(\+\d+\) · \$/ })
  await heal.waitFor()
  const label = await heal.innerText()
  const max = (await one('select health_max from profiles where id = $1', [me])).health_max
  if (!label.includes(`(+${max - 5})`)) throw new Error('heals the whole way: ' + label)
  await p.screenshot({ path: `${SHOTS}/heal-actions.png` })
  const price = dollars(label.split('·')[1])
  await heal.click()
  await p.locator('.toast', { hasText: `Healed to full for $${price.toLocaleString('en-US')}` }).waitFor()
  const healed = await one('select health, health_max, cash from profiles where id = $1', [me])
  if (healed.health !== healed.health_max || Number(healed.cash) !== 50000 - price) throw new Error('healed to full at the shown price: ' + JSON.stringify(healed))
  if (!p.url().endsWith('/actions')) throw new Error('stays on Actions')
  await p.locator('.notice', { hasText: 'hospital bed' }).waitFor({ state: 'detached' })

  // the hospital card: one button, nothing partial; short of cash, it's off and says why
  await layUp(60, 10)
  await p.goto(`${BASE}/services?focus=hospital`)
  const card = p.locator('#hospital')
  const full = card.getByRole('button', { name: /^Heal to Full \(\+\d+\) · \$/ })
  await full.waitFor()
  if (!(await full.isDisabled())) throw new Error('no heal without the cash')
  await card.getByText(/you have \$10 on hand\. Wait till you have it/).waitFor()
  if (await card.locator('.qty').count()) throw new Error('no point picker on the hospital card')
  if (await card.getByRole('button', { name: /Check Out|Buy \+|^\+25$|^\+50$/ }).count()) throw new Error('no partial buys on the hospital card')
  await card.screenshot({ path: `${SHOTS}/heal-card.png` })

  // a player's page from a hospital bed: why Attack is off, and the heal under it
  await layUp(5, 50000)
  const thug = (await one('select id from profiles where is_bot order by bot_level limit 1')).id
  await p.goto(`${BASE}/player/${thug}`)
  await p.getByText("You're in the hospital — heal to full to fight again, or wait it out.").waitFor()
  await p.getByRole('button', { name: /^Heal to Full/ }).click()
  await p.locator('.toast', { hasText: /^Healed to full for \$/ }).waitFor()
  await p.getByRole('button', { name: '⚔️ Attack' }).waitFor()
  // the refresh after the heal turns Attack back on
  await p.waitForFunction(() => [...document.querySelectorAll('button')].some(b => b.textContent.trim() === '⚔️ Attack' && !b.disabled), null, { timeout: 5000 })
    .catch(() => { throw new Error('Attack comes back once you are healed') })

  if (errors.length) throw new Error(errors.join('\n'))
  console.log('e2e-heal PASSED: heal to full in place on Actions and a player page, full-only hospital card, short of cash says why')
} catch (e) {
  console.error('e2e-heal FAILED:', e.message)
  process.exitCode = 1
} finally {
  await browser.close()
  await db.end()
}
