import type { Catalog, ComboDef, ComboStyle, InventoryItem, SetupItem, SetupKind, StyleCode } from './types'

export const comboDef = (catalog: Catalog | null, code: string | null | undefined): ComboDef | undefined =>
  code ? catalog?.combos?.find(c => c.code === code) : undefined
export const comboStyle = (catalog: Catalog | null, code: StyleCode | undefined): ComboStyle | undefined =>
  code ? catalog?.combo_styles?.find(s => s.code === code) : undefined
export const styleOf = (catalog: Catalog | null, combo: string | null | undefined) => comboStyle(catalog, comboDef(catalog, combo)?.style)

export type Matchup = 'counter' | 'countered' | 'even'
/** How my combo fares against theirs: counter (I roll 0–10, they roll nothing), countered, or even (0–5 each). */
export function matchup(catalog: Catalog | null, mine: string | null | undefined, theirs: string | null | undefined): Matchup | null {
  const a = styleOf(catalog, mine), b = styleOf(catalog, theirs)
  if (!a) return null
  if (!b) return 'even'
  if (a.beats.includes(b.code)) return 'counter'
  if (b.beats.includes(a.code)) return 'countered'
  return 'even'
}

export const tierName: Record<1 | 2 | 3, string> = { 1: 'Street', 2: 'Pro', 3: 'Elite' }

/** Combos an item is part of. */
export const itemCombos = (catalog: Catalog | null, itemId: number): ComboDef[] =>
  (catalog?.combos ?? []).filter(c => c.parts.some(p => p.includes(itemId)))

/** Whether a combo can run in a setup: jail weapons only count in jail, regular weapons never do. */
export function comboFits(catalog: Catalog | null, c: ComboDef, setup: SetupKind): boolean {
  const cat = (id: number) => catalog?.items.find(i => i.id === id)?.category
  return c.parts.every(part => part.some(id => {
    const k = cat(id)
    return setup === 'jail' ? k !== 'weapon' : k !== 'jail_weapon'
  }))
}

/** Parts of a combo a setup is still missing (each part: the item ids that would complete it). */
export const missingParts = (c: ComboDef, equipped: SetupItem[]): number[][] =>
  c.parts.filter(part => !part.some(id => equipped.some(e => e.item_id === id && e.qty > 0)))

/** Parts of a combo you don't own anything for. */
export const unownedParts = (c: ComboDef, inventory: InventoryItem[]): number[][] =>
  c.parts.filter(part => !part.some(id => inventory.some(i => i.item_id === id && i.qty > 0)))

/** "Uzi or MAC-10" for a part. */
export const partLabel = (catalog: Catalog | null, part: number[]) =>
  part.map(id => catalog?.items.find(i => i.id === id)?.name ?? '?').join(' or ')

/** What a combo roll is worth in this matchup, in words. */
export function matchupText(m: Matchup | null, myMax: number, theirMax: number): string {
  if (m === 'counter') return `you counter them: your combo rolls 0–${myMax}, theirs rolls nothing`
  if (m === 'countered') return `they counter you: yours rolls nothing, theirs rolls 0–${theirMax}`
  if (myMax && theirMax) return `neither counters: each combo rolls 0–${myMax}`
  if (myMax) return `only you run one: it rolls 0–${myMax}`
  if (theirMax) return `only they run one: it rolls 0–${theirMax}`
  return 'no combos in play'
}
