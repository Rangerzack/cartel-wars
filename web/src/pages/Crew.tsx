import { useEffect, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { useGame, useMe } from '../lib/game'
import { api } from '../lib/api'
import { ago, money, num, toInt } from '../lib/format'
import { Btn, Card, Empty, Loading, Modal, RowLink, Stat } from '../components/ui'
import { BailButton } from '../components/Bail'
import { BankWhy, Ledger } from '../components/Ledger'
import { useNow } from '../lib/useNow'
import { timeLeft } from '../lib/format'
import type { CrewFightResult } from '../lib/types'
import { businessDef, perkLabel } from '../lib/perks'
import { BackBar } from '../components/BackBar'
import { PlayerLink } from '../components/Linked'
import { useLoad } from '../lib/useLoad'

export default function Crew() {
  const { id } = useParams()
  // keyed by id: opening another crew from a fight row starts clean rather than showing the old crew under the new URL
  return id ? <CrewPage key={id} id={id} /> : <CrewHub />
}

function CrewHub() {
  const me = useMe()
  const { run } = useGame()
  const nav = useNavigate()
  const [q, setQ] = useState('')
  // a short wait folds fast typing into one search; an older search that answers late is dropped by useLoad
  const { data: list, error, reload } = useLoad(() => new Promise(r => setTimeout(r, 200)).then(() => api.listCrews(q)), q)
  const [form, setForm] = useState({ name: '', emblem: '🏴', description: '' })
  // the list comes first; founding is the less common move, so its form stays folded until asked for
  const [founding, setFounding] = useState(false)
  const nameShort = form.name.trim().length < 3

  return (
    <div className="page">
      <BackBar fallback="/" />
      {me.crew && (
        <Card>
          <RowLink to={`/crew/${me.crew.id}`}>
            <span className="ico">{me.crew.emblem}</span>
            <div className="grow"><div className="t">{me.crew.name}</div><div className="s">Your crew · {me.crew.members} members{me.crew.is_capo ? ' · you are Capo' : me.crew.is_co_capo ? ' · you are Co-Capo' : ''}</div></div>
            <span className="chev">›</span>
          </RowLink>
        </Card>
      )}
      <h2>{me.crew ? 'Other crews' : 'Crews'}</h2>
      <div className="small muted">A crew is led by a Capo and a Co-Capo; crews ally into cartels under a Don.</div>
      <input className="input" placeholder="Search crews…" aria-label="Search crews" value={q} onChange={e => setQ(e.target.value)} />
      <Card>
        {!list && <Loading error={error} onRetry={reload} />}
        {list?.length === 0 && <Empty>{q ? 'No crew by that name.' : 'No crews yet. Start the first one below.'}</Empty>}
        {list?.filter(c => c.id !== me.crew?.id).map(c => (
          <RowLink key={c.id} to={`/crew/${c.id}`}>
            <span className="ico">{c.emblem}</span>
            <div className="grow"><div className="t">{c.name} {c.cartel && <span className="muted small">· {c.cartel}</span>}</div><div className="s">{c.members} members · {c.blocks} blocks{c.description ? ` · ${c.description}` : ''}</div></div>
            <span className="chev">›</span>
          </RowLink>
        ))}
      </Card>
      {!me.crew && (
        <Card title="Found your own" right={!founding && <button type="button" className="btn sm" onClick={() => setFounding(true)}>Start a crew</button>}>
          {!founding ? <div className="bd small muted">Name it and pick an emblem; you're its Capo.</div> : (
            <div className="bd stack">
              <div className="grid2" style={{ gridTemplateColumns: '64px 1fr' }}>
                <label className="f">Emblem<input className="input" value={form.emblem} maxLength={8} aria-label="Emblem" onChange={e => setForm({ ...form, emblem: e.target.value })} /></label>
                <label className="f">Name<input className="input" value={form.name} maxLength={24} onChange={e => setForm({ ...form, name: e.target.value })} /></label>
              </div>
              <label className="f">Description<textarea className="input" rows={2} value={form.description} onChange={e => setForm({ ...form, description: e.target.value })} /></label>
              {/* crew_create takes 3–24 characters, trimmed; the field stops at 24 */}
              {nameShort && <div className="why">Pick a name of at least 3 characters.</div>}
              <Btn className="doit block" disabled={nameShort} onClick={async () => { const r = await run(() => api.crewCreate(form.name, form.emblem, form.description), { ok: () => 'Your crew is on the map' }); if (r) nav(`/crew/${r.id}`) }}>Found It</Btn>
            </div>
          )}
        </Card>
      )}
    </div>
  )
}

function CrewPage({ id }: { id: string }) {
  const me = useMe()
  const { run, toast, catalog, ask } = useGame()
  const nav = useNavigate()
  const [amount, setAmount] = useState(0)
  const [edit, setEdit] = useState<{ emblem: string; description: string } | null>(null)
  const [fight, setFight] = useState<CrewFightResult | null>(null)
  const [ledgerV, setLedgerV] = useState(0)
  const [allBlocks, setAllBlocks] = useState(false)
  const now = useNow()
  const { data: c, error, reload: load } = useLoad(() => api.crew(id), id)
  // a crew that no longer exists (the last member left) sends you back to the hub, replacing this URL so Back doesn't
  // return here; anything else that fails (a dropped connection) gets a Retry
  const gone = !!error && /No such crew|invalid input syntax/.test(error)
  useEffect(() => { if (gone) { toast('That crew is gone', 'info'); nav('/crew', { replace: true }) } }, [gone, toast, nav])
  // your standing with the crew changed (an application accepted, a kick): ask again, so the member view isn't fed
  // the outsider's snapshot
  const myCrew = me.crew?.id
  useEffect(() => { load() }, [myCrew, load])
  if (!c) return <div className="page"><BackBar fallback="/crew" /><Loading error={gone ? null : error} onRetry={load} /></div>
  const mine = me.crew?.id === c.id
  const act = async <T,>(fn: () => Promise<T>, ok?: (r: T) => string) => { const r = await run(fn, { ok }); await load(); setLedgerV(v => v + 1); return r }
  // a deposit or withdrawal empties the field, so a second tap doesn't move the same amount again
  const bank = async (n: number) => { if (await act(() => api.crewBank(n), r => `Crew bank: ${money(r.bank)}`)) setAmount(0) }
  const boss = c.is_boss
  const sameCartel = !!me.cartel && c.cartel?.id === me.cartel.id
  const cooldown = c.next_fight_at && new Date(c.next_fight_at).getTime() > now

  return (
    <div className="page">
      <BackBar fallback="/crew" />
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
              <Btn className="doit red block" disabled={!!cooldown || me.hospital} onClick={async () => {
                if (!await ask(`Your whole crew's attack goes against ${c.name}'s defense. Win and you take 5% of their crew bank; lose and 5% of yours goes to them, and everyone on your side takes a beating.`, { title: `Hit ${c.name}?`, yes: 'Crew Fight', tone: 'red' })) return
                const r = await run(() => api.crewFight(c.id), { silent: true }); if (r) { setFight(r); load() }
              }}>
                ⚔️ Crew Fight{cooldown ? ` · ${timeLeft(c.next_fight_at, now)}` : ''}
              </Btn>
              {me.hospital && <div className="why">Not from a hospital bed — heal up first.</div>}
              <div className="small muted">Your whole crew's attack against their defense. Costs {catalog?.config.crew_fight_stamina ?? 5} stamina, winner takes 5% of the loser's crew bank, everyone on the losing side takes a beating. One hit per crew per hour.</div>
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
              <Btn className="sm ghost red" onClick={async () => { if (await ask(c.is_capo ? (c.co_capo_id ? 'Your Co-Capo takes over as Capo.' : 'Leadership passes to your longest-standing member, or the crew disbands if you are the last one.') : c.co_capo_id === me.id ? 'The Co-Capo seat opens up for the Capo to fill.' : 'You can apply to another crew, or found your own.', { title: `Leave ${c.name}?`, yes: 'Leave', tone: 'red' })) return run(api.crewLeave, { ok: () => 'You left the crew' }).then(r => { if (r) nav('/crew', { replace: true }) }) }}>Leave</Btn>
            </div>
          )}
          {edit && (
            <div className="stack">
              <div className="grid2" style={{ gridTemplateColumns: '64px 1fr' }}>
                <input className="input" value={edit.emblem} maxLength={8} aria-label="Emblem" onChange={e => setEdit({ ...edit, emblem: e.target.value })} />
                <textarea className="input" rows={2} value={edit.description} onChange={e => setEdit({ ...edit, description: e.target.value })} />
              </div>
              <div className="hstack">
                <Btn className="sm gold" onClick={async () => { if (await act(() => api.crewUpdate(edit.emblem, edit.description), () => 'Saved')) setEdit(null) }}>Save</Btn>
                <Btn className="sm ghost" onClick={() => setEdit(null)}>Cancel</Btn>
              </div>
            </div>
          )}
        </div>
      </Card>

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
              <div className="grow link" onClick={() => nav(`/player/${a.id}`)}><div className="t"><PlayerLink id={a.id}>{a.name}</PlayerLink></div><div className="s">{ago(a.at)}</div></div>
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
              <div className="t"><PlayerLink id={m.id}>{m.avatar} {m.is_capo ? '👑 ' : m.is_co_capo ? '🎖 ' : ''}{m.name}</PlayerLink></div>
              <div className="s">{m.is_capo ? 'Capo · ' : m.is_co_capo ? 'Co-Capo · ' : ''}{num(m.fights_won)} wins · {num(m.actions)} actions · seen {ago(m.last_seen)}</div>
            </div>
            {c.is_capo && !m.is_capo && (m.is_co_capo
              ? <Btn className="sm ghost" onClick={() => act(() => api.crewSetCoCapo(null), () => `${m.name} is no longer Co-Capo`)}>Demote</Btn>
              : <Btn className="sm ghost" onClick={async () => { if (await ask(c.co_capo_id ? 'This replaces your current Co-Capo.' : 'They can accept applications, kick members and edit the crew.', { title: `Make ${m.name} Co-Capo?`, yes: 'Make Co-Capo' })) return act(() => api.crewSetCoCapo(m.id), () => `${m.name} is Co-Capo`) }}>Co-Capo</Btn>)}
            {boss && !m.is_capo && m.id !== me.id && <Btn className="sm ghost red" onClick={async () => { if (await ask('They leave the crew right away. They can apply again later.', { title: `Kick ${m.name}?`, yes: 'Kick', tone: 'red' })) return act(() => api.crewKick(m.id), () => `${m.name} is out`) }}>Kick</Btn>}
          </div>
        ))}
      </Card>

      {mine && (
        <Card title="Crew Bank" right={<small>{boss ? 'you can withdraw' : 'Capo & Co-Capo withdraw'}</small>}>
          <div className="bd hstack">
            <input className="input" style={{ flex: 1 }} inputMode="numeric" placeholder="Amount" aria-label={boss ? 'Amount to deposit or withdraw' : 'Amount to deposit'} value={amount || ''} onChange={e => setAmount(toInt(e.target.value))} />
            <Btn className="gold" disabled={amount <= 0 || amount > me.cash} onClick={() => bank(amount)}>Deposit</Btn>
            {boss && <Btn disabled={amount <= 0 || amount > (c.bank ?? 0)} onClick={() => bank(-amount)}>Withdraw</Btn>}
          </div>
          <BankWhy amount={amount} cash={me.cash} bank={c.bank ?? null} canWithdraw={!!boss} name="crew" />
        </Card>
      )}
      {mine && <Ledger scope="crew" version={ledgerV} />}
      {c.fights.length > 0 && (
        <Card title="Crew fights">
          {c.fights.map(f => {
            const weWon = f.we_attacked === f.won
            return (
              <RowLink key={f.id} to={`/crew/${f.we_attacked ? f.defender_id : f.attacker_id}`}>
                <span>{weWon ? '🏆' : '💀'}</span>
                <div className="grow"><div className="t">{f.we_attacked ? `${c.name} attacked ${f.defender}` : `${f.attacker} attacked ${c.name}`}{' · '}{weWon ? 'won' : 'lost'}</div><div className="s">{num(f.attack)} vs {num(f.defense)} · {ago(f.at)}</div></div>
                {f.cash === 0 ? <span className="muted tabular">$0</span> : <b className={`tabular ${weWon ? 'gold' : 'red'}`}>{weWon ? '+' : '−'}{money(f.cash)}</b>}
              </RowLink>
            )
          })}
        </Card>
      )}

      {c.perks && c.perks.length > 0 && (
        <Card title="Crew perks" right={<small>{c.perks.length} of {catalog?.businesses?.length ?? 19} businesses</small>}>
          {c.perks.map(p => {
            const d = businessDef(catalog, p.code)
            return (
              <RowLink key={p.code} to={`/territory?hood=${p.best_hood_id}&block=${p.best_block}`}>
                <span className="ico">{d?.icon}</span>
                <div className="grow">
                  <div className="t">{d?.name} <b className="gold tabular">{perkLabel(p.code, p.value)}</b>{d && p.value >= d.ceiling - 0.0001 && <span className="muted small"> · maxed</span>}</div>
                  <div className="s">{d?.perk} · {p.blocks} {p.blocks === 1 ? 'block' : 'blocks'} · best: {p.best_name}{p.best_full ? ' (full hood)' : ''}</div>
                </div>
                <span className="chev">›</span>
              </RowLink>
            )
          })}
          <div className="row small muted">{mine ? 'Every member gets these.' : 'Every member of this crew gets these.'} The best block of each business counts in full; each extra adds a quarter of its own value, up to double the best one.</div>
        </Card>
      )}

      {c.blocks.length > 0 && (
        <Card title="Blocks held" right={<small>{mine ? 'next bonus first' : `${c.blocks.length} blocks`}</small>}>
          {(allBlocks ? c.blocks : c.blocks.slice(0, 8)).map(b => {
            const inner = <div className="grow"><div className="t">{b.name}</div><div className="s">{b.business ? `${businessDef(catalog, b.business)?.icon ?? ''} ${businessDef(catalog, b.business)?.name ?? ''} · ` : ''}{b.island}{mine && b.bonus_at ? ` · bonus in ${timeLeft(b.bonus_at, now)}` : ''}</div></div>
            return mine
              ? <RowLink key={b.id} to={`/territory?hood=${b.hood_id}`}>{inner}<span className="chev">›</span></RowLink>
              : <div key={b.id} className="row">{inner}</div>
          })}
          {c.blocks.length > 8 && <div className="row"><button type="button" className="btn sm ghost block" onClick={() => setAllBlocks(!allBlocks)}>{allBlocks ? 'Show fewer' : `Show all ${c.blocks.length}`}</button></div>}
        </Card>
      )}

      {fight && (
        <Modal title={fight.won ? `${me.crew?.name} took the fight` : `${c.name} held the line`} onClose={() => setFight(null)}>
          <div className="stack">
            <div className="grid2"><Stat k="Your attack" v={num(fight.attack)} cls="green" /><Stat k="Their defense" v={num(fight.defense)} cls="red" /></div>
            <p style={{ margin: 0 }} className={fight.won ? 'gold' : 'red'}>{fight.won ? `${money(fight.cash)} moved from their crew bank to yours.` : `${money(fight.cash)} moved from your crew bank to theirs.`}</p>
            {fight.busted && <div className="notice red">The heat caught up with you — you're in jail.</div>}
            {fight.busted && me.jailed && <BailButton />}
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
