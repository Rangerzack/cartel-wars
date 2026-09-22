export const money = (n: number | null | undefined) => '$' + Math.round(n ?? 0).toLocaleString('en-US')
export const num = (n: number | null | undefined) => Math.round(n ?? 0).toLocaleString('en-US')

export function timeLeft(iso: string | null | undefined, now = Date.now()): string {
  if (!iso) return ''
  const ms = new Date(iso).getTime() - now
  if (ms <= 0) return 'now'
  const s = Math.ceil(ms / 1000)
  if (s < 60) return `${s}s`
  const m = Math.floor(s / 60)
  if (m < 60) return `${m}m ${s % 60}s`
  const h = Math.floor(m / 60)
  if (h < 48) return `${h}h ${m % 60}m`
  return `${Math.floor(h / 24)}d ${h % 24}h`
}

export function ago(iso: string, now = Date.now()): string {
  const s = Math.max(0, Math.floor((now - new Date(iso).getTime()) / 1000))
  if (s < 60) return 'just now'
  const m = Math.floor(s / 60)
  if (m < 60) return `${m}m ago`
  const h = Math.floor(m / 60)
  if (h < 24) return `${h}h ago`
  return `${Math.floor(h / 24)}d ago`
}

export const commodityIcon: Record<string, string> = { herb: '🌿', dust: '❄️', pills: '💊' }
export const categoryLabel: Record<string, string> = {
  weapon: 'Weapons', jail_weapon: 'Jail Weapons', protection: 'Protection', transport: 'Transport',
}
export const hoodlumIcon: Record<string, string> = { thug: '🧢', spy: '🕶️', mercenary: '🔫', enforcer: '🛡️' }

export const accoladeMeta: Record<string, { label: string; icon: string; unit: (n: number) => string }> = {
  fight_win: { label: 'Fights won', icon: '⚔️', unit: n => `${num(n)} ${n === 1 ? 'win' : 'wins'}` },
  defense: { label: 'Defenses', icon: '🛡️', unit: n => `${num(n)} held` },
  action: { label: 'Actions', icon: '💼', unit: n => `${num(n)} actions` },
  import: { label: 'Imports', icon: '🚚', unit: n => `${num(n)} units` },
  market: { label: 'Market', icon: '💰', unit: n => money(n) },
  turf: { label: 'Turf', icon: '🏴', unit: n => `${num(n)} blocks` },
  gambler: { label: 'Gambler', icon: '🎰', unit: n => (n < 0 ? '−' : '') + money(Math.abs(n)) },
}

/** Compact money for chips: $1.2M, $25k */
export const chips = (n: number | null | undefined) => {
  const v = Math.round(n ?? 0)
  const a = Math.abs(v), sign = v < 0 ? '−' : ''
  if (a >= 1_000_000) return `${sign}$${(a / 1_000_000).toFixed(a % 1_000_000 === 0 ? 0 : 1)}M`
  if (a >= 10_000) return `${sign}$${(a / 1000).toFixed(a % 1000 === 0 ? 0 : 1)}k`
  return sign + money(a)
}

