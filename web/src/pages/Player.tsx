import { useCallback, useEffect, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { useGame, useMe } from '../lib/game'
import { api } from '../lib/api'
import { ago, every, money, num } from '../lib/format'
import { Btn, Card, Empty, Modal, Stat } from '../components/ui'
import { Ribbons } from '../components/Ribbons'
import type { FightPreview, FightResult, PublicPlayer } from '../lib/types'
import { BackBar } from '../components/BackBar'

export default function Player() {
  const { id = '' } = useParams()
  const me = useMe()
  const { run, toast, catalog } = useGame()
  const nav = useNavigate()
  const [p, setP] = useState<PublicPlayer | null>(null)
  const [result, setResult] = useState<FightResult | null>(null)
  const [amount, setAmount] = useState(0)
  const [dia, setDia] = useState(0)

  const load = useCallback(() => api.player(id).then(setP).catch(e => toast(e.message, 'bad')), [id, toast])
  useEffect(() => { load() }, [load])
  // odds before you swing; quietly absent if the preview isn't available
  const [pv, setPv] = useState<FightPreview | null>(null)
  const loadPreview = useCallback(() => { if (id && id !== me.id) api.fightPreview(id).then(setPv).catch(() => setPv(null)) }, [id, me.id])
  useEffect(() => { loadPreview() }, [loadPreview])

  if (!p) return <Empty><span className="spin" /></Empty>
  const isMe = p.id === me.id
  const cantFight = isMe || me.hospital || p.hospital || me.stamina < 2

  async function fight() {
    const r = await run(() => api.attack(p!.id), { silent: true })
    if (r) { setResult(r); load(); loadPreview() }
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
          <div className="grid3">
            <Stat k="Health" v={`${num(p.health)}/${num(p.health_max)}`} />
            <Stat k="Fights" v={`${p.fights_won}W · ${p.fights - p.fights_won}L`} cls="sm" />
            <Stat k="Actions" v={num(p.actions)} />
            <Stat k="Reputation" v={`⭐ ${num(p.reputation)}`} cls="dia" />
          </div>
          {!isMe && pv && !p.hospital && !me.hospital && <Odds pv={pv} name={p.name} />}
          {!isMe && !me.hospital && !p.hospital && me.stamina < 2 && <div className="why">You need 2 stamina to fight — it comes back {catalog?.config.stamina_regen_amount ?? 2} {every(catalog?.config.stamina_regen_minutes ?? 10)}.</div>}
          {!isMe && (
            <div className="hstack">
              <Btn className="doit red" disabled={cantFight} onClick={fight}>⚔️ Attack</Btn>
              <Btn className="sm" onClick={async () => nav(`/chat/${await api.dmChannel(p.id)}`)}>💬 Chat</Btn>
              {p.crew && <Btn className="sm ghost" onClick={() => nav(`/crew/${p.crew!.id}`)}>{p.crew.emblem} Crew</Btn>}
            </div>
          )}
          {!isMe && p.hospital && <div className="small muted">They're in the hospital — let them heal up.</div>}
        </div>
      </Card>

      {!isMe && (
        <Card title="Send Money / Diamonds">
          <div className="bd stack">
            <div className="hstack" style={{ flexWrap: 'nowrap' }}>
              <input className="input" style={{ flex: 1 }} inputMode="numeric" placeholder="Cash amount" value={amount || ''} onChange={e => setAmount(Number(e.target.value) || 0)} />
              <Btn className="gold" disabled={amount <= 0 || amount > me.cash} onClick={() => run(() => api.sendCash(p.id, amount), { ok: r => `Sent ${money(r.sent)} to ${p.name}` })}>Send $</Btn>
            </div>
            <div className="hstack" style={{ flexWrap: 'nowrap' }}>
              <input className="input" style={{ flex: 1 }} inputMode="numeric" placeholder="Diamonds" value={dia || ''} onChange={e => setDia(Number(e.target.value) || 0)} />
              <Btn className="blue" disabled={dia <= 0 || dia > me.diamonds} onClick={() => run(() => api.sendDiamonds(p.id, dia), { ok: r => `Sent 💎 ${r.sent} to ${p.name}` })}>Send 💎</Btn>
            </div>
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
            <div className="small muted">Your attack {result.my_att} vs their defense {result.their_def}. Their health is now {result.their_health}; yours {result.my_health}.</div>
            {result.hospitalized_them && <div className="notice red">You put {p.name} in the hospital.</div>}
            {result.hospitalized_me && <div className="notice red">You're in the hospital. Check out at Services.</div>}
            {result.busted && <div className="notice red">A patrol rolled up after the fight — you're in jail.</div>}
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
  const [label, cls] = oddsLabel(pv.win_pct)
  return (
    <div className="odds-box">
      <div className="spread"><span className="small muted">Your odds vs {name}</span><b className={cls}>{label} · {pv.win_pct >= 100 ? '>99' : pv.win_pct <= 0 ? '<1' : `~${pv.win_pct}`}%</b></div>
      <div className={`odds ${cls}`}><div className="fill" style={{ width: Math.max(3, pv.win_pct) + '%' }} /></div>
      <div className="small muted tabular">You'd take {pv.dmg_min}–{pv.dmg_max} damage · costs ⚡{pv.stamina_cost} · 🔥+{pv.heat_gain}{pv.setup === 'jail' ? ' · fighting with your jail setup' : ''}</div>
      {pv.dry && <div className="warn">You've hit them {pv.hits_this_hour}× this hour — you can still fight, but no cash changes hands.</div>}
      {pv.hospital_risk && <div className="warn">At {pv.my_health} health, a bad fight could put you in the hospital.</div>}
      {pv.bust_pct > 0 && <div className="warn">Your heat is in the red — about {pv.bust_pct}% chance a patrol picks you up after.</div>}
    </div>
  )
}
