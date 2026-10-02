import type { Catalog, Commodity, Me, StreetInfo } from './types'
import { perk } from './perks'

const pct = (catalog: Catalog | null, key: string, fallback: number) => (catalog?.config?.[key] ?? fallback) / 100

/** Street price for a wiggle and a dumping pressure — the server's _street(). */
export function streetAt(s: StreetInfo, pressure: number, maxOff: number): number {
  return Math.max(1, s.base * (1 + s.wiggle) * (1 - Math.min(maxOff, Math.max(0, pressure))))
}

/** How street sits against base, and whether hustler dumping is behind it. */
export function streetMood(s: StreetInfo | undefined): { pct: number; flooded: boolean } | null {
  if (!s) return null
  return { pct: Math.round((s.price / s.base - 1) * 100), flooded: s.pressure >= 0.02 }
}

/** The most a listing or buy order may ask per unit. */
export const priceCap = (catalog: Catalog | null, street: number) => Math.floor(street * pct(catalog, 'listing_max_pct', 150))

/** What a seller keeps of a sale after the Marketplace fee. */
export const afterFee = (catalog: Catalog | null, gross: number) => gross - Math.floor(gross * pct(catalog, 'market_fee_pct', 5))

/** What refill number `used + 1` of the day restores, as a share of what's missing. */
/** What a drug refill of `code` does right now (mirrors refill() in 20261004000016_drug_refills.sql): each drug fills
 *  stamina `full` times a game day (3, or 5 on the Daily Drop), then restores `late_share` of max stamina, up to full. */
export function drugRefill(me: Me, catalog: Catalog | null, code: Commodity): { full: number; left: number; gain: number; late: number } {
  const r = me.refills
  const full = r?.full ?? catalog?.config?.refill_full ?? 3
  const left = Math.max(0, full - (r?.used?.[code] ?? 0))
  const missing = Math.max(0, me.stamina_max - me.stamina)
  const late = Math.min(missing, Math.ceil(me.stamina_max * (r?.late_share ?? 0.5)))
  return { full, left, gain: left > 0 ? missing : late, late }
}

export interface HustleQuote {
  trader: boolean; units: number; comped: number; cost: number
  /** Street per unit the batch sells at (halfway through its own push), and street once it's sold. */
  each: number; after: number
  /** Cash they bring back, and the Trader's cut already taken out of it. */
  due: number; cut: number
}

/** Preview of hire_hustlers: the fee or the Trader's cut, perks, and the batch's own push on street price. */
export function hustleQuote(me: Me, catalog: Catalog, com: Commodity, n: number): HustleQuote {
  const c = catalog.commodities.find(x => x.code === com)!
  const trader = me.path === 'trader'
  const units = Math.floor(c.hustler_units * n * (1 + perk(me, 'strip_club')))
  const comped = Math.min(n, me.free_hustlers ?? 0)
  const cost = trader ? 0 : (catalog.config.hustler_price ?? 400) * (n - comped)
  const cutShare = trader ? pct(catalog, 'trader_cut_pct', 10) * (n - comped) / n : 0
  const lift = 1 + perk(me, 'dispensary') + (trader ? pct(catalog, 'trader_markup_pct', 10) : 0)
  const s = me.street?.[com]
  const maxOff = pct(catalog, 'price_pressure_max_pct', 60)
  const depth = Math.max(1, s?.depth ?? c.market_depth ?? 50000)
  const each = s ? streetAt(s, s.pressure + units / depth / 2, maxOff) : me.prices[com]
  const after = s ? Math.round(streetAt(s, s.pressure + units / depth, maxOff)) : me.prices[com]
  const gross = units * each * lift
  return { trader, units, comped, cost, each, after, due: Math.floor(gross * (1 - cutShare)), cut: Math.round(gross * cutShare) }
}
