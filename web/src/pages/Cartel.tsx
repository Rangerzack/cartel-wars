import { useCallback, useEffect, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { useGame, useMe } from '../lib/game'
import { api } from '../lib/api'
import { ago, money } from '../lib/format'
import { Btn, Card, Empty, Stat } from '../components/ui'
import { Ledger } from '../components/Ledger'
import type { CartelDetail, CartelSummary, CrewSummary } from '../lib/types'

export default function Cartel() {
  const { id } = useParams()
  return id ? <CartelPage id={id} /> : <CartelHub />
}

function CartelHub() {
  const me = useMe()
  const { run, toast } = useGame()
  const nav = useNavigate()
  const [list, setList] = useState<CartelSummary[] | null>(null)
  const [name, setName] = useState('')
  const [invites, setInvites] = useState<{ id: string; name: string }[]>([])
  useEffect(() => { api.listCartels().then(setList).catch(e => toast(e.message, 'bad')) }, [toast])
  useEffect(() => { if (me.crew?.is_capo) api.crew(me.crew.id).then(c => setInvites(c.invites ?? [])).catch(() => {}) }, [me.crew, toast])
  useEffect(() => { if (me.cartel) nav(`/cartel/${me.cartel.id}`, { replace: true }) }, [me.cartel, nav])
  return (
    <div className="page">
      {invites.length > 0 && (
        <Card title="Invitations for your crew">
          {invites.map(i => (
            <div key={i.id} className="row">
              <div className="grow t">🕴 {i.name}</div>
              <Btn className="sm gold" onClick={async () => { const r = await run(() => api.cartelAccept(i.id, true), { ok: () => `Joined ${i.name}` }); if (r) nav(`/cartel/${i.id}`) }}>Accept</Btn>
              <Btn className="sm ghost" onClick={async () => { await run(() => api.cartelAccept(i.id, false)); setInvites(v => v.filter(x => x.id !== i.id)) }}>Decline</Btn>
            </div>
          ))}
        </Card>
      )}
      {me.crew?.is_capo ? (
        <Card title="Found a Cartel">
          <div className="bd stack">
            <input className="input" placeholder="Cartel name" value={name} maxLength={24} onChange={e => setName(e.target.value)} />
            <Btn className="doit block" disabled={name.trim().length < 3} onClick={async () => { const r = await run(() => api.cartelCreate(name), { ok: () => 'You are the Don' }); if (r) nav(`/cartel/${r.id}`) }}>Found It</Btn>
          </div>
        </Card>
      ) : (
        <div className="notice blue">Cartels are alliances of crews. Only a Capo can found one or accept an invitation from a Don.</div>
      )}
      <h2>Cartels</h2>
      <Card>
        {!list && <Empty><span className="spin" /></Empty>}
        {list?.length === 0 && <Empty>No cartels yet.</Empty>}
        {list?.map(c => (
          <div key={c.id} className="row link" onClick={() => nav(`/cartel/${c.id}`)}>
            <span style={{ fontSize: 20 }}>🕴</span>
            <div className="grow"><div className="t">{c.name}</div><div className="s">Don {c.don} · {c.crews} crews · {c.blocks} blocks</div></div>
            <span className="chev">›</span>
          </div>
        ))}
      </Card>
    </div>
  )
}

function CartelPage({ id }: { id: string }) {
  const me = useMe()
  const { run, toast } = useGame()
  const nav = useNavigate()
  const [c, setC] = useState<CartelDetail | null>(null)
  const [amount, setAmount] = useState(0)
  const [crews, setCrews] = useState<CrewSummary[] | null>(null)
  const [ledgerV, setLedgerV] = useState(0)
  const load = useCallback(() => api.cartel(id).then(setC).catch(e => { toast(e.message, 'bad'); nav('/cartel') }), [id, toast, nav])
  useEffect(() => { load() }, [load])
  useEffect(() => { if (c?.is_don) api.listCrews().then(setCrews).catch(() => {}) }, [c?.is_don])
  if (!c) return <Empty><span className="spin" /></Empty>
  const act = async <T,>(fn: () => Promise<T>, ok?: (r: T) => string) => { await run(fn, { ok }); load(); setLedgerV(v => v + 1) }
  const inviteable = (crews ?? []).filter(x => !x.cartel)

  return (
    <div className="page">
      <Card title={<>🕴 {c.name}</>} right={<small>Don {c.don}</small>}>
        <div className="bd stack">
          <div className="grid3">
            <Stat k="Crews" v={c.crews.length} />
            <Stat k="Blocks" v={c.crews.reduce((s, x) => s + x.blocks, 0)} />
            {c.bank !== null ? <Stat k="Cartel bank" v={money(c.bank)} cls="gold" /> : <Stat k="Founded" v={ago(c.created_at)} />}
          </div>
          {c.member && (
            <div className="hstack">
              <Btn className="sm" onClick={() => nav(`/chat/cartel:${c.id}`)}>💬 Cartel Chat</Btn>
              {me.crew?.is_capo && <Btn className="sm ghost red" onClick={() => { if (confirm('Pull your crew out of the cartel?')) return act(api.cartelLeave, () => 'Your crew left the cartel') }}>Leave Cartel</Btn>}
            </div>
          )}
          <div className="small muted">Every block pays its bonus once a day: 80% to the crew holding it, 20% to its cartel's bank.</div>
        </div>
      </Card>

      {c.member && (
        <Card title="Cartel Bank" right={<small>{c.is_don ? 'Don can withdraw' : 'deposits only'}</small>}>
          <div className="bd hstack">
            <input className="input" style={{ flex: 1 }} inputMode="numeric" placeholder="Amount" value={amount || ''} onChange={e => setAmount(Number(e.target.value) || 0)} />
            <Btn className="gold" disabled={amount <= 0 || amount > me.cash} onClick={() => act(() => api.cartelBank(amount), r => `Cartel bank: ${money(r.bank)}`)}>Deposit</Btn>
            {c.is_don && <Btn disabled={amount <= 0 || amount > (c.bank ?? 0)} onClick={() => act(() => api.cartelBank(-amount), r => `Cartel bank: ${money(r.bank)}`)}>Withdraw</Btn>}
          </div>
        </Card>
      )}
      {c.member && <Ledger scope="cartel" version={ledgerV} />}

      <Card title="Crews" right={c.can_vote && <small>Capos vote for the Don · majority of {c.crews.length} crews</small>}>
        {c.crews.map(x => (
          <div key={x.id} className="row">
            <span style={{ fontSize: 20, width: 28, textAlign: 'center' }}>{x.emblem}</span>
            <div className="grow link" onClick={() => nav(`/crew/${x.id}`)}><div className="t">{x.name}{x.capo_id === c.don_id ? ' 👑' : ''}</div><div className="s">Capo {x.capo} · {x.members} members · {x.blocks} blocks{x.votes > 0 ? ` · ${x.votes} vote${x.votes > 1 ? 's' : ''} for Don` : ''}</div></div>
            {c.can_vote && x.capo_id !== c.don_id && (
              <Btn className={`sm ${x.my_vote ? 'gold' : 'ghost'}`} onClick={() => act(() => api.cartelVoteDon(x.capo_id), r => (r.elected ? `${x.capo} is the new Don` : `Vote cast — ${r.votes}/${r.needed}`))}>{x.my_vote ? '✓ Voted' : 'Vote Don'}</Btn>
            )}
          </div>
        ))}
      </Card>

      {c.is_don && (
        <Card title="Invite a Crew">
          {inviteable.length === 0 && <Empty>No unaffiliated crews to invite.</Empty>}
          {inviteable.map(x => (
            <div key={x.id} className="row">
              <span style={{ fontSize: 20, width: 28, textAlign: 'center' }}>{x.emblem}</span>
              <div className="grow"><div className="t">{x.name}</div><div className="s">{x.members} members · {x.blocks} blocks</div></div>
              <Btn className="sm gold" onClick={() => act(() => api.cartelInvite(x.id), () => `Invited ${x.name} — their Capo decides`)}>Invite</Btn>
            </div>
          ))}
        </Card>
      )}
    </div>
  )
}
