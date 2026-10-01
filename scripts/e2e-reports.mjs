// Browser walkthrough for reporting and moderating content: Betty reports two of Carl's chat lines from the ⋯ sheet and
// his forum thread; the admin sees them in the queue with the text, deletes the first line (it's gone from Betty's chat
// after a reload) and mutes Carl for a day; Carl's chat and reply boxes say he's muted and his activity says why; the
// admin unmutes him from his profile and he can talk again; Betty blocks him from the ⋯ sheet.
// Usage (local stack running): node scripts/e2e-reports.mjs [--shots dir]
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
async function open(name) {
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 })
  const page = await ctx.newPage()
  lastPage = page
  page.on('pageerror', e => errors.push(`${name}: ${e.message}`))
  page.on('response', r => { if (r.status() === 404) errors.push(`404 ${r.url()}`) })
  page.on('console', m => { if (m.type() === 'error' && !/realtime|websocket|WebSocket|Failed to load resource/i.test(m.text())) errors.push(`${name} console: ${m.text()}`) })
  page.on('dialog', d => d.accept())
  await page.goto(BASE)
  await page.getByRole('button', { name: 'New Player' }).click()
  return page
}
async function signUp(page, name) {
  await page.getByLabel('Street name').fill(name)
  await page.getByLabel('Email').fill(`${name.toLowerCase().replace(/[^a-z0-9]/g, '')}-${Date.now()}@test.local`)
  await page.getByLabel('Password').fill('secret123')
  await page.getByRole('button', { name: 'Enter the City' }).click()
}
async function newPlayer(name) { const p = await open(name); await signUp(p, name); await p.locator('.topbar').waitFor(); return p }
const one = async (sql, args = []) => (await db.query(sql, args)).rows[0]
async function say(page, text) {
  await page.getByPlaceholder('Say something…').fill(text)
  await page.getByRole('button', { name: 'Send' }).click()
  await page.locator('.msg', { hasText: text }).waitFor()
}

try {
  const TRASH = `you are all trash ${RUN}`, BRICKS = `buy my bricks ${RUN}`, MINE = `betty says hi ${RUN}`
  const c = await newPlayer(N('Carl'))
  const cId = (await one('select id from profiles where name = $1', [N('Carl')])).id
  await c.goto(`${BASE}/chat`)
  await say(c, TRASH)
  await say(c, BRICKS)
  const tid = (await one(`insert into forum_threads (category, author_id, title, body, last_poster_id) values ('general', $1, $2, $3, $1) returning id`,
    [cId, `Cheap bricks ${RUN}`, `dm me for bricks ${RUN}`])).id

  // Betty: her own line has no ⋯; Carl's lines do, and the sheet reports one of them
  const b = await newPlayer(N('Betty'))
  await b.goto(`${BASE}/chat`)
  await say(b, MINE)
  if (await b.locator('.msg', { hasText: MINE }).getByRole('button', { name: /^More for/ }).count()) throw new Error('no ⋯ on your own line')
  await b.locator('.msg', { hasText: TRASH }).getByRole('button', { name: `More for ${N('Carl')}'s message` }).click()
  const sheet = b.locator('.modal')
  await sheet.getByText(`“${TRASH}”`).waitFor()
  await sheet.getByRole('button', { name: '🚫 Block' }).waitFor()
  await snap(b, 'sheet')
  await sheet.getByRole('button', { name: '🚩 Report' }).click()
  const modal = b.locator('.modal', { hasText: `Report ${N('Carl')}'s message` })
  await modal.getByRole('button', { name: 'Hate', exact: true }).click()
  await modal.getByPlaceholder(/Anything the admin should know/).fill('slurs in live chat')
  await snap(b, 'report-message')
  await modal.getByRole('button', { name: 'Send Report' }).click()
  await b.getByText('Thanks — an admin will take a look').first().waitFor()
  await modal.waitFor({ state: 'detached' })
  // the second line, as spam
  await b.locator('.msg', { hasText: BRICKS }).getByRole('button', { name: /^More for/ }).click()
  await b.locator('.modal').getByRole('button', { name: '🚩 Report' }).click()
  await b.locator('.modal').getByRole('button', { name: 'Spam', exact: true }).click()
  await b.locator('.modal').getByRole('button', { name: 'Send Report' }).click()
  await b.locator('.modal').waitFor({ state: 'detached' })
  // his forum thread, from the thread's own buttons
  await b.goto(`${BASE}/forum/t/${tid}`)
  await b.getByRole('button', { name: '🚩 Report' }).click()
  await b.locator('.modal', { hasText: `Report ${N('Carl')}'s thread` }).getByRole('button', { name: 'Spam', exact: true }).click()
  await b.locator('.modal').getByRole('button', { name: 'Send Report' }).click()
  await b.locator('.modal').waitFor({ state: 'detached' })
  const reports = (await one(`select count(*)::int n from profile_reports where target_id = $1 and status = 'open'`, [cId])).n
  if (reports !== 3) throw new Error(`three open reports on Carl, got ${reports}`)

  // The admin: the queue shows each report's kind and text; delete the first line, then mute Carl for a day
  const a = await newPlayer(N('Warden'))
  await db.query('update profiles set is_admin = true where name = $1', [N('Warden')])
  await a.goto(`${BASE}/admin`)
  const item = a.locator('.mod-item', { hasText: N('Carl') })
  const hate = item.locator('.mod-report', { hasText: TRASH })
  await hate.getByText('Message', { exact: true }).waitFor()
  await hate.getByText('Hate', { exact: true }).waitFor()
  await hate.getByText('“slurs in live chat”').waitFor()
  await hate.locator('.report-quote', { hasText: TRASH }).waitFor()
  await hate.getByText('in Live Chat').waitFor()
  await item.locator('.mod-report', { hasText: `dm me for bricks ${RUN}` }).getByText('Thread', { exact: true }).waitFor()
  await snap(a, 'queue')
  await hate.getByRole('button', { name: 'Delete' }).click()
  await a.getByText('Message deleted').waitFor()
  await hate.waitFor({ state: 'detached' })
  const gone = await one('select body, deleted from messages where body = $1 or (deleted and sender_id = $2)', [TRASH, cId])
  if (!gone.deleted || gone.body !== '') throw new Error('message deleted: ' + JSON.stringify(gone))
  await item.getByRole('button', { name: 'Mute 1d' }).click()
  await a.getByText(`${N('Carl')} is muted for a day`).waitFor()
  await item.waitFor({ state: 'detached' })
  const muted = await one(`select muted_until > now() + interval '23 hours' and muted_until <= now() + interval '1 day' as ok from profiles where id = $1`, [cId])
  if (!muted.ok) throw new Error('muted for a day')

  // Betty: the deleted line is gone after a reload, the other is still there
  await b.goto(`${BASE}/chat`)
  await b.locator('.msg', { hasText: BRICKS }).waitFor()
  if (await b.locator('.msg', { hasText: TRASH }).count()) throw new Error('deleted line still shows')

  // Carl: muted in chat and the forum, and his activity says why
  await c.reload()
  await c.getByText(/^You're muted until .+\.$/).waitFor()
  if (await c.getByPlaceholder('Say something…').count()) throw new Error('no composer while muted')
  await snap(c, 'muted-chat')
  await c.goto(`${BASE}/forum/t/${tid}`)
  await c.getByText(/^You're muted until/).waitFor()
  if (await c.getByRole('button', { name: 'Post reply' }).count()) throw new Error('no reply box while muted')
  await c.goto(`${BASE}/activity`)
  await c.getByText('An admin removed one of your messages').waitFor()
  await c.getByText(/^An admin muted you until/).waitFor()
  await snap(c, 'activity')

  // The log, then the admin lifts the mute from Carl's profile
  await a.goto(`${BASE}/admin?tab=log`)
  await a.getByText(/removed a message from/).first().waitFor()
  await a.getByText(`(was “${TRASH}”)`).waitFor()
  await a.getByText(/until \d/).first().waitFor()
  await a.goto(`${BASE}/player/${cId}`)
  const admin = a.locator('.card', { has: a.locator('.hd', { hasText: 'Admin' }) })
  await admin.getByText(/^Muted until/).waitFor()
  await snap(a, 'profile-muted')
  await admin.getByRole('button', { name: 'Unmute' }).click()
  await a.getByText(`${N('Carl')} can talk again`).waitFor()
  await admin.getByRole('button', { name: 'Unmute' }).waitFor({ state: 'detached' })
  if ((await one('select muted_until from profiles where id = $1', [cId])).muted_until !== null) throw new Error('unmuted')

  // Carl talks again
  await c.goto(`${BASE}/chat`)
  await say(c, `back again ${RUN}`)
  await c.goto(`${BASE}/activity`)
  await c.getByText('An admin lifted your mute').waitFor()

  // Betty blocks Carl from the ⋯ sheet: his lines drop out of her chat
  await b.goto(`${BASE}/chat`)
  await b.locator('.msg', { hasText: `back again ${RUN}` }).getByRole('button', { name: /^More for/ }).click()
  await b.locator('.modal').getByRole('button', { name: '🚫 Block' }).click()
  await b.getByText(`${N('Carl')} blocked`).waitFor()
  await b.locator('.msg', { hasText: BRICKS }).waitFor({ state: 'detached' })
  await b.locator('.msg', { hasText: MINE }).waitFor()

  console.log('E2E REPORTS PASSED')
} catch (e) {
  console.error('E2E REPORTS FAILED:', e.message)
  if (shots && lastPage) await lastPage.screenshot({ path: `${shots}/FAIL.png`, fullPage: true }).catch(() => {})
  process.exitCode = 1
} finally {
  if (errors.length) { console.error('Page errors:\n' + errors.join('\n')); process.exitCode = 1 }
  await browser.close()
  await db.end()
}
