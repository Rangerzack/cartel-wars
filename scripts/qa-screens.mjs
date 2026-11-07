// Phase 6 QA: every screen at the phone and tablet sizes the app ships to, looking for what a person would trip on
// without anyone noticing in a test: a page that scrolls sideways or a control pushed off the edge, a console error,
// a request that failed, and (at the iPhone size) what axe-core finds for accessibility.
// Needs the local stack with the demo world: scripts/local-db.sh reset, then demo; dev-server.mjs; vite.
// Usage: AXE=/path/to/axe.min.js OUT=/tmp/qa node scripts/qa-screens.mjs   (AXE optional: no AXE, no accessibility scan)
//        SEASON=1 … sweeps with a season running instead (Season 1): first as a player at the start of the campaign (the
//        hood, Marcus, the locked tabs and the Not Yet screen), then with every mission claimed (everything open, the
//        hood and the campaign-complete row). Starts its own season and ends it after.
import { chromium } from 'playwright'
import fs from 'node:fs'
import path from 'node:path'
import pg from 'pg'

const BASE = process.env.BASE || 'http://127.0.0.1:5173'
const OUT = process.env.OUT || '/tmp/qa-screens'
const AXE = process.env.AXE && fs.readFileSync(process.env.AXE, 'utf8')
fs.mkdirSync(OUT, { recursive: true })
const db = new pg.Pool({ host: 'localhost', port: Number(process.env.PGPORT || 54329), user: 'postgres', database: 'cartel' })
const one = async (sql) => (await db.query(sql)).rows[0]

const SEASON = !!process.env.SEASON
const ids = await one(`select (select id from auth.users where email = 'bot07@demo.local') rook,
  (select crew_id from profiles p join auth.users u on u.id = p.id where u.email = 'bot01@demo.local') crew,
  (select id from forum_threads order by id limit 1) thread`)
await db.query(`update profiles set stamina = stamina_max, health = health_max, in_hospital = false, jail_until = null
  where id = (select id from auth.users where email = 'bot01@demo.local')`)
const me = (await one(`select id from auth.users where email = 'bot01@demo.local'`)).id
const season = SEASON ? (await one(`insert into seasons (name, starts_at, ends_at, home_businesses, home_defenders)
  values ('QA Season', now(), now() + interval '1 day', (select array_agg(code) from (select code from business_defs order by random() limit 6) x), array[12, 22, 32, 45, 60, 75, 95]) returning id`)).id : null

const screens = ['/', '/actions', '/economy', '/economy?tab=market', '/items', '/items?tab=shop', '/services', '/fight',
  `/player/${ids.rook}`, '/territory', `/crew/${ids.crew}`, '/crew', '/cartel', '/casino', '/casino/slots', '/casino/blackjack',
  '/casino/roulette', '/casino/craps', '/casino/poker', '/chat', '/profile', '/accolades', '/activity', '/store', '/forum',
  ...(ids.thread ? [`/forum/t/${ids.thread}`] : [])]

// links that point at nothing: an old share, a deleted player, a typo. Each should say so on the page, not crash.
const broken = ['/player/not-a-player', '/player/00000000-0000-4000-8000-000000000000', '/crew/not-a-crew',
  '/crew/00000000-0000-4000-8000-000000000000', '/cartel/00000000-0000-4000-8000-000000000000', '/casino/table/99999',
  '/casino/nope', '/forum/t/99999999', '/forum/t/abc', '/forum/nope', '/chat/dm:nobody', '/chat/crew:00000000-0000-4000-8000-000000000000',
  '/territory?hood=999&block=99999', '/items?tab=nope&setup=nope', '/economy?tab=nope', '/no-such-screen']

const sizes = [
  { name: 'iPhone SE 1st gen', width: 320, height: 568 },
  { name: 'iPhone SE', width: 375, height: 667 },
  { name: 'iPhone 14', width: 390, height: 844, axe: true },
  { name: 'iPhone Pro Max', width: 430, height: 932 },
  { name: 'iPad mini', width: 768, height: 1024 },
  { name: 'iPhone landscape', width: 844, height: 390 },
]

const report = { overflow: [], console: [], requests: [], axe: [], broken: [] }
const browser = await chromium.launch({ executablePath: process.env.CHROME || '/opt/pw-browsers/chromium' })
async function sweep(phase, screens, broken, sizes) {
  for (const size of sizes) {
    const ctx = await browser.newContext({ viewport: { width: size.width, height: size.height }, deviceScaleFactor: 2, isMobile: size.width < 700, hasTouch: true })
    const p = await ctx.newPage()
    let at = '(sign-in)'
    p.on('dialog', d => d.dismiss())
    const tag = phase ? `${phase} ` : ''
    p.on('console', m => { if (m.type() === 'error') report.console.push(`${tag}${size.width} ${at}: ${m.text().slice(0, 200)}`) })
    p.on('pageerror', e => report.console.push(`${size.width} ${at}: uncaught ${String(e).slice(0, 200)}`))
    p.on('requestfailed', r => { if (!/favicon|hot-update/.test(r.url())) report.requests.push(`${size.width} ${at}: ${r.failure()?.errorText} ${r.url().slice(0, 120)}`) })
    p.on('response', r => { if (r.status() >= 400) report.requests.push(`${size.width} ${at}: ${r.status()} ${r.url().slice(0, 120)}`) })
    await p.goto(BASE)
    await p.getByLabel('Email').fill('bot01@demo.local')
    await p.getByLabel('Password').fill('secret123')
    await p.getByRole('button', { name: 'Sign In' }).click()
    await p.locator('.topbar').waitFor()
    for (const s of screens) {
      at = s
      await p.goto(BASE + s)
      await p.locator('.topbar').waitFor()
      await p.waitForFunction(() => !document.querySelector('.spin'), null, { timeout: 15000 }).catch(() => {})
      await p.waitForTimeout(400)
      // sideways scroll, and anything sticking out past the right edge that isn't inside its own scroller
      const o = await p.evaluate(() => {
        const vw = document.documentElement.clientWidth
        const scrolls = (el) => { for (let e = el.parentElement; e; e = e.parentElement) { const ox = getComputedStyle(e).overflowX; if ((ox === 'auto' || ox === 'scroll' || ox === 'hidden') && e !== document.body && e !== document.documentElement) return true } return false }
        const out = []
        for (const el of document.querySelectorAll('body *')) {
          const r = el.getBoundingClientRect()
          if (!r.width || r.right <= vw + 1 || scrolls(el)) continue
          if (getComputedStyle(el).position === 'fixed' && r.left >= vw) continue   // a sheet parked off-screen
          out.push(`${el.tagName.toLowerCase()}${el.className && typeof el.className === 'string' ? '.' + el.className.trim().split(/\s+/).join('.') : ''} "${(el.textContent || '').trim().slice(0, 30)}" right=${Math.round(r.right)}`)
        }
        return { page: document.documentElement.scrollWidth > vw + 1 ? document.documentElement.scrollWidth : 0, els: out.slice(0, 5) }
      })
      if (o.page || o.els.length) {
        report.overflow.push(`${tag}${size.width}×${size.height} ${s}: page ${o.page ? 'scrolls to ' + o.page : 'ok'}; ${o.els.join(' | ')}`)
        await p.screenshot({ path: path.join(OUT, `overflow-${size.width}-${s.replace(/[^a-z0-9]+/gi, '_')}.png`), fullPage: true })
      }
      if (size.axe && AXE) {
        await p.addScriptTag({ content: AXE })
        const v = await p.evaluate(async () => (await window.axe.run(document, { resultTypes: ['violations'] })).violations
          .map(v => ({ id: v.id, impact: v.impact, help: v.help, nodes: v.nodes.slice(0, 4).map(n => n.target.join(' ') + (n.any?.[0]?.message ? ` — ${n.any[0].message.slice(0, 120)}` : '')) , count: v.nodes.length })))
        for (const x of v) report.axe.push({ screen: tag + s, ...x })
      }
    }
    if (size.axe && broken.length) {
      for (const s of broken) {
        at = s
        await p.goto(BASE + s)
        await p.locator('.topbar').waitFor()
        await p.waitForFunction(() => !document.querySelector('.spin'), null, { timeout: 15000 }).catch(() => {})
        await p.waitForTimeout(400)
        const seen = await p.evaluate(() => ({ path: location.pathname + location.search, text: (document.querySelector('main')?.innerText || '').replace(/\s+/g, ' ').trim().slice(0, 110), crashed: !!document.body.innerText.match(/Something went wrong/) }))
        report.broken.push(`${seen.crashed ? 'CRASH ' : ''}${s} → ${seen.path}: ${seen.text}`)
      }
    }
    await ctx.close()
  }
}
try {
  if (!SEASON) await sweep('', screens, broken, sizes)
  else {
    // the start of the campaign: the hood untouched, every gated tab locked, a profile with its Attack locked
    await sweep('locked', ['/', '/territory?focus=hood', '/missions', '/items', '/actions', '/fight', `/player/${ids.rook}`, '/economy', '/services', '/casino', '/crew', '/profile'], [], sizes)
    // the campaign done: every mission claimed, the hood taken and the boss down
    await db.query(`insert into missions (player_id, season_id, key, completed_at, claimed_at) select $1, $2, key, now(), now() from mission_defs
                    on conflict (player_id, season_id, key) do update set completed_at = excluded.completed_at, claimed_at = excluded.claimed_at`, [me, season])
    await db.query(`update home_blocks set cleared_at = now(), collected_at = now() - interval '5 hours', level = 2 where player_id = $1 and season_id = $2`, [me, season])
    await db.query(`update home_hoods set opened_at = coalesce(opened_at, now()), boss_cleared_at = now() where player_id = $1 and season_id = $2`, [me, season])
    await sweep('done', [...screens, '/territory?focus=hood', '/missions'], broken, sizes)
  }
} finally {
  await browser.close()
  if (season) await db.query('delete from seasons where id = $1', [season]).catch(() => {})
  await db.end()
}
fs.writeFileSync(path.join(OUT, 'report.json'), JSON.stringify(report, null, 1))
const byRule = {}
for (const a of report.axe) { byRule[a.id] ??= { impact: a.impact, help: a.help, screens: 0, nodes: 0 }; byRule[a.id].screens++; byRule[a.id].nodes += a.count }
console.log(`overflow: ${report.overflow.length}\n` + report.overflow.join('\n'))
console.log(`console errors: ${report.console.length}\n` + [...new Set(report.console)].slice(0, 30).join('\n'))
console.log(`failed requests: ${report.requests.length}\n` + [...new Set(report.requests)].slice(0, 30).join('\n'))
console.log(`broken links:\n` + report.broken.join('\n'))
console.log('axe rules:\n' + Object.entries(byRule).map(([id, r]) => `${r.impact} ${id} (${r.screens} screens, ${r.nodes} nodes): ${r.help}`).join('\n'))
