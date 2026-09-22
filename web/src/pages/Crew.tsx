import { useCallback, useEffect, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { useGame, useMe } from '../lib/game'
import { api } from '../lib/api'
import { ago, money, num } from '../lib/format'
import { Btn, Card, Empty, Stat } from '../components/ui'
import type { CrewDetail, CrewSummary } from '../lib/types'

export default function Crew() {
  const { id } = useParams()
  return id ? <CrewPage id={id} /> : <CrewHub />
}

function CrewHub() {
  const me = useMe()
  const { run, toast } = useGame()
  const nav = useNavigate()
  const [q, setQ] = useState('')
  const [list, setList] = useState<CrewSummary[] | null>(null)
  const [form, setForm] = useState({ name: '', emblem: '🏴', description: '' })
  useEffect(() => {
    const t = setTimeout(() => api.listCrews(q).then(setList).catch(e => toast(e.message, 'bad')), 200)
    return () => clearTimeout(t)
  }, [q, toast])
  useEffect(() => { if (me.crew) nav(`/crew/${me.crew.id}`, { replace: true }) }, [me.crew, nav])

  return (
    <div className="page">
      <Card title="Found a Crew">
        <div className="bd stack">
          <div className="grid2" style={{ gridTemplateColumns: '64px 1fr' }}>
            <label className="f">Emblem<input className="input" value={form.emblem} maxLength={4} onChange={e => setForm({ ...form, emblem: e.target.value })} /></label>
            <label className="f">Name<input className="input" value={form.name} maxLength={24} onChange={e => setForm({ ...form, name: e.target.value })} /></label>
          </div>
          <label className="f">Description<textarea className="input" rows={2} value={form.description} onChange={e => setForm({ ...form, description: e.target.value })} /></label>
          <Btn className="doit block" disabled={form.name.trim().length < 3} onClick={async () => { const r = await run(() => api.crewCreate(form.name, form.emblem, form.description), { ok: () => 'Your crew is on the map' }); if (r) nav(`/crew/${r.id}`) }}>Found It</Btn>
        </div>
      </Card>
      <h2>Crews</h2>
      <input className="input" placeholder="Search crews…" value={q} onChange={e => setQ(e.target.value)} />
      <Card>
        {!list && <Empty><span className="spin" /></Empty>}
        {list?.length === 0 && <Empty>No crews yet. Be the first.</Empty>}
        {list?.map(c => (
          <div key={c.id} className="row link" onClick={() => nav(`/crew/${c.id}`)}>
            <span style={{ fontSize: 22, width: 30, textAlign: 'center' }}>{c.emblem}</span>
            <div className="grow"><div className="t">{c.name} {c.cartel && <span className="muted small">· {c.cartel}</span>}</div><div className="s">{c.members} members · {c.blocks} blocks{c.description ? ` · ${c.description}` : ''}</div></div>
            <span className="chev">›</span>
          </div>
        ))}
      </Card>
    </div>
  )
}

function CrewPage({ id }: { id: string }) {
  const me = useMe()
  const { run, toast } = useGame()
  const nav = useNavigate()
  const [c, setC] = useState<CrewDetail | null>(null)
  const [amount, setAmount] = useState(0)
  const [edit, setEdit] = useState<{ emblem: string; description: string } | null>(null)
  const load = useCallback(() => api.crew(id).then(setC).catch(e => { toast(e.message, 'bad'); nav('/crew') }), [id, toast, nav])
  useEffect(() => { load() }, [load])
  if (!c) return <Empty><span className="spin" /></Empty>
  const mine = me.crew?.id === c.id
  const act = async <T,>(fn: () => Promise<T>, ok?: (r: T) => string) => { await run(fn, { ok }); load() }

  return (
    <div className="page">
      <Card title={<><span style={{ fontSize: 20 }}>{c.emblem}</span> {c.name}</>} right={c.cartel && <Btn className="sm ghost" onClick={() => nav(`/cartel/${c.cartel!.id}`)}>🕴 {c.cartel.name}</Btn>}>
        <div className="bd stack">
          {c.description && <div>{c.description}</div>}
          <div className="grid3">
            <Stat k="Members" v={c.members.length} />
            <Stat k="Blocks" v={c.blocks.length} />
            {c.bank !== null ? <Stat k="Crew bank" v={money(c.bank)} cls="gold" /> : <Stat k="Founded" v={ago(c.created_at)} />}
          </div>
          {!mine && !me.crew && (
            c.applied
              ? <Btn className="ghost block" onClick={() => act(() => api.crewWithdraw(c.id), () => 'Application withdrawn')}>Withdraw Application</Btn>
              : <Btn className="doit block" onClick={() => act(() => api.crewApply(c.id), () => 'Applied — the Capo will decide')}>Apply to Join</Btn>
          )}
          {mine && (
            <div className="hstack">
              <Btn className="sm" onClick={() => nav(`/chat/crew:${c.id}`)}>💬 Crew Chat</Btn>
              <Btn className="sm" onClick={() => nav('/territory')}>🗺 Territory</Btn>
              {c.is_capo && <Btn className="sm ghost" onClick={() => setEdit({ emblem: c.emblem, description: c.description })}>Edit</Btn>}
              <Btn className="sm ghost red" onClick={() => { if (confirm(c.is_capo ? 'Leave? Leadership passes to your longest-standing member, or the crew disbands.' : 'Leave the crew?')) return act(api.crewLeave, () => 'You left the crew') }}>Leave</Btn>
            </div>
          )}
          {edit && (
            <div className="stack">
              <div className="grid2" style={{ gridTemplateColumns: '64px 1fr' }}>
                <input className="input" value={edit.emblem} maxLength={4} onChange={e => setEdit({ ...edit, emblem: e.target.value })} />
                <textarea className="input" rows={2} value={edit.description} onChange={e => setEdit({ ...edit, description: e.target.value })} />
              </div>
              <Btn className="sm gold" onClick={async () => { await act(() => api.crewUpdate(edit.emblem, edit.description), () => 'Saved'); setEdit(null) }}>Save</Btn>
            </div>
          )}
        </div>
      </Card>

      {mine && (
        <Card title="Crew Bank" right={<small>{c.is_capo ? 'Capo can withdraw' : 'deposits only'}</small>}>
          <div className="bd hstack">
            <input className="input" style={{ flex: 1 }} inputMode="numeric" placeholder="Amount" value={amount || ''} onChange={e => setAmount(Number(e.target.value) || 0)} />
            <Btn className="gold" disabled={amount <= 0 || amount > me.cash} onClick={() => act(() => api.crewBank(amount), r => `Crew bank: ${money(r.bank)}`)}>Deposit</Btn>
            {c.is_capo && <Btn disabled={amount <= 0 || amount > (c.bank ?? 0)} onClick={() => act(() => api.crewBank(-amount), r => `Crew bank: ${money(r.bank)}`)}>Withdraw</Btn>}
          </div>
        </Card>
      )}

      {c.is_capo && c.invites && c.invites.length > 0 && (
        <Card title="Cartel Invitations">
          {c.invites.map(i => (
            <div key={i.id} className="row">
              <div className="grow t">🕴 {i.name}</div>
              <Btn className="sm gold" onClick={() => act(() => api.cartelAccept(i.id, true), () => `Joined ${i.name}`)}>Accept</Btn>
              <Btn className="sm ghost" onClick={() => act(() => api.cartelAccept(i.id, false))}>Decline</Btn>
            </div>
          ))}
        </Card>
      )}

      {c.is_capo && c.applications && c.applications.length > 0 && (
        <Card title="Applications">
          {c.applications.map(a => (
            <div key={a.id} className="row">
              <div className="grow link" onClick={() => nav(`/player/${a.id}`)}><div className="t">{a.name}</div><div className="s">{ago(a.at)}</div></div>
              <Btn className="sm gold" onClick={() => act(() => api.crewDecide(a.id, true), () => `${a.name} is in`)}>Accept</Btn>
              <Btn className="sm ghost" onClick={() => act(() => api.crewDecide(a.id, false))}>Reject</Btn>
            </div>
          ))}
        </Card>
      )}

      <Card title="Members">
        {c.members.map(m => (
          <div key={m.id} className="row">
            <div className="grow link" onClick={() => nav(`/player/${m.id}`)}>
              <div className="t">{m.is_capo ? '👑 ' : ''}{m.name}</div>
              <div className="s">{num(m.fights_won)} wins · {num(m.actions)} actions · seen {ago(m.last_seen)}</div>
            </div>
            {c.is_capo && !m.is_capo && <Btn className="sm ghost" onClick={() => { if (confirm(`Kick ${m.name}?`)) return act(() => api.crewKick(m.id), () => `${m.name} is out`) }}>Kick</Btn>}
          </div>
        ))}
      </Card>

      {c.blocks.length > 0 && (
        <Card title="Blocks held">
          {c.blocks.map(b => <div key={b.id} className="row"><div className="grow"><div className="t">{b.name}</div><div className="s">{b.hood} · {b.island}</div></div></div>)}
        </Card>
      )}

      {mine && c.is_capo && !c.cartel && (
        <Card title="Cartel">
          <div className="bd stack">
            <div className="small muted">As Capo you can found a cartel, or accept an invitation from an existing Don.</div>
            <Btn className="block" onClick={() => nav('/cartel')}>Found or Browse Cartels</Btn>
          </div>
        </Card>
      )}
    </div>
  )
}
