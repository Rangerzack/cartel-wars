// report-notify: tells the admin that players have filed reports (#13; Apple guideline 1.2 wants "timely responses to
// concerns"). The _report_notify() trigger calls it through pg_net, at most once every 10 minutes, with a shared secret
// in x-report-secret instead of a user JWT, so it's deployed with --no-verify-jwt. It sends one Discord post, or one
// email through Resend, whichever is configured. Secrets and setup: docs/ops.md.

const ADMIN_URL = 'https://rangerzack.github.io/cartel-wars/admin'
const DEFAULT_FROM = 'Cartel Wars <noreply@rangelab.io>'

type Latest = { reason?: string; note?: string; target?: string | null; reporter?: string | null; at?: string }
type Payload = { kind?: string; open_targets?: number; open_reports?: number; latest?: Latest }

const json = (status: number, body: unknown) =>
  new Response(JSON.stringify(body), { status, headers: { 'Content-Type': 'application/json' } })

// Compares every byte, so the response time doesn't give away how much of a guess was right.
function sameSecret(given: string, want: string): boolean {
  const a = new TextEncoder().encode(given), b = new TextEncoder().encode(want)
  let diff = a.length ^ b.length
  for (let i = 0; i < Math.max(a.length, b.length); i++) diff |= (a[i] ?? 0) ^ (b[i] ?? 0)
  return diff === 0
}

const count = (n: unknown, one: string, many: string) => {
  const k = Math.max(0, Math.floor(Number(n) || 0))
  return `${k} ${k === 1 ? one : many}`
}

// The message as separate lines (Discord joins them with spaces, email with line breaks). Names and notes are typed by
// players, so in Discord their markdown characters are escaped and they can't restyle the post.
function message(p: Payload, markdown: boolean) {
  const t = (s: unknown) => {
    const v = String(s ?? '').replace(/\s+/g, ' ').trim()
    return markdown ? v.replace(/[\\*_~`|>]/g, '\\$&') : v
  }
  const bold = (s: string) => (markdown ? `**${s}**` : s), italic = (s: string) => (markdown ? `*${s}*` : s)
  const players = count(p.open_targets, 'player', 'players'), reports = count(p.open_reports, 'report', 'reports')
  const l = p.latest ?? {}, note = t(l.note)
  return {
    subject: `🚩 ${players} with open reports`,
    lines: [
      `🚩 ${bold(players)} with open reports (${reports}).`,
      `Latest: ${italic(t(l.reason) || 'other')} on ${bold(t(l.target) || 'a player')} by ${t(l.reporter) || 'a player'}${note ? ` — "${note}"` : ''}.`,
      `Review: ${ADMIN_URL}`,
    ],
  }
}

async function post(channel: string, url: string, headers: Record<string, string>, body: unknown): Promise<Response> {
  let res: Response
  try {
    res = await fetch(url, { method: 'POST', headers: { 'Content-Type': 'application/json', ...headers }, body: JSON.stringify(body) })
  } catch (e) {
    return json(502, { error: `${channel} unreachable: ${e instanceof Error ? e.message : String(e)}` })
  }
  if (!res.ok) return json(502, { error: `${channel} answered ${res.status}: ${(await res.text()).slice(0, 200)}` })
  return json(200, { sent: channel.toLowerCase() })
}

Deno.serve(async (req: Request) => {
  if (req.method !== 'POST') return json(405, { error: 'POST only' })
  const secret = Deno.env.get('REPORT_SECRET') ?? ''
  if (!secret || !sameSecret(req.headers.get('x-report-secret') ?? '', secret)) return json(401, { error: 'Bad secret' })
  let p: Payload
  try {
    p = await req.json()
  } catch {
    return json(400, { error: 'Body must be JSON' })
  }
  if (p?.kind !== 'report') return json(400, { error: 'Unknown kind' })

  const discord = Deno.env.get('DISCORD_WEBHOOK_URL')
  if (discord) {
    // allowed_mentions: a player named @everyone pings nobody
    return post('Discord', discord, {}, { content: message(p, true).lines.join(' '), allowed_mentions: { parse: [] } })
  }
  const key = Deno.env.get('RESEND_API_KEY'), to = (Deno.env.get('REPORT_EMAIL_TO') ?? '').split(',').map((s) => s.trim()).filter(Boolean)
  if (key && to.length) {
    const m = message(p, false)
    return post('Resend', 'https://api.resend.com/emails', { Authorization: `Bearer ${key}` },
      { from: Deno.env.get('REPORT_EMAIL_FROM') || DEFAULT_FROM, to, subject: m.subject, text: m.lines.join('\n') })
  }
  return json(200, { skipped: 'no channel configured' })
})
