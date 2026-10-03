import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { api } from '../lib/api'
import { useGame, useMe } from '../lib/game'
import { ago, money, num } from '../lib/format'
import { Btn, Card, Loading, RowLink, Stat } from '../components/ui'
import { Ribbons } from '../components/Ribbons'
import { AccountCard } from '../components/Account'
import { BackBar } from '../components/BackBar'
import { PlayerLink } from '../components/Linked'
import { HelpPolicies } from '../components/HelpPolicies'
import { useLoad } from '../lib/useLoad'

export default function Profile() {
  const me = useMe()
  const { run } = useGame()
  const nav = useNavigate()
  const p = me.power
  const [edit, setEdit] = useState<{ avatar: string; bio: string } | null>(null)
  return (
    <div className="page">
      <BackBar fallback="/" />
      <Card title={<><span style={{ fontSize: 20 }}>{me.avatar}</span> {me.name}</>} right={<small>since {ago(me.created_at)}</small>}>
        <div className="bd stack">
          {me.bio && !edit && <div className="small" style={{ fontStyle: 'italic' }}>“{me.bio}”</div>}
          {edit ? (
            <div className="stack">
              <div className="grid2" style={{ gridTemplateColumns: '64px 1fr' }}>
                <input className="input" value={edit.avatar} maxLength={4} onChange={e => setEdit({ ...edit, avatar: e.target.value })} />
                <textarea className="input" rows={2} maxLength={200} placeholder="Say something about yourself" value={edit.bio} onChange={e => setEdit({ ...edit, bio: e.target.value })} />
              </div>
              <div className="hstack"><Btn className="sm gold" onClick={async () => { if (await run(() => api.updateProfile(edit.avatar, edit.bio), { ok: () => 'Profile saved' })) setEdit(null) }}>Save</Btn><Btn className="sm ghost" onClick={() => setEdit(null)}>Cancel</Btn></div>
            </div>
          ) : <div><Btn className="sm ghost" onClick={() => setEdit({ avatar: me.avatar, bio: me.bio })}>Edit avatar & bio</Btn></div>}
          <Ribbons list={me.ribbons} empty="No accolade stripes yet." />
          <div className="grid3 stat-grid">
            <Stat k="Cash" v={money(me.cash)} cls="gold" />
            <Stat k="Bank" v={money(me.bank)} />
            <Stat k="Diamonds" v={`💎 ${num(me.diamonds)}`} cls="dia" />
            <Stat k="Reputation" v={`⭐ ${num(me.reputation)}`} cls="dia" />
            <Stat k="Actions" v={num(me.actions_done)} />
            <Stat k="Fights" v={`${me.fights_won}W · ${me.fights_lost}L`} cls="sm" />
            <Stat k="Product moved" v={num(me.imports)} />
            <Stat k="Market sales" v={money(me.market_volume)} />
            <Stat k="Storage" v={`${num(me.storage_used)}/${num(me.storage_cap)}`} />
          </div>
        </div>
      </Card>
      <Card title="Setups">
        {(['offense', 'defense', 'jail'] as const).map(s => (
          <RowLink key={s} to={`/items?setup=${s}`}>
            <div className="grow t" style={{ textTransform: 'capitalize' }}>{s}</div>
            <span className="tabular">att {p[s].att} · def {p[s].def}{p[s].combo ? ' · combo' : ''}</span>
            <span className="chev">›</span>
          </RowLink>
        ))}
      </Card>
      <Card title="Crew & Cartel">
        <RowLink to={me.crew ? `/crew/${me.crew.id}` : '/crew'}><div className="grow t">{me.crew ? `${me.crew.emblem} ${me.crew.name}` : 'No crew'}</div><span className="chev">›</span></RowLink>
        <RowLink to={me.cartel ? `/cartel/${me.cartel.id}` : '/cartel'}><div className="grow t">{me.cartel ? `🕴 ${me.cartel.name}` : 'No cartel'}</div><span className="chev">›</span></RowLink>
      </Card>
      {me.is_admin && (
        <Card title="🛡 Admin">
          <RowLink to="/admin"><div className="grow t">Reports, moderation log and word filter</div>{(me.reports_open ?? 0) > 0 && <span className="pill red">{me.reports_open} open</span>}<span className="chev">›</span></RowLink>
        </Card>
      )}
      <BlockedPlayers />
      <AccountCard onSignedOut={() => nav('/')} />
      <HelpPolicies />
      <p className="muted small center">Cartel Wars is an independent fan project and is not affiliated with the creators of the original 2009 game.</p>
    </div>
  )
}

/** Players I've blocked (no DMs either way, their chat lines and posts hidden from me), each with a way back. */
function BlockedPlayers() {
  const { run } = useGame()
  const { data: list, error, reload: load } = useLoad(() => api.blockedList())
  return (
    <Card title="Blocked players" right={list?.length ? <small>{list.length}</small> : undefined}>
      {!list && <Loading error={error} onRetry={load} />}
      {list?.length === 0 && <div className="bd small muted">Nobody blocked.</div>}
      {list?.map(b => (
        <div key={b.id} className="row blocked">
          <span style={{ fontSize: 20 }}>{b.avatar}</span>
          <div className="grow"><PlayerLink id={b.id} className="t">{b.name}</PlayerLink><div className="s">blocked {ago(b.at)}</div></div>
          <Btn className="sm ghost" onClick={async () => { if (await run(() => api.unblockPlayer(b.id), { ok: () => `${b.name} unblocked` })) load() }}>Unblock</Btn>
        </div>
      ))}
    </Card>
  )
}
