// UI review screenshots (Phase 4): the same screens, the same player, every time, so a style change can be judged
// side by side. Signs in as bot01 of the demo world and captures each screen at iPhone 13/14 size (390×844 @2x),
// one phone screen each, plus the signed-out screen, sign-up, a new player's Home, Next up, the refill sheet and a toast. It also measures every control on each screen and lists the
// ones under 44 pt (Apple's minimum touch target) to <OUT>/targets.json.
// Needs the local stack with the demo world: scripts/local-db.sh reset, then demo; dev-server.mjs; vite.
// Usage: OUT=/tmp/shots/before node scripts/ui-shots.mjs
import { chromium } from 'playwright'
import fs from 'node:fs'
import path from 'node:path'
import pg from 'pg'

const BASE = process.env.BASE || 'http://127.0.0.1:5173'
const OUT = process.env.OUT || '/tmp/ui-shots'
const db = new pg.Pool({ host: 'localhost', port: Number(process.env.PGPORT || 54329), user: 'postgres', database: 'cartel' })
fs.mkdirSync(OUT, { recursive: true })

const one = async (sql) => (await db.query(sql)).rows[0]
const ids = await one(`select (select id from auth.users where email = 'bot07@demo.local') rook,
  (select crew_id from profiles p join auth.users u on u.id = p.id where u.email = 'bot01@demo.local') crew`)
// the same state each run: rested, out of jail and the hospital, a trip back and a full house for Next up
await db.query(`update profiles set stamina = stamina_max, health = health_max, in_hospital = false, jail_until = null, heat = 34
  where id = (select id from auth.users where email = 'bot01@demo.local')`)

const screens = [
  { file: '01-home', path: '/' },
  { file: '02-actions', path: '/actions', ready: '.row.action' },
  { file: '03-economy', path: '/economy' },
  { file: '04-market', path: '/economy?tab=market' },
  { file: '05-items', path: '/items' },
  { file: '06-shop', path: '/items?tab=shop' },
  { file: '07-services', path: '/services' },
  { file: '08-fight', path: '/fight' },
  { file: '09-player', path: `/player/${ids.rook}` },
  { file: '10-territory', path: '/territory' },
  { file: '11-crew', path: `/crew/${ids.crew}` },
  { file: '12-slots', path: '/casino/slots' },
  { file: '13-blackjack', path: '/casino/blackjack' },
  { file: '14-roulette', path: '/casino/roulette' },
  { file: '15-craps', path: '/casino/craps' },
  { file: '16-poker', path: '/casino/poker' },
  { file: '17-chat', path: '/chat' },
  { file: '18-profile', path: '/profile' },
  { file: '19-store', path: '/store' },
]

const browser = await chromium.launch({ executablePath: process.env.CHROME || '/opt/pw-browsers/chromium' })
const targets = {}
try {
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true })
  const p = await ctx.newPage()
  p.on('dialog', d => d.dismiss())
  await p.goto(BASE)
  await p.screenshot({ path: path.join(OUT, '00-signin.png') })
  await p.getByLabel('Email').fill('bot01@demo.local')
  await p.getByLabel('Password').fill('secret123')
  await p.getByRole('button', { name: 'Sign In' }).click()
  await p.locator('.topbar').waitFor()
  for (const s of screens) {
    await p.goto(BASE + s.path)
    await p.locator('.topbar').waitFor()
    if (s.ready) await p.locator(s.ready).first().waitFor()
    await p.waitForFunction(() => !document.querySelector('.spin, .toast'), null, { timeout: 15000 }).catch(() => {})
    await p.waitForTimeout(500)
    await p.screenshot({ path: path.join(OUT, `${s.file}.png`) })
    // controls smaller than 44 pt in either direction, counting a ::after hit area that reaches further
    targets[s.file] = await p.evaluate(() => {
      const small = []
      for (const el of document.querySelectorAll('button, a[href], input, select, [role="button"], summary')) {
        const r = el.getBoundingClientRect()
        if (!r.width || !r.height || getComputedStyle(el).visibility === 'hidden') continue
        if (el.closest('p, .small, .s, .why, .notice') && el.tagName === 'A') continue   // a link inside a sentence
        const a = getComputedStyle(el, '::after')
        let h = r.height, w = r.width
        if (a.content !== 'none' && a.position === 'absolute') {
          const t = parseFloat(a.top) || 0, b = parseFloat(a.bottom) || 0, l = parseFloat(a.left) || 0, rr = parseFloat(a.right) || 0
          h = Math.max(h, r.height - t - b); w = Math.max(w, r.width - l - rr)
        }
        if (h < 43.5 || w < 43.5) small.push(`${el.tagName.toLowerCase()}.${[...el.classList].join('.')} "${(el.getAttribute('aria-label') || el.textContent || '').trim().slice(0, 24)}" ${Math.round(w)}×${Math.round(h)}`)
      }
      return small
    })
  }
  // states a screen list can't reach: Next up with things waiting, the refill sheet, a toast, a brand-new player's Home
  const me = (await one(`select id from auth.users where email = 'bot01@demo.local'`)).id
  await db.query(`update profiles set health = 12, in_hospital = true, drop_crates = 2 where id = $1`, [me])
  await db.query(`insert into hustlers (player_id, commodity, count, units, cash_due, departs_at, returns_at) values ($1, 'herb', 2, 20, 4200, now() - interval '5 hours', now() - interval '1 minute')`, [me])
  await p.goto(BASE + '/')
  await p.locator('.next-up').waitFor()
  await p.waitForTimeout(400)
  await p.screenshot({ path: path.join(OUT, '20-nextup.png') })
  await db.query(`delete from hustlers where player_id = $1 and cash_due = 4200`, [me])
  await db.query(`update profiles set health = health_max, in_hospital = false, drop_crates = 0, stamina = 0 where id = $1`, [me])
  await p.goto(BASE + '/actions')
  await p.locator('.row.action .doit').first().click()
  await p.locator('.refill-sheet').waitFor()
  await p.waitForTimeout(400)
  await p.screenshot({ path: path.join(OUT, '21-refill-sheet.png') })
  await db.query(`update profiles set stamina = stamina_max where id = $1`, [me])
  await p.goto(BASE + '/services?focus=bank')
  await p.getByLabel('Amount to deposit or withdraw').fill('100')
  await p.getByRole('button', { name: 'Deposit' }).click()
  await p.locator('.toast').waitFor()
  await p.screenshot({ path: path.join(OUT, '22-toast.png') })
  const fresh = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2, isMobile: true, hasTouch: true })
  const q = await fresh.newPage()
  const name = 'Ui' + Date.now().toString(36).slice(-5)
  await q.goto(BASE)
  await q.getByRole('button', { name: 'New Player' }).click()
  await q.getByLabel('Street name').fill(name)
  await q.getByLabel('Email').fill(`${name}@shots.local`)
  await q.getByLabel('Password').fill('secret123')
  await q.screenshot({ path: path.join(OUT, '23-signup.png') })
  await q.getByRole('button', { name: 'Enter the City' }).click()
  await q.locator('.getting-started').waitFor()
  await q.waitForTimeout(500)
  await q.screenshot({ path: path.join(OUT, '24-new-home.png') })
  await fresh.close()
  fs.writeFileSync(path.join(OUT, 'targets.json'), JSON.stringify(targets, null, 1))
  const total = Object.values(targets).reduce((n, l) => n + l.length, 0)
  console.log(`ui-shots: ${screens.length + 6} screens in ${OUT}; ${total} controls under 44 pt`)
} finally {
  await browser.close()
  await db.end()
}
