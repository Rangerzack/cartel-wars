// Browser walkthrough for Fight › Players filters (find_fighters): search by name, the chips (all, can fight, online,
// hospital, jail) with their counts, the sort, a dimmed row for someone you can't hit, Back from a player keeping the
// list, and the filter remembered on the next visit.
// Usage (local stack running): node scripts/e2e-fighters.mjs
import { chromium } from 'playwright'
import pg from 'pg'
const db = new pg.Pool({ host: 'localhost', port: Number(process.env.PGPORT || 54329), user: 'postgres', database: 'cartel' })

const BASE = process.env.BASE || 'http://127.0.0.1:5173'
const SHOTS = process.env.SHOTS || '/tmp/claude-0/shots'
const browser = await chromium.launch({ executablePath: process.env.CHROME || '/opt/pw-browsers/chromium' })
const errors = []
const RUN = Date.now().toString(36).slice(-4)
const N = (base) => `${base}${RUN}`

try {
  // four rivals sharing a tag, so a search for it isolates them: one free and online, one laid up, one locked up, one long gone
  const tag = N('Zq')
  const ids = {}
  for (const [k, name] of [['free', `${tag}Free`], ['hosp', `${tag}Hosp`], ['jail', `${tag}Jail`], ['gone', `${tag}Gone`]]) {
    const id = (await db.query(`insert into auth.users (id, raw_user_meta_data) values (gen_random_uuid(), $1) returning id`, [JSON.stringify({ name })])).rows[0].id
    ids[k] = id
  }
  await db.query(`update profiles set health = health_max, in_hospital = false, jail_until = null, last_seen = now(), fights_won = 0, fights_lost = 0 where id = any($1)`, [Object.values(ids)])
  await db.query(`update profiles set fights_won = 12 where id = $1`, [ids.free])
  await db.query(`update profiles set health = 4, in_hospital = true, fights_won = 3 where id = $1`, [ids.hosp])
  await db.query(`update profiles set jail_until = 'infinity', fights_won = 7 where id = $1`, [ids.jail])
  await db.query(`update profiles set last_seen = now() - interval '3 hours', fights_won = 1 where id = $1`, [ids.gone])

  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 })
  const p = await ctx.newPage()
  p.on('pageerror', e => errors.push(e.message))
  p.on('dialog', d => d.accept())
  await p.goto(BASE)
  await p.getByRole('button', { name: 'New Player' }).click()
  await p.getByLabel('Street name').fill(N('Vex'))
  await p.getByLabel('Email').fill(`vex${RUN}-${Date.now()}@test.local`)
  await p.getByLabel('Password').fill('secret123')
  await p.getByRole('button', { name: 'Enter the City' }).click()
  await p.locator('.topbar').waitFor()

  const rows = p.locator('.card .row.link')
  const chip = (name) => p.locator('.chip-nav button', { hasText: name })
  const names = async () => (await rows.locator('.t').allInnerTexts()).map(t => t.trim())

  await p.goto(`${BASE}/fight`)
  await p.getByPlaceholder('Search by name…').fill(tag)
  await rows.first().waitFor()
  await p.waitForFunction(() => document.querySelectorAll('.card .row.link').length === 4)
  // counts on the chips cover the whole search
  for (const [c, n] of [['All', 4], ['Can fight', 2], ['Online', 3], ['Hospital', 1], ['Jail', 1]]) {
    const got = (await chip(c).locator('.n').innerText()).trim()
    if (got !== String(n)) throw new Error(`${c} chip should count ${n}, got ${got}`)
  }
  // someone you can't hit is dimmed and says why; the online one has the dot
  await rows.filter({ hasText: `${tag}Hosp` }).locator('.pill', { hasText: 'Hospital' }).waitFor()
  if (!(await rows.filter({ hasText: `${tag}Jail` }).getAttribute('class')).includes('cant')) throw new Error('the jailed row should be dimmed')
  await rows.filter({ hasText: `${tag}Free` }).locator('.online-dot').waitFor()
  if (await rows.filter({ hasText: `${tag}Gone` }).locator('.online-dot').count()) throw new Error('no dot for someone gone 3 hours')

  // each chip
  // the list shows exactly these names (in this order when `ordered`), once the fetch for the new filter has landed
  const shows = async (want, ordered = false, what = '') => {
    try {
      await p.waitForFunction(([w, o]) => {
        if (document.querySelector('.card.stale')) return false
        const got = [...document.querySelectorAll('.card .row.link .t')].map(e => e.textContent.trim().split(' ')[0])
        return JSON.stringify(o ? got : got.sort()) === JSON.stringify(o ? w : [...w].sort())
      }, [want, ordered], { timeout: 5000 })
    } catch { throw new Error(`${what}: wanted ${want}, got ${(await names()).map(t => t.split(' ')[0])}`) }
  }
  const expect = async (c, want) => {
    await chip(c).click()
    await shows(want, false, c)
  }
  await expect('Can fight', [`${tag}Free`, `${tag}Gone`])
  await expect('Online', [`${tag}Free`, `${tag}Hosp`, `${tag}Jail`])
  await expect('Hospital', [`${tag}Hosp`])
  await expect('Jail', [`${tag}Jail`])
  await p.screenshot({ path: `${SHOTS}/fighters-jail.png` })

  // an empty filter offers everyone back
  await p.getByPlaceholder('Search by name…').fill(`${tag}Free`)
  await p.locator('.empty', { hasText: /Nobody named like/ }).waitFor()
  await p.getByRole('button', { name: 'Show everyone' }).click()
  await rows.filter({ hasText: `${tag}Free` }).waitFor()
  if (await chip('All').getAttribute('aria-pressed') !== 'true') throw new Error('Show everyone switches to All')

  // sort by most wins; Back from a player's page lands on the same search, filter and sort
  await p.getByPlaceholder('Search by name…').fill(tag)
  await p.getByLabel('Sort players').selectOption('wins')
  await shows([`${tag}Free`, `${tag}Jail`, `${tag}Hosp`, `${tag}Gone`], true, 'most wins first')
  await snapList()
  await rows.filter({ hasText: `${tag}Free` }).click()
  await p.waitForURL(/\/player\//)
  await p.goBack()
  await rows.first().waitFor()
  if (await p.getByPlaceholder('Search by name…').inputValue() !== tag) throw new Error('the search should survive Back')
  if (await p.getByLabel('Sort players').inputValue() !== 'wins') throw new Error('the sort should survive Back')

  // the filter you picked comes back on the next visit to the tab
  await chip('Can fight').click()
  await p.goto(`${BASE}/`)
  await p.goto(`${BASE}/fight`)
  if (await chip('Can fight').getAttribute('aria-pressed') !== 'true') throw new Error('the last filter should be remembered')
  if (await p.getByLabel('Sort players').inputValue() !== 'wins') throw new Error('the last sort should be remembered')

  async function snapList() { await p.screenshot({ path: `${SHOTS}/fighters.png` }) }
  if (errors.length) throw new Error(errors.join('\n'))
  console.log('e2e-fighters PASSED: search, filter chips with counts, sort, dimmed rows, Back keeps the list, filter remembered')
} catch (e) {
  console.error('e2e-fighters FAILED:', e.message)
  process.exitCode = 1
} finally {
  await browser.close()
  await db.end()
}
