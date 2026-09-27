import { useNavigate } from 'react-router-dom'
import { useGame, useMe } from '../lib/game'
import { api } from '../lib/api'
import { num } from '../lib/format'
import { Btn, Card } from './ui'
import type { Me, Path } from '../lib/types'

const pathInfo: Record<Path, { icon: string; name: string; does: string; gives_up: string }> = {
  producer: { icon: '🏭', name: 'Producer', does: 'Build, run and upgrade grow houses', gives_up: "Can't send hustlers — sell on the Marketplace" },
  trader: { icon: '🚚', name: 'Trader', does: 'Send hustlers to move product for cash', gives_up: "Can't run grow houses — buy product on the Marketplace" },
}

/** Can this player use grow houses / hustlers right now? null = yes, otherwise the reason. */
export function pathBlock(me: Me, want: Path): string | null {
  if (me.path_required) return 'Pick Producer or Trader above first.'
  if (me.path && me.path !== want) return want === 'producer' ? 'Traders don\'t run grow houses — switch paths above to produce.' : 'Producers don\'t send hustlers — switch paths above to trade.'
  return null
}

export function PathCard() {
  const me = useMe()
  const { catalog, run } = useGame()
  if (!catalog) return null
  const need = catalog.config.path_rep ?? 100
  const fee = catalog.config.path_switch_diamonds ?? 50
  if (!me.path && !me.path_required) {
    return <div className="small muted">At {need} reputation you'll pick a path: Producer (grow houses) or Trader (hustlers). You've earned {num(me.rep_earned)}.</div>
  }
  if (me.path) {
    const other: Path = me.path === 'producer' ? 'trader' : 'producer'
    return (
      <div className="notice gold spread">
        <span>{pathInfo[me.path].icon} You're a <b>{pathInfo[me.path].name}</b> · {pathInfo[me.path].does.toLowerCase()}.</span>
        <Btn className="sm ghost" disabled={me.diamonds < fee} onClick={() => { if (confirm(`Switch to ${pathInfo[other].name} for ${fee} diamonds?`)) return run(() => api.choosePath(other), { ok: () => `You're a ${pathInfo[other].name} now` }) }}>Switch · 💎 {fee}</Btn>
      </div>
    )
  }
  return (
    <Card title="Choose your path" right={<small>{num(me.rep_earned)} rep</small>}>
      <div className="bd stack">
        <div className="small">You've made a name for yourself. Pick how you run product — you can switch later for 💎 {fee}.</div>
        <div className="grid2">
          {(['producer', 'trader'] as const).map(p => (
            <div key={p} className="stat stack" style={{ gap: 6 }}>
              <div style={{ fontSize: 26 }}>{pathInfo[p].icon}</div>
              <b>{pathInfo[p].name}</b>
              <div className="small">{pathInfo[p].does}</div>
              <div className="small muted">{pathInfo[p].gives_up}</div>
              <Btn className="doit" onClick={() => { if (confirm(`Become a ${pathInfo[p].name}?`)) return run(() => api.choosePath(p), { ok: () => `You're a ${pathInfo[p].name}` }) }}>Be a {pathInfo[p].name}</Btn>
            </div>
          ))}
        </div>
      </div>
    </Card>
  )
}


/** Home: the path choice when it's due, and a teaser once a player is most of the way there. */
export function HomePath() {
  const me = useMe()
  const { catalog } = useGame()
  const nav = useNavigate()
  if (!catalog || me.path) return null
  if (me.path_required) return <PathCard />
  const need = catalog.config.path_rep ?? 100
  if (me.rep_earned < need * 0.5) return null
  const pct = Math.min(100, (me.rep_earned / need) * 100)
  return (
    <div className="card path-teaser link" onClick={() => nav('/actions')}>
      <div className="bd stack" style={{ gap: 6 }}>
        <div className="spread"><b>🔓 Pick a path at {num(need)} reputation</b><span className="small tabular">{num(me.rep_earned)}/{num(need)}</span></div>
        <div className="bar"><div className="track"><div className="fill" style={{ width: pct + '%' }} /></div></div>
        <div className="small muted">Producer runs grow houses; Trader sends hustlers. Reputation jobs on the Actions page get you there.</div>
      </div>
    </div>
  )
}
