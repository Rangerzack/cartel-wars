import { useState } from 'react'
import { api } from '../../lib/api'
import { useGame, useMe } from '../../lib/game'
import { chips, money } from '../../lib/format'
import type { RouletteBet, RouletteBetType, RouletteResult } from '../../lib/types'
import { Card } from '../ui'
import { BetPicker, Net, useBet } from './shared'

const RED = new Set([1, 3, 5, 7, 9, 12, 14, 16, 18, 19, 21, 23, 25, 27, 30, 32, 34, 36])
const key = (b: { type: RouletteBetType; value?: number }) => b.value === undefined ? b.type : `${b.type}:${b.value}`
const label = (b: { type: RouletteBetType; value?: number }) => {
  switch (b.type) {
    case 'straight': return `#${b.value}`
    case 'dozen': return ['1st 12', '2nd 12', '3rd 12'][(b.value ?? 1) - 1]
    case 'column': return `Col ${b.value}`
    case 'low': return '1–18'
    case 'high': return '19–36'
    default: return b.type[0].toUpperCase() + b.type.slice(1)
  }
}

/** The casino's per-spin limit (rouletteSpin rejects more: 'Table max is $500000 per spin'). */
const TABLE_MAX = 500_000

export default function Roulette() {
  const me = useMe()
  const { run } = useGame()
  const [chip, setChip] = useBet('roulette')
  const [bets, setBets] = useState<Record<string, RouletteBet>>({})
  const [last, setLast] = useState<RouletteResult | null>(null)
  const [spinning, setSpinning] = useState(false)
  const list = Object.values(bets)
  const total = list.reduce((a, b) => a + b.amount, 0)
  // what stops the spin: over the table max, or more on the felt than on hand (the server checks both too)
  const whyNot = total > TABLE_MAX ? `Table max is ${money(TABLE_MAX)} a spin` : total > me.cash ? `That's ${money(total)} on the felt — you have ${money(me.cash)} on hand` : null

  function add(type: RouletteBetType, value?: number) {
    if (spinning) return   // a chip dropped mid-spin would look like part of this spin
    const k = key({ type, value })
    setBets(b => ({ ...b, [k]: { type, value, amount: (b[k]?.amount ?? 0) + chip } }))
  }
  function remove(k: string) { setBets(b => { const n = { ...b }; delete n[k]; return n }) }

  async function spin() {
    if (!list.length) return
    setSpinning(true); setLast(null)
    const r = await run(() => api.rouletteSpin(list), { silent: true })
    await new Promise(res => setTimeout(res, r ? 900 : 0))
    if (r) setLast(r)
    setSpinning(false)
  }
  const hit = last?.number
  const amt = (type: RouletteBetType, value?: number) => bets[key({ type, value })]?.amount

  return (
    <>
      <Card title="🎡 Roulette" className="table-card" right={<small>European · single zero</small>}>
        <div className="bd stack">
          <div className={`wheel-result ${spinning ? 'spinning' : ''} ${last ? last.color : ''}`}>
            {spinning ? <span className="spin" /> : last ? <>{last.number}</> : '—'}
          </div>
          <div className="center" style={{ minHeight: 22 }}>
            {last && (last.payout > 0 ? <span className="gold">{last.color} {last.number} — paid {money(last.payout)} (<Net n={last.net} />)</span> : <span className="muted">{last.color} {last.number} — house takes it (<Net n={last.net} />)</span>)}
          </div>
          <fieldset className="lockable roulette" disabled={spinning}>
            <button className={`n green ${hit === 0 ? 'hit' : ''}`} onClick={() => add('straight', 0)}>0{amt('straight', 0) && <i>{chips(amt('straight', 0))}</i>}</button>
            <div className="grid">
              {Array.from({ length: 12 }, (_, row) => [3, 2, 1].map(c => row * 3 + c)).flat().map(n => (
                <button key={n} className={`n ${RED.has(n) ? 'red' : 'black'} ${hit === n ? 'hit' : ''}`} onClick={() => add('straight', n)}>{n}{amt('straight', n) && <i>{chips(amt('straight', n))}</i>}</button>
              ))}
            </div>
            <div className="cols">
              {[3, 2, 1].map(c => <button key={c} className="o" onClick={() => add('column', c)}>2:1{amt('column', c) && <i>{chips(amt('column', c))}</i>}</button>)}
            </div>
          </fieldset>
          <div className="outside">
            {[1, 2, 3].map(d => <button key={d} className="o" onClick={() => add('dozen', d)}>{['1st 12', '2nd 12', '3rd 12'][d - 1]}{amt('dozen', d) && <i>{chips(amt('dozen', d))}</i>}</button>)}
          </div>
          <div className="outside six">
            <button className="o" onClick={() => add('low')}>1–18{amt('low') && <i>{chips(amt('low'))}</i>}</button>
            <button className="o" onClick={() => add('even')}>Even{amt('even') && <i>{chips(amt('even'))}</i>}</button>
            <button className="o redsq" onClick={() => add('red')}>Red{amt('red') && <i>{chips(amt('red'))}</i>}</button>
            <button className="o blacksq" onClick={() => add('black')}>Black{amt('black') && <i>{chips(amt('black'))}</i>}</button>
            <button className="o" onClick={() => add('odd')}>Odd{amt('odd') && <i>{chips(amt('odd'))}</i>}</button>
            <button className="o" onClick={() => add('high')}>19–36{amt('high') && <i>{chips(amt('high'))}</i>}</button>
          </div>
          {/* chips and Spin ride above the tab bar while the board scrolls under them */}
          <div className="table-bar">
            <BetPicker part="chips" value={chip} onChange={setChip} max={Math.min(500000, me.cash)} label="Chip (tap a spot to place it)" />
            <div className="hstack" style={{ flexWrap: 'nowrap' }}>
              <button type="button" className="btn gold flex1" disabled={spinning || !list.length || !!whyNot} onClick={spin}>{spinning ? <span className="spin" /> : list.length ? `Spin · ${money(total)} on the felt` : 'Place a bet'}</button>
              <button type="button" className="btn ghost" disabled={spinning || !list.length} onClick={() => setBets({})}>Clear</button>
            </div>
            {whyNot && <div className="why">{whyNot}</div>}
          </div>
          <BetPicker part="amount" value={chip} onChange={setChip} max={Math.min(500000, me.cash)} />
          {list.length > 0 && (
            <div className="betlist">
              {list.map(b => <button type="button" key={key(b)} className="pill" aria-label={`Take back ${label(b)} ${money(b.amount)}`} onClick={() => remove(key(b))}>{label(b)} {money(b.amount)} ✕</button>)}
            </div>
          )}
          <div className="small muted">Straight 35:1 · dozens & columns 2:1 · even-money bets 1:1. Table max {money(500000)} per spin.</div>
        </div>
      </Card>
    </>
  )
}
