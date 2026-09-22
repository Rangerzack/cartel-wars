import { useState } from 'react'
import { useGame, useMe } from '../lib/game'
import { api } from '../lib/api'
import { money } from '../lib/format'
import { Btn, Card, Empty, Modal } from '../components/ui'
import type { ActionDef } from '../lib/types'

export default function Actions() {
  const me = useMe()
  const { catalog, run } = useGame()
  const [result, setResult] = useState<{ a: ActionDef; pay: number; busted: boolean; heat: number; stamina: number } | null>(null)
  if (!catalog) return <Empty><span className="spin" /></Empty>

  const list = catalog.actions.filter(a => a.is_jail === me.jailed)
  const owned = new Set(me.inventory.map(i => i.item_id))
  const itemName = (id: number | null) => catalog.items.find(i => i.id === id)?.name ?? ''
  const crewSize = me.crew?.members ?? 0

  async function go(a: ActionDef) {
    const r = await run(() => api.doAction(a.id), { silent: true })
    if (r) setResult({ a, pay: r.pay, busted: r.busted, heat: r.heat, stamina: r.stamina })
  }

  return (
    <div className="page">
      <h2>{me.jailed ? 'Jail Actions' : 'Actions'}</h2>
      {me.jailed && <div className="notice red">Inside, the hustle is different. These are the only actions you can run until you're out.</div>}
      {me.hospital && <div className="notice red">You can't work from a hospital bed. Check out at Services first.</div>}
      <Card>
        {list.map(a => {
          const needItem = a.requires_item && !owned.has(a.requires_item)
          const needCrew = a.min_crew > crewSize
          const cant = me.hospital || me.stamina < a.stamina_cost || me.cash < a.cash_cost || needItem || needCrew
          return (
            <div key={a.id} className="row">
              <div className="grow">
                <div className="t">{a.name}</div>
                <div className="s">{a.description}</div>
                <div className="s tabular">
                  <span style={{ color: '#7dd3fc' }}>⚡ {a.stamina_cost}</span>
                  {' · '}
                  {a.effect === 'go_to_jail' ? <span>🔒 2 hours in jail</span> : <span className="gold">{money(a.pay_min)}–{money(a.pay_max)}</span>}
                  {a.heat_gain > 0 && <> · <span className="red">🔥 +{a.heat_gain}</span></>}
                  {a.cash_cost > 0 && <> · costs {money(a.cash_cost)}</>}
                  {a.requires_item && <> · <span className={needItem ? 'red' : 'green'}>needs {itemName(a.requires_item)}</span></>}
                  {a.min_crew > 0 && <> · <span className={needCrew ? 'red' : 'green'}>crew of {a.min_crew}</span></>}
                </div>
              </div>
              <Btn className="doit" disabled={!!cant} onClick={() => go(a)}>Do It</Btn>
            </div>
          )
        })}
      </Card>
      {result && (
        <Modal title={result.busted && result.a.effect !== 'go_to_jail' ? 'BUSTED!' : result.a.name} onClose={() => setResult(null)}>
          {result.a.effect === 'go_to_jail' ? (
            <p>The cops took the money and the hint. You're in jail for two hours — check your jail setup.</p>
          ) : (
            <>
              <p className="gold" style={{ fontSize: 26, fontWeight: 800, margin: '4px 0' }}>+{money(result.pay)}</p>
              <div className="small muted">⚡ −{result.a.stamina_cost} stamina ({result.stamina} left) · 🔥 +{result.a.heat_gain} heat (now {result.heat})</div>
              {result.busted && <p className="red">Your heat was in the red and a patrol caught you. You're in jail — regular weapons are confiscated, jail setup is active.</p>}
            </>
          )}
        </Modal>
      )}
    </div>
  )
}
