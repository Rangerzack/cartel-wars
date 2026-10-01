// "Can't reach the city" (#20): when the first load can't reach the server the app shows a full-screen Retry instead of
// a spinner that never ends; errors the server sends back keep the toast. Self-contained: builds the web app against a
// fake Supabase host and serves it through Playwright routes, so it needs no database, dev server or port.
// Run from the repo root: node scripts/e2e-offline.mjs
import { chromium } from 'playwright'
import { execFileSync } from 'node:child_process'
import { mkdtempSync, readFileSync, rmSync } from 'node:fs'
import { tmpdir } from 'node:os'
import { extname, join } from 'node:path'

const out = mkdtempSync(join(tmpdir(), 'cw-offline-'))
execFileSync('npx', ['vite', 'build', '--outDir', out, '--emptyOutDir', '--logLevel', 'error'], {
  cwd: 'web', stdio: 'inherit',
  env: { ...process.env, BASE_PATH: '/', VITE_SUPABASE_URL: 'http://supabase.test', VITE_SUPABASE_ANON_KEY: 'test' },
})

const APP = 'http://app.test'
const TYPES = { '.html': 'text/html', '.js': 'text/javascript', '.css': 'text/css', '.svg': 'image/svg+xml', '.png': 'image/png', '.woff2': 'font/woff2', '.woff': 'font/woff', '.webmanifest': 'application/manifest+json' }
const now = () => Math.floor(Date.now() / 1000)
const session = expiresAt => JSON.stringify({
  access_token: 'test-access', refresh_token: 'test-refresh', token_type: 'bearer', expires_in: 3600, expires_at: expiresAt,
  user: { id: '00000000-0000-4000-8000-000000000001', aud: 'authenticated', role: 'authenticated', email: 'offline@test.local', app_metadata: {}, user_metadata: {}, created_at: new Date().toISOString() },
})

let failures = 0
const check = (ok, what) => { console.log(`${ok ? 'ok  ' : 'FAIL'} ${what}`); if (!ok) failures++ }

const browser = await chromium.launch({ executablePath: process.env.CHROME || '/opt/pw-browsers/chromium' })

/** A fresh browser profile with the app served from `out`; `net` decides what Supabase does: 'down' (airplane mode) or 'error' (server says no). */
async function open(stored) {
  const ctx = await browser.newContext()
  const state = { net: 'down', calls: 0, chunks: [] }
  await ctx.route(`${APP}/**`, r => {
    const path = new URL(r.request().url()).pathname
    const file = path === '/' || !extname(path) ? 'index.html' : path.slice(1)
    if (/^assets\/(esm|web)-/.test(file)) state.chunks.push(file)
    try { return r.fulfill({ status: 200, contentType: TYPES[extname(file)] ?? 'application/octet-stream', body: readFileSync(join(out, file)) }) }
    catch { return r.fulfill({ status: 404, body: '' }) }
  })
  await ctx.route('http://supabase.test/**', r => {
    state.calls++
    if (state.net === 'down') return r.abort('internetdisconnected')
    const url = r.request().url()
    if (url.includes('/rpc/get_me')) return r.fulfill({ status: 400, contentType: 'application/json', body: JSON.stringify({ code: 'P0001', message: 'The city is closed', details: null, hint: null }) })
    return r.fulfill({ status: 200, contentType: 'application/json', body: '{}' })
  })
  if (stored) await ctx.addInitScript(s => { if (!sessionStorage.getItem('seeded')) { localStorage.setItem('sb-supabase-auth-token', s); sessionStorage.setItem('seeded', '1') } }, stored)
  const page = await ctx.newPage()
  await page.goto(APP + '/')
  return { ctx, page, state }
}

// 1. Signed in, no network: get_me never reaches the server.
{
  const { ctx, page, state } = await open(session(now() + 3600))
  const title = page.getByText("Can't reach the city")
  await title.waitFor({ timeout: 10_000 }).catch(() => {})
  check(await title.isVisible(), 'signed in + offline: shows "Can\'t reach the city"')
  check(await page.getByText('Check your connection and try again.').isVisible(), 'shows the one-line hint')
  check(!(await page.getByText('Entering the city').isVisible()), 'no endless "Entering the city" spinner')
  check(!(await page.locator('.toast').count()), 'no toast on top of it')
  check(state.chunks.length === 0, `web build loaded no native plugin chunks (${state.chunks.join(', ') || 'none'})`)

  // 2. Retry while still offline: the boot runs again and lands on the same screen.
  const before = state.calls
  await page.getByRole('button', { name: 'Retry' }).click()
  await page.waitForTimeout(800)
  check(state.calls > before, `Retry re-ran the start-up (${state.calls - before} new requests)`)
  check(await title.isVisible(), 'still offline: the screen comes back')

  // 3. The connection comes back (the browser fires `online`) but the server refuses: retried without a tap,
  //    then the old behaviour (toast + spinner), not the offline screen.
  state.net = 'error'
  const beforeOnline = state.calls
  await page.evaluate(() => window.dispatchEvent(new Event('online')))
  await page.locator('.toast.bad', { hasText: 'The city is closed' }).waitFor({ timeout: 5_000 }).catch(() => {})
  check(state.calls > beforeOnline, 'connection back: retried by itself')
  check(await page.locator('.toast.bad', { hasText: 'The city is closed' }).isVisible(), 'server error after the retry: toasted as before')
  check(!(await title.isVisible()), 'server error: offline screen gone')
  check(await page.getByText('Entering the city').isVisible(), 'server error: back on the existing "Entering the city" state')
  await ctx.close()
}

// 4. Signed out and offline: the sign-in page as before (nothing was requested, so nothing failed).
{
  const { ctx, page, state } = await open(null)
  await page.waitForTimeout(1500)
  check(!(await page.getByText("Can't reach the city").isVisible()), 'signed out + offline: no offline screen')
  check(await page.locator('.auth input[type=email]').isVisible(), 'signed out + offline: sign-in form shown')
  check(state.calls === 0, 'signed out: no Supabase requests at boot')
  await ctx.close()
}

// 5. Expired token, no network: the token refresh fails (supabase-js retries it for up to ~30 s first) → offline screen, not sign-in.
{
  const { ctx, page } = await open(session(now() - 3600))
  const title = page.getByText("Can't reach the city")
  await title.waitFor({ timeout: 90_000 }).catch(() => {})
  check(await title.isVisible(), 'expired token + offline: shows "Can\'t reach the city" instead of the sign-in page')
  await ctx.close()
}

await browser.close()
rmSync(out, { recursive: true, force: true })
console.log(failures ? `\n${failures} check(s) failed` : '\nall offline checks passed')
process.exit(failures ? 1 : 0)
