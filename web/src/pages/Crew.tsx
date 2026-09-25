import { useCallback, useEffect, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { useGame, useMe } from '../lib/game'
import { api } from '../lib/api'
import { ago, money, num } from '../lib/format'
import { Btn, Card, Empty, Modal, Stat } from '../components/ui'
import { Ledger } from '../components/Ledger'
import { useNow } from '../lib/useNow'
import { timeLeft } from '../lib/format'
import type { CrewDetail, CrewFightResult, CrewSummary } from '../lib/types'

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

  return (
    <div className="page">
      {me.crew && (
        <Card>
          <div className="row link" onClick={() => nav(`/crew/${me.crew!.id}`)}>
            <span style={{ fontSize: 22, width: 30, textAlign: 'center' }}>{me.crew.emblem}</span>
            <div className="grow"><div className="t">{me.crew.name}</div><div className="s">Your crew · {me.crew.members} members{me.crew.is_capo ? ' · you are Capo' : me.crew.is_co_capo ? ' · you are Co-Capo' : ''}</div></div>
            <span className="chev">›</span>
          </div>
        </Card>
      )}
      {!me.crew && <Card title="Found a Crew">
        <div className="bd stack">
          <div className="grid2" style={{ gridTemplateColumns: '64px 1fr' }}>
            <label className="f">Emblem<input className="input" value={form.emblem} maxLength={4} onChange={e => setForm({ ...form, emblem: e.target.value })} /></label>
            <label className="f">Name<input className="input" value={form.name} maxLength={24} onChange={e => setForm({ ...form, name: e.target.value })} /></label>
          </div>
          <label className="f">Description<textarea className="input" rows={2} value={form.description} onChange={e => setForm({ ...form, description: e.target.value })} /></label>
          <Btn className="doit block" disabled={form.name.trim().length < 3} onClick={async () => { const r = await run(() => api.crewCreate(form.name, form.emblem, form.description), { ok: () => 'Your crew is on the map' }); if (r) nav(`/crew/${r.id}`) }}>Found It</Btn>
        </div>
      </Card>}
      <h2>{me.crew ? 'Other crews' : 'Crews'}</h2>
      <input className="input" placeholder="Search crews…" value={q} onChange={e => setQ(e.target.value)} />
      <Card>
        {!list && <Empty><span className="spin" /></Empty>}
        {list?.length === 0 && <Empty>No crews yet. Be the first.</Empty>}
        {list?.filter(c => c.id !== me.crew?.id).map(c => (
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
  const [fight, setFight] = useState<CrewFightResult | null>(null)
  const [ledgerV, setLedgerV] = useState(0)
  const [allBlocks, setAllBlocks] = useState(false)
  const now = useNow()
  const load = useCallback(() => api.crew(id).then(setC).catch(e => { toast(e.message, 'bad'); nav('/crew') }), [id, toast, nav])
  useEffect(() => { load() }, [load])
  if (!c) return <Empty><span className="spin" /></Empty>
  const mine = me.crew?.id === c.id
  const act = async <T,>(fn: () => Promise<T>, ok?: (r: T) => string) => { await run(fn, { ok }); load(); setLedgerV(v => v + 1) }
  const boss = c.is_boss
  const sameCartel = !!me.cartel && c.cartel?.id === me.cartel.id
  const cooldown = c.next_fight_at && new Date(c.next_fight_at).getTime() > now

  return (
    <div className="page">
      <Card title={<><span style={{ fontSize: 20 }}>{c.emblem}</span> {c.name}</>} right={c.cartel && <Btn className="sm ghost" onClick={() => nav(`/cartel/${c.cartel!.id}`)}>🕴 {c.cartel.name}</Btn>}>
        <div className="bd stack">
          {c.description && <div>{c.description}</div>}
          <div className="grid3">
            <Stat k="Members" v={c.members.length} />
            <Stat k="Blocks" v={c.blocks.length} />
            {c.bank !== null ? <Stat k="Crew bank" v={money(c.bank)} cls="gold" /> : <Stat k="Founded" v={ago(c.created_at)} />}
            <Stat k="Crew attack" v={num(c.power.att)} />
            <Stat k="Crew defense" v={num(c.power.def)} />
            <Stat k="Crew fights" v={`${c.fights.filter(f => f.we_attacked === f.won).length}W · ${c.fights.filter(f => f.we_attacked !== f.won).length}L`} cls="sm" />
          </div>
          {!mine && me.crew && !sameCartel && (
            <div className="stack">
              <Btn className="doit red block" disabled={!!cooldown || me.hospital} onClick={async () => { const r = await run(() => api.crewFight(c.id), { silent: true }); if (r) { setFight(r); load() } }}>
                ⚔️ Crew Fight{cooldown ? ` · ${timeLeft(c.next_fight_at, now)}` : ''}
              </Btn>
              <div className="small muted">Your whole crew's attack against their defense. Costs 5 stamina, winner takes 5% of the loser's crew bank, everyone on the losing side takes a beating. One hit per crew per hour.</div>
            </div>
          )}
          {!mine && sameCartel && <div className="small muted">Same cartel — no crew fights between allies.</div>}
          {!mine && !me.crew && (
            c.applied
              ? <Btn className="ghost block" onClick={() => act(() => api.crewWithdraw(c.id), () => 'Application withdrawn')}>Withdraw Application</Btn>
              : <Btn className="doit block" onClick={() => act(() => api.crewApply(c.id), () => 'Applied — the Capo will decide')}>Apply to Join</Btn>
          )}
          {mine && (
            <div className="hstack">
              <Btn className="sm" onClick={() => nav(`/chat/crew:${c.id}`)}>💬 Crew Chat</Btn>
              <Btn className="sm" onClick={() => nav('/territory')}>🗺 Territory</Btn>
              {boss && <Btn className="sm ghost" onClick={() => setEdit({ emblem: c.emblem, description: c.description })}>Edit</Btn>}
              <Btn className="sm ghost red" onClick={() => { if (confirm(c.is_capo ? `Leave? ${c.co_capo_id ? 'Your Co-Capo takes over.' : 'Leadership passes to your longest-standing member, or the crew disbands.'}` : 'Leave the crew?')) return run(api.crewLeave, { ok: () => 'You left the crew' }).then(r => { if (r) nav('/crew') }) }}>Leave</Btn>
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
        <Card title="Crew Bank" right={<small>{boss ? 'you can withdraw' : 'Capo & Co-Capo withdraw'}</small>}>
          <div className="bd hstack">
            <input className="input" style={{ flex: 1 }} inputMode="numeric" placeholder="Amount" value={amount || ''} onChange={e => setAmount(Number(e.target.value) || 0)} />
            <Btn className="gold" disabled={amount <= 0 || amount > me.cash} onClick={() => act(() => api.crewBank(amount), r => `Crew bank: ${money(r.bank)}`)}>Deposit</Btn>
            {boss && <Btn disabled={amount <= 0 || amount > (c.bank ?? 0)} onClick={() => act(() => api.crewBank(-amount), r => `Crew bank: ${money(r.bank)}`)}>Withdraw</Btn>}
          </div>
        </Card>
      )}
      {mine && <Ledger scope="crew" version={ledgerV} />}

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

      {boss && c.applications && c.applications.length > 0 && (
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

      {c.fights.length > 0 && (
        <Card title="Crew fights">
          {c.fights.map(f => {
            const weWon = f.we_attacked === f.won
            return (
              <div key={f.id} className="row link" onClick={() => nav(`/crew/${f.we_attacked ? f.defender_id : f.attacker_id}`)}>
                <span>{weWon ? '🏆' : '💀'}</span>
                <div className="grow"><div className="t">{f.we_attacked ? `${c.name} attacked ${f.defender}` : `${f.attacker} attacked ${c.name}`}{' · '}{weWon ? 'won' : 'lost'}</div><div className="s">{num(f.attack)} vs {num(f.defense)} · {ago(f.at)}</div></div>
                <b className={`tabular ${weWon ? 'gold' : 'red'}`}>{weWon ? '+' : '−'}{money(f.cash)}</b>
              </div>
            )
          })}
        </Card>
      )}

      <Card title="Members">
        {c.members.map(m => (
          <div key={m.id} className="row">
            <div className="grow link" onClick={() => nav(`/player/${m.id}`)}>
              <div className="t">{m.avatar} {m.is_capo ? '👑 ' : m.is_co_capo ? '🎖 ' : ''}{m.name}</div>
              <div className="s">{m.is_capo ? 'Capo · ' : m.is_co_capo ? 'Co-Capo · ' : ''}{num(m.fights_won)} wins · {num(m.actions)} actions · seen {ago(m.last_seen)}</div>
            </div>
            {c.is_capo && !m.is_capo && (m.is_co_capo
              ? <Btn className="sm ghost" onClick={() => act(() => api.crewSetCoCapo(null), () => `${m.name} is no longer Co-Capo`)}>Demote</Btn>
              : <Btn className="sm ghost" onClick={() => { if (confirm(`Make ${m.name} Co-Capo?${c.co_capo_id ? ' This replaces your current Co-Capo.' : ''}`)) return act(() => api.crewSetCoCapo(m.id), () => `${m.name} is Co-Capo`) }}>Co-Capo</Btn>)}
            {boss && !m.is_capo && m.id !== me.id && <Btn className="sm ghost" onClick={() => { if (confirm(`Kick ${m.name}?`)) return act(() => api.crewKick(m.id), () => `${m.name} is out`) }}>Kick</Btn>}
          </div>
        ))}
      </Card>

      {c.blocks.length > 0 && (
        <Card title="Blocks held" right={<small>{mine ? 'next bonus first' : `${c.blocks.length} blocks`}</small>}>
          {(allBlocks ? c.blocks : c.blocks.slice(0, 8)).map(b => (
            <div key={b.id} className={`row ${mine ? 'link' : ''}`} onClick={mine ? () => nav(`/territory?hood=${b.hood_id}`) : undefined}>
              <div className="grow"><div className="t">{b.name}</div><div className="s">{b.island}{mine && b.bonus_at ? ` · bonus in ${timeLeft(b.bonus_at, now)}` : ''}</div></div>
              {mine && <span className="chev">›</span>}
            </div>
          ))}
          {c.blocks.length > 8 && <div className="row"><button className="btn sm ghost block" onClick={() => setAllBlocks(!allBlocks)}>{allBlocks ? 'Show fewer' : `Show all ${c.blocks.length}`}</button></div>}
        </Card>
      )}

      {fight && (
        <Modal title={fight.won ? `${me.crew?.name} took the fight` : `${c.name} held the line`} onClose={() => setFight(null)}>
          <div className="stack">
            <div className="grid2"><Stat k="Your attack" v={num(fight.attack)} cls="green" /><Stat k="Their defense" v={num(fight.defense)} cls="red" /></div>
            <p style={{ margin: 0 }} className={fight.won ? 'gold' : 'red'}>{fight.won ? `${money(fight.cash)} moved from their crew bank to yours.` : `${money(fight.cash)} moved from your crew bank to theirs.`}</p>
            {fight.busted && <div className="notice red">The heat caught up with you — you're in jail.</div>}
          </div>
        </Modal>
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
