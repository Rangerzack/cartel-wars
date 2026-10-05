import { useEffect, type MouseEvent, type ReactNode } from 'react'
import { Link, NavLink, Outlet, useLocation, useNavigationType } from 'react-router-dom'
import { useGame } from '../lib/game'
import { money, num, timeLeft } from '../lib/format'
import { useNow } from '../lib/useNow'
import { Toasts } from './ui'
import { RefillSheet } from './Refill'
import { ConfirmSheet } from './Confirm'
import type { Me } from '../lib/types'
import { NamePrompt } from './NamePrompt'

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

/** `mark`: a value to draw a 1 px tick at on the track (heat: where red, the bust risk, starts). */
function Bar({ cls, label, value, max, extra, mark }: { cls: string; label: string; value: number; max: number; extra?: string; mark?: number }) {
  const pct = (v: number) => Math.max(0, Math.min(100, (v / Math.max(1, max)) * 100))
  return (
    <div className={`bar ${cls}`}>
      <div className="lbl"><span>{label}</span><span>{num(value)}/{num(max)}{extra ? ` · ${extra}` : ''}</span></div>
      <div className="track"><div className="fill" style={{ width: pct(value) + '%' }} />{mark !== undefined && mark < max && <i className="mark" style={{ left: pct(mark) + '%' }} />}</div>
    </div>
  )
}

/** A top-bar shortcut (P2-5): looks exactly like the plain text it replaces. Tapping it while already on that card
 *  (Services doesn't re-run its scroll for the same ?focus=) brings the card back into view and flashes it again. */
function TopLink({ to, label, className = '', children }: { to: string; label: string; className?: string; children: ReactNode }) {
  const loc = useLocation()
  const again = (e: MouseEvent) => {
    if (loc.pathname + loc.search !== to) return
    const el = document.getElementById(new URLSearchParams(to.split('?')[1] ?? '').get('focus') ?? '')
    if (!el) return
    e.preventDefault()
    el.scrollIntoView({ behavior: matchMedia('(prefers-reduced-motion: reduce)').matches ? 'auto' : 'smooth', block: 'start' })
    el.classList.remove('focused'); void el.offsetWidth; el.classList.add('focused')
  }
  return <Link to={to} className={`tb-link ${className}`.trim()} aria-label={label} onClick={again}>{children}</Link>
}

/** A new screen starts at the top: opening a crew from the bottom of another crew's page, or Profile from the end of
 *  Home, used to land mid-page. Back (a POP) is left to the browser, which puts the scroll back where it was. A change
 *  of query only (a tab, a filter) keeps the scroll. */
function ScrollToTop() {
  const { pathname } = useLocation()
  const how = useNavigationType()
  useEffect(() => { if (how !== 'POP') window.scrollTo({ top: 0 }) }, [pathname, how])
  return null
}

export default function Layout() {
  const { me, catalog, netDown } = useGame()
  const now = useNow()
  const onHome = useLocation().pathname === '/'
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
      <ScrollToTop />
      {me && (
        <header className="topbar">
          <Link to="/profile" className="title tb-link" aria-label={`${me.name}, ${me.crew ? me.crew.name : 'no crew'}: your profile`}>
            <span className="av">{me.avatar}</span>
            <span className="who"><b>{me.name}</b><small>{me.crew ? `${me.crew.emblem} ${me.crew.name}` : 'no crew'}</small></span>
          </Link>
          <div className="money tabular">
            <TopLink to="/services?focus=bank" className="cash" label={`${money(me.cash)} cash: bank`}>{money(me.cash)}</TopLink>
            <TopLink to="/store" className="dia" label={`${num(me.diamonds)} diamonds: store`}>💎 {num(me.diamonds)}</TopLink>
            {/* locked up, the heat corner says so (heat is maxed inside anyway) and takes you to bail */}
            {me.jailed
              ? <TopLink to="/services?focus=jail" className="jail-tag" label="In jail until you post bail: jail">🔒 Jail</TopLink>
              : <TopLink to="/services?focus=police" label={`Heat ${num(me.heat)} of ${num(me.heat_max)}: police`}>
                  <Bar cls={`heat mini ${me.heat_level}`} label="🔥" value={me.heat} max={me.heat_max} mark={me.heat_red ?? catalog?.config.heat_red} />
                </TopLink>}
          </div>
          <div className="bars">
            <TopLink to="/services?focus=refills" label={`Stamina ${num(me.stamina)} of ${num(me.stamina_max)}: refills`}>
              <Bar cls="stamina" label="⚡ Stamina" value={me.stamina} max={me.stamina_max} extra={me.stamina < me.stamina_max ? timeLeft(me.next_tick, now) : undefined} />
            </TopLink>
            <TopLink to="/services?focus=hospital" label={`Health ${num(me.health)} of ${num(me.health_max)}: hospital`}>
              <Bar cls="health" label="❤️ Health" value={me.health} max={me.health_max} extra={me.health < me.health_max ? timeLeft(me.health_next, now) : undefined} />
            </TopLink>
          </div>
        </header>
      )}
      {/* the strip only says what nothing else on screen does: offline anywhere, the hospital off Home (the top bar's
          JAIL tag covers jail, and Home's Next up covers both) */}
      {me && (netDown || (me.hospital && !onHome)) && (
        <div className="status-strip">
          {netDown && <span className="pill red">📡 Offline · retrying</span>}
          {me.hospital && !onHome && <span className="pill red">🏥 Hospitalized</span>}
        </div>
      )}
      {me && <NamePrompt />}
      <Outlet />
      <RefillSheet />
      <ConfirmSheet />
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
