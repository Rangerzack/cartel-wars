import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { api } from '../lib/api'
import { useGame, useMe } from '../lib/game'
import { chips, money } from '../lib/format'
import { useNow } from '../lib/useNow'
import type { PokerSeat, PokerState } from '../lib/types'
import { Btn, Empty, Modal } from '../components/ui'
import { BackBar } from '../components/BackBar'
import { BetPicker, Cards } from '../components/casino/shared'
import { Channel } from './Chat'

// seat slots around the felt, index 0 = bottom centre (always "me" when seated); the side seats sit at 16 / 84 % so
// their 84 px boxes stay inside the rail at 375 and 390 px
const POS = [[50, 90], [16, 68], [16, 28], [50, 9], [84, 28], [84, 68]]

export default function PokerTable() {
  const { id } = useParams()
  const tid = Number(id)
  const me = useMe()
  const { toast, refresh, run, ask } = useGame()
  const nav = useNavigate()
  const now = useNow()
  // the table state and when it arrived (the server clock it carries is measured forward from there)
  const [snap, setSnap] = useState<{ st: PokerState; at: number } | null>(null)
  const st = snap?.st ?? null
  const [raise, setRaise] = useState<number | null>(null)
  const [raising, setRaising] = useState(false)
  const [pick, setPick] = useState<number | null>(null)
  const [buyin, setBuyin] = useState(0)
  const [showChat, setShowChat] = useState(false)
  const [err, setErr] = useState<string | null>(null)
  const busy = useRef(false)
  const lastHand = useRef<number | null>(null)
  // every state that lands bumps this; a poll that started before an action answered is thrown away, so the action
  // buttons can't come back for a round trip on the pre-action state
  const ver = useRef(0)
  const [acting, setActing] = useState(false)
  const land = useCallback((s: PokerState) => {
    ver.current++
    setSnap({ st: s, at: Date.now() })
    // the clock checked or folded for you: the raise panel doesn't carry over to a later street
    if (!s.hand?.my?.my_turn) { setRaising(false); setRaise(null) }
  }, [])

  const load = useCallback(async () => {
    if (busy.current) return
    busy.current = true
    const v = ver.current
    try { const s = await api.pokerState(tid); if (v === ver.current) land(s); setErr(null) } catch (e) { setErr((e as Error).message) } finally { busy.current = false }
  }, [tid, land])
  useEffect(() => {
    load()
    const t = setInterval(() => { if (document.visibilityState === 'visible') load() }, 1500)
    return () => clearInterval(t)
  }, [load])
  // hand changed → reset raise slider, refresh cash after a hand
  useEffect(() => {
    const h = st?.hand?.id ?? null
    if (h !== lastHand.current) { lastHand.current = h; setRaise(null); setRaising(false); if (h) refresh() }
  }, [st?.hand?.id, refresh])

  const hand = st?.hand ?? null
  const mine = st?.me ?? null
  const my = hand?.my ?? null
  const myTurn = !!(my?.my_turn && mine && !mine.sitting_out)
  const stack = mine?.stack ?? 0
  const allInTo = (my?.street_bet ?? 0) + stack
  const minTo = Math.min(hand?.my?.min_raise_to ?? 0, allInTo)
  const potNow = hand?.pot ?? 0
  const rel = useCallback((seat: number) => mine ? (seat - mine.seat + 6) % 6 : seat, [mine])
  const seatAt = useMemo(() => { const m = new Map<number, PokerSeat>(); st?.seats.forEach(s => m.set(s.seat, s)); return m }, [st])
  // the deadline is server time: measure from the server clock the state came with, so a wrong phone clock can't
  // make the countdown run early or late
  const serverNow = snap ? Date.parse(snap.st.server_time) + (now - snap.at) : now
  const secondsLeft = hand?.deadline ? Math.max(0, Math.ceil((new Date(hand.deadline).getTime() - serverNow) / 1000)) : null
  const showdown = !!(hand?.finished && hand.result && !hand.result.fold_out)

  async function act(action: 'fold' | 'check' | 'call' | 'bet' | 'raise', amount?: number) {
    if (acting) return   // a double tap: the second one must not act on the next street
    setActing(true)
    try { land(await api.pokerAct(action, amount)); setRaising(false); setRaise(null) } catch (e) { toast((e as Error).message, 'bad'); load() } finally { setActing(false) }
  }
  async function leave() {
    // mid-hand, leaving folds you and the chips already in the pot stay there
    if (my && !my.folded && hand && !hand.finished
      && !await ask(`Leaving now folds this hand — the ${money(my.total_bet)} you've put in the pot stays there.`, { title: 'Leave the table?', yes: 'Leave', tone: 'red' })) return
    const r = await run(() => api.pokerLeave(), { ok: r => `Cashed out ${money(r.cashed_out)}` })
    if (r) nav('/casino/poker')
  }
  async function sitIn() { const r = await run(() => api.pokerSitIn(), { silent: true }); if (r) land(r) }
  async function join(seat: number) {
    const r = await run(() => api.pokerJoin(tid, seat, buyin), { ok: () => `Bought in for ${money(buyin)}` })
    if (r) { land(r); setPick(null) }
  }

  if (err && !st) return <div className="page"><div className="notice red">{err}</div><button className="btn" onClick={() => nav('/casino/poker')}>Back to the lobby</button></div>
  if (!st) return <Empty><span className="spin" /></Empty>
  const t = st.table

  return (
    <div className="page poker">
      {/* Back keeps your seat (the clock checks or folds for you while you're away); Leave cashes you out */}
      <BackBar fallback="/casino/poker" right={
        <div className="hstack">
          <button type="button" className="btn sm ghost" aria-label={showChat ? 'Hide table talk' : 'Table talk'} aria-pressed={showChat} onClick={() => setShowChat(v => !v)}>💬</button>
          {mine && <Btn className="sm ghost red" onClick={leave}>Leave</Btn>}
        </div>
      } />
      <div>
        <b>{t.name}</b>
        <div className="small muted">Blinds {money(t.small_blind)}/{money(t.big_blind)} · {hand ? `hand #${hand.no}` : 'waiting for players'}</div>
      </div>
      {err && <div className="notice red">Can't reach the table — retrying. The clock keeps running on the server.</div>}

      <div className="felt">
        <div className="board">
          {hand ? (
            <>
              <div className="pot">Pot {money(potNow)}{hand.finished && hand.result && hand.result.rake > 0 && <span className="muted"> · rake {money(hand.result.rake)}</span>}</div>
              <Cards list={[...hand.board, ...Array(Math.max(0, 5 - hand.board.length)).fill(undefined)]} size="md" />
              {hand.finished && hand.result && (
                <div className="small gold">
                  {Object.entries(hand.result.won).map(([s, w]) => `${seatAt.get(Number(s))?.name ?? 'seat ' + s} wins ${money(w)}${hand.result?.hands?.[s] ? ` (${hand.result.hands[s]})` : ''}`).join(' · ')}
                </div>
              )}
              {!hand.finished && hand.to_act !== null && secondsLeft !== null && (
                <div className="small muted">{seatAt.get(hand.to_act)?.is_me ? 'Your move' : `${seatAt.get(hand.to_act)?.name ?? 'seat'} to act`} · {secondsLeft}s</div>
              )}
            </>
          ) : null}
          {(!hand || hand.finished) && (
            <div className="small muted center">{st.seats.filter(s => !s.sitting_out && s.stack > 0).length < 2 ? 'Need two players to deal.' : 'Shuffling…'}</div>
          )}
        </div>
        {Array.from({ length: t.seats }, (_, seat) => {
          const s = seatAt.get(seat)
          const [x, y] = POS[rel(seat)]
          const style = { left: x + '%', top: y + '%' }
          if (!s) {
            return (
              <button key={seat} className="seat empty" style={style} disabled={!!mine} onClick={() => { setBuyin(Math.min(me.cash, Math.max(t.min_buyin, Math.min(t.max_buyin, t.min_buyin * 2)))); setPick(seat) }}>
                {mine ? 'empty' : 'Sit here'}
              </button>
            )
          }
          const acting = hand && !hand.finished && hand.to_act === seat
          const reveal = s.hole && (s.is_me || showdown)
          return (
            <div key={seat} className={`seat ${acting ? 'acting' : ''} ${s.folded ? 'folded' : ''} ${s.sitting_out ? 'out' : ''} ${s.is_me ? 'me' : ''} ${hand?.finished && s.won ? 'winner' : ''}`} style={style}>
              {hand && hand.dealer === seat && <span className="dealer">D</span>}
              <div className="cards">
                {s.in_hand && !s.folded && <Cards list={reveal ? (s.hole as string[]) : [null, null]} size="sm" dim={!!(hand?.finished && !s.won && showdown)} />}
              </div>
              <div className="who"><span>{s.avatar}</span> {s.name}</div>
              <div className="stk tabular">{s.all_in ? 'ALL IN' : s.sitting_out ? 'sitting out' : chips(s.stack)}</div>
              {(s.street_bet ?? 0) > 0 && <div className="bet">{chips(s.street_bet)}</div>}
              {hand?.finished && s.won ? <div className="won">+{chips(s.won)}</div> : s.hand_name && showdown ? <div className="hn">{s.hand_name}</div> : null}
              {acting && secondsLeft !== null && <div className="clock" style={{ width: Math.min(100, (secondsLeft / 30) * 100) + '%' }} />}
            </div>
          )
        })}
      </div>

      {mine && mine.sitting_out && (
        <div className="notice gold">You're sitting out. {stack > 0 ? <button type="button" className="linkbtn" onClick={sitIn}>Deal me in →</button> : 'Rebuy to keep playing.'}</div>
      )}
      {mine && (
        <div className="actions">
          {myTurn && my ? (
            raising ? (
              <div className="stack">
                <div className="hstack" style={{ justifyContent: 'space-between' }}>
                  <span className="small muted">{hand!.current_bet > 0 ? 'Raise to' : 'Bet'}</span>
                  <b className="tabular">{money(raise ?? minTo)}{(raise ?? minTo) >= allInTo ? ' · all in' : ''}</b>
                </div>
                <input type="range" min={minTo} max={allInTo} step={Math.max(1, Math.round(t.big_blind / 2))} value={raise ?? minTo} onChange={e => setRaise(Number(e.target.value))} />
                <div className="hstack">
                  <button className="btn sm" onClick={() => setRaise(minTo)}>Min</button>
                  <button className="btn sm" onClick={() => setRaise(Math.min(allInTo, Math.max(minTo, Math.round(potNow / 2 + (my.to_call || 0)))))}>½ pot</button>
                  <button className="btn sm" onClick={() => setRaise(Math.min(allInTo, Math.max(minTo, potNow + (my.to_call || 0) * 2)))}>Pot</button>
                  <button className="btn sm" onClick={() => setRaise(allInTo)}>All in</button>
                </div>
                <div className="hstack">
                  <button type="button" className="btn ghost" onClick={() => setRaising(false)}>Back</button>
                  <button type="button" className="btn gold grow" disabled={acting} onClick={() => act(hand!.current_bet > 0 ? 'raise' : 'bet', raise ?? minTo)}>{hand!.current_bet > 0 ? 'Raise to' : 'Bet'} {money(raise ?? minTo)}</button>
                </div>
              </div>
            ) : (
              <div className="hstack">
                <button type="button" className="btn ghost red grow" disabled={acting} onClick={() => act('fold')}>Fold</button>
                {my.to_call > 0
                  ? <button type="button" className="btn doit grow" disabled={acting} onClick={() => act('call')}>Call {money(my.to_call)}{my.to_call >= stack ? ' (all in)' : ''}</button>
                  : <button type="button" className="btn doit grow" disabled={acting} onClick={() => act('check')}>Check</button>}
                <button type="button" className="btn gold grow" disabled={acting || stack <= my.to_call} onClick={() => { setRaise(minTo); setRaising(true) }}>{hand!.current_bet > 0 ? 'Raise' : 'Bet'}</button>
              </div>
            )
          ) : (
            <div className="hstack" style={{ justifyContent: 'space-between' }}>
              <span className="small muted">{my ? (my.folded ? 'You folded.' : hand?.finished ? 'Next hand in a moment…' : 'Waiting for others…') : hand && !hand.finished ? "You'll be dealt in next hand." : 'Waiting…'}</span>
              <button type="button" className="btn sm" disabled={t.max_buyin - stack < 100 || me.cash < 100} onClick={() => { setBuyin(Math.min(me.cash, t.max_buyin - stack)); setPick(mine.seat) }}>Rebuy</button>
            </div>
          )}
        </div>
      )}

      {showChat && <Channel channel={`table:${tid}`} compact />}

      {pick !== null && (
        <Modal title={mine ? 'Rebuy' : `Seat ${pick + 1} · buy in`} onClose={() => setPick(null)}>
          <div className="stack">
            <div className="small muted">{mine ? `Top up to at most ${money(t.max_buyin)}. You have ${money(me.cash)} on hand.` : `Bring ${money(t.min_buyin)} to ${money(t.max_buyin)}. You have ${money(me.cash)} on hand.`}</div>
            <BetPicker value={buyin} onChange={setBuyin} min={mine ? 100 : t.min_buyin} max={Math.max(100, Math.min(me.cash, mine ? t.max_buyin - stack : t.max_buyin))} label={mine ? 'Add' : 'Buy-in'} />
            <Btn className="gold block" disabled={buyin > me.cash || (!mine && buyin < t.min_buyin) || (!!mine && buyin > t.max_buyin - stack)} onClick={() => join(pick)}>{mine ? `Add ${money(buyin)}` : `Sit down with ${money(buyin)}`}</Btn>
            {!mine && me.cash < t.min_buyin && <div className="why">The table takes at least {money(t.min_buyin)} — you have {money(me.cash)} on hand.</div>}
            {mine && buyin > t.max_buyin - stack && <div className="why">Your stack can't go past {money(t.max_buyin)} here — room for {money(t.max_buyin - stack)}.</div>}
          </div>
        </Modal>
      )}
    </div>
  )
}
