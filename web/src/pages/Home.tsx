import { useEffect, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { api } from '../lib/api'
import { ago } from '../lib/format'
import type { ActivityItem, FightLog } from '../lib/types'
import { useGame, useMe } from '../lib/game'
import { commodityIcon, money, num, timeLeft } from '../lib/format'
import { useNow } from '../lib/useNow'
import { Card, Stat } from '../components/ui'
import { Ribbons } from '../components/Ribbons'
import { GettingStarted } from '../components/GettingStarted'
import { features } from '../lib/features'
import { ActivityRow } from '../components/Activity'
import { HomePath } from '../components/Path'
import { DailyDrop } from '../components/DailyDrop'

export default function Home() {
  const me = useMe()
  const now = useNow()
  const nav = useNavigate()
  const off = me.power.offense, def = me.power.defense
  const { refresh, catalog } = useGame()
  const healAmt = catalog?.config.health_regen_amount ?? 10
  const ready = me.grow_houses.filter(g => g.produced > 0).length
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

  const links: { to: string; ic: string; t: string; s: string }[] = [
    { to: '/items', ic: '🎒', t: 'Inventory & Setups', s: `${me.inventory_slots} slots · att ${off.att} / def ${def.def}` },
    { to: '/economy', ic: '🏭', t: 'Grow Houses & Storage', s: `${me.grow_houses.length} houses · ${num(me.storage_used)}/${num(me.storage_cap)} stored${ready ? ` · ${ready} ready` : ''}` },
    { to: me.crew ? `/crew/${me.crew.id}` : '/crew', ic: me.crew?.emblem ?? '🏴', t: me.crew ? me.crew.name : 'Join a Crew', s: me.crew ? `${me.crew.members} members${me.crew.is_capo ? ' · you are Capo' : ''}${me.crew.applications ? ` · ${me.crew.applications} application${me.crew.applications > 1 ? 's' : ''} waiting` : ''}${me.crew.invites ? ` · ${me.crew.invites} cartel invite${me.crew.invites > 1 ? 's' : ''}` : ''}` : 'Crews hold blocks and run turf wars' },
    { to: me.cartel ? `/cartel/${me.cartel.id}` : '/cartel', ic: '🕴', t: me.cartel ? me.cartel.name : 'Cartels', s: me.cartel ? (me.cartel.is_don ? 'You are the Don' : 'Your cartel') : 'Alliances of crews' },
    { to: '/territory', ic: '🗺', t: 'Territory', s: '81 hoods · 6 blocks each · bonuses every 24h' },
    { to: '/casino', ic: '🎰', t: 'Casino', s: features.casinoGames.length > 1 ? 'Live poker, blackjack, craps, roulette, slots' : 'Slots are open · tables coming soon' },
    ...(features.forum ? [{ to: '/forum', ic: '🗣', t: 'Forum', s: 'Game updates, help, market, war, suggestions' }] : []),
    { to: '/activity', ic: '📰', t: 'Activity', s: unread ? `${unread} new` : 'Attacks on you, sales, sieges, crew news' },
    { to: '/accolades', ic: '🎖', t: 'Accolades', s: me.ribbons.length ? `${me.ribbons.length} stripe${me.ribbons.length > 1 ? 's' : ''} this week` : 'Weekly ranked stripes' },
    { to: '/fight?tab=top', ic: '🏆', t: 'Top Users', s: 'Fighters, hustlers, traders, crews' },
  ]

  return (
    <div className="page">
      {me.jailed && (
        <div className="notice red">You're locked up until {timeLeft(me.jail_until, now)} from now. Only jail actions work, and fights use your jail setup. <Link to="/services">Post bail →</Link></div>
      )}
      {me.hospital && (
        <div className="notice red">You're in the hospital at {me.health} health — +{healAmt} in {timeLeft(me.health_next, now)}, out at {me.hospital_out_at ?? 20}. <Link to="/services">Buy health →</Link></div>
      )}
      {back > 0 && <div className="notice gold">{back} hustler trip{back > 1 ? 's are' : ' is'} back with cash. <Link to="/economy?tab=hustlers">Collect →</Link></div>}
      {(me.drop?.crates ?? 0) > 0 && <div className="notice gold">📦 {me.drop!.crates === 1 ? 'A Daily Drop crate is' : `${me.drop!.crates} Daily Drop crates are`} waiting. <a onClick={() => document.getElementById('drop')?.scrollIntoView({ behavior: 'smooth', block: 'center' })}>Open →</a></div>}
      {full > 0 && <div className="notice gold">{full} grow house{full > 1 ? 's are' : ' is'} full — collect to keep production going. <Link to="/economy">Collect →</Link></div>}

      {away.length > 0 && (
        <Card title="While you were away" className="away" right={<button className="btn sm ghost" onClick={clearAway}>Clear</button>}>
          {away.slice(0, 6).map(a => <ActivityRow key={a.id} a={a} fresh />)}
          <div className="row link more" onClick={() => nav('/activity')}>
            <div className="grow small muted">{away.length > 6 ? `${away.length - 6} more · ` : ''}See all activity</div><span className="chev">›</span>
          </div>
        </Card>
      )}

      <HomePath />

      {me.ribbons.length > 0 && <Ribbons list={me.ribbons} />}
      <GettingStarted me={me} />

      <div className="grid3">
        <Stat k="Cash" v={money(me.cash)} cls="gold" />
        <Stat k="Bank" v={money(me.bank)} />
        <Stat k="Diamonds" v={`💎 ${num(me.diamonds)}`} cls="dia" />
        <Stat k="Attack" v={off.att} />
        <Stat k="Defense" v={def.def} />
        <Stat k="Fights" v={`${me.fights_won}W · ${me.fights_lost}L`} cls="sm" />
      </div>

      <DailyDrop />

      <Card title="Storage" right={<small>{num(me.storage_used)} / {num(me.storage_cap)}</small>}>
        <div className="bd hstack" style={{ justifyContent: 'space-around' }}>
          {(['herb', 'dust', 'pills'] as const).map(c => (
            <div key={c} className="center">
              <div style={{ fontSize: 22 }}>{commodityIcon[c]}</div>
              <div className="tabular bignum">{num(me.storage[c] ?? 0)}</div>
              <div className="small muted">{money(me.prices[c])}/u</div>
            </div>
          ))}
        </div>
      </Card>

      {fights.length > 0 && (
        <Card title="Latest fights" right={<Link to="/fight?tab=log" className="small">all ›</Link>}>
          {fights.map(f => (
            <div key={f.id} className="row link" onClick={() => nav(`/player/${f.i_attacked ? f.defender_id : f.attacker_id}`)}>
              <span>{f.won ? '🏆' : '💀'}</span>
              <div className="grow"><div className="t">{f.i_attacked ? `You attacked ${f.defender}` : `${f.attacker} attacked you`}</div><div className="s">{f.won ? 'won' : 'lost'} · {ago(f.at)}</div></div>
              <b className={`tabular ${f.won ? 'gold' : 'red'}`}>{f.won ? '+' : '−'}{money(f.cash)}</b>
            </div>
          ))}
        </Card>
      )}

      <Card>
        {links.map(l => (
          <div key={l.to} className="row link" onClick={() => nav(l.to)}>
            <span className="ico">{l.ic}</span>
            <div className="grow"><div className="t">{l.t}</div><div className="s">{l.s}</div></div>
            <span className="chev">›</span>
          </div>
        ))}
      </Card>
    </div>
  )
}
