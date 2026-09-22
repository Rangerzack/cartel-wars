import { useCallback, useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useGame, useMe } from '../lib/game'
import { api } from '../lib/api'
import { ago, hoodlumIcon, money, num } from '../lib/format'
import { Btn, Card, Empty, Modal, Qty, Seg } from '../components/ui'
import type { Block, Hood, Island, TerritoryLog } from '../lib/types'

export default function Territory() {
  const me = useMe()
  const { run, toast } = useGame()
  const nav = useNavigate()
  const [islands, setIslands] = useState<Island[] | null>(null)
  const [log, setLog] = useState<TerritoryLog[] | null>(null)
  const [isl, setIsl] = useState(0)
  const [selId, setSelId] = useState<{ hood: number; block: number } | null>(null)
  const [force, setForce] = useState({ thugs: 0, mercs: 0 })
  const [station, setStation] = useState({ code: 'thug', n: 1 })
  const [intel, setIntel] = useState<{ garrison: Record<string, number>; resistance: number } | null>(null)
  const [result, setResult] = useState<{ success: boolean; attack: number; resistance: number; lost_thugs: number; lost_mercs: number; claim_paid: number } | null>(null)

  const load = useCallback(() => Promise.all([api.territory(), api.territoryLog(15)]).then(([t, l]) => { setIslands(t); setLog(l) }).catch(e => toast(e.message, 'bad')), [toast])
  useEffect(() => { load() }, [load])

  if (!islands) return <Empty><span className="spin" /></Empty>
  // derive the selected block from the freshest territory data
  const sel: { hood: Hood; block: Block } | null = (() => {
    if (!selId) return null
    const h = islands.flatMap(i => i.hoods).find(h => h.id === selId.hood)
    const b = h?.blocks.find(b => b.id === selId.block)
    return h && b ? { hood: h, block: b } : null
  })()
  const setSel = (v: { hood: Hood; block: Block } | null) => setSelId(v ? { hood: v.hood.id, block: v.block.id } : null)
  const thugs = me.hoodlums.thug ?? 0, mercs = me.hoodlums.mercenary ?? 0, spies = me.hoodlums.spy ?? 0
  const island = islands[isl]
  const attackPower = force.thugs * 10 + force.mercs * 60

  async function attack() {
    if (!sel) return
    const r = await run(() => api.attackBlock(sel.block.id, force.thugs, force.mercs), { silent: true })
    if (r) { setResult(r); setIntel(null); setSel(null); load() }
  }

  return (
    <div className="page">
      {!me.crew && <div className="notice blue">Territory is held by crews. <a onClick={() => nav('/crew')}>Join or found a crew</a> to fight for blocks.</div>}
      <div className="grid3" style={{ gridTemplateColumns: 'repeat(3, 1fr)' }}>
        {(['thug', 'mercenary', 'spy'] as const).map(k => (
          <div key={k} className="stat"><div className="k">{hoodlumIcon[k]} {k === 'mercenary' ? 'Mercenaries' : k === 'spy' ? 'Spies' : 'Thugs'}</div><div className="v">{num(me.hoodlums[k] ?? 0)}</div></div>
        ))}
      </div>
      <Seg value={String(isl)} onChange={v => setIsl(Number(v))} options={islands.map((i, n) => ({ v: String(n), l: i.island }))} />

      {island.hoods.map(h => (
        <Card key={h.id} title={<>{h.name} {h.owner && <span className="small muted">· held by {h.owner.emblem} {h.owner.name}</span>}</>} right={<small className="gold">{money(h.daily_income)}/day</small>}>
          <div className="blocks">
            {h.blocks.map(b => (
              <div key={b.id} className={`block ${b.mine ? 'mine' : b.owner ? 'enemy' : ''} ${sel?.block.id === b.id ? 'sel' : ''}`} onClick={() => { setSel({ hood: h, block: b }); setIntel(null) }}>
                <div className="em">{b.owner ? b.owner.emblem : '\u00a0'}</div>
                <div>{b.name.split('— ')[1] ?? b.name}</div>
                <div className="muted" style={{ fontSize: 10 }}>{b.owner ? (b.garrison_size !== null ? `${num(b.garrison_size)} guards` : b.garrisoned ? 'guarded' : 'unguarded') : money(b.claim_price)}</div>
              </div>
            ))}
          </div>
          <div className="row small muted">Base resistance {num(h.base_resistance)} · hold 3 of 4 blocks to own the hood.</div>
        </Card>
      ))}

      {sel && (
        <Modal title={sel.block.name} onClose={() => setSel(null)}>
          <div className="stack">
            <div className="small muted">
              {sel.block.owner ? <>Held by {sel.block.owner.emblem} {sel.block.owner.name}{sel.block.garrison_size !== null ? ` with ${num(sel.block.garrison_size)} hoodlums stationed.` : sel.block.garrisoned ? ' — there is a garrison. Send a spy to size it up.' : ' — no garrison.'}</> : <>Unclaimed. Taking it costs {money(sel.block.claim_price)} on top of beating the base resistance of {num(sel.hood.base_resistance)}.</>}
            </div>
            {sel.block.garrison && (
              <div className="hstack">{Object.entries(sel.block.garrison).map(([k, v]) => <span key={k} className="pill">{hoodlumIcon[k]} {num(v)} {k}</span>)}</div>
            )}
            {intel && (
              <div className="notice blue">Your spy reports resistance <b>{num(intel.resistance)}</b>: {Object.entries(intel.garrison).length === 0 ? 'no garrison' : Object.entries(intel.garrison).map(([k, v]) => `${num(v)} ${k}`).join(', ')}.</div>
            )}

            {sel.block.mine ? (
              <>
                <h2>Station hoodlums</h2>
                <div className="hstack">
                  <select className="input" style={{ width: 'auto' }} value={station.code} onChange={e => setStation({ ...station, code: e.target.value })}>
                    {['thug', 'enforcer', 'mercenary'].map(k => <option key={k} value={k}>{k} ({num(me.hoodlums[k] ?? 0)})</option>)}
                  </select>
                  <Qty value={station.n} onChange={n => setStation({ ...station, n })} min={1} max={Math.max(1, me.hoodlums[station.code] ?? 0)} />
                  <Btn className="sm gold" disabled={(me.hoodlums[station.code] ?? 0) < station.n} onClick={async () => { await run(() => api.stationHoodlums(sel.block.id, station.code, station.n), { ok: () => 'Stationed' }); load() }}>Station</Btn>
                </div>
                {me.crew?.is_capo && sel.block.garrison && Object.keys(sel.block.garrison).length > 0 && (
                  <div className="hstack">
                    {Object.entries(sel.block.garrison).map(([k, v]) => (
                      <Btn key={k} className="sm ghost" onClick={async () => { await run(() => api.withdrawGarrison(sel.block.id, k, v), { ok: () => 'Withdrawn to your pool' }); load() }}>Pull {num(v)} {k}</Btn>
                    ))}
                  </div>
                )}
              </>
            ) : me.crew ? (
              <>
                <h2>Attack with</h2>
                <div className="grid2">
                  <label className="f">🧢 Thugs (10 att) · have {num(thugs)}<input className="input" inputMode="numeric" value={force.thugs} onChange={e => setForce({ ...force, thugs: Math.min(thugs, Number(e.target.value) || 0) })} /></label>
                  <label className="f">🔫 Mercenaries (60 att) · have {num(mercs)}<input className="input" inputMode="numeric" value={force.mercs} onChange={e => setForce({ ...force, mercs: Math.min(mercs, Number(e.target.value) || 0) })} /></label>
                </div>
                <div className="small muted">Attack strength ≈ <b>{num(attackPower)}</b> (±10%). Costs 3 stamina; you need at least a quarter of the block's resistance to even get a fight. Losses on both sides scale with how close it was. Spies reveal the exact resistance.</div>
                <div className="hstack">
                  <Btn className="doit red" disabled={attackPower === 0 || me.jailed || me.stamina < 3} onClick={attack}>Attack</Btn>
                  <Btn className="sm" disabled={spies < 1} onClick={async () => { const r = await run(() => api.spyBlock(sel.block.id), { silent: true }); if (r) setIntel(r) }}>🕶 Send a Spy ({num(spies)})</Btn>
                  {thugs + mercs === 0 && <Btn className="sm ghost" onClick={() => nav('/services')}>Hire hoodlums</Btn>}
                </div>
              </>
            ) : null}
          </div>
        </Modal>
      )}

      {result && (
        <Modal title={result.success ? 'Block taken!' : 'Pushed back'} onClose={() => setResult(null)}>
          <div className="stack">
            <div>Your {num(result.attack)} attack against {num(result.resistance)} resistance.</div>
            <div className="small muted">Lost {num(result.lost_thugs)} thugs and {num(result.lost_mercs)} mercenaries.{result.claim_paid ? ` Paid ${money(result.claim_paid)} to claim the block.` : ''}</div>
          </div>
        </Modal>
      )}

      <h2>Recent turf wars</h2>
      <Card>
        {log?.length === 0 && <Empty>The streets are quiet.</Empty>}
        {log?.map(l => (
          <div key={l.id} className="row">
            <span>{l.success ? '🏴' : '💥'}</span>
            <div className="grow"><div className="t">{l.crew ?? l.attacker} {l.success ? 'took' : 'failed at'} {l.block}</div><div className="s">{num(l.attack)} vs {num(l.resistance)} · {ago(l.at)}</div></div>
          </div>
        ))}
      </Card>
    </div>
  )
}
