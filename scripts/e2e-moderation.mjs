// Browser walkthrough for profile moderation: a blocked name at sign-up, reporting a profile, the admin queue (clear a
// bio), resetting a name from the profile page, the reset player's rename prompt and activity line, the log, the word
// filter (and its per-word chat switch), and the filter on bios.
// Usage (local stack running): node scripts/e2e-moderation.mjs [--shots dir]
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

try {
  // Sign-up asks about the name first: a blocked one never becomes an account
  const c = await open('Carl')
  await signUp(c, `BigDick_${RUN}`)
  await c.getByText("That name isn't allowed").waitFor()
  if (await c.locator('.topbar').count()) throw new Error('no account for a blocked name')
  await signUp(c, N('Carl'))
  await c.locator('.topbar').waitFor()
  const cId = (await one('select id from profiles where name = $1', [N('Carl')])).id
  await db.query(`update profiles set avatar = '🤑', bio = 'I sell cheap bricks' where id = $1`, [cId])

  // Someone reports Carl's bio
  const b = await newPlayer(N('Betty'))
  await b.goto(`${BASE}/player/${cId}`)
  await b.getByRole('button', { name: '🚩 Report' }).click()
  const modal = b.locator('.modal')
  await modal.getByRole('button', { name: 'Bio' }).click()
  await modal.getByPlaceholder(/Anything the admin should know/).fill('selling in his bio')
  await snap(b, 'report')
  await modal.getByRole('button', { name: 'Send Report' }).click()
  await b.getByText('Thanks — an admin will take a look').waitFor()
  // thugs have no Report button
  const thug = (await one('select id from profiles where is_bot order by bot_level limit 1')).id
  await b.goto(`${BASE}/player/${thug}`)
  await b.getByRole('button', { name: '⚔️ Attack' }).waitFor()
  if (await b.getByRole('button', { name: '🚩 Report' }).count()) throw new Error('no reporting thugs')

  // The admin: Home points at the queue; clear the bio from there
  const a = await newPlayer(N('Warden'))
  const aId = (await one('select id from profiles where name = $1', [N('Warden')])).id
  await db.query('update profiles set is_admin = true where id = $1', [aId])
  await a.reload()
  await a.getByText(/open reports\. Review →/).waitFor()
  await a.goto(`${BASE}/admin`)
  const item = a.locator('.mod-item', { hasText: N('Carl') })
  await item.getByText('“selling in his bio”').waitFor()
  await item.getByText(N('Betty')).waitFor()
  await item.getByText('“I sell cheap bricks”').waitFor()
  await snap(a, 'queue')
  await item.getByRole('button', { name: 'Clear bio' }).click()
  await a.getByText('Bio cleared').waitFor()
  await item.waitFor({ state: 'detached' })
  if ((await one('select bio from profiles where id = $1', [cId])).bio !== '') throw new Error('bio cleared')

  // Reset his name from his profile
  await a.goto(`${BASE}/player/${cId}`)
  await a.locator('.card', { has: a.locator('.hd', { hasText: 'Admin' }) }).getByRole('button', { name: 'Reset name' }).click()
  await a.getByText(/name reset — they'll pick a new one/).waitFor()
  const reset = await one('select name, rename_pending from profiles where id = $1', [cId])
  if (!reset.name.startsWith('player_') || !reset.rename_pending) throw new Error('reset: ' + JSON.stringify(reset))

  // The log
  await a.goto(`${BASE}/admin?tab=log`)
  await a.getByText(/reset the name of/).first().waitFor()
  await a.getByText(`(was “${N('Carl')}”)`).waitFor()
  await a.getByText('(was “I sell cheap bricks”)').first().waitFor()
  await snap(a, 'log')

  // The word filter: add one (it blocks chat too, by default), switch chat off for it, remove it
  await a.goto(`${BASE}/admin?tab=words`)
  await a.getByPlaceholder('word').fill('snitchy')
  await a.getByRole('button', { name: 'Inside a word' }).click()
  if (!(await a.getByRole('checkbox', { name: /^Chat/ }).isChecked())) throw new Error('Chat is checked by default')
  await a.getByRole('button', { name: 'Add Word' }).click()
  await a.getByText('“snitchy” added').waitFor()
  await b.goto(`${BASE}/chat`)
  await b.getByPlaceholder('Say something…').fill(`what a snitchy move ${RUN}`)
  await b.getByRole('button', { name: 'Send' }).click()
  await b.getByText("That message has a word that isn't allowed", { exact: true }).waitFor()
  await a.getByRole('button', { name: 'Chat on for snitchy' }).click()
  await a.getByText('“snitchy” no longer blocks chat').waitFor()
  await a.getByRole('button', { name: 'Chat off for snitchy' }).waitFor()
  if ((await one(`select new_value from mod_log where action = 'set_word' order by id desc limit 1`)).new_value !== 'snitchy (part, chat off)') throw new Error('set_word logged')
  await b.getByPlaceholder('Say something…').fill(`what a snitchy move ${RUN}`)
  await b.getByRole('button', { name: 'Send' }).click()
  await b.locator('.msg', { hasText: `what a snitchy move ${RUN}` }).waitFor()
  const pillX = a.getByRole('button', { name: 'Remove snitchy' })
  await pillX.waitFor()
  await snap(a, 'words')
  await pillX.click()
  await a.getByText('“snitchy” removed').waitFor()

  // Carl: the rename prompt and the activity lines
  await c.reload()
  await c.locator('.name-prompt').getByText('An admin reset your name').waitFor()
  await snap(c, 'rename-prompt')
  await c.getByLabel('New street name').fill(N('Betty'))
  await c.getByRole('button', { name: 'Save' }).click()
  await c.getByText('That name is taken').waitFor()
  await c.getByLabel('New street name').fill(N('Clean Carl'))
  await c.getByRole('button', { name: 'Save' }).click()
  await c.getByText(`You're ${N('Clean Carl')} now`).waitFor()
  await c.locator('.name-prompt').waitFor({ state: 'detached' })
  await c.goto(`${BASE}/activity`)
  await c.getByText(/An admin reset your name for breaking the rules/).waitFor()
  await c.getByText(/An admin cleared your bio/).waitFor()

  // and the filter guards bios
  await c.goto(`${BASE}/profile`)
  await c.getByRole('button', { name: 'Edit avatar & bio' }).click()
  await c.getByPlaceholder('Say something about yourself').fill('eat sh1t')
  await c.getByRole('button', { name: 'Save' }).click()
  await c.getByText("Your bio has a word that isn't allowed").waitFor()

  console.log('E2E MODERATION PASSED')
} catch (e) {
  console.error('E2E MODERATION FAILED:', e.message)
  if (shots && lastPage) await lastPage.screenshot({ path: `${shots}/FAIL.png`, fullPage: true }).catch(() => {})
  process.exitCode = 1
} finally {
  if (errors.length) { console.error('Page errors:\n' + errors.join('\n')); process.exitCode = 1 }
  await browser.close()
  await db.end()
}
