import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { api } from '../../lib/api'
import { useGame, useMe } from '../../lib/game'
import { chips, money } from '../../lib/format'
import type { PokerTableInfo } from '../../lib/types'
import { Card, Empty, Modal } from '../ui'
import { BetPicker } from './shared'

export default function PokerLobby() {
  const me = useMe()
  const { toast, run } = useGame()
  const nav = useNavigate()
  const [tables, setTables] = useState<PokerTableInfo[] | null>(null)
  const [join, setJoin] = useState<PokerTableInfo | null>(null)
  const [buyin, setBuyin] = useState(0)
  useEffect(() => {
    const load = () => api.pokerLobby().then(setTables).catch(e => toast(e.message, 'bad'))
    load()
    const t = setInterval(() => { if (document.visibilityState === 'visible') load() }, 5000)
    return () => clearInterval(t)
  }, [toast])
  const mine = tables?.find(t => t.mine)

  async function sit(t: PokerTableInfo) {
    // take the lowest free seat; the table page shows where you landed
    const st = await run(() => api.pokerState(t.id), { silent: true })
    if (!st) return
    const taken = new Set(st.seats.map(s => s.seat))
    const seat = Array.from({ length: t.seats }, (_, i) => i).find(i => !taken.has(i))
    if (seat === undefined) { toast('Table is full', 'bad'); return }
    const r = await run(() => api.pokerJoin(t.id, seat, buyin), { ok: () => `Bought in for ${money(buyin)}` })
    if (r) { setJoin(null); nav(`/casino/table/${t.id}`) }
  }

  return (
    <>
      {mine && <div className="notice gold">You're seated at {mine.name}. <a onClick={() => nav(`/casino/table/${mine.id}`)} style={{ cursor: 'pointer' }}>Back to the table →</a></div>}
      <Card title="♠ No-Limit Hold'em" right={<small>6-max · live players · 30s clock</small>}>
        {!tables && <Empty><span className="spin" /></Empty>}
        {tables?.map(t => (
          <div key={t.id} className="row">
            <div className="grow">
              <div className="t">{t.name}</div>
              <div className="s">Blinds {chips(t.small_blind)}/{chips(t.big_blind)} · buy-in {chips(t.min_buyin)}–{chips(t.max_buyin)}{t.players.length ? ` · ${t.players.join(', ')}` : ''}</div>
            </div>
            <span className={`small tabular ${t.seated ? '' : 'muted'}`}>{t.seated}/{t.seats}</span>
            {t.mine ? <button className="btn sm gold" onClick={() => nav(`/casino/table/${t.id}`)}>Sit</button>
              : <button className="btn sm" disabled={!!mine || t.seated >= t.seats} onClick={() => { setBuyin(Math.min(me.cash, Math.max(t.min_buyin, Math.min(t.max_buyin, t.min_buyin * 2)))); setJoin(t) }}>{t.seated ? 'Join' : 'Open'}</button>}
          </div>
        ))}
      </Card>
      <div className="small muted">Rake 5% of the pot, capped at 3 big blinds, no flop no drop. Fold or check happens for you when the clock runs out; three misses in a row sits you out. Buy-ins come from cash on hand — the bank doesn't take chips.</div>
      {join && (
        <Modal title={`Buy in · ${join.name}`} onClose={() => setJoin(null)}>
          <div className="stack">
            <div className="small muted">Blinds {money(join.small_blind)}/{money(join.big_blind)}. Bring {money(join.min_buyin)} to {money(join.max_buyin)}. You have {money(me.cash)} on hand.</div>
            <BetPicker value={buyin} onChange={setBuyin} min={join.min_buyin} max={Math.min(join.max_buyin, me.cash)} label="Buy-in" />
            <button className="btn gold block" disabled={buyin < join.min_buyin || buyin > join.max_buyin || buyin > me.cash} onClick={() => sit(join)}>
              {me.cash < join.min_buyin ? `Need ${money(join.min_buyin)} cash on hand` : `Sit down with ${money(buyin)}`}
            </button>
          </div>
        </Modal>
      )}
    </>
  )
}
