import { useEffect, useRef, useState } from 'react'
import { api } from '../../lib/api'
import { useGame, useMe } from '../../lib/game'
import { money } from '../../lib/format'
import type { SlotsResult } from '../../lib/types'
import { Card } from '../ui'
import { BetPicker, Net } from './shared'

const SYM: Record<string, string> = { cherry: '🍒', lemon: '🍋', bell: '🔔', bar: '🅱️', diamond: '💎', seven: '7️⃣' }
const ALL = Object.keys(SYM)

export default function Slots() {
  const me = useMe()
  const { run } = useGame()
  const [wager, setWager] = useState(1000)
  const [reels, setReels] = useState<string[]>(['seven', 'seven', 'seven'])
  const [spinning, setSpinning] = useState(false)
  const [last, setLast] = useState<SlotsResult | null>(null)
  const timer = useRef<number | null>(null)
  useEffect(() => () => { if (timer.current) window.clearInterval(timer.current) }, [])

  async function spin() {
    if (spinning) return
    setSpinning(true); setLast(null)
    timer.current = window.setInterval(() => setReels([0, 1, 2].map(() => ALL[Math.floor(Math.random() * ALL.length)])), 70)
    const r = await run(() => api.slotsSpin(wager), { silent: true })
    await new Promise(res => setTimeout(res, r ? 600 : 0))
    if (timer.current) window.clearInterval(timer.current)
    if (r) { setReels(r.reels); setLast(r) }
    setSpinning(false)
  }

  return (
    <>
      <Card title="🎰 One-Armed Bandit" right={<small>3 reels · up to 100×</small>}>
        <div className="bd stack">
          <div className={`reels ${last && last.mult >= 4 ? 'win' : ''}`}>
            {reels.map((s, i) => <div key={i} className={`reel ${spinning ? 'spinning' : ''}`}>{SYM[s]}</div>)}
          </div>
          <div className="center" style={{ minHeight: 24 }}>
            {last ? (last.payout > 0 ? <span className="gold">{last.mult}× — you win {money(last.payout)} (<Net n={last.net} />)</span> : <span className="muted">No luck. <Net n={last.net} /></span>) : spinning ? <span className="muted">Spinning…</span> : <span className="muted">Pull the lever.</span>}
          </div>
          <BetPicker value={wager} onChange={setWager} max={Math.min(500000, me.cash)} />
          <button className="btn gold block" disabled={spinning || me.cash < wager} onClick={spin}>{spinning ? <span className="spin" /> : `Spin for ${money(wager)}`}</button>
        </div>
      </Card>
      <Card title="Paytable">
        <div className="bd paytable">
          {[['seven', 100], ['diamond', 40], ['bar', 20], ['bell', 12], ['lemon', 6], ['cherry', 4]].map(([s, m]) => (
            <div key={s as string}><span>{SYM[s as string]}{SYM[s as string]}{SYM[s as string]}</span><b>{m as number}×</b></div>
          ))}
          <div><span>🍒🍒 any</span><b>2×</b></div>
          <div><span>🍒 any</span><b>1×</b></div>
        </div>
      </Card>
    </>
  )
}
