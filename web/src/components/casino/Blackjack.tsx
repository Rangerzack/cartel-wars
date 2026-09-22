import { useEffect, useState } from 'react'
import { api } from '../../lib/api'
import { useGame, useMe } from '../../lib/game'
import { money } from '../../lib/format'
import type { BlackjackState } from '../../lib/types'
import { Card, Empty } from '../ui'
import { BetPicker, Cards, Net } from './shared'

const OUTCOME: Record<string, string> = {
  blackjack: 'Blackjack! Pays 3:2', win: 'You win', push: 'Push', lose: 'Dealer wins', bust: 'Bust', dealer_bust: 'Dealer busts — you win',
}

export default function Blackjack() {
  const me = useMe()
  const { run, toast } = useGame()
  const [wager, setWager] = useState(1000)
  const [g, setG] = useState<BlackjackState | null>(null)
  useEffect(() => { api.blackjackState().then(setG).catch(e => toast(e.message, 'bad')) }, [toast])

  const playing = g?.status === 'playing'
  async function deal() { const r = await run(() => api.blackjackDeal(wager), { silent: true }); if (r) setG(r) }
  async function act(a: 'hit' | 'stand' | 'double') { const r = await run(() => api.blackjackAction(a), { silent: true }); if (r) setG(r) }

  return (
    <Card title="🃏 Blackjack" right={<small>6 decks · dealer stands on 17 · BJ pays 3:2</small>}>
      <div className="bd stack">
        {!g ? <Empty><span className="spin" /></Empty> : g.status === 'none' ? (
          <div className="bjtable"><Empty>Place a bet and deal.</Empty></div>
        ) : (
          <div className={`bjtable ${g.status === 'done' ? (g.result && g.result.net > 0 ? 'won' : g.result && g.result.net < 0 ? 'lost' : '') : ''}`}>
            <div className="hand">
              <div className="small muted">Dealer {g.dealer_hidden ? '' : `· ${g.dealer_total}`}</div>
              <Cards list={g.dealer_hidden ? [g.dealer[0], null] : g.dealer} size="lg" />
            </div>
            <div className="hand">
              <div className="small muted">You · {g.player_total}{g.player_soft && g.player_total < 21 ? ' (soft)' : ''} · {money(g.wager)}</div>
              <Cards list={g.player} size="lg" />
            </div>
            {g.status === 'done' && g.result && (
              <div className="center outcome">{OUTCOME[g.result.outcome]} · <Net n={g.result.net} /></div>
            )}
          </div>
        )}
        {playing ? (
          <div className="hstack">
            <button className="btn grow" onClick={() => act('hit')}>Hit</button>
            <button className="btn doit grow" onClick={() => act('stand')}>Stand</button>
            <button className="btn gold grow" disabled={!g?.can_double || me.cash < (g?.wager ?? 0)} onClick={() => act('double')}>Double</button>
          </div>
        ) : (
          <>
            <BetPicker value={wager} onChange={setWager} max={Math.min(500000, me.cash)} />
            <button className="btn gold block" disabled={me.cash < wager} onClick={deal}>Deal for {money(wager)}</button>
          </>
        )}
      </div>
    </Card>
  )
}
