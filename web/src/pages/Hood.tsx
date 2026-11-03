import { useState } from 'react'
import { api } from '../lib/api'
import type { HoodBlock, HoodFight } from '../lib/types'
import { useGame, useMe } from '../lib/game'
import { ago, money, num, timeLeft } from '../lib/format'
import { useLoad } from '../lib/useLoad'
import { useNow } from '../lib/useNow'
import { haptic } from '../lib/haptics'
import { BackBar } from '../components/BackBar'
import { Btn, Card, Empty, Loading } from '../components/ui'

/**
 * Your Hood (Season 1): six private blocks held by defenders until you take them, each with one of the season's
 * businesses. Taking a block is the fight formula against a number; a taken block pays by the hour and gives its perk.
 * The grid is drawn like Territory's blocks, gold-edged for yours, the next one up with its odds, the rest greyed.
 * Tapping a tile opens its panel under the grid with the one thing to do there: Attack, Collect or Upgrade.
 */
export default function Hood() {
  const me = useMe()
  const { run, refresh } = useGame()
  const now = useNow(30_000)
  // the first look at the hood is mission 1: the server marks it on home_state, so me catches up right away
  const opened = me.home?.opened
  const { data: hood, error, reload, set } = useLoad(() => api.homeState().then(h => { if (!opened) refresh(); return h }), 'hood')
  const [picked, setSel] = useState<number | null>(null)
  const [result, setResult] = useState<HoodFight | null>(null)
  // until a tile is tapped, the panel is the next block to take (or the boss, or the first block with cash waiting)
  const sel = picked ?? (hood ? hood.next_slot ?? (hood.boss.ready ? 7 : hood.blocks.find(b => b.ready > 0)?.slot ?? 1) : null)

  if (!me.season) return <div className="page"><BackBar fallback="/" /><Empty>No season is running. Your hood opens with the next one.</Empty></div>
  if (!hood) return <div className="page"><BackBar fallback="/" /><Loading error={error} onRetry={reload} /></div>

  const fight = async (slot: number) => {
    const r = await run(() => (slot === 7 ? api.homeBoss() : api.homeAttack(slot)), { silent: true })
    if (!r) return
    set(r.hood); setResult(r); haptic(r.won ? 'success' : 'error')
    if (r.won && slot < 7) setSel(r.hood.next_slot ?? (r.hood.boss.ready ? 7 : slot))
  }
  const collect = async (slot?: number) => {
    const r = await run(() => api.homeCollect(slot), { ok: r => `Collected ${money(r.collected)}` })
    if (r) { set(r.hood); haptic('light') }
  }
  const upgrade = async (b: HoodBlock) => {
    const r = await run(() => api.homeUpgrade(b.slot), { ok: r => `${b.name} is level ${r.level}` })
    if (r) { set(r.hood); haptic('medium') }
  }

  const selected = sel && sel <= 6 ? hood.blocks.find(b => b.slot === sel) ?? null : null
  const readyBlocks = hood.blocks.filter(b => b.ready > 0).length
  const ends = timeLeft(hood.season.ends_at, now)

  return (
    <div className="page hood">
      <BackBar fallback="/" right={<span className="muted small">{hood.season.name} · {ends} left</span>} />
      <Card title={`${me.name}'s Hood`} className="hood-head"
        right={<small className="tabular">{hood.cleared}/6 blocks{hood.boss.cleared ? ' · boss down' : ''}</small>}>
        <div className="grid3">
          <div className="stat"><div className="k">Pays</div><div className="v sm">{hood.income_day ? `${money(hood.income_day)}/day` : '—'}</div></div>
          <div className="stat"><div className="k">Waiting</div><div className={`v sm ${hood.ready_cash ? 'gold' : ''}`}>{money(hood.ready_cash)}</div></div>
          <div className="stat"><div className="k">Perks</div><div className="v sm">{Object.keys(hood.perks).length || '—'}</div></div>
        </div>
        {readyBlocks >= 2 && (
          <div className="bd"><Btn className="doit block" onClick={() => collect()}>Collect All · {money(hood.ready_cash)}</Btn></div>
        )}
      </Card>

      {result && <FightResult r={result} onClose={() => setResult(null)} />}

      {/* the boss, once all six are yours: a seventh fight, then the hood's name plate */}
      {hood.boss.ready && (
        <div className={`row boss ${sel === 7 ? 'sel' : ''}`}>
          <button type="button" className={`block boss-tile ${sel === 7 ? 'sel' : ''}`} onClick={() => setSel(7)} aria-label={`The boss, ${hood.boss.defender} attack and defense`}>
            <div className="em">🕴</div><div><b>The Boss</b></div>
            <div className="small muted">{num(hood.boss.defender)} / {num(hood.boss.defender)}</div>
            {hood.next && <div className="small gold">{hood.next.win_pct}% to win</div>}
          </button>
        </div>
      )}
      {hood.boss.cleared && (
        <div className="notice gold hood-plate"><b>{me.name}'s Hood</b> — all six blocks and the boss, taken {ago(hood.boss.cleared_at ?? hood.season.starts_at, now)}. Every block pays +{Math.round(hood.cfg.boss_bonus * 100)}%.</div>
      )}

      <div className="card">
        <div className="blocks6 hood-grid">
          {hood.blocks.map(b => <Tile key={b.slot} b={b} next={hood.next_slot === b.slot} odds={hood.next_slot === b.slot ? hood.next?.win_pct ?? null : null} sel={sel === b.slot} onClick={() => setSel(b.slot)} />)}
        </div>
      </div>

      {sel === 7 && hood.boss.ready && hood.next && (
        <Card title="The Boss">
          <div className="bd stack">
            <div className="small">The guy who ran these blocks before the reset. He fights at <b className="tabular">{num(hood.boss.defender)}</b> attack and <b className="tabular">{num(hood.boss.defender)}</b> defense; you bring {num(hood.next.my_att)} and {num(hood.next.my_def)}. Beat him and every block pays +{Math.round(hood.cfg.boss_bonus * 100)}%.</div>
            <Btn className="red block" onClick={() => fight(7)} disabled={me.hospital || me.jailed}>Attack · {hood.next.win_pct}% to win · {hood.next.stamina} stamina</Btn>
            {(me.hospital || me.jailed) && <div className="small muted why">{me.hospital ? 'Not from the hospital.' : 'Not from a cell.'}</div>}
          </div>
        </Card>
      )}

      {selected && (
        <Card title={`Block ${selected.slot} · ${selected.name}`} right={selected.cleared ? <small className="tabular">Level {selected.level}</small> : undefined}>
          <div className="bd stack">
            <div className="small"><span aria-hidden>{selected.icon}</span> {selected.perk}{selected.perk_value != null && <b className="gold"> · {Math.round(selected.perk_value * 100)}%</b>}</div>
            {selected.cleared ? (
              <>
                <div className="grid2">
                  <div className="stat"><div className="k">Pays</div><div className="v sm">{money(selected.income_day ?? 0)}/day</div></div>
                  <div className="stat"><div className="k">Waiting</div><div className={`v sm ${selected.ready ? 'gold' : ''}`}>{money(selected.ready)}</div></div>
                </div>
                <div className="small muted">
                  {selected.ready > 0
                    ? (selected.cap_at && new Date(selected.cap_at).getTime() <= now ? `Full — it stopped piling up after ${hood.cfg.cap_hours} hours.` : `Piles up for ${timeLeft(selected.cap_at, now)} more, then stops.`)
                    : 'Nothing yet — it pays by the hour.'}
                </div>
                <div className="hstack">
                  <Btn className="doit grow" onClick={() => collect(selected.slot)} disabled={selected.ready <= 0}>Collect{selected.ready > 0 ? ` · ${money(selected.ready)}` : ''}</Btn>
                  {selected.upgrade_cost != null
                    ? <Btn className="gold grow" onClick={() => upgrade(selected)} disabled={me.cash < selected.upgrade_cost} label={`Upgrade to level ${selected.level + 1} for ${money(selected.upgrade_cost)}`}>Level {selected.level + 1} · {money(selected.upgrade_cost)}</Btn>
                    : <span className="pill gold">Top level</span>}
                </div>
                {selected.upgrade_cost != null && me.cash < selected.upgrade_cost && <div className="small muted why">You have {money(me.cash)} on hand. The bank doesn't count.</div>}
              </>
            ) : hood.next_slot === selected.slot && hood.next ? (
              <>
                <div className="small">Held by defenders at <b className="tabular">{num(selected.defender)}</b> attack and <b className="tabular">{num(selected.defender)}</b> defense. You bring {num(hood.next.my_att)} attack and {num(hood.next.my_def)} defense from your Offensive setup.</div>
                <Btn className="red block" onClick={() => fight(selected.slot)} disabled={me.hospital || me.jailed}>Attack · {hood.next.win_pct}% to win · {hood.next.stamina} stamina</Btn>
                {(me.hospital || me.jailed) ? <div className="small muted why">{me.hospital ? 'Not from the hospital.' : 'Not from a cell.'}</div>
                  : hood.next.win_pct < 50 ? <div className="small muted why">Long odds. Better gear on the Items screen moves this number.</div> : null}
              </>
            ) : (
              <div className="small muted">Held by defenders at {num(selected.defender)}. Take block {hood.next_slot} first.</div>
            )}
          </div>
        </Card>
      )}

      {Object.keys(hood.perks).length > 0 && (
        <Card title="Your perks">
          {hood.blocks.filter(b => b.cleared).map(b => (
            <div key={b.slot} className="row">
              <span aria-hidden>{b.icon}</span>
              <div className="grow"><div className="t">{b.name}</div><div className="s">{b.perk}</div></div>
              <b className="tabular gold">{Math.round((b.perk_value ?? 0) * 100)}%</b>
            </div>
          ))}
          <div className="row small muted">Level 5 is the full perk a crew gets from a block. Where your crew has the same business, the larger one counts.</div>
        </Card>
      )}
    </div>
  )
}

function Tile({ b, next, odds, sel, onClick }: { b: HoodBlock; next: boolean; odds: number | null; sel: boolean; onClick: () => void }) {
  const state = b.cleared ? 'yours' : next ? 'next' : 'held'
  return (
    <button type="button" className={`block ${state} ${sel ? 'sel' : ''}`} onClick={onClick}
      aria-label={`Block ${b.slot}, ${b.name}, ${b.cleared ? `yours, level ${b.level}` : next ? `held by defenders at ${b.defender}, ${odds ?? 0}% to win` : `held by defenders at ${b.defender}`}`}>
      <div className="em">{b.cleared ? b.icon : '🔒'}</div>
      <div className="biz-name"><b>{b.name}</b></div>
      {b.cleared ? (
        <>
          <div className="small muted">Level {b.level}</div>
          <div className="small muted tabular">{money(b.income_day ?? 0)}/day</div>
          {b.ready > 0 && <div className="small gold tabular">{money(b.ready)} waiting</div>}
        </>
      ) : next ? (
        <>
          <div className="small muted">def {num(b.defender)}</div>
          {odds != null && <div className={`small ${odds >= 50 ? 'gold' : 'red'}`}>{odds}% to win</div>}
        </>
      ) : <div className="small muted">def {num(b.defender)}</div>}
    </button>
  )
}

function FightResult({ r, onClose }: { r: HoodFight; onClose: () => void }) {
  const line = r.won
    ? (r.boss ? 'The boss is down. The hood is yours.' : `Block ${r.slot} is ours.`)
    : (r.damage_taken > 0 ? `They held. You took ${r.damage_taken} damage.` : 'They held.')
  return (
    <div className={`notice ${r.won ? 'gold' : 'red'} attack-result`} role="status">
      <div className="spread"><b>{r.won ? 'Won' : 'Lost'}</b><button type="button" className="btn sm ghost" onClick={onClose}>Dismiss</button></div>
      <div>{line}{!r.won && ' Better gear moves the odds.'}</div>
      <div className={`scoreline ${r.won ? 'won' : 'lost'}`}>
        <span>You <b className="tabular">{r.my_score.toFixed(1)}</b></span>
        <span className="muted small">vs</span>
        <span><b className="tabular">{r.their_score.toFixed(1)}</b> {r.boss ? 'the boss' : 'defenders'}</span>
      </div>
      <div className="small muted">Your {num(r.my_att)}/{num(r.my_def)} against their {num(r.defender)}/{num(r.defender)} · rolls {r.my_roll} vs {r.their_roll}{r.my_combo ? ` · combo +${r.my_combo_bonus}` : ''}.</div>
    </div>
  )
}
