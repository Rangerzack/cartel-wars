// Forum walkthrough against the local stack: an admin posts a Game Update, a player starts a thread and replies.
// Usage: node scripts/e2e-forum.mjs [--shots dir]
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
async function newPlayer(name, email) {
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 })
  const page = await ctx.newPage()
  lastPage = page
  page.on('pageerror', e => errors.push(`${name}: ${e.message}`))
  page.on('response', r => { if (r.status() === 404) errors.push(`404 ${r.url()}`) })
  page.on('console', m => { if (m.type() === 'error' && !/realtime|websocket|WebSocket|Failed to load resource/i.test(m.text())) errors.push(`${name} console: ${m.text()}`) })
  page.on('dialog', d => d.accept())
  await page.goto(BASE)
  await page.getByRole('button', { name: 'New Player' }).click()
  await page.getByLabel('Street name').fill(name)
  await page.getByLabel('Email').fill(email ?? `${name.toLowerCase()}-${Date.now()}@test.local`)
  await page.getByLabel('Password').fill('secret123')
  await page.getByRole('button', { name: 'Enter the City' }).click()
  await page.getByText(name, { exact: false }).first().waitFor()
  return page
}
const toast = (page, re) => page.locator('.toast').filter({ hasText: re }).first().waitFor({ timeout: 8000 })

try {
  // the admin list is by email; give this run's admin a unique one
  const adminEmail = `admin-${RUN}@test.local`
  await db.query(`insert into admins (email) values ($1)`, [adminEmail])
  const admin = await newPlayer(N('Boss'), adminEmail)
  const player = await newPlayer(N('Rook'))

  // boards
  await player.goto(BASE + '/forum')
  await player.getByText('Game Updates').waitFor()
  await player.getByText('Suggestions').waitFor()
  await snap(player, 'boards')

  // players can't start threads in Game Updates
  await player.getByText('Game Updates').click()
  await player.locator('.card .hd', { hasText: 'Game Updates' }).waitFor()
  await player.locator('.card .hd small', { hasText: /thread/ }).waitFor()
  if (await player.getByRole('button', { name: 'New thread' }).count()) throw new Error('player should not see New thread in updates')

  // admin posts an update and pins it
  await admin.goto(BASE + '/forum/updates')
  await admin.getByRole('button', { name: 'New thread' }).click()
  await admin.getByPlaceholder('Title').fill(N('Casino opens '))
  await admin.getByPlaceholder('Say your piece…').fill('Slots first. Tables when staging signs off.')
  await admin.getByRole('button', { name: 'Post thread' }).click()
  await admin.getByRole('heading', { name: new RegExp(N('Casino opens ')) }).waitFor()
  await admin.getByRole('button', { name: 'Pin' }).click()
  await admin.getByRole('button', { name: 'Unpin' }).waitFor()
  await snap(admin, 'update-thread')

  // player starts a thread in New Player and the admin replies; player edits then deletes their reply
  await player.goto(BASE + '/forum/new_player')
  await player.getByRole('button', { name: 'New thread' }).click()
  await player.getByPlaceholder('Title').fill(N('How do I get out of jail '))
  await player.getByPlaceholder('Say your piece…').fill('Stuck for an hour. Help?')
  await player.getByRole('button', { name: 'Post thread' }).click()
  await player.getByRole('heading', { name: /How do I get out of jail/ }).waitFor()
  const url = player.url()
  await admin.goto(url)
  await admin.getByPlaceholder('Write a reply…').fill('Bribe the guard on the Services page.')
  await admin.getByRole('button', { name: 'Post reply' }).click()
  await admin.locator('.post.reply', { hasText: 'Bribe the guard' }).waitFor()
  await player.reload()
  await player.locator('.post.reply', { hasText: 'Bribe the guard' }).waitFor()
  await player.locator('.post.reply .pill', { hasText: 'admin' }).waitFor()
  await player.getByPlaceholder('Write a reply…').fill('thanks, worked')
  await player.getByRole('button', { name: 'Post reply' }).click()
  await player.locator('.post.reply', { hasText: 'thanks, worked' }).waitFor()
  await snap(player, 'thread')
  await player.locator('.post.reply', { hasText: 'thanks, worked' }).getByRole('button', { name: 'Edit' }).click()
  await player.locator('.modal textarea').fill('thanks, that worked')
  await player.getByRole('button', { name: 'Save' }).click()
  await player.locator('.post.reply', { hasText: 'thanks, that worked' }).waitFor()
  await player.locator('.post.reply', { hasText: 'thanks, that worked' }).getByRole('button', { name: 'Delete' }).click()
  await player.locator('.post.reply', { hasText: '[deleted]' }).waitFor()
  // the admin's reply has no Edit/Delete for the player
  if (await player.locator('.post.reply', { hasText: 'Bribe the guard' }).getByRole('button', { name: 'Delete' }).count()) throw new Error('player can delete admin post')

  // admin locks it → player can't reply; admin moves it to General
  await admin.getByRole('button', { name: 'Lock' }).click()
  await admin.getByRole('button', { name: 'Unlock' }).waitFor()
  await player.reload()
  await player.getByText('This thread is locked').waitFor()
  await admin.locator('select').selectOption('general')
  await toast(admin, /Moved to General/)
  await admin.getByText(/How do I get out of jail/).waitFor()
  await snap(admin, 'general-board')

  // boards page shows activity
  await player.goto(BASE + '/forum')
  await player.locator('.row', { hasText: 'Game Updates' }).getByText(/Casino opens/).waitFor()
  await player.locator('.row', { hasText: 'General' }).getByText(/How do I get out of jail/).waitFor()
  console.log('E2E FORUM PASSED')
} catch (e) {
  console.error('E2E FAILED:', e.message)
  if (shots && lastPage) await lastPage.screenshot({ path: `${shots}/FAIL.png`, fullPage: true }).catch(() => {})
  process.exitCode = 1
} finally {
  if (errors.length) { console.error('Page errors:\n' + errors.join('\n')); process.exitCode = 1 }
  await browser.close()
  await db.end()
}
