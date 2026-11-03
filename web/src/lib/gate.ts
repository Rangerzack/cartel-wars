import type { Me } from './types'

/**
 * The campaign's gate (Season 1): tabs open as Marcus's missions are claimed. The server says which are open
 * (`me.unlocked`); the client only maps a route to its code. With no season running everything is open. Social and
 * spending screens never lock. This is a tutorial fence, not a security boundary: the RPCs keep their own rules.
 */
export type GateCode = 'items' | 'actions' | 'services' | 'casino' | 'economy' | 'fight' | 'crew' | 'territory'

/** The gate code a path falls under, or null for a screen that never locks. */
export function gateOf(pathname: string): GateCode | null {
  const top = pathname.split('/')[1] ?? ''
  switch (top) {
    case 'items': return 'items'
    case 'actions': return 'actions'
    case 'services': return 'services'
    case 'casino': return 'casino'
    case 'economy': return 'economy'
    case 'fight': case 'player': return 'fight'
    case 'crew': case 'cartel': return 'crew'
    case 'territory': return 'territory'
    default: return null
  }
}

export const isLocked = (me: Me | null, code: GateCode | null) =>
  !!(me?.season && code && me.unlocked && !me.unlocked.includes(code))

export const lockedPath = (me: Me | null, pathname: string) => isLocked(me, gateOf(pathname))

/** What a locked tab says when tapped: Marcus, in one line. */
export const LOCK_LINE = "Not yet, boss. Finish what's on Home first."

/** The label on the Marcus card's button, from where the mission sends you. */
export function goLabel(link: string): string {
  const top = link.split('?')[0].split('/')[1] ?? ''
  switch (top) {
    case 'hood': return 'Open Your Hood'
    case 'items': return 'Open the Shop'
    case 'actions': return 'Go to Actions'
    case 'services': return 'Go to Services'
    case 'economy': return 'Go to Economy'
    case 'fight': return 'Go to Fight'
    case 'crew': return 'Go to Crew'
    case 'territory': return 'Go to Territory'
    default: return 'Go'
  }
}
