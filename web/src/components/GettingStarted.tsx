import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import type { Me } from '../lib/types'
import { Card } from './ui'

const KEY = 'cw.gettingStarted.dismissed'

export function GettingStarted({ me }: { me: Me }) {
  const nav = useNavigate()
  const [dismissed, setDismissed] = useState(() => { try { return localStorage.getItem(KEY) === '1' } catch { return false } })
  const steps = [
    { done: me.actions_done >= 1, t: 'Run an Action', s: 'Stamina in, cash out. Watch your Heat.', to: '/actions' },
    { done: me.power.offense.att > 20, t: 'Arm your Offensive setup', s: 'Buy a weapon and equip it under Setups.', to: '/items' },
    { done: me.grow_houses.length >= 1, t: 'Build a Grow House', s: 'Production runs while you sleep.', to: '/economy' },
    { done: me.imports > 0 || me.hustlers.length > 0 || me.market_volume > 0, t: 'Move product', s: 'Send hustlers out or list a batch on the Marketplace.', to: '/economy?tab=hustlers' },
    { done: me.bank > 0, t: 'Bank your cash', s: 'Cash on hand can be taken in fights.', to: '/services' },
    { done: !!me.crew, t: 'Join or found a Crew', s: 'Crews hold blocks and split the income.', to: '/crew' },
  ]
  const left = steps.filter(s => !s.done).length
  if (dismissed || left === 0) return null
  return (
    <Card title="Getting started" right={<button className="btn sm ghost" onClick={() => { try { localStorage.setItem(KEY, '1') } catch { /* private mode */ } setDismissed(true) }}>Hide</button>}>
      {steps.map(s => (
        <div key={s.t} className={`row ${s.done ? '' : 'link'}`} onClick={() => !s.done && nav(s.to)} style={s.done ? { opacity: .5 } : undefined}>
          <span style={{ width: 22, textAlign: 'center' }}>{s.done ? '✅' : '☐'}</span>
          <div className="grow"><div className="t">{s.t}</div><div className="s">{s.s}</div></div>
          {!s.done && <span className="chev">›</span>}
        </div>
      ))}
    </Card>
  )
}
