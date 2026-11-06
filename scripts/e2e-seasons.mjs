// The Seasons tab on Admin (pages/Admin.tsx, 20261106000025): an admin starts a season from the form, sees it running
// with its draw, schedules the next one for the moment it ends, cancels that, ends the running one, and the past list
// grows. A player sees the rollover: a fresh hood and Marcus's first card again, with the city still open because
// they had a hood in the season before (the veteran rule). Non-admins never see the tab. Starts with no season and
// ends with none, so the other suites are unaffected.
// Usage (local stack with the demo world): node scripts/e2e-seasons.mjs
import { chromium } from 'playwright'
import pg from 'pg'
const db = new pg.Pool({ host: 'localhost', port: Number(process.env.PGPORT || 54329), user: 'postgres', database: 'cartel' })

const BASE = process.env.BASE || 'http://127.0.0.1:5173'
const SHOTS = process.env.SHOTS || '/tmp/claude-0/shots'
const browser = await chromium.launch({ executablePath: process.env.CHROME || '/opt/pw-browsers/chromium' })
const errors = []
const RUN = Date.now().toString(36).slice(-4)
const one = async (sql, args = []) => (await db.query(sql, args)).rows[0]
// under automation useGame().ask is a native confirm (see lib/game.tsx); every one here is a yes, the last question kept
let asked = ''

const adminId = (await one(`select id from auth.users where email = 'bot01@demo.local'`)).id
const palId = (await one(`select id from auth.users where email = 'bot02@demo.local'`)).id
await db.query(`update profiles set is_admin = true where id = $1`, [adminId])
if (await one(`select 1 from seasons where ends_at > now()`)) throw new Error('this suite needs no season running or scheduled')
const signIn = async (ctx, email) => {
  const p = await ctx.newPage()
  p.on('pageerror', e => errors.push(e.message))
  p.on('dialog', d => { asked = d.message(); d.accept() })
  await p.goto(BASE)
  await p.getByLabel('Email').fill(email)
  await p.getByLabel('Password').fill('secret123')
  await p.getByRole('button', { name: 'Sign In' }).click()
  await p.locator('.topbar').waitFor()
  return p
}
try {
  // two players, two profiles: a context keeps one sign-in
  const a = await signIn(await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 }), 'bot01@demo.local')
  const b = await signIn(await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 }), 'bot02@demo.local')

  // a player has no Seasons tab (no Admin at all)
  await b.goto(`${BASE}/admin?tab=seasons`)
  await b.getByText('Admins only.').waitFor()
  await b.goto(BASE)
  await b.locator('.quick').waitFor()
  if (await b.locator('.marcus').count()) throw new Error('no season: no Marcus')

  // 1. nothing running: the notice and the form; start one now
  await a.goto(`${BASE}/admin?tab=seasons`)
  await a.getByText('No season is running').waitFor()
  await a.getByRole('button', { name: /^Start Season \d+ Now$/ }).waitFor()
  await a.getByLabel('Name').fill(`E2E Season ${RUN}`)
  await a.getByLabel('Defenders, blocks 1–6 and the boss').fill('1, 1, 1, 1, 1, 1')
  await a.getByText('Seven whole numbers above zero.').waitFor()
  if (!(await a.getByRole('button', { name: /^Start E2E Season/ }).isDisabled())) throw new Error('six defenders: no start')
  await a.getByLabel('Defenders, blocks 1–6 and the boss').fill('1, 22, 32, 45, 60, 75, 95')
  await a.getByRole('button', { name: `Start E2E Season ${RUN} Now` }).click()
  await a.locator('.toast', { hasText: `E2E Season ${RUN} is on` }).waitFor()
  if (!/Six businesses are drawn at random/.test(asked)) throw new Error('the start asks first: ' + asked)
  await a.locator('#season-running .hd', { hasText: `E2E Season ${RUN}` }).waitFor()
  if ((await a.locator('#season-running .pill').count()) !== 6) throw new Error('six businesses on the running season')
  await a.getByText('Defenders 1 · 22 · 32 · 45 · 60 · 75 · boss 95').waitFor()
  await a.screenshot({ path: `${SHOTS}/seasons-running.png`, fullPage: true })

  // the player: Marcus is on, the hood is fresh, the city is locked (first season)
  await b.goto(BASE)
  await b.locator('.marcus').waitFor()
  await b.getByRole('link', { name: 'Actions, locked' }).waitFor()
  await b.getByRole('link', { name: 'Open Your Hood' }).click()
  await b.locator('.hood-grid').waitFor()
  await b.getByRole('button', { name: /^Attack · 100% to win/ }).click()
  await b.locator('.attack-result', { hasText: 'Block 1 is ours.' }).waitFor()
  const s1 = (await one(`select id from seasons where name = $1`, [`E2E Season ${RUN}`])).id
  if ((await one(`select count(*)::int n from home_blocks where player_id = $1 and season_id = $2 and cleared_at is not null`, [palId, s1])).n !== 1) throw new Error('block 1 taken in season 1')

  // 2. schedule the next for the moment this ends, then cancel it
  await a.reload(); await a.locator('#season-running').waitFor()
  await a.getByText(/^Starts the moment E2E Season/).waitFor()
  await a.getByRole('button', { name: /^Schedule Season \d+$/ }).click()
  await a.locator('.toast', { hasText: 'scheduled' }).waitFor()
  if (!/^Schedule Season \d+ on /.test(asked)) throw new Error('scheduling names the day: ' + asked)
  await a.locator('#season-scheduled').waitFor()
  await a.locator('#season-scheduled').getByRole('button', { name: 'Cancel' }).click()
  await a.locator('.toast', { hasText: 'cancelled' }).waitFor()
  await a.locator('#season-scheduled').waitFor({ state: 'detached' })
  await a.locator('#season-next').waitFor()
  await a.locator('.card', { hasText: 'Past seasons' }).getByText('· cancelled').waitFor()   // kept, marked

  // 3. end it now: the past list has it; the player is between seasons
  await a.getByRole('button', { name: 'End Season Now' }).click()
  await a.locator('.toast', { hasText: 'is over' }).waitFor()
  if (!/plays with no season/.test(asked)) throw new Error('ending says what follows: ' + asked)
  await a.getByText('No season is running').waitFor()
  await a.locator('.card', { hasText: 'Past seasons' }).getByText(`E2E Season ${RUN}`).waitFor()
  await b.goto(BASE)
  await b.locator('.quick').waitFor()
  if (await b.locator('.marcus').count()) throw new Error('between seasons: no Marcus')
  await b.locator('.tabbar a[href="/actions"]:not(.locked)').waitFor()

  // 4. the next season: the veteran keeps the city, gets a fresh hood and mission 1 again; season 1's rows stay
  await a.getByLabel('Name').fill(`E2E Season ${RUN}b`)
  await a.getByRole('button', { name: `Start E2E Season ${RUN}b Now` }).click()
  await a.locator('.toast', { hasText: 'is on' }).waitFor()
  await b.goto(BASE)
  await b.locator('.marcus').waitFor()
  await b.getByText('Look at your six blocks').waitFor()
  await b.locator('.tabbar a[href="/actions"]:not(.locked)').waitFor()   // open: a veteran
  if (await b.getByRole('link', { name: 'Actions, locked' }).count()) throw new Error('a veteran keeps the city')
  await b.getByRole('link', { name: 'Open Your Hood' }).click()
  await b.locator('.hood-grid').waitFor()
  if ((await b.locator('.hood-grid .block.yours').count()) !== 0) throw new Error('a fresh hood')
  if ((await one(`select count(*)::int n from home_blocks where player_id = $1 and season_id = $2 and cleared_at is not null`, [palId, s1])).n !== 1) throw new Error('season 1 history kept')
  await b.screenshot({ path: `${SHOTS}/seasons-rollover.png` })

  if (errors.length) throw new Error(errors.join('\n'))
  console.log('e2e-seasons PASSED: start, schedule, cancel, end from the Admin tab; the rollover gives a fresh hood, mission 1 and an open city to a veteran')
} catch (e) {
  console.error('e2e-seasons FAILED:', e.message)
  process.exitCode = 1
} finally {
  await browser.close()
  await db.query(`delete from seasons where name like $1`, [`E2E Season ${RUN}%`]).catch(() => {})
  await db.query(`update profiles set is_admin = false where id = $1`, [adminId]).catch(() => {})
  await db.end()
}
