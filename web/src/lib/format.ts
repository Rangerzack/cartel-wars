import { now as clockNow } from './clock'
export const money = (n: number | null | undefined) => { const v = Math.round(n ?? 0); return (v < 0 ? '−$' : '$') + Math.abs(v).toLocaleString('en-US') }
export const num = (n: number | null | undefined) => Math.round(n ?? 0).toLocaleString('en-US')
/** "a, b and c" */
export const andList = (xs: string[]) => xs.length > 1 ? `${xs.slice(0, -1).join(', ')} and ${xs[xs.length - 1]}` : xs[0] ?? ''
/** What an amount field means as a whole number: "1,000" is 1000, "2.5" is 2, "" is 0 (RPCs take integers). */
export const toInt = (v: string) => { const n = Math.floor(Number(v.replace(/[^0-9.]/g, ''))); return Number.isFinite(n) && n > 0 ? n : 0 }

export function timeLeft(iso: string | null | undefined, now = clockNow()): string {
  if (!iso) return ''
  const ms = new Date(iso).getTime() - now
  if (ms <= 0) return '0s'   // reads in every frame it's used in ("Back in 0s", "0s left"), unlike "now"
  const s = Math.ceil(ms / 1000)
  if (s < 60) return `${s}s`
  const m = Math.floor(s / 60)
  if (m < 60) return `${m}m ${s % 60}s`
  const h = Math.floor(m / 60)
  if (h < 48) return `${h}h ${m % 60}m`
  return `${Math.floor(h / 24)}d ${h % 24}h`
}

export function ago(iso: string, now = clockNow()): string {
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
/** A hoodlum code as a word: "thug" / "12 thugs", "mercenary" / "mercenaries". */
export const hoodlumName = (code: string, n = 1) => {
  const one = code === 'mercenary' ? 'merc' : code
  return n === 1 ? one : one.endsWith('y') ? `${one.slice(0, -1)}ies` : `${one}s`
}

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
  const short = (x: number) => String(Math.round(x * 10) / 10)   // one decimal at most, no trailing .0 ($1M, not $1000.0k)
  if (a >= 999_950) return `${sign}$${short(a / 1_000_000)}M`
  if (a >= 9_995) return `${sign}$${short(a / 1000)}k`
  return sign + money(a)
}


/** "every minute" / "every 10 minutes" */
export const every = (mins: number | null | undefined) => (!mins || mins === 1 ? 'every minute' : `every ${mins} minutes`)

/** The game day rolls over at 00:00 UTC (refills come back, daily cash lands). */
export function nextRollover(now = Date.now()): string {
  const d = new Date(now)
  return new Date(Date.UTC(d.getUTCFullYear(), d.getUTCMonth(), d.getUTCDate() + 1)).toISOString()
}

/** "1 in 500" for a job's rare-find chance (stamina_cost / drop_stamina). */
export const dropOdds = (stamina: number, dropStamina: number | undefined) =>
  `1 in ${num(Math.round((dropStamina || 6000) / Math.max(1, stamina)))}`

/** Icons for the four rare finds, by kind. */
export const findIcon: Record<string, string> = { weapon: '🚀', protection: '🦺', transport: '🚙', jail_weapon: '🔫' }
/** Daily Drop prize icons. */
export const dropIcon: Record<string, string> = { herb: '🌿', dust: '❄️', pills: '💊', diamonds: '💎', cash: '💵', refills: '⚡', thugs: '🧢', hustlers: '🚶' }
