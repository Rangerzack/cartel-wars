import { useState } from 'react'
import { Link } from 'react-router-dom'
import { useGame, useMe } from '../lib/game'
import { api } from '../lib/api'
import { money, num } from '../lib/format'
import { Btn, Card } from './ui'
import type { Catalog, Me, Path } from '../lib/types'

function pathInfo(catalog: Catalog): Record<Path, { icon: string; name: string; does: string; gives_up: string }> {
  const lvl = catalog.config.path_grow_level ?? 5
  const cut = catalog.config.trader_cut_pct ?? 10, markup = catalog.config.trader_markup_pct ?? 10
  return {
    producer: { icon: '🏭', name: 'Producer', does: `Build, run and upgrade grow houses past level ${lvl}`, gives_up: "Can't send hustlers — sell on the Marketplace and into buy orders" },
    trader: { icon: '🚚', name: 'Trader', does: `Send hustlers with no hire fee (they keep ${cut}%) and sell ${markup}% over street`, gives_up: "Can't run grow houses — buy product on the Marketplace" },
  }
}

/** Can this player use grow houses / hustlers right now? null = yes, otherwise the reason. */
export function pathBlock(me: Me, want: Path): string | null {
  if (me.path_required) return 'Pick Producer or Trader above first.'
  if (me.path && me.path !== want) return want === 'producer' ? 'Traders don\'t run grow houses — switch paths above to produce.' : 'Producers don\'t send hustlers — switch paths above to trade.'
  return null
}

export function PathCard() {
  const me = useMe()
  const { catalog, run, ask } = useGame()
  const [open, setOpen] = useState(false)
  if (!catalog) return null
  const need = catalog.config.path_rep ?? 100
  const lvl = catalog.config.path_grow_level ?? 5
  const fee = catalog.config.path_switch_diamonds ?? 50
  const info = pathInfo(catalog)
  if (!me.path && !me.path_required && !open) {
    return (
      <div className="notice blue spread path-open">
        <span className="small">No path yet: you can run grow houses up to level {lvl} and send hustlers at {money(catalog.config.hustler_price ?? 400)} each. Pick Producer or Trader any time — you'll have to at {num(need)} reputation or to take a grow house past level {lvl}.</span>
        <Btn className="sm" onClick={() => setOpen(true)}>Choose a path ›</Btn>
      </div>
    )
  }
  if (me.path) {
    const other: Path = me.path === 'producer' ? 'trader' : 'producer'
    return (
      <div className="notice gold spread">
        <span>{info[me.path].icon} You're a <b>{info[me.path].name}</b> · {info[me.path].does.charAt(0).toLowerCase() + info[me.path].does.slice(1)}.</span>
        <Btn className="sm ghost" disabled={me.diamonds < fee} onClick={async () => { if (await ask(`Switch to ${info[other].name} for ${fee} diamonds? ${other === 'trader' ? 'Your grow houses stop producing (what they hold stays collectable).' : 'Your grow houses stay stopped until you start each one again.'}`, { title: 'Switch paths?', yes: `Switch · 💎 ${fee}`, tone: 'gold' })) return run(() => api.choosePath(other), { ok: () => `You're a ${info[other].name} now` }) }}>Switch · 💎 {fee}</Btn>
        {me.diamonds < fee && <div className="why">Switching costs 💎 {fee} — you have 💎 {num(me.diamonds)}.</div>}
      </div>
    )
  }
  return (
    <Card title="Choose your path" right={me.path_required ? <small>{num(me.rep_earned)} rep</small> : <button className="btn sm ghost" onClick={() => setOpen(false)}>Not yet</button>}>
      <div className="bd stack">
        <div className="small">
          {me.path_due === 'grow' ? <>Your grow houses are past level {lvl} — time to pick how you run product.</>
            : me.path_required ? <>You've made a name for yourself. Pick how you run product.</>
            : <>Pick how you run product.</>} The first pick is free; switching later costs 💎 {fee}.
        </div>
        <div className="grid2">
          {(['producer', 'trader'] as const).map(p => (
            <div key={p} className="stat stack" style={{ gap: 6 }}>
              <div style={{ fontSize: 26 }}>{info[p].icon}</div>
              <b>{info[p].name}</b>
              <div className="small">{info[p].does}</div>
              <div className="small muted">{info[p].gives_up}</div>
              <Btn className="doit" onClick={async () => { if (await ask(`Become a ${info[p].name}? Switching later costs 💎 ${fee}.${p === 'trader' && me.grow_houses.some(g => g.running) ? ' Your grow houses stop producing; what they hold stays collectable.' : ''}`, { title: `Be a ${info[p].name}?`, yes: `Be a ${info[p].name}` })) return run(() => api.choosePath(p), { ok: () => `You're a ${info[p].name}` }) }}>Be a {info[p].name}</Btn>
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
  if (!catalog || me.path) return null
  if (me.path_required) return <PathCard />
  const need = catalog.config.path_rep ?? 100
  if (me.rep_earned < need * 0.5) return null
  const pct = Math.min(100, (me.rep_earned / need) * 100)
  return (
    <Link to="/actions" className="card path-teaser link">
      <div className="bd stack" style={{ gap: 6 }}>
        <div className="spread"><b>🔓 Pick a path at {num(need)} reputation</b><span className="small tabular">{num(me.rep_earned)}/{num(need)}</span></div>
        <div className="bar"><div className="track"><div className="fill" style={{ width: pct + '%' }} /></div></div>
        <div className="small muted">Producer runs grow houses; Trader sends hustlers on better terms. You can pick early on the Economy page.</div>
      </div>
    </Link>
  )
}
