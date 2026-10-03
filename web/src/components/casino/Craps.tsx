import { useEffect, useRef, useState, type ReactNode } from 'react'
import { api } from '../../lib/api'
import { useGame, useMe } from '../../lib/game'
import { money } from '../../lib/format'
import type { CrapsBetKind, CrapsEvent, CrapsLogLine, CrapsRoll } from '../../lib/types'
import { Card, Loading } from '../ui'
import { BetPicker, ChipStack, Die, Net, useBet } from './shared'
import { useLoad } from '../../lib/useLoad'

const NUMBERS = [4, 5, 6, 8, 9, 10] as const
const NUM_LABEL: Record<number, string> = { 4: '4', 5: '5', 6: 'SIX', 8: '8', 9: 'NINE', 10: '10' }
const PLACE_PAYS: Record<number, string> = { 4: '9:5', 5: '7:5', 6: '7:6', 8: '7:6', 9: '7:5', 10: '9:5' }
const ODDS_PAYS: Record<number, string> = { 4: '2:1', 5: '3:2', 6: '6:5', 8: '6:5', 9: '3:2', 10: '2:1' }
const LAY_PAYS: Record<number, string> = { 4: '1:2', 5: '2:3', 6: '5:6', 8: '5:6', 9: '2:3', 10: '1:2' }
const NAME: Record<string, string> = {
  pass: 'Pass Line', dont: "Don't Pass", pass_odds: 'Pass odds', dont_odds: 'Lay odds', field: 'Field', come: 'Come', dcome: "Don't Come",
  any7: 'Any 7', anycraps: 'Any Craps',
}
/** Human name for any bet key, including the ones that move onto numbers. */
function betName(k: string): string {
  if (NAME[k]) return NAME[k]
  const m = k.match(/^(place|hard|come|dcome)(\d+)(_odds)?$/)
  if (!m) return k
  const what = { place: 'Place', hard: 'Hard', come: 'Come', dcome: "Don't Come" }[m[1]]
  return `${what} ${m[2]}${m[3] ? (m[1] === 'dcome' ? ' lay odds' : ' odds') : ''}`
}
const isOdds = (k: CrapsBetKind) => k.endsWith('_odds')

/** What the stickman says. */
function call(r: { dice: [number, number]; sum: number; event?: CrapsEvent }, point: number | null): string {
  const [a, b] = r.dice, s = r.sum, hard = a === b && [4, 6, 8, 10].includes(s)
  switch (r.event) {
    case 'natural': return s === 11 ? 'Yo-leven. Front line wins' : 'Seven. Front line wins'
    case 'craps': return s === 2 ? 'Aces — craps' : s === 3 ? 'Ace-deuce — craps' : 'Boxcars — craps'
    case 'point': return `The point is ${s}`
    case 'hit': return `${s}${hard ? ' the hard way' : ''} — pay the line`
    case 'seven_out': return 'Seven out — line away'
    default:
      if (s === 11) return 'Yo-leven'
      if (s === 2 || s === 3 || s === 12) return `${s}, craps`
      return `${s}${hard ? ' the hard way' : [4, 6, 8, 10].includes(s) ? ', easy' : ''}${point ? ` — point is ${point}` : ''}`
  }
}

type FlashLine = { n: number; cls: string; text?: string }
type Flash = Partial<Record<CrapsBetKind, FlashLine>>

/** One betting area on the felt: tap to put the current chip on it. */
function BetSpot({ k, className = '', children, disabled, label, amount, flash, busy, onBet }: {
  k: CrapsBetKind; className?: string; children: ReactNode; disabled?: boolean; label: string
  amount: number; flash?: FlashLine; busy: boolean; onBet: (k: CrapsBetKind) => void
}) {
  return (
    <button className={`cr-spot ${className} ${amount ? 'has' : ''} ${flash ? 'flash-' + flash.cls : ''}`} disabled={disabled || busy} onClick={() => onBet(k)}
      aria-label={`${label}${amount ? `, ${money(amount)} on it` : ''}`}>
      {children}
      {amount > 0 && <span className="cr-chip"><ChipStack amount={amount} /></span>}
      {flash && <span className={`cr-float ${flash.cls}`}>{flash.text ?? (flash.cls === 'push' ? 'push' : flash.n >= 0 ? `+${money(flash.n)}` : `−${money(-flash.n)}`)}</span>}
    </button>
  )
}

export default function Craps() {
  const me = useMe()
  const { run, toast } = useGame()
  const [chip, setChip] = useBet('craps')
  const { data: st, error, reload, set: setSt } = useLoad(() => api.crapsState())
  const [roll, setRoll] = useState<CrapsRoll | null>(null)
  const [rolling, setRolling] = useState(false)
  const [placing, setPlacing] = useState(false)   // a chip is on its way to the server
  // the faces on the table: the roll in progress or the last one, else the last roll the server remembers
  const [shownDice, setDice] = useState<[number, number] | null>(null)
  const [flash, setFlash] = useState<Flash>({})
  const [session, setSession] = useState({ rolls: 0, net: 0 })
  const flashTimer = useRef<number | null>(null)
  const dice: [number, number] = shownDice ?? st?.last?.dice ?? [5, 2]
  useEffect(() => () => { if (flashTimer.current) window.clearTimeout(flashTimer.current) }, [])

  const bets = st?.bets ?? {}
  const onFelt = Object.values(bets).reduce((a, b) => a + (b ?? 0), 0)
  const point = st?.point ?? null
  /** Most odds allowed behind this bet right now. */
  const oddsMax = (k: CrapsBetKind): number => {
    const om = st?.odds_max
    if (k === 'pass_odds' || k === 'dont_odds') return om?.[k] ?? 0
    const m = k.match(/^(d?come)(\d+)_odds$/)
    return m ? (m[1] === 'come' ? om?.come?.[m[2]] : om?.dcome?.[m[2]]) ?? 0 : 0
  }
  const oddsLeft = (k: CrapsBetKind) => Math.max(0, oddsMax(k) - (bets[k] ?? 0))
  const comePoints = NUMBERS.filter(n => (bets[`come${n}`] ?? 0) > 0)
  const dcomePoints = NUMBERS.filter(n => (bets[`dcome${n}`] ?? 0) > 0)

  async function bet(k: CrapsBetKind) {
    if (rolling || placing) return   // one bet at a time: two in flight can land out of order on the felt
    let amt = chip
    if (isOdds(k)) {
      const left = oddsLeft(k)
      if (left < 100) { toast(left > 0 ? 'Odds are full' : 'Odds need a bet to sit behind', 'info'); return }
      amt = Math.min(chip, left)
    }
    setPlacing(true)
    try { const s = await run(() => api.crapsBet(k, amt), { silent: true }); if (s) setSt(s) } finally { setPlacing(false) }
  }

  async function doRoll() {
    setRolling(true); setRoll(null); setFlash({})
    const t = window.setInterval(() => setDice([1 + Math.floor(Math.random() * 6), 1 + Math.floor(Math.random() * 6)]), 70)
    const r = await run(() => api.crapsRoll(), { silent: true })
    await new Promise(res => setTimeout(res, r ? 650 : 0))
    window.clearInterval(t)
    if (r) {
      setDice(r.dice); setRoll(r); setSt(r)
      setSession(s => ({ rolls: s.rolls + 1, net: s.net + r.net }))
      const f: Flash = {}
      for (const l of r.log) {
        if (l.result === 'win') f[l.bet] = { n: (l.win ?? 0) - (l.stays ? 0 : l.amount), cls: 'win' }
        else if (l.result === 'lose') f[l.bet] = { n: -l.amount, cls: 'lose' }
        else if (l.result === 'push') f[l.bet] = { n: 0, cls: 'push' }
        else if (l.result === 'moves') f[l.bet] = { n: 0, cls: 'push', text: `→ ${l.to}` }
      }
      setFlash(f)
      if (flashTimer.current) window.clearTimeout(flashTimer.current)
      flashTimer.current = window.setTimeout(() => setFlash({}), 2600)
    } else setDice(null)   // a failed roll: back to the last real roll, not a random frame
    setRolling(false)
  }
  async function takeDown() { const s = await run(() => api.crapsClear(), { silent: true }); if (s) setSt(s) }

  const sp = (k: CrapsBetKind) => ({ amount: bets[k] ?? 0, flash: flash[k], busy: rolling || placing, onBet: bet })

  const history = st?.history ?? []
  const lastCall = roll ? call(roll, roll.point) : point ? `Point is ${point}` : st?.last ? call({ ...st.last, event: st.last.event }, point) : 'Place your bets — come-out roll'
  const settled = roll?.log.filter((l: CrapsLogLine) => l.result === 'win' || l.result === 'lose' || l.result === 'push') ?? []

  return (
    <Card title="🎲 Craps" className="table-card" right={<small>{point ? `Point is ${point}` : 'Come-out roll'}</small>}>
      <div className="bd stack">
        {!st ? <Loading error={error} onRetry={reload} /> : (
          <div className="cr-table">
            <div className="cr-rail">
              <div className="cr-dice">
                <Die n={dice[0]} rolling={rolling} size={46} /><Die n={dice[1]} rolling={rolling} size={46} />
                <span className={`cr-sum ${rolling ? 'muted' : ''}`}>{rolling ? '…' : roll || st.last ? dice[0] + dice[1] : ''}</span>
              </div>
              <div className={`cr-call ${roll?.event ?? ''}`}>{rolling ? 'Dice are out…' : lastCall}</div>
              {roll && !rolling && (roll.wager > 0 || roll.payout > 0) && <div className="cr-net">This roll <Net n={roll.net} /></div>}
              {history.length > 0 && (
                <div className="cr-history" aria-label="Last rolls">
                  {history.slice(0, 12).map((h, i) => (
                    <span key={i} className={`cr-h ${h.sum === 7 ? 'seven' : ''} ${h.event === 'hit' || h.event === 'natural' ? 'good' : ''} ${h.event === 'point' ? 'point' : ''}`}
                      title={`${h.dice[0]}-${h.dice[1]}`}>{h.sum}</span>
                  ))}
                </div>
              )}
              <div className={`cr-puck ${point ? 'on' : ''}`}>{point ? 'ON' : 'OFF'}</div>
            </div>

            <div className="cr-felt">
              <div className="cr-numbers">
                {NUMBERS.map(n => (
                  <BetSpot key={n} k={`place${n}` as CrapsBetKind} {...sp(`place${n}` as CrapsBetKind)} className={`cr-num ${point === n ? 'point' : ''}`} label={`Place ${n}, pays ${PLACE_PAYS[n]}`}>
                    {point === n && <span className="cr-puck mini on">ON</span>}
                    {((bets[`come${n}`] ?? 0) > 0 || (bets[`dcome${n}`] ?? 0) > 0) &&
                      <span className="cr-cbadge">{(bets[`come${n}`] ?? 0) > 0 ? 'C' : ''}{(bets[`dcome${n}`] ?? 0) > 0 ? 'DC' : ''}</span>}
                    <span className="cr-n">{NUM_LABEL[n]}</span>
                    <span className="cr-pay">{PLACE_PAYS[n]}</span>
                  </BetSpot>
                ))}
              </div>

              <div className="cr-props">
                <div className="cr-props-title">Hardways</div>
                <div className="cr-hards">
                  {([4, 10, 6, 8] as const).map(n => (
                    <BetSpot key={n} k={`hard${n}` as CrapsBetKind} {...sp(`hard${n}` as CrapsBetKind)} className="cr-hard" label={`Hard ${n}, pays ${n === 4 || n === 10 ? '7:1' : '9:1'}`}>
                      <span className="cr-mini-dice"><Die n={n / 2} size={16} /><Die n={n / 2} size={16} /></span>
                      <span className="cr-pay">{n === 4 || n === 10 ? '7:1' : '9:1'}</span>
                    </BetSpot>
                  ))}
                </div>
                <div className="cr-oneroll">
                  <BetSpot k="any7" {...sp('any7')} className="cr-prop seven" label="Any 7, pays 4:1"><span className="cr-l">Any 7</span><span className="cr-pay">4:1</span></BetSpot>
                  <BetSpot k="anycraps" {...sp('anycraps')} className="cr-prop" label="Any craps, pays 7:1"><span className="cr-l">Any Craps</span><span className="cr-pay">7:1</span></BetSpot>
                </div>
              </div>

              <div className="cr-line come">
                <BetSpot k="come" {...sp('come')} className="cr-come" disabled={point === null} label="Come, plays like a new pass line bet">
                  <span className="cr-l">COME</span>
                  <span className="cr-pay">{point === null ? 'opens once the point is on' : '7 or 11 wins · 2, 3, 12 lose · else moves to the number'}</span>
                </BetSpot>
                <BetSpot k="dcome" {...sp('dcome')} className="cr-dcome" disabled={point === null} label="Don't come, bar 12">
                  <span className="cr-l">DON'T COME</span><span className="cr-pay">Bar 12</span>
                </BetSpot>
              </div>

              {(comePoints.length > 0 || dcomePoints.length > 0) && (
                <div className="cr-comepts">
                  <div className="cr-props-title">Your come bets</div>
                  {comePoints.map(n => (
                    <div key={`c${n}`} className="cr-line">
                      <div className="cr-cp"><span className="cr-l">COME {n}</span><span className="cr-pay">wins on {n} · loses on 7</span>
                        <span className="cr-chip"><ChipStack amount={bets[`come${n}`] ?? 0} /></span></div>
                      <BetSpot k={`come${n}_odds`} {...sp(`come${n}_odds`)} className="cr-odds" label={`Odds on come ${n}, pays ${ODDS_PAYS[n]}, ${money(oddsLeft(`come${n}_odds`))} left`}>
                        <span className="cr-l">ODDS</span><span className="cr-pay">pays {ODDS_PAYS[n]}<br />max {money(oddsMax(`come${n}_odds`))}</span>
                      </BetSpot>
                    </div>
                  ))}
                  {dcomePoints.map(n => (
                    <div key={`d${n}`} className="cr-line">
                      <div className="cr-cp dont"><span className="cr-l">DON'T COME {n}</span><span className="cr-pay">wins on 7 · loses on {n}</span>
                        <span className="cr-chip"><ChipStack amount={bets[`dcome${n}`] ?? 0} /></span></div>
                      <BetSpot k={`dcome${n}_odds`} {...sp(`dcome${n}_odds`)} className="cr-odds" label={`Lay odds on don't come ${n}, pays ${LAY_PAYS[n]}, ${money(oddsLeft(`dcome${n}_odds`))} left`}>
                        <span className="cr-l">LAY</span><span className="cr-pay">pays {LAY_PAYS[n]}<br />max {money(oddsMax(`dcome${n}_odds`))}</span>
                      </BetSpot>
                    </div>
                  ))}
                  {point === null && comePoints.some(n => (bets[`come${n}_odds`] ?? 0) > 0) && <div className="cr-pay center">Come odds are off on the come-out roll.</div>}
                </div>
              )}

              <BetSpot k="field" {...sp('field')} className="cr-field" label="Field, one roll. 2 pays double, 12 pays triple">
                <span className="cr-l">FIELD</span>
                <span className="cr-field-nums"><b>2</b>·3·4·9·10·11·<b>12</b></span>
                <span className="cr-pay">2 pays double · 12 pays triple</span>
              </BetSpot>

              <div className="cr-line dont">
                <BetSpot k="dont" {...sp('dont')} className="cr-dont" disabled={point !== null} label="Don't pass bar, bar 12">
                  <span className="cr-l">DON'T PASS BAR</span><span className="cr-pay">{point !== null ? `Wins on 7 · loses on ${point}` : 'Bar 12 · pays 1:1'}</span>
                </BetSpot>
                {point !== null && (bets.dont ?? 0) > 0 && (
                  <BetSpot k="dont_odds" {...sp('dont_odds')} className="cr-odds" label={`Lay odds, pays ${LAY_PAYS[point]}, ${money(oddsLeft('dont_odds'))} left`}>
                    <span className="cr-l">LAY</span><span className="cr-pay">pays {LAY_PAYS[point]}<br />max {money(st.odds_max?.dont_odds ?? 0)}</span>
                  </BetSpot>
                )}
              </div>

              <div className="cr-line pass">
                <BetSpot k="pass" {...sp('pass')} className="cr-pass" disabled={point !== null} label="Pass line">
                  <span className="cr-l">PASS LINE</span><span className="cr-pay">{point !== null ? `Wins on ${point} · loses on 7` : 'Pays 1:1 · 7 or 11 wins on the come-out'}</span>
                </BetSpot>
                {point !== null && (bets.pass ?? 0) > 0 && (
                  <BetSpot k="pass_odds" {...sp('pass_odds')} className="cr-odds" label={`Pass odds, pays ${ODDS_PAYS[point]}, ${money(oddsLeft('pass_odds'))} left`}>
                    <span className="cr-l">ODDS</span><span className="cr-pay">pays {ODDS_PAYS[point]}<br />max {money(st.odds_max?.pass_odds ?? 0)}</span>
                  </BetSpot>
                )}
              </div>
            </div>
          </div>
        )}

        {point !== null && (bets.pass ?? 0) > 0 && !(bets.pass_odds) && <div className="cr-tip">💡 Take odds behind your Pass Line — it's the only bet in the house with no edge.</div>}
        {comePoints.some(n => !(bets[`come${n}_odds`])) && (!(bets.pass ?? 0) || (bets.pass_odds ?? 0) > 0) && <div className="cr-tip">💡 Back your come bets with odds too — same true-odds payout, no edge.</div>}
        {point === null && ((bets.place4 ?? 0) + (bets.place5 ?? 0) + (bets.place6 ?? 0) + (bets.place8 ?? 0) + (bets.place9 ?? 0) + (bets.place10 ?? 0) + (bets.hard4 ?? 0) + (bets.hard6 ?? 0) + (bets.hard8 ?? 0) + (bets.hard10 ?? 0)) > 0 &&
          <div className="small muted center">Place bets and hardways are off on the come-out roll.</div>}

        {/* chips and Roll ride above the tab bar while the felt scrolls under them */}
        <div className="table-bar">
          <BetPicker part="chips" value={chip} onChange={setChip} max={Math.min(500000, me.cash)} label="Chip — tap the felt to bet" />
          <div className="hstack" style={{ flexWrap: 'nowrap' }}>
            <button type="button" className="btn gold flex1 cr-roll" disabled={rolling || placing || onFelt === 0} onClick={doRoll}>
              {rolling ? <span className="spin" /> : onFelt ? <>Roll <small>{money(onFelt)} on the felt</small></> : 'Place a bet to roll'}
            </button>
            <button type="button" className="btn ghost" disabled={rolling || onFelt === 0} onClick={takeDown} aria-label="Take down everything except Pass / Don't Pass once the point is on, and come bets">Take down</button>
          </div>
        </div>
        <BetPicker part="amount" value={chip} onChange={setChip} max={Math.min(500000, me.cash)} />

        {settled.length > 0 && !rolling && (
          <div className="cr-log">
            {settled.map((l, i) => (
              <div key={i} className="spread small">
                <span>{betName(l.bet)} {money(l.amount)}</span>
                <span className={l.result === 'win' ? 'green' : l.result === 'lose' ? 'red' : 'muted'}>
                  {l.result === 'win' ? `wins ${money((l.win ?? 0) - (l.stays ? 0 : l.amount))}${l.stays ? ', stays up' : ''}` : l.result === 'push' ? 'push' : 'lost'}
                </span>
              </div>
            ))}
          </div>
        )}

        <div className="spread small muted">
          <span>{session.rolls ? <>This session: {session.rolls} roll{session.rolls > 1 ? 's' : ''} · <Net n={session.net} /></> : 'Pass & odds is the best bet on the table.'}</span>
        </div>
        <details className="cr-rules small muted">
          <summary>How the table plays</summary>
          <p>Pass wins on 7 or 11 on the come-out and loses on 2, 3 or 12; any other number becomes the point, and Pass wins if the point comes again before a 7. Don't Pass is the opposite (12 is a push).</p>
          <p>Odds behind the line pay true odds (4/10 2:1, 5/9 3:2, 6/8 6:5) up to 3-4-5x your line bet; lay odds behind Don't Pass up to 6x. Place bets pay 9:5 on 4/10, 7:5 on 5/9, 7:6 on 6/8. Hardways pay 7:1 (4, 10) and 9:1 (6, 8) and lose on the easy way or a 7. Place bets and hardways are off on the come-out, and stay up after they win. Field, Any 7 and Any Craps are one-roll bets.</p>
          <p>Come and Don't Come work like Pass and Don't Pass, but you make them after the point is on: the next roll is their come-out, and any point number moves the bet onto that number. Back a come bet with odds (3-4-5x, true odds) — they're off on the come-out roll, so a 7 there takes the flat bet but hands the odds back. Lay up to 6x behind a Don't Come.</p>
          <p>Pass and Don't Pass lock once the point is on, and come bets stay until they win or lose; everything else, odds included, can be taken down between rolls.</p>
        </details>
      </div>
    </Card>
  )
}
