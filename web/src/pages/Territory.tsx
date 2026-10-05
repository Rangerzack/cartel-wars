import { useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { useGame, useMe } from '../lib/game'
import { api } from '../lib/api'
import { ago, hoodlumIcon, hoodlumName, money, num, timeLeft, toInt } from '../lib/format'
import { useNow } from '../lib/useNow'
import { Btn, Card, Empty, Loading, Modal, Qty, RowLink } from '../components/ui'
import { HireHoodlums } from '../components/Hire'
import type { AttackBlockResult, Block, BlockDetail, BusinessCode, Hood, Territory as TerritoryData, TerritoryLog } from '../lib/types'
import { businessDef, perkLabel } from '../lib/perks'
import { BackBar } from '../components/BackBar'
import { useLoad } from '../lib/useLoad'
import { haptic } from '../lib/haptics'

const ROWS = 'ABCDEFGHI'
const coord = (h: { gx: number; gy: number }) => `${ROWS[h.gy - 1]}${h.gx}`
const ring = (h: { gx: number; gy: number }) => Math.max(Math.abs(h.gx - 5), Math.abs(h.gy - 5))
const slotName = (b: { slot: number }) => `Block ${String.fromCharCode(64 + b.slot)}`

export default function Territory() {
  const me = useMe()
  const [sp, setSp] = useSearchParams()
  const { catalog } = useGame()
  // ?hood=12 opens a hood; &block=70 also opens that block (links from the activity feed)
  const [blockId, setBlockId] = useState<number | null>(() => Number(sp.get('block')) || null)
  // which hoodlum the hire panel under the tiles is open on (?hire=thug opens it from a link)
  const [hire, setHire] = useState<string | null>(() => sp.get('hire'))
  const hoodId = Number(sp.get('hood')) || null
  // highlight one business across the city (?biz=gym); kept in the URL so Back keeps it, read from the catalog's list
  // so a made-up code doesn't dim the whole map
  const bizParam = sp.get('biz')
  const biz = (catalog?.businesses?.some(b => b.code === bizParam) ? bizParam : null) as BusinessCode | null

  // the map and the log load together; a failed load gets a Retry rather than a spinner that stays
  const { data: both, error, reload: load } = useLoad(() => Promise.all([api.territory(), api.territoryLog(15)]))
  const data = both?.[0] ?? null, log = both?.[1] ?? null
  // the crews in my cartel: their blocks are allies' (attack_block refuses them), drawn and described as such
  const cartelId = me.cartel?.id ?? ''
  const { data: cartel } = useLoad(() => (cartelId ? api.cartel(cartelId) : Promise.resolve(null)), cartelId)
  const allies = new Set((cartel?.crews ?? []).map(c => c.id))

  if (!data) return <div className="page"><BackBar fallback="/" /><Loading error={error} onRetry={load} /></div>
  const hood = hoodId ? data.hoods.find(h => h.id === hoodId) ?? null : null
  const thugs = me.hoodlums.thug ?? 0, mercs = me.hoodlums.mercenary ?? 0, spies = me.hoodlums.spy ?? 0
  const openHood = (id: number) => setSp({ hood: String(id), ...(biz ? { biz } : {}) })
  // a filter change replaces the entry: Back leaves Territory rather than undoing each filter
  const setBiz = (b: string) => setSp(b ? { biz: b } : {}, { replace: true })
  const bizList = catalog?.businesses ?? []

  return (
    <div className="page">
      {/* opening a hood pushes ?hood=, so Back is a history step: to the city, or to the page that linked the hood (a
          crew's perks or blocks). A hood opened from outside the app falls back to the city, keeping a business highlight. */}
      {hood
        ? <BackBar fallback={biz ? `/territory?biz=${biz}` : '/territory'} right={<span className="muted small">{hood.district} · {coord(hood)}</span>} />
        : <BackBar fallback="/" />}
      {!me.crew && <div className="notice blue">Territory is held by crews. <Link to="/crew">Join or found a crew</Link> to fight for blocks.</div>}
      {/* the tiles are the hire buttons: hoodlums are bought where they're used, not two pages away */}
      <div className="grid3">
        {(['thug', 'mercenary', 'spy'] as const).map(k => (
          <button key={k} type="button" className={`stat stat-btn ${hire === k ? 'on' : ''}`} aria-expanded={hire === k} onClick={() => setHire(hire === k ? null : k)}>
            <div className="k">{hoodlumIcon[k]} {k === 'mercenary' ? 'Mercs' : k === 'spy' ? 'Spies' : 'Thugs'}</div><div className="v">{num(me.hoodlums[k] ?? 0)}</div>
            <span className="stat-add">+ Hire</span>
          </button>
        ))}
      </div>
      {hire ? (
        <Card title="🧢 Hire hoodlums" right={<button type="button" className="btn sm ghost" onClick={() => setHire(null)}>Done</button>}>
          <div className="bd"><HireHoodlums key={hire} initial={{ code: hire, n: hire === 'thug' ? Math.max(10, (data?.rules.min_thugs ?? 51) - thugs) : 5 }} /></div>
        </Card>
      ) : <div className="small muted">Thugs and mercs attack blocks; spies size up a garrison. Tap one to hire more.</div>}

      {hood ? (
        <HoodView hood={hood} onBlock={setBlockId} biz={biz} allies={allies} siegeWins={data.rules.siege_wins} />
      ) : (
        <>
          <Card title="The City">
            <div className="bd">
              {bizList.length > 0 && (
                <select className="input biz-filter" value={biz ?? ''} onChange={e => setBiz(e.target.value)} aria-label="Show a business">
                  <option value="">All businesses</option>
                  {bizList.map(d => <option key={d.code} value={d.code}>{d.icon} {d.name} — {d.perk}</option>)}
                </select>
              )}
              <div className="hoodgrid">
                <span />
                {Array.from({ length: 9 }, (_, i) => <span key={i} className="axis">{i + 1}</span>)}
                {Array.from({ length: 9 }, (_, y) => (
                  <Row key={y} y={y + 1} hoods={data.hoods.filter(h => h.gy === y + 1)} onOpen={openHood} biz={biz} />
                ))}
              </div>
              <div className="small muted city-hint">Tap a hood to see its six blocks.</div>
              <div className="legend small muted">
                <span><i className="mine" /> your crew</span><span><i className="enemy" /> rival</span><span><i /> unclaimed</span><span><i className="siege" /> under your siege</span>
                {biz && <span><i className="biz" /> {businessDef(catalog, biz)?.name}</span>}
              </div>
            </div>
          </Card>
          <div className="small muted">
            Every block is a business, and your crew gets its perk while it holds the block: one of each kind per hood, stronger toward the center,
            ×1.5 when your crew holds the whole hood (×1.75 in a cartel). More of the same business adds a little, up to double your best one.
            Hoods pay more toward the center. Each block pays its bonus every {data.rules.bonus_hours}h. A turf attack needs at least {data.rules.min_thugs} thugs and {data.rules.stamina} stamina.
            Empty blocks fall to one win; a held block falls after your crew lands {data.rules.siege_wins} successful hits — and every hit restarts the owner's bonus clock.
          </div>

          <h2>Recent turf wars</h2>
          <Card>
            {log?.length === 0 && <Empty>The streets are quiet.</Empty>}
            {log?.map(l => <LogRow key={l.id} l={l} showBlock siegeWins={data.rules.siege_wins} onOpen={() => { openHood(l.hood_id); setBlockId(l.block_id) }} />)}
          </Card>
        </>
      )}

      {blockId !== null && (
        <BlockModal id={blockId} rules={data.rules} thugs={thugs} mercs={mercs} spies={spies} allies={allies}
          onClose={() => setBlockId(null)} onChanged={load} />
      )}
    </div>
  )
}

function Row({ y, hoods, onOpen, biz }: { y: number; hoods: Hood[]; onOpen: (id: number) => void; biz: BusinessCode | null }) {
  return (
    <>
      <span className="axis">{ROWS[y - 1]}</span>
      {hoods.sort((a, b) => a.gx - b.gx).map(h => {
        const sieging = h.blocks.some(b => b.my_wins > 0)
        const hit = biz ? h.blocks.some(b => b.business === biz) : false
        return (
          <button key={h.id} className={`hcell r${ring(h)} ${h.owner ? (h.my_blocks >= 4 ? 'own-mine' : 'own-enemy') : ''} ${biz ? (hit ? 'biz-hit' : 'biz-dim') : ''}`} title={`${h.name} (${coord(h)})`} onClick={() => onOpen(h.id)}>
            <span className="mini">
              {h.blocks.map(b => <i key={b.id} className={`${b.mine ? 'mine' : b.owner ? 'enemy' : ''} ${b.my_wins > 0 ? 'siege' : ''} ${biz && b.business === biz ? 'biz' : ''}`} />)}
            </span>
            <span className="lbl">{h.owner ? h.owner.emblem : sieging ? '⚔️' : coord(h)}</span>
          </button>
        )
      })}
    </>
  )
}

function HoodView({ hood, onBlock, biz, allies, siegeWins }: { hood: Hood; onBlock: (id: number) => void; biz: BusinessCode | null; allies: Set<string>; siegeWins: number }) {
  const now = useNow()
  return (
    <>
      <Card title={<>{hood.name} {hood.owner && <span className="small muted">· held by {hood.owner.emblem} {hood.owner.name}</span>}</>} right={<small className="gold">{money(hood.block_bonus)}/block</small>}>
        <div className="blocks6">
          {hood.blocks.map(b => <BlockTile key={b.id} b={b} hood={hood} now={now} onClick={() => onBlock(b.id)} hl={!!biz && b.business === biz} ally={!!b.owner && !b.mine && allies.has(b.owner.id)} siegeWins={siegeWins} />)}
        </div>
        {hood.full_hood && <div className="row small"><span className="pill gold nowrap">★ Full hood</span><span className="muted"> {(hood.owner ?? hood.blocks[0]?.owner)?.name} holds all six — every business here counts ×1.5 for them (×1.75 in a cartel).</span></div>}
        <div className="row small muted">
          Base resistance {num(hood.base_resistance)} · empty blocks cost {money(hood.claim_price)} to claim · hold 4 of 6 to own the hood, all 6 for the full-hood bonus.
        </div>
      </Card>
    </>
  )
}

function BlockTile({ b, hood, now, onClick, hl, ally, siegeWins }: { b: Block; hood: Hood; now: number; onClick: () => void; hl: boolean; ally: boolean; siegeWins: number }) {
  const { catalog } = useGame()
  const d = businessDef(catalog, b.business)
  return (
    // a button, so the tile takes focus and VoiceOver reads it; drawn as the tile it was
    <button type="button" className={`block ${b.mine ? 'mine' : ally ? 'ally' : b.owner ? 'enemy' : ''} ${hl ? 'biz-hl' : ''}`} onClick={onClick}
      aria-label={`${slotName(b)}${b.owner ? `, held by ${b.owner.name}${b.mine ? ' (your crew)' : ally ? ' (your cartel)' : ''}` : ', unclaimed'}`}>
      <div className="em">{b.owner ? b.owner.emblem : ' '}{ally && <span className="small muted"> ally</span>}</div>
      {d ? <div className="biz-name"><span>{d.icon}</span> <b>{d.name}</b></div> : <div><b>{slotName(b)}</b></div>}
      {/* the perk on the tile itself, not in a tooltip a touch screen never shows */}
      {d && <div className="small muted biz-perk">{d.perk}</div>}
      {b.owner ? (
        <>
          <div className="small tabular">⏱ {timeLeft(b.bonus_at, now)}</div>
          <div className="small muted">{b.garrison_size !== null ? `${num(b.garrison_size)} guards` : b.garrisoned ? 'guarded' : 'unguarded'}</div>
          {b.top_wins > 0 && <div className="siegebar"><div style={{ width: `${Math.min(100, (b.top_wins / siegeWins) * 100)}%` }} className={b.my_wins > 0 && b.my_wins === b.top_wins ? 'mine' : ''} /></div>}
          {b.my_wins > 0 && <div className="small gold">your siege {b.my_wins}/{siegeWins}</div>}
        </>
      ) : <div className="small muted">{money(hood.claim_price)}</div>}
    </button>
  )
}

function LogRow({ l, showBlock, onOpen, siegeWins }: { l: TerritoryLog; showBlock?: boolean; onOpen?: () => void; siegeWins: number }) {
  const what = l.captured ? (l.defender_crew ? `took it from ${l.defender_crew}` : 'claimed it') : l.success ? `landed a hit${l.siege_wins ? ` (${l.siege_wins}/${siegeWins})` : ''}` : 'was pushed back'
  const inner = <>
    <span>{l.captured ? '🏴' : l.success ? '🎯' : '💥'}</span>
    <div className="grow">
      <div className="t">{l.crew_emblem} {l.attacker ?? <span className="muted">Deleted player</span>} {what}{showBlock ? <span className="muted"> · {l.block}</span> : null}</div>
      <div className="s">{num(l.attack)} vs {num(l.resistance)} · {num(l.thugs)} thugs{l.mercs ? `, ${num(l.mercs)} mercs` : ''} · lost {num(l.lost_thugs + l.lost_mercs)}{l.garrison_lost ? ` · killed ${num(l.garrison_lost)} guards` : ''} · {ago(l.at)}</div>
    </div>
  </>
  return onOpen ? <RowLink onClick={onOpen}>{inner}</RowLink> : <div className="row">{inner}</div>
}

function BlockModal({ id, rules, thugs, mercs, spies, allies, onClose, onChanged }: {
  id: number; rules: TerritoryData['rules']; thugs: number; mercs: number; spies: number; allies: Set<string>; onClose: () => void; onChanged: () => void
}) {
  const me = useMe()
  const { run, askRefill, ask } = useGame()
  const [spyOpen, setSpyOpen] = useState(false)
  const now = useNow()
  const [force, setForce] = useState({ thugs: Math.min(thugs, rules.min_thugs), mercs: 0 })
  const [station, setStation] = useState({ code: 'thug', n: 1 })
  const [intel, setIntel] = useState<{ garrison: Record<string, number>; resistance: number } | null>(null)
  const [result, setResult] = useState<AttackBlockResult | null>(null)
  const [moreOpen, setMoreOpen] = useState(false)
  const { data: b, error, reload: load } = useLoad(() => api.block(id), String(id))
  const refresh = () => { load(); onChanged() }
  const boss = !!(me.crew?.is_capo || me.crew?.is_co_capo)
  const attackPower = force.thugs * 10 + force.mercs * 60

  async function attack() {
    const r = await run(() => api.attackBlock(id, force.thugs, force.mercs), { silent: true })
    if (r) { haptic(r.captured ? 'success' : r.success ? 'medium' : 'error'); setResult(r); setIntel(null); setForce(f => ({ thugs: Math.min(f.thugs, Math.max(0, thugs - r.lost_thugs)), mercs: Math.min(f.mercs, Math.max(0, mercs - r.lost_mercs)) })); refresh() }
  }

  const ally = !!(b?.owner && !b.mine && allies.has(b.owner.id))
  // the result stays in the sheet, above the form: the next hit is one tap (Attack again) with nothing scrolled away
  const resultLine = result && (
    <div className={`notice ${result.success ? 'gold' : 'red'} attack-result`} role="status">
      <b>{result.captured ? 'Block taken' : result.success ? 'Hit landed' : 'Pushed back'}</b> — your {num(result.attack)} attack against {num(result.resistance)} resistance.
      {result.success && !result.captured && result.wins !== null && <> Siege {num(result.wins)}/{num(result.wins_needed)}: {num(result.wins_needed - result.wins)} more hit{result.wins_needed - result.wins === 1 ? '' : 's'} takes it, and their bonus clock restarted.</>}
      {' '}Lost {num(result.lost_thugs)} thugs and {num(result.lost_mercs)} mercs.{result.garrison_lost ? ` Took out ${num(result.garrison_lost)} of their guards.` : ''}{result.claim_paid ? ` Paid ${money(result.claim_paid)} to claim it.` : ''}
    </div>
  )

  return (
    <Modal title={b ? `${b.hood} — ${slotName(b)}` : 'Block'} onClose={onClose}>
      {!b ? <Loading error={error} onRetry={load} /> : (
        <div className="stack">
          {resultLine}
          <div className="small muted">
            {b.owner ? <>Held by {b.owner.emblem} <b>{b.owner.name}</b>{ally ? ' (your cartel)' : ''}{b.taken_at ? ` · taken ${ago(b.taken_at, now)}` : ''}.{!b.mine && !ally && (b.garrisoned ? ' There is a garrison — send a spy to size it up.' : ' No garrison.')}</>
              : <>Unclaimed. Taking it costs {money(b.claim_price)} on top of beating the base resistance of {num(b.base_resistance)}.</>}
          </div>
          {b.business && <BusinessPanel b={b} />}
          {b.owner && (
            <div className="grid2">
              <div className="stat"><div className="k">Next bonus</div><div className="v">⏱ {timeLeft(b.bonus_at, now)}</div></div>
              <div className="stat"><div className="k">Bonus</div><div className="v gold">{money(b.block_bonus)}</div></div>
            </div>
          )}
          {b.garrison && Object.keys(b.garrison).length > 0 && (
            <div className="hstack">{Object.entries(b.garrison).map(([k, v]) => <span key={k} className="pill">{hoodlumIcon[k]} {num(v)} {hoodlumName(k, v)}</span>)}</div>
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
                    <Btn key={k} className="sm ghost" onClick={async () => {
                      if (!await ask(`The block keeps only its base resistance until someone stations guards again.`, { title: `Pull ${num(v)} ${hoodlumName(k, v)} off ${slotName(b)}?`, yes: 'Pull them' })) return
                      await run(() => api.withdrawGarrison(b.id, k, v), { ok: () => 'Withdrawn to your pool' }); refresh()
                    }}>Pull {num(v)} {hoodlumName(k, v)}</Btn>
                  ))}
                </div>
              )}
            </>
          ) : ally ? (
            <div className="notice blue">Same cartel — no attacks on allies. Hit a rival crew's block instead.</div>
          ) : !me.crew ? (
            <div className="notice blue">Turf is held by crews. <Link to="/crew" onClick={onClose}>Join or found a crew →</Link> to attack and hold blocks.</div>
          ) : (
            <>
              <h2>Attack with</h2>
              <div className="grid2">
                <label className="f">🧢 Thugs (min {rules.min_thugs}) · have {num(thugs)}<input className="input" inputMode="numeric" value={force.thugs} onChange={e => setForce({ ...force, thugs: Math.min(thugs, toInt(e.target.value)) })} /></label>
                <label className="f">🔫 Mercenaries · have {num(mercs)}<input className="input" inputMode="numeric" value={force.mercs} onChange={e => setForce({ ...force, mercs: Math.min(mercs, toInt(e.target.value)) })} /></label>
              </div>
              <div className="small muted">
                Attack ≈ <b>{num(attackPower)}</b> (±10%) · {rules.stamina} stamina. {b.owner ? `Every win counts toward your crew's ${rules.siege_wins} and restarts their bonus clock.` : 'One win claims it.'}
              </div>
              {(me.hospital || me.jailed) && <div className="notice red">{me.hospital ? "You're in the hospital — heal up before you attack." : "You can't run a turf war from jail."}</div>}
              {!b.owner && me.cash < b.claim_price && <div className="why">Claiming it costs {money(b.claim_price)} on hand — you have {money(me.cash)}.</div>}
              {thugs < rules.min_thugs ? (
                <div className="hire-inline">
                  <div className="small"><b>You need {num(rules.min_thugs)} thugs</b> to start a turf attack — you have {num(thugs)}. Hire the rest here; they join this attack.</div>
                  <HireHoodlums kinds={['thug', 'mercenary']} btnClass="gold" initial={{ code: 'thug', n: rules.min_thugs - thugs }}
                    onHired={(code, n) => setForce(f => code === 'thug' ? { ...f, thugs: Math.max(f.thugs, Math.min(thugs + n, rules.min_thugs)) } : { ...f, mercs: f.mercs + n })} />
                </div>
              ) : !moreOpen ? (
                <button type="button" className="linkbtn small" onClick={() => setMoreOpen(true)}>🧢 Hire more thugs or mercs</button>
              ) : (
                <div className="hire-inline">
                  <HireHoodlums kinds={['thug', 'mercenary']} btnClass="gold"
                    onHired={(code, n) => setForce(f => code === 'thug' ? { ...f, thugs: f.thugs + n } : { ...f, mercs: f.mercs + n })} />
                </div>
              )}
              <div className="hstack">
                <Btn className="doit red" disabled={force.thugs < rules.min_thugs || me.jailed || me.hospital || (!b.owner && me.cash < b.claim_price)} onClick={() => me.stamina < rules.stamina ? askRefill(rules.stamina) : attack()}>{result ? 'Attack Again' : 'Attack'}</Btn>
                {spies > 0
                  ? <Btn className="sm" onClick={async () => { const r = await run(() => api.spyBlock(b.id), { silent: true }); if (r) setIntel(r) }}>🕶 Spy ({num(spies)})</Btn>
                  : <button type="button" className="btn sm ghost" aria-expanded={spyOpen} onClick={() => setSpyOpen(v => !v)}>🕶 No Spies · Hire</button>}
              </div>
              {intel && (
                <div className="notice blue" role="status">Your spy reports resistance <b>{num(intel.resistance)}</b>: {Object.entries(intel.garrison).length === 0 ? 'no garrison' : Object.entries(intel.garrison).map(([k, v]) => `${num(v)} ${hoodlumName(k, v)}`).join(', ')}.</div>
              )}
              {spyOpen && spies === 0 && (
                <div className="hire-inline">
                  <div className="small">A spy sizes up a garrison before you commit thugs to it.</div>
                  <HireHoodlums kinds={['spy']} btnClass="gold" initial={{ code: 'spy', n: 1 }} onHired={() => setSpyOpen(false)} />
                </div>
              )}
            </>
          )}

          <h2>Attack log</h2>
          <div className="card">
            {b.log.length === 0 && <Empty>No one has hit this block yet.</Empty>}
            {b.log.map(l => <LogRow key={l.id} l={l} siegeWins={rules.siege_wins} />)}
          </div>
        </div>
      )}
    </Modal>
  )
}

/** What this block's business does, what it's worth here, and who's getting it. */
function BusinessPanel({ b }: { b: BlockDetail }) {
  const biz = b.business!
  const code = biz.code
  return (
    <div className="biz-panel">
      <div className="spread"><b>{biz.icon} {biz.name}</b><span className="small muted">{biz.perk}</span></div>
      <div className="grid3 biz-values">
        <div className="stat"><div className="k">This block</div><div className="v sm">{perkLabel(code, biz.value)}</div></div>
        <div className="stat"><div className="k">Full hood</div><div className="v sm">{perkLabel(code, biz.value_full)}</div></div>
        <div className="stat"><div className="k">+ cartel</div><div className="v sm">{perkLabel(code, biz.value_full_cartel)}</div></div>
      </div>
      <div className="small muted">
        {b.owner && biz.owner_total != null
          ? <>{b.mine ? 'Your crew' : `${b.owner.emblem} ${b.owner.name}`} gets {perkLabel(code, biz.owner_value ?? 0)} from it{biz.owner_full ? ' (full hood)' : ''}, and {perkLabel(code, biz.owner_total)} from all their {biz.name}s together. </>
          : 'Nobody holds it yet. '}
        {!b.mine && biz.my_total > 0 ? <>Your crew's {biz.name} perk is {perkLabel(code, biz.my_total)}. </> : null}
        Tops out at {perkLabel(code, biz.ceiling)}.
      </div>
    </div>
  )
}
