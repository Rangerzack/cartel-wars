import type { BusinessCode, BusinessDef, Catalog, Me } from './types'

/** Your crew's perk for a business, as a fraction (0 when you don't hold one). */
export const perk = (me: Me, code: BusinessCode): number => me.perks?.[code] ?? 0

export const businessDef = (catalog: Catalog | null, code: BusinessCode | undefined | null): BusinessDef | undefined =>
  code ? catalog?.businesses?.find(b => b.code === code) : undefined

const pct = (v: number) => `${Math.round(v * 1000) / 10}%`
const DISCOUNT: BusinessCode[] = ['chop_shop', 'gym', 'shooting_range', 'pawn_shop', 'pharmacy', 'clinic', 'law_office', 'bent_cop']

/** How a perk value reads for its business: "−20%", "+20%", "20% sooner", "60% resale". */
export function perkLabel(code: BusinessCode, v: number): string {
  if (code === 'repo') return `${pct(0.5 + v)} resale`
  if (code === 'night_club') return `${pct(v)} sooner`
  return `${DISCOUNT.includes(code) ? '−' : '+'}${pct(v)}`
}

/** Price after a discount perk, rounded the way the server rounds it. */
export const discounted = (price: number, v: number, round: 'round' | 'ceil' = 'round') =>
  v > 0 ? Math[round](price * (1 - v)) : price

/** Bail, the way bail_out prices it: the flat bail less the Law Office, rounded up. */
export const bailCost = (me: Me, cfg: Record<string, number>) => Math.ceil((cfg.bail_base ?? 8000) * (1 - perk(me, 'law_office')))

/** n points of health, the way buy_health prices them: the per-point price climbs with what you've bought in the last
 *  24 hours (_health_price), less the Clinic, rounded up at each step like the server. */
export const healthCost = (me: Me, cfg: Record<string, number>, n: number) =>
  Math.ceil(Math.ceil(cfg.hospital_per_point * n * (1 + (me.health_bought + n / 2) / cfg.health_price_scale)) * (1 - perk(me, 'clinic')))
