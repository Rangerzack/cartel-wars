import { useEffect, useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useGame, useMe } from '../lib/game'
import { api } from '../lib/api'
import { money, num } from '../lib/format'
import { Btn, Card, Empty, Modal } from '../components/ui'
import type { ActionDef } from '../lib/types'

type Result = { a: ActionDef; pay: number; rep: number; busted: boolean; heat: number; stamina: number }
type Flash = Result & { key: number }

export default function Actions() {
  const me = useMe()
  const { catalog, run } = useGame()
  const nav = useNavigate()
  // Only jail / busts get the pop-up — they change what you can do next. Everything else shows in place.
  const [bust, setBust] = useState<Result | null>(null)
  const [flash, setFlash] = useState<Record<number, Flash>>({})
  const [session, setSession] = useState({ jobs: 0, cash: 0, rep: 0 })
  const [onlyAvailable, setOnlyAvailable] = useState(false)
  const flashKey = useRef(0)
  const timers = useRef<Record<number, ReturnType<typeof setTimeout>>>({})
  useEffect(() => () => Object.values(timers.current).forEach(clearTimeout), [])
  if (!catalog) return <Empty><span className="spin" /></Empty>

  const list = catalog.actions.filter(a => a.is_jail === me.jailed)
  const owned = new Set(me.inventory.map(i => i.item_id))
  const itemName = (id: number | null) => catalog.items.find(i => i.id === id)?.name ?? ''
  const crewSize = me.crew?.members ?? 0
  const blockedBy = (a: ActionDef) => {
    if (a.requires_item && !owned.has(a.requires_item)) return 'item'
    if (a.min_crew > crewSize) return 'crew'
    if (me.cash < a.cash_cost) return 'cash'
    return null
  }
  const shown = onlyAvailable ? list.filter(a => !blockedBy(a)) : list

  async function go(a: ActionDef) {
    const r = await run(() => api.doAction(a.id), { silent: true })
    if (!r) return
    const res: Result = { a, pay: r.pay, rep: r.rep, busted: r.busted, heat: r.heat, stamina: r.stamina }
    setSession(s => ({ jobs: s.jobs + 1, cash: s.cash + (r.pay || 0), rep: s.rep + (r.rep || 0) }))
    if (r.busted || a.effect === 'go_to_jail') { setBust(res); return }
    const key = ++flashKey.current
    setFlash(f => ({ ...f, [a.id]: { ...res, key } }))
    clearTimeout(timers.current[a.id])
    timers.current[a.id] = setTimeout(() => setFlash(f => { const n = { ...f }; if (n[a.id]?.key === key) delete n[a.id]; return n }), 2600)
  }

  const perStamina = (a: ActionDef) => a.stamina_cost > 0 ? Math.round((a.pay_min + a.pay_max) / 2 / a.stamina_cost) : 0

  return (
    <div className="page">
      <h2>{me.jailed ? 'Jail Actions' : 'Actions'}</h2>
      {me.jailed && <div className="notice red">Inside, the hustle is different. These are the only actions you can run until you're out. <a onClick={() => nav('/services')}>Post bail →</a></div>}
      {me.hospital && <div className="notice red">You can't work from a hospital bed. <a onClick={() => nav('/services')}>Buy health →</a></div>}
      {!me.hospital && me.stamina === 0 && <div className="notice blue">Out of stamina. It comes back 2 every 10 minutes, or <a onClick={() => nav('/services?focus=refills')}>refill it →</a></div>}

      <div className="spread">
        {session.jobs > 0
          ? <div className="session-tally tabular">This session: <b>{num(session.jobs)}</b> {session.jobs === 1 ? 'job' : 'jobs'} · <b className="gold">+{money(session.cash)}</b>{session.rep > 0 && <> · <b className="dia">⭐ +{num(session.rep)}</b></>}</div>
          : <div className="small muted">Tap Do It — results show right on the job.</div>}
        <label className="toggle small"><input type="checkbox" checked={onlyAvailable} onChange={e => setOnlyAvailable(e.target.checked)} /> Can do now</label>
      </div>

      <Card>
        {shown.length === 0 && <Empty>Nothing you can run right now — buy the gear or find a bigger crew.</Empty>}
        {shown.map(a => {
          const block = blockedBy(a)
          const cant = me.hospital || me.stamina < a.stamina_cost || !!block
          const f = flash[a.id]
          return (
            <div key={a.id} className={`row action ${f ? 'flashing' : ''}`}>
              <div className="grow">
                <div className="t">{a.name}</div>
                <div className="s">{a.description}</div>
                <div className="s tabular">
                  <span style={{ color: '#7dd3fc' }}>⚡ {a.stamina_cost}</span>
                  {' · '}
                  {a.effect === 'go_to_jail' ? <span>🔒 2 hours in jail</span> : a.pay_rep > 0 ? <span className="dia">⭐ +{a.pay_rep} reputation</span> : <span className="gold">{money(a.pay_min)}–{money(a.pay_max)}</span>}
                  {a.heat_gain > 0 && <> · <span className="red">🔥 +{a.heat_gain}</span></>}
                  {a.cash_cost > 0 && <> · costs {money(a.cash_cost)}</>}
                  {a.requires_item && <> · <span className={block === 'item' ? 'red' : 'green'}>needs {itemName(a.requires_item)}</span></>}
                  {a.min_crew > 0 && <> · <span className={block === 'crew' ? 'red' : 'green'}>crew of {a.min_crew}</span></>}
                  {perStamina(a) > 0 && a.pay_rep === 0 && <span className="muted"> · ~{money(perStamina(a))}/⚡</span>}
                </div>
                {f && (
                  <div key={f.key} className="action-result tabular">
                    {f.rep > 0 ? <b className="dia">⭐ +{f.rep} rep</b> : <b className="gold">+{money(f.pay)}</b>}
                    <span className="muted"> · ⚡ {num(f.stamina)} left · 🔥 {num(f.heat)}</span>
                  </div>
                )}
              </div>
              <div className="doit-wrap">
                <Btn className="doit" disabled={!!cant} onClick={() => go(a)}>Do It</Btn>
                {f && <span key={f.key} className="floater">{f.rep > 0 ? `⭐+${f.rep}` : `+${money(f.pay)}`}</span>}
              </div>
            </div>
          )
        })}
      </Card>
      {bust && (
        <Modal title={bust.a.effect === 'go_to_jail' ? bust.a.name : 'Busted!'} onClose={() => setBust(null)}>
          {bust.a.effect === 'go_to_jail' ? (
            <p>The cops took the money and the hint. You're in jail for two hours — check your jail setup.</p>
          ) : (
            <>
              {bust.pay > 0 && <p className="gold" style={{ fontSize: 22, fontWeight: 800, margin: '4px 0' }}>+{money(bust.pay)}</p>}
              <p className="red">Your heat was in the red and a patrol caught you. You're in jail — regular weapons are confiscated, jail setup is active.</p>
            </>
          )}
          <Btn className="gold block" onClick={() => { setBust(null); nav('/services') }}>Post bail</Btn>
        </Modal>
      )}
    </div>
  )
}
