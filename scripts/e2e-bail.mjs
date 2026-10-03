// Browser walkthrough for posting bail where you got busted (components/Bail.tsx): the bust sheet after a job pays
// bail on the spot and leaves you on Actions; a deliberate trip in (the Bribe Police job) offers Stay inside first;
// short of cash, the button is off and says why.
// Usage (local stack running): node scripts/e2e-bail.mjs
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

try {
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 })
  const p = await ctx.newPage()
  p.on('pageerror', e => errors.push(e.message))
  p.on('dialog', d => d.accept())
  await p.goto(BASE)
  await p.getByRole('button', { name: 'New Player' }).click()
  await p.getByLabel('Street name').fill(N('Bix'))
  await p.getByLabel('Email').fill(`bix${RUN}-${Date.now()}@test.local`)
  await p.getByLabel('Password').fill('secret123')
  await p.getByRole('button', { name: 'Enter the City' }).click()
  await p.locator('.topbar').waitFor()
  const me = (await one('select id from profiles where name = $1', [N('Bix')])).id
  await db.query('update profiles set cash = 20000, stamina = 50, stamina_max = 50, heat = 0 where id = $1', [me])

  // the next job comes back busted: the server's answer with busted set, and the player put inside before it lands
  const bustNext = () => p.route('**/rpc/do_action', async route => {
    const res = await route.fetch()
    const body = await res.json()
    await db.query(`update profiles set jail_until = 'infinity' where id = $1`, [me])
    body.busted = true
    await route.fulfill({ response: res, json: body })
    await p.unroute('**/rpc/do_action')
  })
  const sling = p.locator('.row.action', { hasText: 'Sling on the Corner' })

  // busted on a job: Post Bail on the sheet pays it, right there
  await p.goto(`${BASE}/actions`)
  await bustNext()
  await sling.getByRole('button', { name: 'Do It' }).click()
  const sheet = p.locator('.modal', { hasText: 'Busted' })
  await sheet.waitFor()
  if ((await one('select heat = heat_max as maxed from profiles where id = $1', [me])).maxed !== true) throw new Error('busted: heat maxed')
  await p.screenshot({ path: `${SHOTS}/bail-sheet.png` })
  const cash0 = Number((await one('select cash from profiles where id = $1', [me])).cash)
  await sheet.getByRole('button', { name: 'Post Bail · $8,000' }).click()
  await p.locator('.toast', { hasText: 'Bailed out for $8,000 · heat back to 0' }).waitFor()
  await sheet.waitFor({ state: 'detached' })
  if (!p.url().endsWith('/actions')) throw new Error('bail keeps you on Actions, not the jail card: ' + p.url())
  const out = await one('select jail_until, heat, cash from profiles where id = $1', [me])
  if (out.jail_until !== null || out.heat !== 0 || Number(out.cash) !== cash0 - 8000) throw new Error('bailed on the spot: ' + JSON.stringify(out))
  await p.locator('h2', { hasText: /^Actions$/ }).waitFor()

  // the Bribe Police job puts you in on purpose: Stay inside comes first, and closes the sheet with you still inside
  const bribe = p.locator('.row.action', { hasText: 'Bribe Police To Get In Jail' })
  await bribe.getByRole('button', { name: 'Do It' }).click()
  const inSheet = p.locator('.modal', { hasText: 'Bribe Police To Get In Jail' })
  await inSheet.getByRole('button', { name: 'Post Bail · $8,000' }).waitFor()
  await p.screenshot({ path: `${SHOTS}/bail-bribe.png` })
  await inSheet.getByRole('button', { name: 'Stay inside' }).click()
  await inSheet.waitFor({ state: 'detached' })
  if ((await one('select jail_until from profiles where id = $1', [me])).jail_until === null) throw new Error('Stay inside keeps you in')
  await p.locator('h2', { hasText: 'Jail Actions' }).waitFor()

  // short of cash: the button is off and says why
  await db.query('update profiles set jail_until = null, cash = 300 where id = $1', [me])
  await p.goto(`${BASE}/actions`)
  await bustNext()
  await sling.getByRole('button', { name: 'Do It' }).click()
  await sheet.waitFor()
  if (!(await sheet.getByRole('button', { name: 'Post Bail · $8,000' }).isDisabled())) throw new Error('no bail without the cash')
  await sheet.getByText(/Bail comes out of cash on hand — you have \$/).waitFor()

  if (errors.length) throw new Error(errors.join('\n'))
  console.log('e2e-bail PASSED: bail paid on the bust sheet, Stay inside after the bribe job, short of cash says why')
} catch (e) {
  console.error('e2e-bail FAILED:', e.message)
  process.exitCode = 1
} finally {
  await browser.close()
  await db.end()
}
