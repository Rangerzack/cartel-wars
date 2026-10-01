// Unit test for supabase/functions/iap-webhook: the Authorization check, bad bodies, and how a RevenueCat event maps
// onto iap_apply's arguments (no database: the Supabase client is a stub that records the rpc call).
// Usage: node scripts/iap-webhook-test.mjs
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'
import assert from 'node:assert/strict'

// Load the function with Deno.serve, Deno.env and createClient stubbed. Node strips the TypeScript types itself.
let handler
const env = {}
globalThis.Deno = { serve: (h) => { handler = h }, env: { get: (k) => env[k] } }
const calls = []
let reply = { data: { credited: 100 }, error: null }
globalThis.__createClient = (url, key, opts) => ({ rpc: async (fn, args) => { calls.push({ url, key, opts, fn, args }); return reply } })
const src = fs.readFileSync(new URL('../supabase/functions/iap-webhook/index.ts', import.meta.url), 'utf8')
const stubbed = src.replace(/^import \{ createClient \} from 'jsr:@supabase\/supabase-js@2'$/m, 'const createClient = globalThis.__createClient')
assert.notEqual(stubbed, src, 'the supabase-js import is where the test expects it')
const dir = fs.mkdtempSync(path.join(os.tmpdir(), 'iap-webhook-'))
fs.writeFileSync(path.join(dir, 'index.ts'), stubbed)
await import(path.join(dir, 'index.ts'))
fs.rmSync(dir, { recursive: true, force: true })

const USER = '6f1c2a3b-4d5e-4f60-8a9b-0c1d2e3f4a5b'
const post = (body, auth = 'Bearer rc-secret') => handler(new Request('http://x/iap-webhook', {
  method: 'POST', headers: { 'Content-Type': 'application/json', ...(auth == null ? {} : { Authorization: auth }) },
  body: typeof body === 'string' ? body : JSON.stringify(body),
}))
const event = (e) => ({ api_version: '1.0', event: { id: 'evt-1', app_user_id: USER, environment: 'SANDBOX', ...e } })
const pack = event({ type: 'NON_RENEWING_PURCHASE', product_id: 'io.rangelab.cartelwars.diamonds.100', transaction_id: '2000000123', expiration_at_ms: null })

// Locked until the secret is set, and then only with it
let r = await post(pack)
assert.equal(r.status, 401, 'no REVENUECAT_WEBHOOK_AUTH configured: nothing gets in')
env.REVENUECAT_WEBHOOK_AUTH = 'Bearer rc-secret'
env.SUPABASE_URL = 'https://example.supabase.co'
env.SUPABASE_SERVICE_ROLE_KEY = 'service-key'
assert.equal((await post(pack, 'Bearer rc-secre')).status, 401, 'wrong header')
assert.equal((await post(pack, null)).status, 401, 'no header')
assert.equal((await handler(new Request('http://x/', { method: 'GET' }))).status, 405)
assert.equal((await post('{nope')).status, 400, 'malformed JSON')
assert.equal((await post({ api_version: '1.0' })).status, 400, 'no event')
assert.equal((await post({ event: { type: 'TEST' } })).status, 400, 'no transaction or event id')
assert.equal(calls.length, 0, 'nothing reached the database')

// A pack: the event maps onto iap_apply with the service key, and the answer comes back as is
r = await post(pack)
assert.equal(r.status, 200)
assert.deepEqual(await r.json(), { credited: 100 })
let c = calls.at(-1)
assert.equal(c.fn, 'iap_apply')
assert.equal(c.url, 'https://example.supabase.co')
assert.equal(c.key, 'service-key')
assert.deepEqual(c.args, {
  provider: 'revenuecat', event: 'NON_RENEWING_PURCHASE', transaction_id: '2000000123',
  product_id: 'io.rangelab.cartelwars.diamonds.100', player: USER, expires_at: null, raw: pack.event,
})

// The subscription: the expiry becomes a timestamp; a refund keeps its cancel_reason in raw for iap_apply
await post(event({ type: 'RENEWAL', product_id: 'io.rangelab.cartelwars.drop.monthly', transaction_id: '2000000456', expiration_at_ms: Date.UTC(2026, 10, 1, 12) }))
assert.equal(calls.at(-1).args.expires_at, '2026-11-01T12:00:00.000Z')
const refund = event({ type: 'CANCELLATION', product_id: 'io.rangelab.cartelwars.drop.monthly', transaction_id: '2000000456', cancel_reason: 'CUSTOMER_SUPPORT' })
await post(refund)
assert.equal(calls.at(-1).args.event, 'CANCELLATION')
assert.equal(calls.at(-1).args.raw.cancel_reason, 'CUSTOMER_SUPPORT')

// No transaction id: the event id stands in. An app_user_id that isn't a Supabase user id is no player.
await post(event({ type: 'TEST', id: 'evt-test', product_id: 'test_product', transaction_id: null, app_user_id: '$RCAnonymousID:abc' }))
c = calls.at(-1)
assert.equal(c.args.transaction_id, 'evt-test')
assert.equal(c.args.player, null)

// Something we don't use is still a 200, or RevenueCat keeps retrying it
reply = { data: { ignored: 'unknown product' }, error: null }
r = await post(event({ type: 'NON_RENEWING_PURCHASE', product_id: 'io.rangelab.cartelwars.gold', transaction_id: '2000000789' }))
assert.equal(r.status, 200)
assert.deepEqual(await r.json(), { ignored: 'unknown product' })

// A database failure is a 500, so RevenueCat retries it
reply = { data: null, error: { message: 'connection refused' } }
r = await post(pack)
assert.equal(r.status, 500)
assert.deepEqual(await r.json(), { error: 'connection refused' })

console.log('IAP WEBHOOK TEST PASSED')
