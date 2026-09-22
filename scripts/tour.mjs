// Screenshot every screen as a demo bot. Needs the local stack + `npm run db:demo`.
// Usage: node scripts/tour.mjs [outDir]   (default /tmp/tour)
import { chromium } from 'playwright'
import fs from 'node:fs'

const BASE = process.env.BASE || 'http://127.0.0.1:5173'
const out = process.argv[2] || '/tmp/tour'
fs.mkdirSync(out, { recursive: true })
const b = await chromium.launch({ executablePath: process.env.CHROME || '/opt/pw-browsers/chromium' })
const ctx = await b.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 })
const p = await ctx.newPage()
const errs = []
p.on('pageerror', e => errs.push(e.message))
await p.goto(BASE)
await p.getByLabel('Email').fill(process.env.BOT || 'bot01@demo.local')
await p.getByLabel('Password').fill('secret123')
await p.getByRole('button', { name: 'Sign In' }).click()
await p.locator('.topbar').waitFor()
const paths = ['/', '/actions', '/economy', '/economy?tab=hustlers', '/economy?tab=market', '/fight', '/fight?tab=log', '/fight?tab=top',
  '/services', '/items', '/items#shop', '/crew', '/cartel', '/territory', '/accolades', '/chat', '/profile']
let i = 0
for (const path of paths) {
  await p.goto(BASE + path)
  await p.waitForTimeout(800)
  await p.screenshot({ path: `${out}/${String(++i).padStart(2, '0')}-${path.replace(/[^a-z]+/g, '-').replace(/^-|-$/g, '') || 'home'}.png`, fullPage: true })
}
if (errs.length) { console.error('page errors:', errs); process.exitCode = 1 } else console.log(`${i} screenshots in ${out}`)
await b.close()
