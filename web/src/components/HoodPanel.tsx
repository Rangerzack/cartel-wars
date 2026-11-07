import { useEffect, useRef, useState } from 'react'
import { api } from '../lib/api'
import type { HoodBlock, HoodFight, HoodNext } from '../lib/types'
import { useGame, useMe } from '../lib/game'
import { ago, money, num, timeLeft, toInt } from '../lib/format'
import { useLoad } from '../lib/useLoad'
import { useNow } from '../lib/useNow'
import { haptic } from '../lib/haptics'
import { Btn, Card, Loading } from './ui'
import { Glyph, Icon } from './Icon'
import { HireHoodlums } from './Hire'

/** $50k, $2.5M: a garrison's worth in troops, short. */
const short = (v: number) => v >= 1_000_000 ? `$${(v / 1_000_000).toLocaleString('en-US', { maximumFractionDigits: 1 })}M` : `$${Math.round(v / 1000)}k`
/** 1,875 → 1.9k: a garrison count that fits a tile. */
const compact = (n: number) => n >= 1000 ? `${(n / 1000).toFixed(n >= 10000 ? 0 : 1)}k` : String(n)
const garrison = (thugs: number, enforcers: number) => [thugs ? `${num(thugs)} thug${thugs === 1 ? '' : 's'}` : '', enforcers ? `${num(enforcers)} enforcer${enforcers === 1 ? '' : 's'}` : ''].filter(Boolean).join(' and ') || 'nobody'

/** The smallest force sure to take it (0.9 × attack beats the resistance), thugs first, then mercs; everything you have if that's not enough. */
function suggest(n: HoodNext): { thugs: number; mercs: number } {
  const need = Math.floor(n.resistance / 0.9) + 1
  const thugs = Math.min(n.my_thugs, Math.ceil(need / 10))
  const rest = Math.max(0, need - thugs * 10)
  const mercs = Math.min(n.my_mercs, Math.ceil(rest / 60))
  return { thugs, mercs }
}

/**
 * Your Hood (Season 1), on the Territory page: six private blocks, each held by a garrison of thugs and enforcers
 * until you take it with your own thugs and mercs — the same fight as a city block. A taken block pays by the hour and
 * gives its perk. The grid is drawn like the city's blocks: gold-edged for yours, the next one up with its garrison,
 * the rest waiting. Tapping a tile opens its panel under the grid with the one thing to do there: Attack, Collect
 * or Upgrade. The first look is mission 1.
 */
export function HoodPanel({ focus }: { focus?: boolean }) {
  const me = useMe()
  const { run, refresh } = useGame()
  const now = useNow(30_000)
  const opened = me.home?.opened
  const { data: hood, error, reload, set } = useLoad(() => api.homeState().then(h => { if (!opened) refresh(); return h }), 'hood')
  const [picked, setSel] = useState<number | null>(null)
  const [result, setResult] = useState<HoodFight | null>(null)
  const top = useRef<HTMLDivElement>(null)
  // a mission's Go button lands here (?focus=hood): the hood scrolls into view once it's drawn
  useEffect(() => { if (focus && hood) top.current?.scrollIntoView({ block: 'start' }) }, [focus, hood])
  const sel = picked ?? (hood ? hood.next_slot ?? (hood.boss.ready ? 7 : hood.blocks.find(b => b.ready > 0)?.slot ?? 1) : null)

  if (!me.season) return null
  if (!hood) return <Loading error={error} onRetry={reload} />

  const fight = async (slot: number, thugs: number, mercs: number) => {
    const r = await run(() => (slot === 7 ? api.homeBoss(thugs, mercs) : api.homeAttack(slot, thugs, mercs)), { silent: true })
    if (!r) return
    set(r.hood); setResult(r); haptic(r.won ? 'success' : 'error'); refresh()   // refresh: the hoodlum counts in the tiles above
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
    <div className="hood stack" id="hood" ref={top}>
      <Card title={`${me.name}'s Hood`} className="hood-head"
        right={<small className="tabular">{hood.cleared}/6 blocks{hood.boss.cleared ? ' · boss down' : ''} · {ends} left</small>}>
        <div className="grid3">
          <div className="stat"><div className="k">Pays</div><div className="v sm">{hood.income_day ? `${money(hood.income_day)}/day` : '—'}</div></div>
          <div className="stat"><div className="k">Waiting</div><div className={`v sm ${hood.ready_cash ? 'gold' : ''}`}>{money(hood.ready_cash)}</div></div>
          <div className="stat"><div className="k">Perks</div><div className="v sm">{Object.keys(hood.perks).length || '—'}</div></div>
        </div>
        {readyBlocks >= 2 && (
          <div className="bd"><Btn className="gold block" onClick={() => collect()}>Collect All · {money(hood.ready_cash)}</Btn></div>
        )}
      </Card>

      {result && <FightResult r={result} onClose={() => setResult(null)} />}

      {/* the boss, once all six are yours: a seventh fight, then the hood's name plate */}
      {hood.boss.ready && (
        <div className={`row boss ${sel === 7 ? 'sel' : ''}`}>
          <button type="button" className={`block boss-tile ${sel === 7 ? 'sel' : ''}`} onClick={() => setSel(7)}
            aria-label={`The boss, held by ${garrison(hood.boss.thugs, hood.boss.enforcers)}, resistance ${num(hood.boss.resistance)}`}>
            <div className="em"><Icon name="user" size={24} /></div><div><b>The Boss</b></div>
            <div className="small muted">{garrison(hood.boss.thugs, hood.boss.enforcers)}</div>
            <div className="small red tabular">resistance {num(hood.boss.resistance)}</div>
          </button>
        </div>
      )}
      {hood.boss.cleared && (
        <div className="notice gold hood-plate"><b>{me.name}'s Hood</b> — all six blocks and the boss, taken {ago(hood.boss.cleared_at ?? hood.season.starts_at, now)}. Every block pays +{Math.round(hood.cfg.boss_bonus * 100)}%.</div>
      )}

      <div className="card">
        <div className="blocks6 hood-grid">
          {hood.blocks.map(b => <Tile key={b.slot} b={b} next={hood.next_slot === b.slot} sel={sel === b.slot} onClick={() => setSel(b.slot)} />)}
        </div>
      </div>

      {sel === 7 && hood.boss.ready && hood.next && (
        <Card title="The Boss">
          <div className="bd stack">
            <div className="small">The guy who ran these blocks before the reset, with {short(hood.boss.value)} of muscle around him: {garrison(hood.boss.thugs, hood.boss.enforcers)}. Beat him and every block pays +{Math.round(hood.cfg.boss_bonus * 100)}%.</div>
            <AttackForm next={hood.next} boss onFight={(t, m) => fight(7, t, m)} />
          </div>
        </Card>
      )}

      {selected && (
        <Card title={`Block ${selected.slot} · ${selected.name}`} right={selected.cleared ? <small className="tabular">Level {selected.level}</small> : <small className="tabular">{short(selected.value)} of muscle</small>}>
          <div className="bd stack">
            <div className="small"><Glyph e={selected.icon} size={15} className="gold" /> {selected.perk}{selected.perk_value != null && <b className="gold"> · {Math.round(selected.perk_value * 100)}%</b>}</div>
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
              <AttackForm next={hood.next} onFight={(t, m) => fight(selected.slot, t, m)} />
            ) : (
              <div className="small muted">Held by {garrison(selected.thugs, selected.enforcers)}, resistance {num(selected.resistance)}. Take block {hood.next_slot} first.</div>
            )}
          </div>
        </Card>
      )}

      {Object.keys(hood.perks).length > 0 && (
        <Card title="Your perks">
          {hood.blocks.filter(b => b.cleared).map(b => (
            <div key={b.slot} className="row">
              <span className="ico gold"><Glyph e={b.icon} size={18} /></span>
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

/** Pick the force: thugs (10 attack) and mercs (60) against the garrison's resistance; the verdict before you swing. */
function AttackForm({ next, boss, onFight }: { next: HoodNext; boss?: boolean; onFight: (thugs: number, mercs: number) => Promise<void> }) {
  const me = useMe()
  const [force, setForce] = useState(() => suggest(next))
  const [hiring, setHiring] = useState(false)
  // what the server will see, ±10%: the verdict is honest about the roll
  const attack = force.thugs * 10 + force.mercs * 60
  const low = attack * 0.9, high = attack * 1.1
  const tooSmall = low < next.min_force
  const verdict = attack === 0 ? 'Send some muscle.'
    : tooSmall ? `Too small to get a fight — bring at least ${num(next.min_force)} attack (a quarter of the resistance).`
    : low > next.resistance ? 'Takes the block, whatever the roll.'
    : high > next.resistance ? 'Could go either way on the roll.'
    : 'They hold, but you bleed the garrison for next time.'
  const cantFight = me.hospital || me.jailed || attack === 0 || tooSmall || force.thugs > next.my_thugs || force.mercs > next.my_mercs
  const loss = attack ? Math.min(1, next.resistance / attack) / 2 : 0
  return (
    <>
      <div className="small">Held by <b>{garrison(next.thugs, next.enforcers)}</b> — resistance <b className="tabular">{num(next.resistance)}</b>. You have {num(next.my_thugs)} thugs and {num(next.my_mercs)} mercs.</div>
      <div className="grid2">
        <label className="f"><span><Icon name="cap" size={13} className="gold" /> Thugs · have {num(next.my_thugs)}</span><input className="input" inputMode="numeric" aria-label="Thugs to send" value={force.thugs} onChange={e => setForce({ ...force, thugs: Math.min(next.my_thugs, toInt(e.target.value)) })} /></label>
        <label className="f"><span><Icon name="sword" size={13} className="red" /> Mercs · have {num(next.my_mercs)}</span><input className="input" inputMode="numeric" aria-label="Mercenaries to send" value={force.mercs} onChange={e => setForce({ ...force, mercs: Math.min(next.my_mercs, toInt(e.target.value)) })} /></label>
      </div>
      <div className="hstack">
        <button type="button" className="btn sm ghost" onClick={() => setForce(suggest(next))}>Just enough</button>
        <button type="button" className="btn sm ghost" onClick={() => setForce({ thugs: next.my_thugs, mercs: next.my_mercs })}>Everything</button>
        <button type="button" className="btn sm ghost" onClick={() => setHiring(h => !h)} aria-expanded={hiring}><Icon name="plus" size={14} /> Hire more</button>
      </div>
      {hiring && <HireHoodlums kinds={['thug', 'mercenary']} btnClass="gold" initial={{ code: 'thug', n: 10 }} />}
      <div className="small"><b className="tabular">{num(attack)}</b> attack ({num(Math.round(low))}–{num(Math.round(high))} on the roll) against {num(next.resistance)}. <span className={low > next.resistance ? 'gold' : tooSmall ? 'red' : 'muted'}>{verdict}</span></div>
      {!tooSmall && attack > 0 && <div className="small muted">Win or lose, you lose about {Math.round(loss * 100)}% of what you send — {num(Math.floor(force.thugs * loss))} thugs{force.mercs ? ` and ${num(Math.floor(force.mercs * loss))} mercs` : ''}.</div>}
      <Btn className="red block" onClick={() => onFight(force.thugs, force.mercs)} disabled={cantFight}>
        Attack{boss ? ' the Boss' : ''} · {num(attack)} vs {num(next.resistance)} · {next.stamina} stamina
      </Btn>
      {(me.hospital || me.jailed) && <div className="small muted why">{me.hospital ? 'Not from the hospital.' : 'Not from a cell.'}</div>}
    </>
  )
}

function Tile({ b, next, sel, onClick }: { b: HoodBlock; next: boolean; sel: boolean; onClick: () => void }) {
  const state = b.cleared ? 'yours' : next ? 'next' : 'held'
  return (
    <button type="button" className={`block ${state} ${sel ? 'sel' : ''}`} onClick={onClick}
      aria-label={`Block ${b.slot}, ${b.name}, ${b.cleared ? `yours, level ${b.level}` : `held by ${garrison(b.thugs, b.enforcers)}, resistance ${num(b.resistance)}${next ? ', next' : ''}`}`}>
      <div className="em"><Glyph e={b.icon} size={24} /></div>
      <div className="biz-name"><b>{b.name}</b></div>
      {b.cleared ? (
        <>
          <div className="small muted">Level {b.level}</div>
          <div className="small muted tabular">{money(b.income_day ?? 0)}/day</div>
          {b.ready > 0 && <div className="small gold tabular">{money(b.ready)} waiting</div>}
        </>
      ) : (
        <>
          <div className="small muted nowrap">{compact(b.thugs)} <Icon name="cap" size={12} /> · {compact(b.enforcers)} <Icon name="shield" size={12} /></div>
          <div className={`small tabular ${next ? 'red' : 'muted'}`}>{short(b.value)} of muscle</div>
        </>
      )}
    </button>
  )
}

function FightResult({ r, onClose }: { r: HoodFight; onClose: () => void }) {
  const line = r.won
    ? (r.boss ? 'The boss is down. The hood is yours.' : `Block ${r.slot} is ours.`)
    : `They held — ${num(r.garrison_left)} resistance left on the block.`
  return (
    <div className={`notice ${r.won ? 'gold' : 'red'} attack-result`} role="status">
      <div className="spread"><b>{r.won ? 'Won' : 'Lost'}</b><button type="button" className="btn sm ghost" onClick={onClose}>Dismiss</button></div>
      <div>{line}</div>
      <div className={`scoreline ${r.won ? 'won' : 'lost'}`}>
        <span>You <b className="tabular">{num(r.attack)}</b></span>
        <span className="muted small">vs</span>
        <span><b className="tabular">{num(r.resistance)}</b> {r.boss ? 'the boss' : 'the garrison'}</span>
      </div>
      <div className="small muted">Sent {num(r.thugs)} thugs{r.mercs ? ` and ${num(r.mercs)} mercs` : ''} · lost {num(r.lost_thugs)}{r.mercs ? ` and ${num(r.lost_mercs)}` : ''} · took out {num(r.garrison_lost)} of theirs.</div>
    </div>
  )
}
