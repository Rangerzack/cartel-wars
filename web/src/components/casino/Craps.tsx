import { useEffect, useState } from 'react'
import { api } from '../../lib/api'
import { useGame, useMe } from '../../lib/game'
import { money } from '../../lib/format'
import type { CrapsBetKind, CrapsRoll, CrapsState } from '../../lib/types'
import { Card, Empty } from '../ui'
import { BetPicker, Net } from './shared'

const DIE = ['', '⚀', '⚁', '⚂', '⚃', '⚄', '⚅']
const SPOTS: { k: CrapsBetKind; l: string; pays: string; line?: boolean }[] = [
  { k: 'pass', l: 'Pass Line', pays: '1:1', line: true },
  { k: 'dont', l: "Don't Pass", pays: '1:1 · 12 pushes', line: true },
  { k: 'field', l: 'Field', pays: '2 pays 2:1 · 12 pays 3:1' },
  { k: 'place6', l: 'Place 6', pays: '7:6' },
  { k: 'place8', l: 'Place 8', pays: '7:6' },
  { k: 'any7', l: 'Any 7', pays: '4:1' },
  { k: 'anycraps', l: 'Any Craps', pays: '7:1' },
]

export default function Craps() {
  const me = useMe()
  const { run, toast } = useGame()
  const [chip, setChip] = useState(1000)
  const [st, setSt] = useState<CrapsState | null>(null)
  const [roll, setRoll] = useState<CrapsRoll | null>(null)
  const [rolling, setRolling] = useState(false)
  const [dice, setDice] = useState<[number, number]>([1, 1])
  useEffect(() => { api.crapsState().then(s => { setSt(s); if (s.last) setDice(s.last.dice) }).catch(e => toast(e.message, 'bad')) }, [toast])

  const onFelt = st ? Object.values(st.bets).reduce((a, b) => a + (b ?? 0), 0) : 0
  async function bet(k: CrapsBetKind) {
    const s = await run(() => api.crapsBet(k, chip), { silent: true })
    if (s) setSt(s)
  }
  async function doRoll() {
    setRolling(true); setRoll(null)
    const t = window.setInterval(() => setDice([1 + Math.floor(Math.random() * 6), 1 + Math.floor(Math.random() * 6)]), 80)
    const r = await run(() => api.crapsRoll(), { silent: true })
    await new Promise(res => setTimeout(res, r ? 500 : 0))
    window.clearInterval(t)
    if (r) { setDice(r.dice); setRoll(r); setSt({ point: r.point, bets: r.bets, last: r }) }
    else if (st?.last) setDice(st.last.dice)
    setRolling(false)
  }
  async function clear() { const s = await run(() => api.crapsClear(), { silent: true }); if (s) setSt(s) }

  return (
    <>
      <Card title="🎲 Craps" right={<small>{st?.point ? `Point is ${st.point}` : 'Come-out roll'}</small>}>
        <div className="bd stack">
          <div className="dice">
            <span className={rolling ? 'rolling' : ''}>{DIE[dice[0]]}</span><span className={rolling ? 'rolling' : ''}>{DIE[dice[1]]}</span>
            <div className={`puck ${st?.point ? 'on' : ''}`}>{st?.point ? `ON ${st.point}` : 'OFF'}</div>
          </div>
          <div className="center" style={{ minHeight: 22 }}>
            {roll && <span>{roll.sum} — {roll.wager > 0 ? <>settled {money(roll.wager)}: <Net n={roll.net} /></> : <span className="muted">bets stay up</span>}</span>}
          </div>
          {!st ? <Empty><span className="spin" /></Empty> : (
            <div className="spots">
              {SPOTS.map(s => {
                const a = st.bets[s.k] ?? 0
                const frozen = s.line && st.point !== null
                return (
                  <button key={s.k} className={`spot ${a ? 'on' : ''}`} disabled={frozen || rolling} onClick={() => bet(s.k)}>
                    <span className="l">{s.l}</span>
                    <span className="p">{frozen ? 'point is on' : s.pays}</span>
                    {a > 0 && <b>{money(a)}</b>}
                  </button>
                )
              })}
            </div>
          )}
          <BetPicker value={chip} onChange={setChip} max={Math.min(500000, me.cash)} label="Chip (tap a spot to place it)" />
          <div className="hstack">
            <button className="btn gold grow" disabled={rolling || onFelt === 0} onClick={doRoll}>{rolling ? <span className="spin" /> : onFelt ? `Roll · ${money(onFelt)} in play` : 'Place a bet'}</button>
            <button className="btn ghost" disabled={rolling || onFelt === 0} onClick={clear}>Take down</button>
          </div>
          {roll && roll.log.length > 0 && (
            <div className="small muted">
              {roll.log.map((l, i) => <div key={i}>{SPOTS.find(s => s.k === l.bet)?.l} {money(l.amount)}: {l.result === 'stays' ? 'stays' : l.result === 'push' ? 'push' : l.result === 'win' ? `wins ${money((l.win ?? 0) - l.amount)}` : 'lost'}</div>)}
            </div>
          )}
          <div className="small muted">Pass wins on 7 or 11 come-out, loses on 2, 3 or 12; anything else sets the point. Line bets lock once the point is on — everything else can be taken down between rolls.</div>
        </div>
      </Card>
    </>
  )
}
