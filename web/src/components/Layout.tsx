import { useEffect } from 'react'
import { NavLink, Outlet, useNavigate } from 'react-router-dom'
import { useGame } from '../lib/game'
import { money, num, timeLeft } from '../lib/format'
import { useNow } from '../lib/useNow'
import { Toasts } from './ui'
import type { Me } from '../lib/types'

type Badge = { n: number; tone?: 'red' | 'gold'; dot?: boolean; label: string } | null

/** What each tab wants you to look at. Counts show a number; "dot" badges just flag a state. */
function badges(me: Me): Record<string, Badge> {
  const activity = me.unread_activity ?? 0
  const dms = me.unread_dms ?? 0
  const collect = me.hustlers.filter(h => h.back).length
    + me.grow_houses.filter(g => g.running && g.produced >= g.cap).length
    + me.listings.filter(l => l.held).length
  const staminaFull = me.stamina >= me.stamina_max && !me.jailed && !me.hospital
  return {
    '/': activity ? { n: activity, tone: 'red', label: `${activity} new on Home` } : null,
    '/actions': staminaFull ? { n: 0, dot: true, tone: 'gold', label: 'stamina full' } : null,
    '/economy': collect ? { n: collect, tone: 'gold', label: `${collect} ready to collect` } : null,
    '/services': me.jailed || me.hospital ? { n: 0, dot: true, tone: 'red', label: me.jailed ? 'in jail' : 'in the hospital' } : null,
    '/chat': dms ? { n: dms, tone: 'red', label: `${dms} unread conversation${dms > 1 ? 's' : ''}` } : null,
  }
}

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
  const b = me ? badges(me) : {}
  const unread = (me?.unread_activity ?? 0) + (me?.unread_dms ?? 0)
  // (2) in the browser tab title, and the home-screen app icon badge where the platform supports it
  useEffect(() => {
    document.title = unread ? `(${unread}) Cartel Wars` : 'Cartel Wars'
    const n = navigator as Navigator & { setAppBadge?: (n?: number) => Promise<void>; clearAppBadge?: () => Promise<void> }
    try { if (unread) n.setAppBadge?.(unread)?.catch(() => {}); else n.clearAppBadge?.()?.catch(() => {}) } catch { /* unsupported */ }
  }, [unread])
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
          <div className="title" onClick={() => nav('/profile')}>
            <span className="av">{me.avatar}</span>
            <span className="who"><b>{me.name}</b><small>{me.crew ? `${me.crew.emblem} ${me.crew.name}` : 'no crew'}</small></span>
          </div>
          <div className="money tabular">
            <span className="cash">{money(me.cash)}</span><span className="dia">💎 {num(me.diamonds)}</span>
            <Bar cls={`heat mini ${me.heat_level}`} label="🔥" value={me.heat} max={me.heat_max} />
          </div>
          <div className="bars">
            <Bar cls="stamina" label="⚡ Stamina" value={me.stamina} max={me.stamina_max} extra={me.stamina < me.stamina_max ? timeLeft(me.next_tick, now) : undefined} />
            <Bar cls="health" label="❤️ Health" value={me.health} max={me.health_max} extra={me.health < me.health_max ? timeLeft(me.health_next, now) : undefined} />
          </div>
        </header>
      )}
      {me && (me.jailed || me.hospital) && (
        <div className="status-strip">
          {me.jailed && <span className="pill red">🔒 In jail · {timeLeft(me.jail_until, now)}</span>}
          {me.hospital && <span className="pill red">🏥 Hospitalized</span>}
        </div>
      )}
      <Outlet />
      <nav className="tabbar">
        <div className="inner">
          {tabs.map(t => (
            <NavLink key={t.to} to={t.to} end={t.to === '/'} className={({ isActive }) => (isActive ? 'active' : '')}
              aria-label={b[t.to] ? `${t.l}, ${b[t.to]!.label}` : undefined}>
              <span className="icw"><span className="ic">{t.ic}</span>{b[t.to] && <span className={`tbadge ${b[t.to]!.tone ?? 'red'} ${b[t.to]!.dot ? 'dot' : ''}`}>{b[t.to]!.dot ? '' : b[t.to]!.n > 99 ? '99+' : b[t.to]!.n}</span>}</span>{t.l}
            </NavLink>
          ))}
        </div>
      </nav>
    </div>
  )
}
