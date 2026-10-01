import { useState } from 'react'
import { api } from '../lib/api'
import { useGame, useMe } from '../lib/game'
import { hoodlumIcon, money, num } from '../lib/format'
import { perk } from '../lib/perks'
import type { BusinessCode } from '../lib/types'
import { Btn, Qty } from './ui'
import { PerkTag } from './Perk'

/** Hiring hoodlums wherever they're needed: the Services card, the top of Territory, and a block's attack sheet when
 *  you're short of thugs. The price mirrors buy_hoodlums: base × count, climbing with how many you already hold
 *  (+1 % of base per 20 held, averaged over the batch), less the Gym (thugs) or Shooting Range (mercs, enforcers)
 *  perk. The server prices it again. `onHired` gets what was bought, so a sheet can put the new thugs to work. */
export function HireHoodlums({ initial, kinds, btnClass = 'doit', onHired }: {
  initial?: { code: string; n: number }
  /** Only these types (a block's attack only takes thugs and mercs); all of them when left out. */
  kinds?: string[]
  btnClass?: string
  onHired?: (code: string, n: number) => void
}) {
  const me = useMe()
  const { catalog, run } = useGame()
  const [hood, setHood] = useState(initial ?? { code: 'thug', n: 10 })
  if (!catalog) return null
  const list = kinds ? catalog.hoodlums.filter(h => kinds.includes(h.code)) : catalog.hoodlums
  const hdef = list.find(h => h.code === hood.code) ?? list[0]
  const owned = me.hoodlums[hdef.code] ?? 0
  const hoodPerk: BusinessCode | null = hdef.code === 'thug' ? 'gym' : hdef.code === 'mercenary' || hdef.code === 'enforcer' ? 'shooting_range' : null
  const cost = Math.ceil(Math.round(hdef.base_price * hood.n * (1 + (owned + hood.n / 2) / 2000)) * (1 - (hoodPerk ? perk(me, hoodPerk) : 0)))
  const short = me.cash < cost
  return (
    <div className="stack hire">
      {list.length > 1 && (
        <div className="seg">
          {list.map(h => <button key={h.code} className={hdef.code === h.code ? 'on' : ''} onClick={() => setHood({ ...hood, code: h.code })}>{hoodlumIcon[h.code]} {h.name}</button>)}
        </div>
      )}
      <div className="small muted">
        {hdef.att ? `${hdef.att} attack` : ''}{hdef.att && hdef.def ? ' · ' : ''}{hdef.def ? `${hdef.def} defense` : ''}{hdef.intel ? 'Reveals a block\'s garrison before you attack' : ''}
        {' '}· base {money(hdef.base_price)} — the price climbs with how many you hold. You have {num(owned)}.
      </div>
      {hoodPerk && perk(me, hoodPerk) > 0 && <PerkTag code={hoodPerk} />}
      <div className="spread">
        <Qty value={hood.n} onChange={n => setHood({ ...hood, n })} min={1} max={1000} />
        <Btn className={btnClass} disabled={short} onClick={async () => {
          const code = hdef.code, n = hood.n
          if (await run(() => api.buyHoodlums(code, n), { ok: r => `Hired ${num(n)} ${n === 1 ? hdef.name.toLowerCase() : plural(hdef.name.toLowerCase())} for ${money(r.cost)}` })) onHired?.(code, n)
        }}>Hire · {money(cost)}</Btn>
      </div>
      {short && <div className="why">That's {money(cost)} — you have {money(me.cash)} on hand.</div>}
    </div>
  )
}

const plural = (w: string) => (w.endsWith('y') ? `${w.slice(0, -1)}ies` : `${w}s`)
