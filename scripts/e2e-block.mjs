// Browser walkthrough for blocking: Ana blocks Bo from his profile, Bo's open DM to her is refused and then closes, his
// global chat line and forum thread are hidden from her, she finds him under Blocked players on her Profile, unblocks
// him, and they can talk again. Thugs have no Block button.
// Usage (local stack running): node scripts/e2e-block.mjs [--shots dir]
import { chromium } from 'playwright'
import fs from 'node:fs'
import pg from 'pg'
const db = new pg.Pool({ host: 'localhost', port: Number(process.env.PGPORT || 54329), user: 'postgres', database: 'cartel' })

const BASE = process.env.BASE || 'http://127.0.0.1:5173'
const shots = process.argv.includes('--shots') ? process.argv[process.argv.indexOf('--shots') + 1] : null
if (shots) fs.mkdirSync(shots, { recursive: true })
const browser = await chromium.launch({ executablePath: process.env.CHROME || '/opt/pw-browsers/chromium' })
const errors = []
const dialogs = []
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
  page.on('dialog', d => { dialogs.push(d.message()); d.accept() })
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

try {
  const a = await newPlayer(N('Ana'))
  const b = await newPlayer(N('Bo'))
  const aId = (await one('select id from profiles where name = $1', [N('Ana')])).id
  const bId = (await one('select id from profiles where name = $1', [N('Bo')])).id
  // Bo has already talked in Live Chat and started a forum thread; so has Ana
  await db.query(`insert into messages (channel, sender_id, sender_name, body) values ('global', $1, $2, $3), ('global', $4, $5, $6)`,
    [bId, N('Bo'), `bo was here ${RUN}`, aId, N('Ana'), `ana was here ${RUN}`])
  const tid = (await one(`insert into forum_threads (category, author_id, title, body, last_poster_id) values ('general', $1, $2, $3, $1) returning id`,
    [bId, `Bo's plan ${RUN}`, `secret plans ${RUN}`])).id

  // Bo opens a DM with Ana and says hello
  await b.goto(`${BASE}/player/${aId}`)
  await b.getByRole('button', { name: '💬 Chat' }).click()
  await b.getByPlaceholder('Say something…').fill('before the block')
  await b.getByRole('button', { name: 'Send' }).click()
  await b.locator('.msg', { hasText: 'before the block' }).waitFor()

  // Ana blocks him from his profile (the harness accepts the confirm)
  await a.goto(`${BASE}/player/${bId}`)
  await a.getByRole('button', { name: '🚫 Block' }).click()
  await a.getByText(`${N('Bo')} blocked`, { exact: true }).waitFor()
  if (!dialogs.some(d => d === `Block ${N('Bo')}? They can't message you and their posts are hidden. You can undo this from your Profile.`))
    throw new Error('confirm text: ' + JSON.stringify(dialogs))
  await a.getByText("You've blocked them — no messages either way").waitFor()
  await a.getByRole('button', { name: 'Unblock' }).waitFor()
  await snap(a, 'blocked-profile')

  // Bo's DM, still open, is refused; reopened, the composer is gone
  await b.getByPlaceholder('Say something…').fill('you there?')
  await b.getByRole('button', { name: 'Send' }).click()
  await b.getByText("You can't message them", { exact: true }).waitFor()
  await b.reload()
  await b.getByText("You can't message each other.").waitFor()
  if (await b.getByPlaceholder('Say something…').count()) throw new Error('no composer in a blocked DM')
  await snap(b, 'dm-closed')

  // Ana doesn't see his Live Chat line or his forum thread's text
  await a.goto(`${BASE}/chat`)
  await a.locator('.msg', { hasText: `ana was here ${RUN}` }).waitFor()
  if (await a.locator('.msg', { hasText: `bo was here ${RUN}` }).count()) throw new Error('blocked line shown in Live Chat')
  await a.goto(`${BASE}/forum/general`)
  const row = a.locator('.row', { hasText: `Bo's plan ${RUN}` })
  await row.getByText('Hidden — you blocked this player').waitFor()
  await a.goto(`${BASE}/forum/t/${tid}`)
  await a.locator('.post').getByText('Hidden — you blocked this player').waitFor()
  if (await a.getByText(`secret plans ${RUN}`).count()) throw new Error('blocked thread body shown')
  await snap(a, 'forum-hidden')

  // Her Profile lists him; unblocking puts things back
  await a.goto(`${BASE}/profile`)
  const card = a.locator('.card', { has: a.locator('.hd', { hasText: 'Blocked players' }) })
  const blockedRow = card.locator('.row', { hasText: N('Bo') })
  await blockedRow.waitFor()
  await snap(a, 'blocked-list')
  await blockedRow.getByRole('button', { name: 'Unblock' }).click()
  await a.getByText(`${N('Bo')} unblocked`, { exact: true }).waitFor()
  await card.getByText('Nobody blocked.').waitFor()
  await a.goto(`${BASE}/chat`)
  await a.locator('.msg', { hasText: `bo was here ${RUN}` }).waitFor()

  // and the DM works again
  await b.reload()
  await b.getByPlaceholder('Say something…').fill('back on speaking terms')
  await b.getByRole('button', { name: 'Send' }).click()
  await b.locator('.msg', { hasText: 'back on speaking terms' }).waitFor()
  await a.goto(`${BASE}/chat/dms`)
  await a.locator('.row', { hasText: N('Bo') }).getByText('back on speaking terms').waitFor()

  // Thugs and you yourself have no Block button
  const thug = (await one('select id from profiles where is_bot order by bot_level limit 1')).id
  await a.goto(`${BASE}/player/${thug}`)
  await a.getByRole('button', { name: '⚔️ Attack' }).waitFor()
  if (await a.getByRole('button', { name: '🚫 Block' }).count()) throw new Error('no blocking thugs')
  await a.goto(`${BASE}/player/${aId}`)
  await a.getByText(N('Ana')).first().waitFor()
  if (await a.getByRole('button', { name: '🚫 Block' }).count()) throw new Error('no blocking yourself')

  console.log('E2E BLOCK PASSED')
} catch (e) {
  console.error('E2E BLOCK FAILED:', e.message)
  if (shots && lastPage) await lastPage.screenshot({ path: `${shots}/FAIL.png`, fullPage: true }).catch(() => {})
  process.exitCode = 1
} finally {
  if (errors.length) { console.error('Page errors:\n' + errors.join('\n')); process.exitCode = 1 }
  await browser.close()
  await db.end()
}
