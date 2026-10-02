import { money, num } from './format'
import type { Me, MilestoneDef, MilestoneKind } from './types'

/** Where a player stands on each milestone count (20261004000017_milestones.sql _milestone_total). */
export function milestoneTotal(me: Me, kind: MilestoneKind): number {
  switch (kind) {
    case 'actions': return me.actions_done
    case 'wins': return me.fights_won
    case 'fights': return me.fights_won + me.fights_lost
    case 'turf': return me.turf_attacks ?? 0
    case 'wagered': return me.casino_wagered ?? 0
  }
}

/** The count's name, short: "actions", "fight wins", "turf attacks", "wagered". */
export const milestoneLabel: Record<MilestoneKind, string> = {
  actions: 'actions', wins: 'fight wins', fights: 'fights (won or lost)', turf: 'turf attacks', wagered: 'wagered at the casino',
}

/** "2,750 actions", "500 fight wins", "$10,000,000 wagered at the casino" — a milestone count in words. */
export function milestoneCount(what: MilestoneKind | undefined, n: number): string {
  if (!what) return num(n)
  return what === 'wagered' ? `${money(n)} wagered at the casino` : `${num(n)} ${milestoneLabel[what]}`
}

/** A repeating step: the next multiple of n past where you are, and how far along you are toward it. */
export function nextRepeat(m: MilestoneDef, total: number): { at: number; from: number } {
  const at = (Math.floor(total / m.n) + 1) * m.n
  return { at, from: at - m.n }
}
