// iap-webhook: RevenueCat tells us about App Store purchases (#15, #16) — diamond packs and the Daily Drop
// subscription. Each event goes to iap_apply() in the database, which credits, claws back or extends and records the
// event once (supabase/migrations/20261004000012_store.sql). RevenueCat sends the Authorization header we set in its
// dashboard instead of a user JWT, so the function is deployed with --no-verify-jwt. Setup: docs/ops.md, "Purchases".
//
// RevenueCat retries anything but a 2xx, so an event we don't use still gets 200 (iap_apply records it as ignored),
// and only a database failure answers 500, to be retried.
import { createClient } from 'jsr:@supabase/supabase-js@2'

// The parts of RevenueCat's webhook event we read; the whole event is stored as iap_grants.raw.
type RcEvent = {
  type?: string; id?: string; app_user_id?: string; product_id?: string; transaction_id?: string | null
  expiration_at_ms?: number | null; cancel_reason?: string | null; environment?: string
}

const UUID = /^[0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}$/i

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })

// Compares every byte, so the response time doesn't give away how much of a guess was right.
function sameSecret(given: string, want: string): boolean {
  const a = new TextEncoder().encode(given), b = new TextEncoder().encode(want)
  let diff = a.length ^ b.length
  for (let i = 0; i < Math.max(a.length, b.length); i++) diff |= (a[i] ?? 0) ^ (b[i] ?? 0)
  return diff === 0
}

// The event as iap_apply's arguments. app_user_id is the Supabase user id (the app logs in to RevenueCat with it);
// anything else (an anonymous RevenueCat id) is no player. A refund is a CANCELLATION whose cancel_reason iap_apply
// reads from raw.
function toArgs(e: RcEvent) {
  return {
    provider: 'revenuecat',
    event: String(e.type ?? ''),
    transaction_id: String(e.transaction_id || e.id || ''),
    product_id: String(e.product_id ?? ''),
    player: UUID.test(e.app_user_id ?? '') ? e.app_user_id : null,
    expires_at: e.expiration_at_ms ? new Date(e.expiration_at_ms).toISOString() : null,
    raw: e,
  }
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return json(405, { error: 'POST only' })
  const auth = Deno.env.get('REVENUECAT_WEBHOOK_AUTH') ?? ''
  if (!auth || !sameSecret(req.headers.get('Authorization') ?? '', auth)) return json(401, { error: 'Bad authorization' })
  let body: { event?: RcEvent }
  try {
    body = await req.json()
  } catch {
    return json(400, { error: 'Body must be JSON' })
  }
  const e = body?.event
  if (!e || typeof e !== 'object' || !e.type || !(e.transaction_id || e.id)) return json(400, { error: 'No event' })

  const db = createClient(Deno.env.get('SUPABASE_URL') ?? '', Deno.env.get('SUPABASE_SERVICE_ROLE_KEY') ?? '',
    { auth: { persistSession: false } })
  const { data, error } = await db.rpc('iap_apply', toArgs(e))
  if (error) return json(500, { error: error.message })
  return json(200, data)
})
