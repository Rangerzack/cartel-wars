import { useEffect, useState } from 'react'
import { api } from './api'

/** Every player, crew and cartel name in the game, so chat and forum text can link them. */
export type NameKind = 'player' | 'crew' | 'cartel'
export interface NamedThing { kind: NameKind; id: string; name: string }
export interface NameDirectory { byName: Map<string, NamedThing>; pattern: RegExp | null; loadedAt: number }

// Real words that happen to be names are only linked when written as an @mention, so "cash" or "boss"
// in a sentence doesn't turn into a link to a player called Cash or Boss.
const COMMON = new Set(('the and for you are but not all any can had her was one our out day get has him his how man new now old see two way who ' +
  'boy did its let put say she too use cash bank boss king kings crew gang game play team pills dust herb block hood war money deal plug ' +
  'yes nah lol gg bro man guys shot gun guns cop cops jail').split(' '))

const escape = (s: string) => s.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')

function build(things: NamedThing[]): NameDirectory {
  const byName = new Map<string, NamedThing>()
  // the same name used twice: a cartel wins over a crew, a crew over a player (their pages are the more useful target)
  const rank: Record<NameKind, number> = { cartel: 0, crew: 1, player: 2 }
  for (const t of things) {
    const k = t.name.trim().toLowerCase()
    if (k.length < 3) continue
    const had = byName.get(k)
    if (!had || rank[t.kind] < rank[had.kind]) byName.set(k, t)
  }
  const names = [...byName.values()].map(t => t.name.trim()).sort((a, b) => b.length - a.length)
  const pattern = names.length
    ? new RegExp(`(@?)(?<![\\p{L}\\p{N}_])(${names.map(escape).join('|')})(?![\\p{L}\\p{N}_])`, 'giu')
    : null
  return { byName, pattern, loadedAt: Date.now() }
}

let cache: NameDirectory | null = null
let inflight: Promise<NameDirectory> | null = null
const listeners = new Set<(d: NameDirectory) => void>()
const MAX_AGE = 60_000

export function loadNames(force = false): Promise<NameDirectory> {
  if (!force && cache && Date.now() - cache.loadedAt < MAX_AGE) return Promise.resolve(cache)
  if (inflight) return inflight
  // an empty find_players search leaves the NPC thugs out (Fight › Players), so they come from a search of their own:
  // "Thug 50" in chat stays a link
  inflight = Promise.all([api.me(), api.findPlayers('', 5000), api.findPlayers('Thug', 300), api.listCrews(''), api.listCartels()])
    .then(([me, players, thugs, crews, cartels]) => {
      cache = build([
        { kind: 'player', id: me.id, name: me.name },
        ...[...players, ...thugs].map(p => ({ kind: 'player' as const, id: p.id, name: p.name })),
        ...crews.map(c => ({ kind: 'crew' as const, id: c.id, name: c.name })),
        ...cartels.map(c => ({ kind: 'cartel' as const, id: c.id, name: c.name })),
      ])
      listeners.forEach(l => l(cache!))
      return cache
    })
    .finally(() => { inflight = null })
  return inflight
}

/** The name directory, refreshed at most once a minute. Null until the first load finishes. */
export function useNames(): NameDirectory | null {
  const [dir, setDir] = useState<NameDirectory | null>(cache)
  useEffect(() => {
    listeners.add(setDir)
    loadNames().then(setDir).catch(() => {})
    return () => { listeners.delete(setDir) }
  }, [])
  return dir
}

export type Segment = string | { thing: NamedThing; text: string }

/** Split text into plain strings and name matches. */
export function splitNames(text: string, dir: NameDirectory | null): Segment[] {
  if (!dir?.pattern || !text) return [text]
  const out: Segment[] = []
  let last = 0
  for (const m of text.matchAll(dir.pattern)) {
    const at = m[1] ?? '', word = m[2]
    const thing = dir.byName.get(word.toLowerCase())
    if (!thing) continue
    if (!at && COMMON.has(word.toLowerCase())) continue
    const start = m.index! + at.length
    if (start > last) out.push(text.slice(last, start))
    out.push({ thing, text: word })
    last = start + word.length
  }
  if (last < text.length) out.push(text.slice(last))
  return out
}
