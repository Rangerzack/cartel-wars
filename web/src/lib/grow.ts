import { api } from './api'
import { andList, num } from './format'
import type { Catalog, Me } from './types'
import { errorText } from './errors'

type House = Me['grow_houses'][number]

/** What a house holds right now: the server's count when `me` arrived, carried forward at the house's rate (the server
 *  computes the same thing from started_at when you collect), so the number and Collect don't sit still between polls. */
export const producedNow = (g: House, now: number, meAt: number) =>
  (g.running ? Math.min(g.cap, g.produced + Math.floor(Math.max(0, now - meAt) / 3_600_000 * g.rate)) : g.produced)

/** Collect each house in turn, for one toast for the lot; a full storage ends the round. The first failure is thrown
 *  (run() toasts it); a later one ends the round with what was already collected. */
export async function collectHouses(houses: House[], catalog: Catalog) {
  const nameOf = (c: string) => catalog.commodities.find(x => x.code === c)?.name ?? c
  const got: string[] = []
  let stop = ''
  for (const g of houses) {
    try {
      const r = await api.growCollect(g.id)
      if (r.collected > 0) got.push(`${num(r.collected)} ${nameOf(g.commodity)}`)
      if (r.left > 0) { stop = 'storage is full'; break }
    } catch (e) {
      if (!got.length) throw e
      stop = errorText(e).toLowerCase()
      break
    }
  }
  return { got, stop }
}

export const collectedLine = (r: { got: string[]; stop: string }) =>
  r.got.length ? `Collected ${andList(r.got)}${r.stop ? ` — ${r.stop}` : ''}` : `Nothing to collect${r.stop ? ` — ${r.stop}` : ' yet'}`
