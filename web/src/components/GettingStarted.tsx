import { useState } from 'react'
import type { Me } from '../lib/types'
import { Card, RowLink } from './ui'

const KEY = 'cw.gettingStarted.dismissed'

/**
 * A new player's checklist, at the top of Home (Phase 3): the next step is the one line that shows, gold-edged, with how
 * far along you are; the rest open under it. It was six rows below the stats and the tiles, which put the first thing
 * to do under the fold of a phone. Gone once every step is done, or for good with Hide.
 */
export function GettingStarted({ me }: { me: Me }) {
  const [dismissed, setDismissed] = useState(() => { try { return localStorage.getItem(KEY) === '1' } catch { return false } })
  const [all, setAll] = useState(false)
  const steps = [
    { done: me.actions_done >= 1, t: 'Run an Action', s: 'Stamina in, cash out. Watch your Heat.', to: '/actions' },
    { done: me.power.offense.att > 20, t: 'Arm your Offensive setup', s: 'Buy a weapon and equip it under Setups.', to: '/items?tab=shop&cat=weapon' },
    { done: me.grow_houses.length >= 1, t: 'Build a Grow House', s: 'Production runs while you sleep.', to: '/economy' },
    { done: me.imports > 0 || me.hustlers.length > 0 || me.market_volume > 0, t: 'Move product', s: 'Send hustlers out or list a batch on the Marketplace.', to: '/economy?tab=hustlers' },
    { done: me.bank > 0, t: 'Bank your cash', s: 'Cash on hand can be taken in fights.', to: '/services?focus=bank' },
    { done: !!me.crew, t: 'Join or found a Crew', s: 'Crews hold blocks and split the income.', to: '/crew' },
  ]
  const done = steps.filter(s => s.done).length
  const next = steps.find(s => !s.done)
  if (dismissed || !next) return null
  const hide = () => { try { localStorage.setItem(KEY, '1') } catch { /* private mode */ } setDismissed(true) }
  return (
    <Card title="Getting started" className="getting-started"
      right={<span className="hstack"><small className="tabular">{done} of {steps.length} done</small><button className="btn sm ghost" onClick={hide}>Hide</button></span>}>
      {(all ? steps : [next]).map(s => s.done ? (
        <div key={s.t} className="row done">
          <span className="check" aria-hidden>✅</span>
          <div className="grow"><div className="t"><span className="sr-only">Done: </span>{s.t}</div><div className="s">{s.s}</div></div>
        </div>
      ) : (
        <RowLink key={s.t} to={s.to} className={s === next ? 'next' : ''}>
          <span className="check" aria-hidden>☐</span>
          <div className="grow"><div className="t">{s === next && <span className="sr-only">Next: </span>}{s.t}</div><div className="s">{s.s}</div></div>
          <span className="chev">›</span>
        </RowLink>
      ))}
      <button type="button" className="row link more small muted" aria-expanded={all} onClick={() => setAll(!all)}>
        <span className="grow">{all ? 'Just the next step' : `See all ${steps.length} steps`}</span><span className="chev" style={all ? { transform: 'rotate(-90deg)' } : { transform: 'rotate(90deg)' }}>›</span>
      </button>
    </Card>
  )
}
