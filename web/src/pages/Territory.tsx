import { useCallback, useEffect, useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { useGame, useMe } from '../lib/game'
import { api } from '../lib/api'
import { ago, hoodlumIcon, money, num, timeLeft } from '../lib/format'
import { useNow } from '../lib/useNow'
import { Btn, Card, Empty, Modal, Qty } from '../components/ui'
import type { AttackBlockResult, Block, BlockDetail, Hood, Territory as TerritoryData, TerritoryLog } from '../lib/types'

const ROWS = 'ABCDEFGHI'
const coord = (h: { gx: number; gy: number }) => `${ROWS[h.gy - 1]}${h.gx}`
const ring = (h: { gx: number; gy: number }) => Math.max(Math.abs(h.gx - 5), Math.abs(h.gy - 5))
const slotName = (b: { slot: number }) => `Block ${String.fromCharCode(64 + b.slot)}`

export default function Territory() {
  const me = useMe()
  const { toast } = useGame()
  const nav = useNavigate()
  const [sp, setSp] = useSearchParams()
  const [data, setData] = useState<TerritoryData | null>(null)
  const [log, setLog] = useState<TerritoryLog[] | null>(null)
  const [blockId, setBlockId] = useState<number | null>(null)
  const hoodId = Number(sp.get('hood')) || null

  const load = useCallback(() => Promise.all([api.territory(), api.territoryLog(15)]).then(([t, l]) => { setData(t); setLog(l) }).catch(e => toast(e.message, 'bad')), [toast])
  useEffect(() => { load() }, [load])

  if (!data) return <Empty><span className="spin" /></Empty>
  const hood = hoodId ? data.hoods.find(h => h.id === hoodId) ?? null : null
  const thugs = me.hoodlums.thug ?? 0, mercs = me.hoodlums.mercenary ?? 0, spies = me.hoodlums.spy ?? 0
  const openHood = (id: number | null) => setSp(id ? { hood: String(id) } : {})

  return (
    <div className="page">
      {!me.crew && <div className="notice blue">Territory is held by crews. <a onClick={() => nav('/crew')}>Join or found a crew</a> to fight for blocks.</div>}
      <div className="grid3">
        {(['thug', 'mercenary', 'spy'] as const).map(k => (
          <div key={k} className="stat"><div className="k">{hoodlumIcon[k]} {k === 'mercenary' ? 'Mercs' : k === 'spy' ? 'Spies' : 'Thugs'}</div><div className="v">{num(me.hoodlums[k] ?? 0)}</div></div>
        ))}
      </div>

      {hood ? (
        <HoodView hood={hood} onBack={() => openHood(null)} onBlock={setBlockId} />
      ) : (
        <>
          <Card title="The City" right={<small>tap a hood</small>}>
            <div className="bd">
              <div className="hoodgrid">
                <span />
                {Array.from({ length: 9 }, (_, i) => <span key={i} className="axis">{i + 1}</span>)}
                {Array.from({ length: 9 }, (_, y) => (
                  <Row key={y} y={y + 1} hoods={data.hoods.filter(h => h.gy === y + 1)} onOpen={openHood} />
                ))}
              </div>
              <div className="legend small muted">
                <span><i className="mine" /> your crew</span><span><i className="enemy" /> rival</span><span><i /> unclaimed</span><span><i className="siege" /> under your siege</span>
              </div>
            </div>
          </Card>
          <div className="small muted">
            Hoods pay more toward the center. Each block pays its bonus every {data.rules.bonus_hours}h. A turf attack needs at least {data.rules.min_thugs} thugs and {data.rules.stamina} stamina.
            Empty blocks fall to one win; a held block falls after your crew lands {data.rules.siege_wins} successful hits — and every hit restarts the owner's bonus clock.
          </div>

          <h2>Recent turf wars</h2>
          <Card>
            {log?.length === 0 && <Empty>The streets are quiet.</Empty>}
            {log?.map(l => <LogRow key={l.id} l={l} showBlock onOpen={() => { openHood(l.hood_id); setBlockId(l.block_id) }} />)}
          </Card>
        </>
      )}

      {blockId !== null && (
        <BlockModal id={blockId} rules={data.rules} thugs={thugs} mercs={mercs} spies={spies}
          onClose={() => setBlockId(null)} onChanged={load} />
      )}
    </div>
  )
}

function Row({ y, hoods, onOpen }: { y: number; hoods: Hood[]; onOpen: (id: number) => void }) {
  return (
    <>
      <span className="axis">{ROWS[y - 1]}</span>
      {hoods.sort((a, b) => a.gx - b.gx).map(h => {
        const sieging = h.blocks.some(b => b.my_wins > 0)
        return (
          <button key={h.id} className={`hcell r${ring(h)} ${h.owner ? (h.my_blocks >= 4 ? 'own-mine' : 'own-enemy') : ''}`} title={`${h.name} (${coord(h)})`} onClick={() => onOpen(h.id)}>
            <span className="mini">
              {h.blocks.map(b => <i key={b.id} className={`${b.mine ? 'mine' : b.owner ? 'enemy' : ''} ${b.my_wins > 0 ? 'siege' : ''}`} />)}
            </span>
            <span className="lbl">{h.owner ? h.owner.emblem : sieging ? '⚔️' : coord(h)}</span>
          </button>
        )
      })}
    </>
  )
}

function HoodView({ hood, onBack, onBlock }: { hood: Hood; onBack: () => void; onBlock: (id: number) => void }) {
  const now = useNow()
  return (
    <>
      <div className="hstack"><button className="btn sm ghost" onClick={onBack}>‹ City</button><span className="muted small">{hood.district} · {coord(hood)}</span></div>
      <Card title={<>{hood.name} {hood.owner && <span className="small muted">· held by {hood.owner.emblem} {hood.owner.name}</span>}</>} right={<small className="gold">{money(hood.block_bonus)}/block</small>}>
        <div className="blocks6">
          {hood.blocks.map(b => <BlockTile key={b.id} b={b} hood={hood} now={now} onClick={() => onBlock(b.id)} />)}
        </div>
        <div className="row small muted">
          Base resistance {num(hood.base_resistance)} · empty blocks cost {money(hood.claim_price)} to claim · hold 4 of 6 to own the hood.
        </div>
      </Card>
    </>
  )
}

function BlockTile({ b, hood, now, onClick }: { b: Block; hood: Hood; now: number; onClick: () => void }) {
  return (
    <div className={`block ${b.mine ? 'mine' : b.owner ? 'enemy' : ''}`} onClick={onClick}>
      <div className="em">{b.owner ? b.owner.emblem : ' '}</div>
      <div><b>{slotName(b)}</b></div>
      {b.owner ? (
        <>
          <div className="small tabular">⏱ {timeLeft(b.bonus_at, now)}</div>
          <div className="muted" style={{ fontSize: 10 }}>{b.garrison_size !== null ? `${num(b.garrison_size)} guards` : b.garrisoned ? 'guarded' : 'unguarded'}</div>
          {b.top_wins > 0 && <div className="siegebar" title={`siege ${b.top_wins}`}><div style={{ width: `${Math.min(100, b.top_wins * 2)}%` }} className={b.my_wins > 0 && b.my_wins === b.top_wins ? 'mine' : ''} /></div>}
          {b.my_wins > 0 && <div className="gold" style={{ fontSize: 10 }}>your siege {b.my_wins}/50</div>}
        </>
      ) : <div className="muted" style={{ fontSize: 10 }}>{money(hood.claim_price)}</div>}
    </div>
  )
}

function LogRow({ l, showBlock, onOpen }: { l: TerritoryLog; showBlock?: boolean; onOpen?: () => void }) {
  const what = l.captured ? (l.defender_crew ? `took it from ${l.defender_crew}` : 'claimed it') : l.success ? `landed a hit${l.siege_wins ? ` (${l.siege_wins}/50)` : ''}` : 'was pushed back'
  return (
    <div className={`row ${onOpen ? 'link' : ''}`} onClick={onOpen}>
      <span>{l.captured ? '🏴' : l.success ? '🎯' : '💥'}</span>
      <div className="grow">
        <div className="t">{l.crew_emblem} {l.attacker ?? l.crew} {what}{showBlock ? <span className="muted"> · {l.block}</span> : null}</div>
        <div className="s">{num(l.attack)} vs {num(l.resistance)} · {num(l.thugs)} thugs{l.mercs ? `, ${num(l.mercs)} mercs` : ''} · lost {num(l.lost_thugs + l.lost_mercs)}{l.garrison_lost ? ` · killed ${num(l.garrison_lost)} guards` : ''} · {ago(l.at)}</div>
      </div>
    </div>
  )
}

function BlockModal({ id, rules, thugs, mercs, spies, onClose, onChanged }: {
  id: number; rules: TerritoryData['rules']; thugs: number; mercs: number; spies: number; onClose: () => void; onChanged: () => void
}) {
  const me = useMe()
  const { run, toast } = useGame()
  const nav = useNavigate()
  const now = useNow()
  const [b, setB] = useState<BlockDetail | null>(null)
  const [force, setForce] = useState({ thugs: Math.min(thugs, rules.min_thugs), mercs: 0 })
  const [station, setStation] = useState({ code: 'thug', n: 1 })
  const [intel, setIntel] = useState<{ garrison: Record<string, number>; resistance: number } | null>(null)
  const [result, setResult] = useState<AttackBlockResult | null>(null)
  const load = useCallback(() => api.block(id).then(setB).catch(e => toast(e.message, 'bad')), [id, toast])
  useEffect(() => { load() }, [load])
  const refresh = () => { load(); onChanged() }
  const boss = !!(me.crew?.is_capo || me.crew?.is_co_capo)
  const attackPower = force.thugs * 10 + force.mercs * 60

  async function attack() {
    const r = await run(() => api.attackBlock(id, force.thugs, force.mercs), { silent: true })
    if (r) { setResult(r); setIntel(null); setForce(f => ({ thugs: Math.min(f.thugs, Math.max(0, thugs - r.lost_thugs)), mercs: Math.min(f.mercs, Math.max(0, mercs - r.lost_mercs)) })); refresh() }
  }

  if (result) {
    const title = result.captured ? 'Block taken!' : result.success ? 'Hit landed' : 'Pushed back'
    return (
      <Modal title={title} onClose={() => setResult(null)}>
        <div className="stack">
          <div>Your {num(result.attack)} attack against {num(result.resistance)} resistance.</div>
          {result.success && !result.captured && result.wins !== null && (
            <div className="notice gold">Siege {num(result.wins)}/{num(result.wins_needed)} — {num(result.wins_needed - result.wins)} more hits takes it. Their bonus clock restarted.</div>
          )}
          <div className="small muted">
            Lost {num(result.lost_thugs)} thugs and {num(result.lost_mercs)} mercenaries.{result.garrison_lost ? ` Took out ${num(result.garrison_lost)} of their guards.` : ''}{result.claim_paid ? ` Paid ${money(result.claim_paid)} to claim the block.` : ''}
          </div>
        </div>
      </Modal>
    )
  }

  return (
    <Modal title={b ? `${b.hood} — ${slotName(b)}` : 'Block'} onClose={onClose}>
      {!b ? <Empty><span className="spin" /></Empty> : (
        <div className="stack">
          <div className="small muted">
            {b.owner ? <>Held by {b.owner.emblem} <b>{b.owner.name}</b>{b.taken_at ? ` · taken ${ago(b.taken_at)}` : ''}.{!b.mine && (b.garrisoned ? ' There is a garrison — send a spy to size it up.' : ' No garrison.')}</>
              : <>Unclaimed. Taking it costs {money(b.claim_price)} on top of beating the base resistance of {num(b.base_resistance)}.</>}
          </div>
          {b.owner && (
            <div className="grid2">
              <div className="stat"><div className="k">Next bonus</div><div className="v">⏱ {timeLeft(b.bonus_at, now)}</div></div>
              <div className="stat"><div className="k">Bonus</div><div className="v gold">{money(b.block_bonus)}</div></div>
            </div>
          )}
          {b.garrison && Object.keys(b.garrison).length > 0 && (
            <div className="hstack">{Object.entries(b.garrison).map(([k, v]) => <span key={k} className="pill">{hoodlumIcon[k]} {num(v)} {k}</span>)}</div>
          )}
          {intel && (
            <div className="notice blue">Your spy reports resistance <b>{num(intel.resistance)}</b>: {Object.entries(intel.garrison).length === 0 ? 'no garrison' : Object.entries(intel.garrison).map(([k, v]) => `${num(v)} ${k}`).join(', ')}.</div>
          )}

          {b.siege.length > 0 && (
            <>
              <h2>Siege</h2>
              {b.siege.map(s => (
                <div key={s.crew_id} className="stack" style={{ gap: 3 }}>
                  <div className="spread small"><span>{s.emblem} {s.crew}{s.mine ? ' (you)' : ''}</span><span className="tabular">{num(s.wins)}/{num(rules.siege_wins)}</span></div>
                  <div className="siegebar"><div className={s.mine ? 'mine' : ''} style={{ width: `${Math.min(100, (s.wins / rules.siege_wins) * 100)}%` }} /></div>
                </div>
              ))}
            </>
          )}

          {b.mine ? (
            <>
              <h2>Station hoodlums</h2>
              <div className="hstack">
                <select className="input" style={{ width: 'auto' }} value={station.code} onChange={e => setStation({ ...station, code: e.target.value })}>
                  {['thug', 'enforcer', 'mercenary'].map(k => <option key={k} value={k}>{k} ({num(me.hoodlums[k] ?? 0)})</option>)}
                </select>
                <Qty value={station.n} onChange={n => setStation({ ...station, n })} min={1} max={Math.max(1, me.hoodlums[station.code] ?? 0)} />
                <Btn className="sm gold" disabled={(me.hoodlums[station.code] ?? 0) < station.n} onClick={async () => { await run(() => api.stationHoodlums(b.id, station.code, station.n), { ok: () => 'Stationed' }); refresh() }}>Station</Btn>
              </div>
              {boss && b.garrison && Object.keys(b.garrison).length > 0 && (
                <div className="hstack">
                  {Object.entries(b.garrison).map(([k, v]) => (
                    <Btn key={k} className="sm ghost" onClick={async () => { await run(() => api.withdrawGarrison(b.id, k, v), { ok: () => 'Withdrawn to your pool' }); refresh() }}>Pull {num(v)} {k}</Btn>
                  ))}
                </div>
              )}
            </>
          ) : me.crew ? (
            <>
              <h2>Attack with</h2>
              <div className="grid2">
                <label className="f">🧢 Thugs (min {rules.min_thugs}) · have {num(thugs)}<input className="input" inputMode="numeric" value={force.thugs} onChange={e => setForce({ ...force, thugs: Math.min(thugs, Number(e.target.value) || 0) })} /></label>
                <label className="f">🔫 Mercenaries · have {num(mercs)}<input className="input" inputMode="numeric" value={force.mercs} onChange={e => setForce({ ...force, mercs: Math.min(mercs, Number(e.target.value) || 0) })} /></label>
              </div>
              <div className="small muted">
                Attack ≈ <b>{num(attackPower)}</b> (±10%) · {rules.stamina} stamina. {b.owner ? `Every win counts toward your crew's ${rules.siege_wins} and restarts their bonus clock.` : 'One win claims it.'}
              </div>
              {(me.hospital || me.jailed) && <div className="notice red">{me.hospital ? "You're in the hospital — heal up before you attack." : "You can't run a turf war from jail."}</div>}
              {thugs < rules.min_thugs && <div className="notice red">You need at least {rules.min_thugs} thugs to start a turf attack. <a onClick={() => nav('/services')}>Hire more →</a></div>}
              <div className="hstack">
                <Btn className="doit red" disabled={force.thugs < rules.min_thugs || me.jailed || me.hospital || me.stamina < rules.stamina} onClick={attack}>Attack</Btn>
                <Btn className="sm" disabled={spies < 1} onClick={async () => { const r = await run(() => api.spyBlock(b.id), { silent: true }); if (r) setIntel(r) }}>🕶 Spy ({num(spies)})</Btn>
              </div>
            </>
          ) : null}

          <h2>Attack log</h2>
          <div className="card">
            {b.log.length === 0 && <Empty>No one has hit this block yet.</Empty>}
            {b.log.map(l => <LogRow key={l.id} l={l} />)}
          </div>
        </div>
      )}
    </Modal>
  )
}
