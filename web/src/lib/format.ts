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
