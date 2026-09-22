import { useCallback, useEffect, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { useGame, useMe } from '../lib/game'
import { api } from '../lib/api'
import { ago, money, num } from '../lib/format'
import { Btn, Card, Empty, Modal, Stat } from '../components/ui'
import { Ribbons } from '../components/Ribbons'
import type { FightResult, PublicPlayer } from '../lib/types'

export default function Player() {
  const { id = '' } = useParams()
  const me = useMe()
  const { run, toast } = useGame()
  const nav = useNavigate()
  const [p, setP] = useState<PublicPlayer | null>(null)
  const [result, setResult] = useState<FightResult | null>(null)
  const [amount, setAmount] = useState(0)
  const [dia, setDia] = useState(0)

  const load = useCallback(() => api.player(id).then(setP).catch(e => toast(e.message, 'bad')), [id, toast])
  useEffect(() => { load() }, [load])

  if (!p) return <Empty><span className="spin" /></Empty>
  const isMe = p.id === me.id
  const cantFight = isMe || me.hospital || p.hospital || p.immune || me.stamina < 2

  async function fight() {
    const r = await run(() => api.attack(p!.id), { silent: true })
    if (r) { setResult(r); load() }
  }

  return (
    <div className="page">
      <Card title={<>{p.name} {p.crew && <span className="muted">{p.crew.emblem} {p.crew.name}</span>}</>} right={<small>seen {ago(p.last_seen)}</small>}>
        <div className="bd stack">
          <div className="hstack">
            {p.jailed && <span className="pill red">🔒 In jail</span>}
            {p.hospital && <span className="pill red">🏥 Hospital</span>}
            {p.immune && <span className="pill blue">🛡 New player</span>}
            <span className={`pill ${p.heat_level === 'red' ? 'red' : ''}`}>🔥 heat {p.heat_level}</span>
            {p.cartel && <span className="pill gold">🕴 {p.cartel.name}</span>}
          </div>
          <Ribbons list={p.ribbons} />
          <div className="grid3">
            <Stat k="Health" v={`${num(p.health)}/${num(p.health_max)}`} />
            <Stat k="Fights" v={`${p.fights_won}W · ${p.fights - p.fights_won}L`} cls="sm" />
            <Stat k="Actions" v={num(p.actions)} />
          </div>
          {!isMe && (
            <div className="hstack">
              <Btn className="doit red" disabled={cantFight} onClick={fight}>⚔️ Attack</Btn>
              <Btn className="sm" onClick={async () => nav(`/chat/${await api.dmChannel(p.id)}`)}>💬 Chat</Btn>
              {p.crew && <Btn className="sm ghost" onClick={() => nav(`/crew/${p.crew!.id}`)}>{p.crew.emblem} Crew</Btn>}
            </div>
          )}
          {!isMe && (p.immune ? <div className="small muted">New players can't be attacked yet.</div> : p.hospital ? <div className="small muted">They're in the hospital — let them heal up.</div> : me.immune ? <div className="small muted">Attacking ends your own new-player immunity.</div> : null)}
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
