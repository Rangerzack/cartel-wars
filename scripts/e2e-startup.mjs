// Start-up's second chance (lib/game.tsx): now and then the first call after a token refresh comes back 401 from the
// API while the same token works a moment later (seen on staging, Nov 2026). The first get_me or get_catalog that
// fails for a reason other than the network is tried once more after a beat, so the player sees the city, not a
// toast and a minute of "Entering the city…". A call that keeps failing still shows its error.
// Usage (local stack with the demo world): node scripts/e2e-startup.mjs
import { chromium } from 'playwright'

const BASE = process.env.BASE || 'http://127.0.0.1:5173'
const API = process.env.API || 'http://127.0.0.1:54321'
const browser = await chromium.launch({ executablePath: process.env.CHROME || '/opt/pw-browsers/chromium' })
const errors = []
const deny = { status: 401, contentType: 'application/json', body: JSON.stringify({ code: 'PGRST301', message: 'JWT expired', details: null, hint: null }) }

try {
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 } })
  const p = await ctx.newPage()
  p.on('pageerror', e => errors.push(e.message))
  await p.goto(BASE)
  await p.getByLabel('Email').fill('bot05@demo.local')
  await p.getByLabel('Password').fill('secret123')
  await p.getByRole('button', { name: 'Sign In' }).click()
  await p.locator('.topbar').waitFor()

  // 1. the first get_me and the first get_catalog of a load are refused once: the city still comes up, no toast
  const refused = { get_me: 0, get_catalog: 0 }
  await p.route(`${API}/rest/v1/rpc/*`, r => {
    const fn = new URL(r.request().url()).pathname.split('/').pop()
    if ((fn === 'get_me' || fn === 'get_catalog') && refused[fn] === 0) { refused[fn]++; return r.fulfill(deny) }
    return r.continue()
  })
  const t0 = Date.now()
  await p.reload()
  await p.locator('.topbar').waitFor({ timeout: 8000 })
  await p.locator('.quick a').first().waitFor()   // Home rendered with the catalog in hand
  const took = Date.now() - t0
  if (refused.get_me !== 1 || refused.get_catalog !== 1) throw new Error('both first calls were refused: ' + JSON.stringify(refused))
  await p.waitForTimeout(1500)
  if (await p.locator('.toast.bad').count()) throw new Error('a refused first call shows no error: ' + await p.locator('.toast.bad').allTextContents())
  await p.unroute(`${API}/rest/v1/rpc/*`)

  // 2. a call that keeps failing: the error shows after the second try, and the splash stays (the poll's job)
  await p.route(`${API}/rest/v1/rpc/get_me`, r => r.fulfill(deny))
  await p.reload()
  await p.locator('.toast.bad', { hasText: 'JWT expired' }).waitFor({ timeout: 8000 })
  if (!(await p.getByText('Entering the city').isVisible())) throw new Error('still failing: the splash stays until the poll')
  await p.unroute(`${API}/rest/v1/rpc/get_me`)

  if (errors.length) throw new Error(errors.join('\n'))
  console.log(`e2e-startup PASSED: a refused first call is retried once (${took} ms to the city), a stuck one still errors`)
} catch (e) {
  console.error('e2e-startup FAILED:', e.message)
  process.exitCode = 1
} finally {
  await browser.close()
}
