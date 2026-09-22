import { useNavigate } from 'react-router-dom'
import { useGame, useMe } from '../lib/game'
import { ago, money, num } from '../lib/format'
import { Btn, Card, Stat } from '../components/ui'
import { Ribbons } from '../components/Ribbons'

export default function Profile() {
  const me = useMe()
  const { signOut } = useGame()
  const nav = useNavigate()
  const p = me.power
  return (
    <div className="page">
      <Card title={me.name} right={<small>since {ago(me.created_at)}</small>}>
        <div className="bd stack">
          <Ribbons list={me.ribbons} empty="No accolade stripes yet." />
          <div className="grid3">
            <Stat k="Cash" v={money(me.cash)} cls="gold" />
            <Stat k="Bank" v={money(me.bank)} />
            <Stat k="Diamonds" v={num(me.diamonds)} cls="dia" />
            <Stat k="Actions" v={num(me.actions_done)} />
            <Stat k="Fights" v={`${me.fights_won}W · ${me.fights_lost}L`} cls="sm" />
            <Stat k="Imports" v={num(me.imports)} />
            <Stat k="Market volume" v={money(me.market_volume)} />
            <Stat k="Storage" v={`${num(me.storage_used)}/${num(me.storage_cap)}`} />
            <Stat k="Setup slots" v={me.inventory_slots} />
          </div>
        </div>
      </Card>
      <Card title="Setups">
        {(['offense', 'defense', 'jail'] as const).map(s => (
          <div key={s} className="row link" onClick={() => nav('/items')}>
            <div className="grow t" style={{ textTransform: 'capitalize' }}>{s}</div>
            <span className="tabular">att {p[s].att} · def {p[s].def}{p[s].combo ? ' · combo' : ''}</span>
            <span className="chev">›</span>
          </div>
        ))}
      </Card>
      <Card title="Crew & Cartel">
        <div className="row link" onClick={() => nav(me.crew ? `/crew/${me.crew.id}` : '/crew')}><div className="grow t">{me.crew ? `${me.crew.emblem} ${me.crew.name}` : 'No crew'}</div><span className="chev">›</span></div>
        <div className="row link" onClick={() => nav(me.cartel ? `/cartel/${me.cartel.id}` : '/cartel')}><div className="grow t">{me.cartel ? `🕴 ${me.cartel.name}` : 'No cartel'}</div><span className="chev">›</span></div>
      </Card>
      <Btn className="ghost block" onClick={async () => { await signOut(); nav('/') }}>Sign Out</Btn>
      <p className="muted small center">Cartel Wars is an unofficial fan reconstruction of SMLSD's <i>The Cartel</i> / <i>Cartel Wars</i> (2009–2010). Not affiliated with SMLSD, Webtouch or Roasted Brains.</p>
    </div>
  )
}
