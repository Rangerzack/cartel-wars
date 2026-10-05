import { useCallback, useEffect, useRef, useState } from 'react'
import { api } from '../../lib/api'
import { useGame, useMe } from '../../lib/game'
import { money } from '../../lib/format'
import type { BlackjackHand, BlackjackOutcome, BlackjackState } from '../../lib/types'
import { Card, Loading } from '../ui'
import { BetPicker, ChipStack, Net, PlayingCard, useBet } from './shared'
import { basicStrategy, type BjMove } from './strategy'
import { useLoad } from '../../lib/useLoad'
import { haptic } from '../../lib/haptics'

const TAG: Record<BlackjackOutcome, { t: string; cls: string }> = {
  blackjack: { t: 'Blackjack', cls: 'gold' }, win: { t: 'Win', cls: 'green' }, dealer_bust: { t: 'Win', cls: 'green' },
  push: { t: 'Push', cls: 'muted' }, lose: { t: 'Lose', cls: 'red' }, bust: { t: 'Bust', cls: 'red' },
}
const DEAL_GAP = 0.14      // seconds between cards on the opening deal
const DEALER_GAP = 0.45    // seconds between the dealer's draws

/** The one hand before splits existed, or every hand after. */
function handsOf(g: BlackjackState): BlackjackHand[] {
  if (g.hands?.length) return g.hands
  return [{ cards: g.player, total: g.player_total, soft: g.player_soft, bet: g.wager, doubled: false, split: false,
            done: g.status === 'done', active: g.status === 'playing', result: g.result && g.result.outcome !== 'split' ? { outcome: g.result.outcome, payout: g.result.payout, net: g.result.net } : null }]
}

function readHint(): boolean { try { return localStorage.getItem('cw.bj.hint') === '1' } catch { return false } }

export default function Blackjack() {
  const me = useMe()
  const { run } = useGame()
  const [wager, setWager] = useBet('blackjack', me.cash)
  const { data: g, error, reload, set: setG } = useLoad(() => api.blackjackState())
  const [round, setRound] = useState(0)
  const [fresh, setFresh] = useState(false)          // opening-deal animation in progress
  const [hint, setHintRaw] = useState(readHint)
  const [session, setSession] = useState({ hands: 0, net: 0 })
  const [busy, setBusy] = useState(false)
  const counted = useRef(-1)
  const setHint = (v: boolean) => { setHintRaw(v); try { localStorage.setItem('cw.bj.hint', v ? '1' : '0') } catch { /* private mode */ } }

  const tally = useCallback((r: BlackjackState, rnd: number) => {
    if (r.status === 'done' && r.result && counted.current !== rnd) {
      counted.current = rnd
      setSession(s => ({ hands: s.hands + 1, net: s.net + r.result!.net }))
      if (r.result.net > 0) haptic('success')
    }
  }, [])

  const playing = g?.status === 'playing'
  const hands = g && g.status !== 'none' ? handsOf(g) : []
  const cur = hands.find(h => h.active) ?? hands[0]
  const extra = cur?.bet ?? 0
  const canDouble = !!g?.can_double && me.cash >= extra
  const canSplit = !!g?.can_split && me.cash >= extra
  const book: BjMove | null = playing && hint && cur && g?.dealer?.[0] ? basicStrategy(cur.cards, g.dealer[0], canDouble, canSplit) : null

  const deal = useCallback(async () => {
    if (busy) return
    setBusy(true)
    const r = await run(() => api.blackjackDeal(wager), { silent: true })
    if (r) {
      const rnd = round + 1
      setRound(rnd); setFresh(true); setG(r); tally(r, rnd)
      window.setTimeout(() => setFresh(false), 900)
    }
    setBusy(false)
  }, [busy, run, wager, round, tally, setG])

  const act = useCallback(async (a: BjMove) => {
    if (busy) return
    setBusy(true)
    const r = await run(() => api.blackjackAction(a), { silent: true })
    if (r) { setG(r); tally(r, round) }
    setBusy(false)
  }, [busy, run, round, tally, setG])

  // keyboard: H hit · S stand · D double · P split · Enter/Space deal
  useEffect(() => {
    const onKey = (e: KeyboardEvent) => {
      // the shortcuts never take a key from something that wants it: a field, a focused button or link (Space and
      // Enter press that, not Deal), an open sheet, or a key held with a modifier
      const t = e.target as HTMLElement | null
      if (e.metaKey || e.ctrlKey || e.altKey || document.querySelector('.modal')) return
      if (t && (t.isContentEditable || t.closest('input, textarea, select, button, a, [role="button"]'))) return
      const k = e.key.toLowerCase()
      if (playing) {
        if (k === 'h') act('hit')
        else if (k === 's') act('stand')
        else if (k === 'd' && canDouble) act('double')
        else if (k === 'p' && canSplit) act('split')
      } else if ((k === 'enter' || k === ' ') && me.cash >= wager && g) { e.preventDefault(); deal() }
    }
    window.addEventListener('keydown', onKey)
    return () => window.removeEventListener('keydown', onKey)
  }, [playing, canDouble, canSplit, act, deal, me.cash, wager, g])

  const done = g?.status === 'done'
  const dealerCards = g?.dealer_hidden ? [g.dealer[0], null] : g?.dealer ?? []
  const settleDelay = done ? Math.max(0, (dealerCards.length - 2)) * DEALER_GAP + 0.35 : 0

  return (
    <Card title="🃏 Blackjack" className="table-card" right={<small>6 decks · S17 · 3:2 · DAS</small>}>
      <div className="bd stack">
        {!g ? <Loading error={error} onRetry={reload} /> : (
          <div className={`bj-felt ${done && g.result ? (g.result.net > 0 ? 'won' : g.result.net < 0 ? 'lost' : 'push') : ''}`}>
            <div className="bj-arc">Blackjack pays 3 to 2</div>

            <div className="bj-dealer">
              {g.status === 'none' ? <div className="bj-shoe">Dealer</div> : (
                <>
                  <div className="bj-cards">
                    {dealerCards.map((c, i) => {
                      const flip = i === 1 && !g.dealer_hidden
                      const delay = fresh ? (i === 0 ? 1 : 3) * DEAL_GAP : i >= 2 ? (i - 1) * DEALER_GAP : flip ? 0 : 0
                      return <PlayingCard key={`${round}-d${i}-${c ?? 'x'}`} c={c} size="xl" className={flip && !fresh ? 'flipin' : 'dealin'} style={{ animationDelay: `${delay}s` }} />
                    })}
                  </div>
                  <span className="bj-total dealer">{g.dealer_hidden ? g.dealer_total : g.dealer_total > 21 ? `Bust ${g.dealer_total}` : g.dealer_total}</span>
                </>
              )}
            </div>

            <div className="bj-rules">Dealer stands on all 17s · Double any two · Split to 4 hands</div>

            <div className={`bj-hands n${Math.max(1, hands.length)}`}>
              {g.status === 'none' && (
                <div className="bj-hand">
                  <div className="bj-spot">{wager > 0 && <ChipStack amount={wager} />}</div>
                  <div className="small muted center">Pick a bet and deal</div>
                </div>
              )}
              {hands.map((h, hi) => (
                <div key={`${round}-h${hi}-${h.cards[0]}`} className={`bj-hand ${h.active ? 'active' : ''} ${h.result ? 'settled ' + TAG[h.result.outcome].cls : ''}`}>
                  <div className="bj-cards fan">
                    {h.cards.map((c, ci) => (
                      <PlayingCard key={`${round}-${hi}-${ci}-${c}`} c={c} size="xl" className="dealin"
                        style={{ animationDelay: `${fresh && hands.length === 1 && ci < 2 ? (ci === 0 ? 0 : 2) * DEAL_GAP : 0}s` }} />
                    ))}
                  </div>
                  <span className={`bj-total ${h.total > 21 ? 'bust' : h.total === 21 ? 'twentyone' : ''}`}>
                    {h.total > 21 ? `Bust ${h.total}` : h.soft && h.total < 21 && !h.done ? `${h.total - 10} / ${h.total}` : h.total}
                  </span>
                  <div className="bj-bet"><ChipStack amount={h.bet} />{h.doubled && <span className="pill gold">Doubled</span>}</div>
                  {h.result && (
                    <div className={`bj-tag ${TAG[h.result.outcome].cls}`} style={{ animationDelay: `${settleDelay}s` }}>
                      {TAG[h.result.outcome].t}{h.result.net !== 0 && <> · <Net n={h.result.net} /></>}
                    </div>
                  )}
                </div>
              ))}
            </div>
          </div>
        )}

        {/* the result, read out once the hand settles (the drawn line below waits for the dealer's cards) */}
        <div className="sr-only" role="status">{done && g?.result ? `${summary(g)} ${g.result.net > 0 ? 'up' : g.result.net < 0 ? 'down' : 'even'} ${money(Math.abs(g.result.net))}` : ''}</div>
        {done && g?.result && (
          <div className={`bj-summary ${g.result.net > 0 ? 'won' : g.result.net < 0 ? 'lost' : ''}`} style={{ animationDelay: `${settleDelay}s` }}>
            {summary(g)} <Net n={g.result.net} />
          </div>
        )}

        {playing ? (
          <>
            {book && <div className="bj-hintline">📖 The book says: <b>{book === 'split' ? 'Split' : book[0].toUpperCase() + book.slice(1)}</b></div>}
            {/* the hand's buttons, and the chips and Deal between hands, ride above the tab bar under the felt */}
            <div className="table-bar">
              <div className="bj-actions">
                <button type="button" className={`btn ${book === 'hit' ? 'hinted' : ''}`} disabled={busy} onClick={() => act('hit')}>Hit<small>H</small></button>
                <button type="button" className={`btn doit ${book === 'stand' ? 'hinted' : ''}`} disabled={busy} onClick={() => act('stand')}>Stand<small>S</small></button>
                <button type="button" className={`btn gold ${book === 'double' ? 'hinted' : ''}`} disabled={busy || !canDouble} onClick={() => act('double')}>Double<small>+{money(extra)}</small></button>
                <button type="button" className={`btn gold ${book === 'split' ? 'hinted' : ''}`} disabled={busy || !canSplit} onClick={() => act('split')}>Split<small>+{money(extra)}</small></button>
              </div>
              {g?.can_double && !canDouble && <div className="why">Doubling needs {money(extra)} on hand.</div>}
              {g?.can_split && !canSplit && <div className="why">Splitting needs {money(extra)} on hand.</div>}
            </div>
          </>
        ) : (
          <>
            <div className="table-bar">
              <BetPicker part="chips" value={wager} onChange={setWager} max={Math.min(500000, me.cash)} />
              <button type="button" className="btn gold block bj-deal" disabled={busy || me.cash < wager || !g} onClick={deal}>
                {me.cash < wager ? `Need ${money(wager)} on Hand` : done ? `Deal Again · ${money(wager)}` : `Deal · ${money(wager)}`}
              </button>
            </div>
            <BetPicker part="amount" value={wager} onChange={setWager} max={Math.min(500000, me.cash)} />
          </>
        )}

        <div className="spread small muted">
          <span>{session.hands ? <>This session: {session.hands} hand{session.hands > 1 ? 's' : ''} · <Net n={session.net} /></> : 'Keys: H hit · S stand · D double · P split · Enter deal'}</span>
          <label className="toggle"><input type="checkbox" checked={hint} onChange={e => setHint(e.target.checked)} /> Strategy hint</label>
        </div>
      </div>
    </Card>
  )
}

function summary(g: BlackjackState): string {
  const r = g.result!
  if (r.outcome === 'split') return `${r.hands?.length ?? 2} hands settled —`
  switch (r.outcome) {
    case 'blackjack': return 'Blackjack — paid 3 to 2 —'
    case 'dealer_bust': return `Dealer busts with ${g.dealer_total} —`
    case 'win': return `${g.player_total} beats ${g.dealer_total} —`
    case 'push': return `Push at ${g.player_total} —`
    case 'bust': return `Bust with ${g.player_total} —`
    case 'lose': return g.dealer.length === 2 && g.dealer_total === 21 ? 'Dealer has blackjack —' : `Dealer's ${g.dealer_total} beats ${g.player_total} —`
  }
}
