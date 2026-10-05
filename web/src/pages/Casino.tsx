import { useEffect, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { api } from '../lib/api'
import { useGame, useMe } from '../lib/game'
import { ago, money } from '../lib/format'
import type { CasinoHistory } from '../lib/types'
import { Card, Empty } from '../components/ui'
import { Net } from '../components/casino/shared'
import PokerLobby from '../components/casino/PokerLobby'
import Blackjack from '../components/casino/Blackjack'
import Craps from '../components/casino/Craps'
import Roulette from '../components/casino/Roulette'
import Slots from '../components/casino/Slots'
import { features } from '../lib/features'
import { BackBar } from '../components/BackBar'
import { errorText } from '../lib/errors'

const ALL_GAMES = [
  { v: 'poker', l: '♠ Poker' }, { v: 'blackjack', l: '🃏 Blackjack' }, { v: 'craps', l: '🎲 Craps' }, { v: 'roulette', l: '🎡 Roulette' }, { v: 'slots', l: '🎰 Slots' },
] as const
type Game = typeof ALL_GAMES[number]['v']
const GAMES = ALL_GAMES.filter(g => (features.casinoGames as readonly string[]).includes(g.v))
const GAME_LABEL: Record<string, string> = { poker: 'Poker', blackjack: 'Blackjack', craps: 'Craps', roulette: 'Roulette', slots: 'Slots' }

export default function Casino() {
  const me = useMe()
  const { game = GAMES[0].v } = useParams()
  const nav = useNavigate()
  const g = (GAMES.some(x => x.v === game) ? game : GAMES[0].v) as Game
  // /casino/foo: the URL is put right (replaced, so Back doesn't return to it)
  useEffect(() => { if (g !== game) nav(`/casino/${g}`, { replace: true }) }, [g, game, nav])
  const locked = me.jailed || me.hospital
  return (
    <div className="page">
      <BackBar fallback="/" />
      {GAMES.length > 1 ? (
        <div className="seg casino-tabs">
          {GAMES.map(t => <button key={t.v} type="button" className={g === t.v ? 'on' : ''} aria-pressed={g === t.v} onClick={() => nav(`/casino/${t.v}`, { replace: true })}>{t.l}</button>)}
        </div>
      ) : (
        <div className="notice gold">The slot machine is open. Tables — poker, blackjack, craps and roulette — are coming soon.</div>
      )}
      {locked && <div className="notice red">{me.jailed ? 'No gambling from a cell.' : 'The casino won\'t seat you from a hospital bed.'} Come back when you're out.</div>}
      {/* locked, every control in the game is off (a disabled fieldset disables everything inside it), not just told off by the server */}
      <fieldset className="lockable" disabled={locked} aria-disabled={locked}>
        {g === 'poker' && <PokerLobby />}
        {g === 'blackjack' && <Blackjack />}
        {g === 'craps' && <Craps />}
        {g === 'roulette' && <Roulette />}
        {g === 'slots' && <Slots />}
      </fieldset>
      <History />
      <div className="small muted">Wins of {money(10000)} or more draw attention: +2 heat. Big gamblers make the weekly Accolades board.</div>
    </div>
  )
}

function History() {
  const me = useMe()
  const { toast } = useGame()
  const [h, setH] = useState<CasinoHistory | null>(null)
  useEffect(() => { api.casinoHistory(8).then(setH).catch(e => toast(errorText(e), 'bad')) }, [me, toast])
  if (!h) return null
  return (
    <Card title="Your ledger" right={<small>all time <Net n={h.net} /></small>}>
      {h.recent.length === 0 && <Empty>No bets yet.</Empty>}
      {h.recent.map((r, i) => (
        <div key={i} className="row">
          <div className="grow"><div className="t">{GAME_LABEL[r.game] ?? r.game}</div><div className="s">{r.wager > 0 ? `${money(r.wager)} wagered` : 'bet stayed up'} · {ago(r.at)}</div></div>
          <Net n={r.net} />
        </div>
      ))}
    </Card>
  )
}
