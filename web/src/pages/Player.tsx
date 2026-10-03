import { useCallback, useEffect, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { useGame, useMe } from '../lib/game'
import { api } from '../lib/api'
import { ago, every, money, num } from '../lib/format'
import { Btn, Card, Empty, Modal, Stat } from '../components/ui'
import { BailButton } from '../components/Bail'
import { HealButton } from '../components/Heal'
import { Ribbons } from '../components/Ribbons'
import type { FightEdge, FightPreview, FightResult, PublicPlayer } from '../lib/types'
import { BackBar } from '../components/BackBar'
import { ComboPill } from '../components/Combo'
import { matchup, matchupText } from '../lib/combos'
import { ReportModal } from '../components/Report'
import { ModButtons } from './Admin'

export default function Player() {
  const { id = '' } = useParams()
  const me = useMe()
  const { run, toast, catalog, askRefill, ask } = useGame()
  const nav = useNavigate()
  const [p, setP] = useState<PublicPlayer | null>(null)
  const [result, setResult] = useState<FightResult | null>(null)
  const [amount, setAmount] = useState(0)
  const [dia, setDia] = useState(0)
  const [reporting, setReporting] = useState(false)

  const load = useCallback(() => api.player(id).then(setP).catch(e => toast(e.message, 'bad')), [id, toast])
  useEffect(() => { load() }, [load])
  // odds before you swing; quietly absent if the preview isn't available
  const [pv, setPv] = useState<FightPreview | null>(null)
  const loadPreview = useCallback(() => { if (id && id !== me.id) api.fightPreview(id).then(setPv).catch(() => setPv(null)) }, [id, me.id])
  useEffect(() => { loadPreview() }, [loadPreview])

  if (!p) return <Empty><span className="spin" /></Empty>
  const isMe = p.id === me.id
  // jail is its own room: inmates only fight inmates
  const jailWall = me.jailed !== p.jailed
  const cantFight = isMe || me.hospital || p.hospital || jailWall
  const tired = me.stamina < 2   // not a dead button: Attack offers a refill

  async function fight() {
    if (me.stamina < 2) { askRefill(2); return }
    const r = await run(() => api.attack(p!.id), { silent: true })
    if (r) setResult(r)
    // reload either way: a refusal (they just went to the hospital, say) is what disables Attack again
    load(); loadPreview()
  }
  async function block() {
    if (!await ask(`Block ${p!.name}? They can't message you and their posts are hidden. You can undo this from your Profile.`, { title: `Block ${p!.name}?`, yes: 'Block', tone: 'red' })) return
    if (await run(() => api.blockPlayer(p!.id), { ok: () => `${p!.name} blocked` })) load()
  }
  async function unblock() {
    if (await run(() => api.unblockPlayer(p!.id), { ok: () => `${p!.name} unblocked` })) load()
  }

  return (
    <div className="page">
      <BackBar fallback="/fight" />
      <Card title={<><span style={{ fontSize: 20 }}>{p.avatar}</span> {p.name} {p.crew && <span className="muted">{p.crew.emblem} {p.crew.name}</span>}</>} right={<small>seen {ago(p.last_seen)}</small>}>
        <div className="bd stack">
          {p.bio && <div className="small" style={{ fontStyle: 'italic' }}>“{p.bio}”</div>}
          <div className="hstack">
            {p.jailed && <span className="pill red">🔒 In jail</span>}
            {p.hospital && <span className="pill red">🏥 Hospital</span>}
            <span className={`pill ${p.heat_level === 'red' ? 'red' : ''}`}>🔥 heat {p.heat_level}</span>
            {p.cartel && <span className="pill gold">🕴 {p.cartel.name}</span>}
          </div>
          <Ribbons list={p.ribbons} />
          <div className="grid2">
            <Stat k="Health" v={`${num(p.health)}/${num(p.health_max)}`} />
            <Stat k="Fights" v={`${p.fights_won}W · ${p.fights - p.fights_won}L`} cls="sm" />
            <Stat k="Actions" v={num(p.actions)} />
            <Stat k="Reputation" v={`⭐ ${num(p.reputation)}`} cls="dia" />
          </div>
          {/* the actions come before the odds so Attack is on the first screen at 375 × 667 (P2-3) */}
          {!isMe && (
            <div className="hstack">
              <Btn className="doit red" disabled={cantFight} onClick={fight}>⚔️ Attack</Btn>
              <Btn className="sm" onClick={async () => nav(`/chat/${await api.dmChannel(p.id)}`)}>💬 Chat</Btn>
              {p.crew && <Btn className="sm ghost" onClick={() => nav(`/crew/${p.crew!.id}`)}>{p.crew.emblem} Crew</Btn>}
              {!p.is_bot && <Btn className="sm ghost" onClick={() => setReporting(true)}>🚩 Report</Btn>}
              {!p.is_bot && (p.blocked ? <Btn className="sm ghost" onClick={unblock}>Unblock</Btn> : <Btn className="sm ghost" onClick={block}>🚫 Block</Btn>)}
            </div>
          )}
          {!isMe && me.hospital && <><div className="why">You're in the hospital — heal to full to fight again, or wait it out.</div><HealButton /></>}
          {!isMe && jailWall && <div className="why">{me.jailed ? "You're locked up — you can only fight other inmates." : "They're locked up — only other inmates can get at them."}</div>}
          {!isMe && !cantFight && tired && <div className="why">You need 2 stamina to fight — it comes back {catalog?.config.stamina_regen_amount ?? 2} {every(catalog?.config.stamina_regen_minutes ?? 10)}, or tap Attack to refill.</div>}
          {!isMe && pv && !p.hospital && !me.hospital && !jailWall && <Odds pv={pv} name={p.name} />}
          {!isMe && p.blocked && <div className="small muted">You've blocked them — no messages either way</div>}
          {!isMe && p.hospital && <div className="small muted">They're in the hospital — let them heal up.</div>}
        </div>
      </Card>

      {!isMe && !p.is_bot && me.is_admin && (
        <Card title="🛡 Admin">
          <div className="bd stack">
            <div className="small muted">Every action is logged, and they get a note in their activity. A reset name makes them pick a new one; a muted player can't chat, post in the forum or change their bio.</div>
            <ModButtons id={p.id} name={p.name} onDone={load} mutedUntil={p.muted_until} />
          </div>
        </Card>
      )}
      {reporting && <ReportModal kind="profile" id={p.id} name={p.name} onClose={() => setReporting(false)} />}

      {!isMe && (
        <Card title="Send Money / Diamonds">
          <div className="bd stack">
            <div className="hstack" style={{ flexWrap: 'nowrap' }}>
              <input className="input" style={{ flex: 1 }} inputMode="numeric" placeholder="Cash amount" aria-label="Cash to send" value={amount || ''} onChange={e => setAmount(Number(e.target.value) || 0)} />
              <Btn className="gold" disabled={amount <= 0 || amount > me.cash} onClick={() => run(() => api.sendCash(p.id, amount), { ok: r => `Sent ${money(r.sent)} to ${p.name}` })}>Send $</Btn>
            </div>
            {amount > me.cash && <div className="why">You have {money(me.cash)} on hand.</div>}
            <div className="hstack" style={{ flexWrap: 'nowrap' }}>
              <input className="input" style={{ flex: 1 }} inputMode="numeric" placeholder="Diamonds" aria-label="Diamonds to send" value={dia || ''} onChange={e => setDia(Number(e.target.value) || 0)} />
              <Btn className="blue" disabled={dia <= 0 || dia > me.diamonds} onClick={() => run(() => api.sendDiamonds(p.id, dia), { ok: r => `Sent 💎 ${r.sent} to ${p.name}` })}>Send 💎</Btn>
            </div>
            {dia > me.diamonds && <div className="why">You have 💎 {num(me.diamonds)}.</div>}
            <div className="small muted">Only diamonds you earned in the game can be sent. Bought ones stay with you.</div>
          </div>
        </Card>
      )}

      {result && (
        <Modal title={result.won ? 'You won the fight' : 'You lost the fight'} onClose={() => setResult(null)}>
          <div className="stack">
            <div className="grid2">
              <Stat k="Damage dealt" v={result.damage_dealt} cls="green" />
              <Stat k="Damage taken" v={result.damage_taken} cls="red" />
            </div>
            <p style={{ margin: 0 }} className={result.won ? 'gold' : 'red'}>{result.dry ? `${p.name} has been shaken down enough this hour — no cash changed hands.` : result.won ? `You took ${money(result.cash)} off ${p.name}.` : `${p.name} took ${money(result.cash)} off you.`}</p>
            {result.my_score != null && result.their_score != null && (
              <div className={`scoreline ${result.won ? 'won' : 'lost'}`}>
                <span>You <b className="tabular">{result.my_score.toFixed(1)}</b></span>
                <span className="muted small">vs</span>
                <span><b className="tabular">{result.their_score.toFixed(1)}</b> {p.name}</span>
              </div>
            )}
            {result.edges && <Edges edges={result.edges} />}
            {result.my_combo !== undefined && (result.my_combo || result.their_combo) && (
              <div className="small combo-result">
                <div className="hstack"><ComboPill code={result.my_combo} />{result.my_combo && <b className="tabular">+{result.my_combo_bonus ?? 0}</b>}<span className="muted">vs</span><ComboPill code={result.their_combo} />{result.their_combo && <b className="tabular">+{result.their_combo_bonus ?? 0}</b>}</div>
                <div className="muted">Combos: {matchupText(matchup(catalog, result.my_combo, result.their_combo) ?? (result.their_combo ? 'even' : null), result.my_combo_max ?? 0, result.their_combo_max ?? 0)}.</div>
              </div>
            )}
            <div className="small muted">
              Your attack {result.my_att} vs their defense {result.their_def}{result.their_att != null && <> · their attack {result.their_att} vs your defense {result.my_def}</>}.
              {' '}{result.won ? 'You won, so your hit landed in full and theirs only glanced.' : result.my_score != null ? 'They won the exchange, so their hit landed in full and yours only glanced.' : ''}
              {' '}Their health is now {result.their_health}; yours {result.my_health}.
            </div>
            {result.hospitalized_them && <div className="notice red">You put {p.name} in the hospital.</div>}
            {result.hospitalized_me && <div className="notice red">You're in the hospital.</div>}
            {me.hospital && <HealButton />}
            {result.busted && <div className="notice red">A patrol rolled up after the fight — you're in jail.</div>}
            {result.busted && me.jailed && <BailButton />}
            {/* a streak is one tap per fight: the same checks as the Attack button, on the refreshed me and p */}
            <Btn className="doit red block" disabled={cantFight} onClick={fight}>⚔️ Attack again · ⚡2 · {num(me.stamina)} left</Btn>
            {cantFight ? <div className="why">{
              p.hospital ? `${p.name} is in the hospital — let them heal up.`
              : me.hospital ? "You're in the hospital — heal to full above, or wait it out."
              : me.jailed ? "You're locked up — you can only fight other inmates." : "They're locked up — only other inmates can get at them."
            }</div> : tired && <div className="why">You're out of stamina — Attack again offers a refill.</div>}
          </div>
        </Modal>
      )}
    </div>
  )
}

function oddsLabel(pct: number): [string, string] {
  if (pct >= 80) return ['Strong favorite', 'green']
  if (pct >= 60) return ['Favored', 'green']
  if (pct >= 40) return ['Coin flip', 'gold']
  if (pct >= 20) return ['Underdog', 'red']
  return ['Long shot', 'red']
}

/** Fight preview: odds from a few hundred simulated fights, what it costs, and anything that makes it a bad idea. */
function Odds({ pv, name }: { pv: FightPreview; name: string }) {
  const { catalog } = useGame()
  const [label, cls] = oddsLabel(pv.win_pct)
  const known = pv.their_combo_known !== false
  return (
    <div className="odds-box">
      <div className="spread"><span className="small muted">Your odds vs {name}</span><b className={cls}>{label} · {pv.win_pct >= 100 ? '>99' : pv.win_pct <= 0 ? '<1' : `~${pv.win_pct}`}%</b></div>
      <div className={`odds ${cls}`}><div className="fill" style={{ width: Math.max(3, pv.win_pct) + '%' }} /></div>
      {pv.edges && <Edges edges={pv.edges} />}
      {pv.base_you != null && pv.base_them != null && (
        <div className="small muted tabular">Gear alone: your hit {pv.base_you.toFixed(1)} vs theirs {pv.base_them.toFixed(1)}. Each side adds a 0–6 roll plus its edges{pv.combo_you || pv.combo_them ? ', and its combo roll' : ''}. Higher total wins; a tie goes to the defender.</div>
      )}
      {pv.my_combo !== undefined && (pv.my_combo || pv.their_has_combo) && (
        <div className="small odds-combo">
          <div className="hstack"><ComboPill code={pv.my_combo} /><span className="muted">vs</span>{known ? <ComboPill code={pv.their_combo} /> : <ComboPill unknown />}</div>
          <div className="muted">
            {!known && 'They run a combo, but you won\'t know which until you hit them — these odds assume neither of you counters. '}
            {known && pv.their_combo && pv.their_combo_seen_at && `That's what they ran when you hit them ${ago(pv.their_combo_seen_at)} — they may have switched. `}
            Combos: {matchupText(known ? matchup(catalog, pv.my_combo, pv.their_combo) : pv.my_combo ? 'even' : null, pv.my_combo_max ?? 0, pv.their_combo_max ?? 0)}.
          </div>
        </div>
      )}
      <div className="small muted tabular">You'd take {pv.dmg_min}–{pv.dmg_max} damage · costs ⚡{pv.stamina_cost} · 🔥+{pv.heat_gain}{pv.setup === 'jail' ? ' · fighting with your jail setup' : ''}</div>
      {pv.dry && <div className="warn">You've hit them {pv.hits_this_hour}× this hour — you can still fight, but no cash changes hands.</div>}
      {pv.hospital_risk && <div className="warn">At {pv.my_health} health, a bad fight could put you in the hospital.</div>}
      {pv.bust_pct > 0 && <div className="warn">Your heat is in the red — about {pv.bust_pct}% chance a patrol picks you up after.</div>}
    </div>
  )
}

const EDGE: Record<FightEdge['k'], { icon: string; label: string }> = {
  defender: { icon: '🛡️', label: 'Defending' },
  cash: { icon: '💵', label: 'More cash on hand' },
  heat: { icon: '🔥', label: 'More heat' },
}

/** The +1 edges each side holds: the defender always gets one; more cash on hand and more heat get one each. */
export function Edges({ edges }: { edges: FightEdge[] }) {
  const side = (who: FightEdge['side']) => edges.filter(e => e.side === who)
  const col = (who: FightEdge['side'], title: string) => {
    const list = side(who)
    return (
      <div className="edge-col">
        <div className="k">{title} <b className="tabular">+{list.length}</b></div>
        {list.length ? list.map(e => <span key={e.k} className={`pill ${who === 'you' ? 'green' : 'red'}`}>{EDGE[e.k].icon} {EDGE[e.k].label}</span>)
          : <span className="small muted">no edges</span>}
      </div>
    )
  }
  return <div className="edges">{col('you', 'Your edges')}{col('them', 'Their edges')}</div>
}
