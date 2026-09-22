import { Link, useNavigate } from 'react-router-dom'
import { useGame, useMe } from '../lib/game'
import { commodityIcon, money, num, timeLeft } from '../lib/format'
import { useNow } from '../lib/useNow'
import { Card, Stat } from '../components/ui'
import { Ribbons } from '../components/Ribbons'
import { GettingStarted } from '../components/GettingStarted'

function HeatGauge({ heat, max, yellow, red }: { heat: number; max: number; yellow: number; red: number }) {
  const segs = 20
  const on = Math.round((heat / max) * segs)
  return (
    <div className="heat-gauge">
      {Array.from({ length: segs }, (_, i) => {
        const v = ((i + 1) / segs) * max
        const cls = v >= red ? 'r' : v >= yellow ? 'y' : 'g'
        return <div key={i} className={`seg-l ${i < on ? 'on ' + cls : ''}`} />
      })}
    </div>
  )
}

export default function Home() {
  const me = useMe()
  const { catalog } = useGame()
  const now = useNow()
  const nav = useNavigate()
  const cfg = catalog?.config ?? {}
  const off = me.power.offense, def = me.power.defense
  const ready = me.grow_houses.filter(g => g.produced > 0).length
  const back = me.hustlers.filter(h => h.back).length

  const links: { to: string; ic: string; t: string; s: string }[] = [
    { to: '/items', ic: '🎒', t: 'Inventory & Setups', s: `${me.inventory_slots} slots · att ${off.att} / def ${def.def}` },
    { to: '/economy', ic: '🏭', t: 'Grow Houses & Storage', s: `${me.grow_houses.length} houses · ${num(me.storage_used)}/${num(me.storage_cap)} stored${ready ? ` · ${ready} ready` : ''}` },
    { to: me.crew ? `/crew/${me.crew.id}` : '/crew', ic: me.crew?.emblem ?? '🏴', t: me.crew ? me.crew.name : 'Join a Crew', s: me.crew ? `${me.crew.members} members${me.crew.is_capo ? ' · you are Capo' : ''}${me.crew.applications ? ` · ${me.crew.applications} application${me.crew.applications > 1 ? 's' : ''} waiting` : ''}${me.crew.invites ? ` · ${me.crew.invites} cartel invite${me.crew.invites > 1 ? 's' : ''}` : ''}` : 'Crews hold blocks and run turf wars' },
    { to: me.cartel ? `/cartel/${me.cartel.id}` : '/cartel', ic: '🕴', t: me.cartel ? me.cartel.name : 'Cartels', s: me.cartel ? (me.cartel.is_don ? 'You are the Don' : 'Your cartel') : 'Alliances of crews' },
    { to: '/territory', ic: '🗺', t: 'Territory', s: 'Hoods & blocks across four islands' },
    { to: '/accolades', ic: '🎖', t: 'Accolades', s: me.ribbons.length ? `${me.ribbons.length} stripe${me.ribbons.length > 1 ? 's' : ''} this week` : 'Weekly ranked stripes' },
    { to: '/fight?tab=top', ic: '🏆', t: 'Top Users', s: 'Fighters, hustlers, traders, crews' },
  ]

  return (
    <div className="page">
      {me.jailed && (
        <div className="notice red">You're locked up until {timeLeft(me.jail_until, now)} from now. Only jail actions work, and fights use your jail setup. <Link to="/services">Post bail →</Link></div>
      )}
      {me.hospital && (
        <div className="notice red">You're in the hospital. No actions or fights until you check out. <Link to="/services">Hospital →</Link></div>
      )}
      {back > 0 && <div className="notice gold">{back} hustler trip{back > 1 ? 's are' : ' is'} back with cash. <Link to="/economy?tab=hustlers">Collect →</Link></div>}

      {me.ribbons.length > 0 && <Ribbons list={me.ribbons} />}
      <GettingStarted me={me} />
      <Card title="Heat" right={<small className={me.heat_level}>{me.heat_level.toUpperCase()} · {me.heat}/{me.heat_max}</small>}>
        <div className="bd stack">
          <HeatGauge heat={me.heat} max={me.heat_max} yellow={cfg.heat_yellow ?? 40} red={cfg.heat_red ?? 75} />
          <div className="small muted">Actions and attacks raise heat. In the red, every move risks getting busted. Heat cools 1 point every 10 minutes, or bribe it down at the Police Station.</div>
        </div>
      </Card>

      <div className="grid3">
        <Stat k="Cash" v={money(me.cash)} cls="gold" />
        <Stat k="Bank" v={money(me.bank)} />
        <Stat k="Diamonds" v={`💎 ${num(me.diamonds)}`} cls="dia" />
        <Stat k="Attack" v={off.att} />
        <Stat k="Defense" v={def.def} />
        <Stat k="Fights" v={`${me.fights_won}W · ${me.fights_lost}L`} cls="sm" />
      </div>

      <Card title="Storage" right={<small>{num(me.storage_used)} / {num(me.storage_cap)}</small>}>
        <div className="bd hstack" style={{ justifyContent: 'space-around' }}>
          {(['herb', 'dust', 'pills'] as const).map(c => (
            <div key={c} className="center">
              <div style={{ fontSize: 22 }}>{commodityIcon[c]}</div>
              <div className="tabular"><b>{num(me.storage[c] ?? 0)}</b></div>
              <div className="small muted">{money(me.prices[c])}/u</div>
            </div>
          ))}
        </div>
      </Card>

      <Card>
        {links.map(l => (
          <div key={l.to} className="row link" onClick={() => nav(l.to)}>
            <span style={{ fontSize: 22, width: 30, textAlign: 'center' }}>{l.ic}</span>
            <div className="grow"><div className="t">{l.t}</div><div className="s">{l.s}</div></div>
            <span className="chev">›</span>
          </div>
        ))}
      </Card>
    </div>
  )
}
