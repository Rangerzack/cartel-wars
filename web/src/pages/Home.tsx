import { useEffect, useState } from 'react'
import { Link } from 'react-router-dom'
import { api } from '../lib/api'
import type { ActivityItem, FightLog } from '../lib/types'
import { useGame, useMe } from '../lib/game'
import { ago, money, num, timeLeft } from '../lib/format'
import { scrollBehavior } from '../lib/scroll'
import { useNow } from '../lib/useNow'
import { Card, RowLink, Stat } from '../components/ui'
import { Ribbons } from '../components/Ribbons'
import { GettingStarted } from '../components/GettingStarted'
import { features } from '../lib/features'
import { ActivityRow } from '../components/Activity'
import { HomePath } from '../components/Path'
import { DailyDrop } from '../components/DailyDrop'

type Tile = { to: string; ic: string; l: string; badge?: { n: number; tone: 'red' | 'gold'; label: string } }

export default function Home() {
  const me = useMe()
  const now = useNow()
  const off = me.power.offense, def = me.power.defense
  const { refresh, catalog } = useGame()
  const healAmt = catalog?.config.health_regen_amount ?? 10
  const heatRed = me.heat_red ?? catalog?.config.heat_red ?? 75
  const full = me.grow_houses.filter(g => g.running && g.produced >= g.cap).length
  const back = me.hustlers.filter(h => h.back).length
  const [fights, setFights] = useState<FightLog[]>([])
  useEffect(() => { api.fights(3).then(setFights).catch(() => {}) }, [me.fights_won, me.fights_lost])
  // "While you were away": unseen activity, until the player clears it or opens the Activity page
  const unread = me.unread_activity ?? 0
  const [fetched, setAway] = useState<ActivityItem[]>([])
  useEffect(() => {
    if (unread) api.activity(20).then(l => setAway(l.filter(a => !a.seen))).catch(() => setAway([]))
  }, [unread])
  const away = unread ? fetched : []
  const clearAway = () => { setAway([]); api.activitySeen().then(() => refresh()).catch(() => {}) }

  // The places with no tab, one tap from Home (P2-4). The counts the old rows spelled out ride along as badges.
  const crewWaiting = (me.crew?.applications ?? 0) + (me.crew?.invites ?? 0)
  const stripes = me.ribbons.length
  const tiles: Tile[] = [
    { to: '/items', ic: '🎒', l: 'Items' },
    { to: me.crew ? `/crew/${me.crew.id}` : '/crew', ic: me.crew?.emblem ?? '🏴', l: me.crew?.name ?? 'Crew',
      badge: crewWaiting ? { n: crewWaiting, tone: 'red', label: `${crewWaiting} waiting on you` } : undefined },
    { to: me.cartel ? `/cartel/${me.cartel.id}` : '/cartel', ic: '🕴', l: 'Cartel' },
    { to: '/territory', ic: '🗺', l: 'Territory' },
    { to: '/casino', ic: '🎰', l: 'Casino' },
    features.forum ? { to: '/forum', ic: '🗣', l: 'Forum' } : { to: '/fight?tab=top', ic: '🏆', l: 'Top Users' },
    { to: '/activity', ic: '📰', l: 'Activity', badge: unread ? { n: unread, tone: 'red', label: `${unread} new` } : undefined },
    { to: '/accolades', ic: '🎖', l: 'Accolades', badge: stripes ? { n: stripes, tone: 'gold', label: `${stripes} stripe${stripes > 1 ? 's' : ''} this week` } : undefined },
    { to: '/store', ic: '💎', l: 'Store' },
  ]

  return (
    <div className="page">
      {me.jailed && (
        <div className="notice red">You're locked up{me.jail_until ? <> for another {timeLeft(me.jail_until, now)}</> : <> until you post bail</>}. Only jail actions work, and you can only fight other inmates, with your jail setup. <Link to="/services?focus=jail">Post bail →</Link></div>
      )}
      {me.hospital && (
        <div className="notice red">You're in the hospital at {me.health} health — +{healAmt} in {timeLeft(me.health_next, now)}, out at {me.hospital_out_at ?? 20}. <Link to="/services?focus=hospital">Buy health →</Link></div>
      )}
      {me.is_admin && (me.reports_open ?? 0) > 0 && <div className="notice blue">🛡 {me.reports_open} player{me.reports_open === 1 ? ' has' : 's have'} open reports. <Link to="/admin">Review →</Link></div>}
      {back > 0 && <div className="notice gold">{back} hustler trip{back > 1 ? 's are' : ' is'} back with cash. <Link to="/economy?tab=hustlers">Collect →</Link></div>}
      {(me.drop?.crates ?? 0) > 0 && <div className="notice gold">📦 {me.drop!.crates === 1 ? 'A Daily Drop crate is' : `${me.drop!.crates} Daily Drop crates are`} waiting. <button type="button" className="linkbtn" onClick={() => document.getElementById('drop')?.scrollIntoView({ behavior: scrollBehavior(), block: 'center' })}>Open →</button></div>}
      {full > 0 && <div className="notice gold">{full} grow house{full > 1 ? 's are' : ' is'} full — collect to keep production going. <Link to="/economy">Collect →</Link></div>}

      {/* Cash and diamonds are already in the top bar (P3-19); Storage replaces the old Storage card and opens Economy, where Expand is */}
      <div className="grid3">
        <Stat k="Heat" v={`🔥 ${num(me.heat)}/${num(me.heat_max)}`} cls={me.heat >= heatRed ? 'red' : ''} />
        <Stat k="Bank" v={money(me.bank)} />
        <Stat k="Reputation" v={`⭐ ${num(me.reputation)}`} cls="dia" />
        <Stat k="Attack" v={off.att} />
        <Stat k="Defense" v={def.def} />
        <Link to="/economy" className="stat-link"><Stat k="Storage" v={`${num(me.storage_used)}/${num(me.storage_cap)}`} /></Link>
      </div>

      <nav className="quick" aria-label="More places">
        {tiles.map(t => (
          <Link key={t.l} to={t.to} aria-label={t.badge ? `${t.l}, ${t.badge.label}` : undefined}>
            <span className="ico">{t.ic}{t.badge && <span className={`tbadge ${t.badge.tone}`}>{t.badge.n > 99 ? '99+' : t.badge.n}</span>}</span>
            <span className="lbl">{t.l}</span>
          </Link>
        ))}
      </nav>

      {away.length > 0 && (
        <Card title="While you were away" className="away" right={<button className="btn sm ghost" onClick={clearAway}>Clear</button>}>
          {away.slice(0, 6).map(a => <ActivityRow key={a.id} a={a} fresh />)}
          <RowLink to="/activity" className="more">
            <div className="grow small muted">{away.length > 6 ? `${away.length - 6} more · ` : ''}See all activity</div><span className="chev">›</span>
          </RowLink>
        </Card>
      )}

      <HomePath />

      {me.ribbons.length > 0 && <Ribbons list={me.ribbons} />}
      <GettingStarted me={me} />

      <DailyDrop compact />

      {fights.length > 0 && (
        <Card title="Latest fights" right={<small className="tabular">{me.fights_won}W · {me.fights_lost}L · <Link to="/fight?tab=log">all ›</Link></small>}>
          {fights.map(f => {
            const otherId = f.i_attacked ? f.defender_id : f.attacker_id
            // a player who deleted their account has no profile to open
            const other = otherId ? (f.i_attacked ? f.defender : f.attacker) : <span className="muted">Deleted player</span>
            const body = <>
              <span>{f.won ? '🏆' : '💀'}</span>
              <div className="grow"><div className="t">{f.i_attacked ? <>You attacked {other}</> : <>{other} attacked you</>}</div><div className="s">{f.won ? 'won' : 'lost'} · {ago(f.at)}</div></div>
              {f.cash === 0 ? <span className="tabular muted">$0</span> : <b className={`tabular ${f.won ? 'gold' : 'red'}`}>{f.won ? '+' : '−'}{money(f.cash)}</b>}
            </>
            return otherId ? <RowLink key={f.id} to={`/player/${otherId}`}>{body}</RowLink> : <div key={f.id} className="row">{body}</div>
          })}
        </Card>
      )}
    </div>
  )
}
