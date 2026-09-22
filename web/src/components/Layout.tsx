import { NavLink, Outlet, useNavigate } from 'react-router-dom'
import { useGame } from '../lib/game'
import { money, num, timeLeft } from '../lib/format'
import { useNow } from '../lib/useNow'
import { Toasts } from './ui'

function Bar({ cls, label, value, max, extra }: { cls: string; label: string; value: number; max: number; extra?: string }) {
  const pct = Math.max(0, Math.min(100, (value / Math.max(1, max)) * 100))
  return (
    <div className={`bar ${cls}`}>
      <div className="lbl"><span>{label}</span><span>{num(value)}/{num(max)}{extra ? ` · ${extra}` : ''}</span></div>
      <div className="track"><div className="fill" style={{ width: pct + '%' }} /></div>
    </div>
  )
}

export default function Layout() {
  const { me } = useGame()
  const now = useNow()
  const nav = useNavigate()
  const tabs = [
    { to: '/', ic: '🏠', l: 'Home' },
    { to: '/actions', ic: '💼', l: 'Actions' },
    { to: '/economy', ic: '🌿', l: 'Economy' },
    { to: '/fight', ic: '🔫', l: 'Fight' },
    { to: '/services', ic: '🏦', l: 'Services' },
    { to: '/chat', ic: '💬', l: 'Chat' },
  ]
  return (
    <div className="app">
      <Toasts />
      {me && (
        <header className="topbar">
          <div className="title" onClick={() => nav('/profile')} style={{ cursor: 'pointer' }}>
            <span style={{ marginRight: 6 }}>{me.avatar}</span>{me.name}<small>{me.crew ? `${me.crew.emblem} ${me.crew.name}` : 'no crew'}</small>
          </div>
          <div className="money tabular">{money(me.cash)}<span className="dia">💎 {num(me.diamonds)}</span></div>
          <div className="bars">
            <Bar cls="stamina" label="Stamina" value={me.stamina} max={me.stamina_max} extra={me.stamina < me.stamina_max ? timeLeft(me.next_tick, now) : undefined} />
            <Bar cls="health" label="Health" value={me.health} max={me.health_max} />
            <Bar cls={`heat ${me.heat_level}`} label="Heat" value={me.heat} max={me.heat_max} />
          </div>
        </header>
      )}
      {me && (me.jailed || me.hospital || me.immune) && (
        <div className="status-strip">
          {me.jailed && <span className="pill red">🔒 In jail · {timeLeft(me.jail_until, now)}</span>}
          {me.hospital && <span className="pill red">🏥 Hospitalized</span>}
          {me.immune && <span className="pill blue">🛡 New-player immunity · {timeLeft(me.immune_until, now)}</span>}
        </div>
      )}
      <Outlet />
      <nav className="tabbar">
        <div className="inner">
          {tabs.map(t => (
            <NavLink key={t.to} to={t.to} end={t.to === '/'} className={({ isActive }) => (isActive ? 'active' : '')}>
              <span className="ic">{t.ic}</span>{t.l}
            </NavLink>
          ))}
        </div>
      </nav>
    </div>
  )
}
