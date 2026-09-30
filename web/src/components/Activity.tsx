import type { ReactNode } from 'react'
import { useNavigate } from 'react-router-dom'
import type { ActivityItem } from '../lib/types'
import { ago, commodityIcon, money, num } from '../lib/format'
import { CrewLink, PlayerLink } from './Linked'
import { ComboPill } from './Combo'

const icon: Record<ActivityItem['kind'], string> = {
  attacked: '⚔️', crew_fight: '🏴', siege: '🧱', block_lost: '🚩', block_taken: '🏁', sold: '💵', applied: '📨', joined: '🤝', kicked: '🚪',
  daily_cash: '💰',
}

/** Where tapping an activity line takes you. */
export function activityLink(a: ActivityItem): string | null {
  switch (a.kind) {
    case 'attacked': return a.actor_id ? `/player/${a.actor_id}` : '/fight?tab=log'
    case 'crew_fight': case 'joined': case 'kicked': case 'applied': return a.crew_id ? `/crew/${a.crew_id}` : '/crew'
    case 'siege': case 'block_lost': case 'block_taken': return a.hood_id ? `/territory?hood=${a.hood_id}${a.block_id ? `&block=${a.block_id}` : ''}` : '/territory'
    case 'sold': return '/economy?tab=market'
    case 'daily_cash': return '/services?focus=bank'
    default: return null
  }
}

/** Signed cash change for you, when the line has one. */
function amount(a: ActivityItem): number | null {
  const d = a.data
  if (a.kind === 'attacked') { const net = (d.cash_won ?? 0) - (d.cash_lost ?? 0); return net === 0 ? null : net }
  if (a.kind === 'sold' || a.kind === 'daily_cash') return d.cash ?? null
  return null
}

function Sentence({ a }: { a: ActivityItem }) {
  const who = a.actor ? <PlayerLink id={a.actor_id} className="strong">{a.actor}</PlayerLink> : <>Someone</>
  const crew = a.crew ? <CrewLink id={a.crew_id} className="strong">{a.crew_emblem ? `${a.crew_emblem} ` : ''}{a.crew}</CrewLink> : <>a crew</>
  const block = <b>{a.block ?? 'a block'}</b>
  const d = a.data
  let body: ReactNode
  switch (a.kind) {
    case 'attacked': {
      const n = d.n ?? 1, held = typeof d.held === 'number' ? d.held : d.held ? 1 : 0
      body = n === 1
        ? <>{who} attacked you{d.combo ? <> with <ComboPill code={d.combo} /></> : null} — {held ? <span className="green">you held them off</span> : <span className="red">you lost</span>}{d.hospital ? <> and ended up in the hospital</> : null}</>
        : <>{who} attacked you {n}×{d.combo ? <> (last with <ComboPill code={d.combo} />)</> : null} — you held {held}, lost {n - held}{d.hospital ? <>, and ended up in the hospital</> : null}</>
      break
    }
    case 'crew_fight': body = <>{crew} hit your crew{a.actor ? <> ({who} led it)</> : null} — {d.held ? <span className="green">you held the line</span> : <span className="red">they won</span>}</>; break
    case 'siege': body = a.siege_wins != null
      ? <>{crew} is sieging your block {block} — <b className="tabular">{num(a.siege_wins)}/{num(a.siege_need ?? 50)}</b> hits</>
      : <>{crew} laid siege to your block {block}</>; break
    case 'block_lost': body = <>{crew} took your block {block}{a.actor ? <> ({who})</> : null}</>; break
    case 'block_taken': body = <>{who} took {block} for your crew{a.crew ? <> from {crew}</> : null}</>; break
    case 'sold': body = <>{who} bought {num(d.units ?? 0)} {d.commodity ? `${commodityIcon[d.commodity]} ${d.commodity}` : 'units'} from your listing</>; break
    case 'applied': body = <>{who} applied to join your crew</>; break
    case 'joined': body = <>{who} let you into {crew}</>; break
    case 'kicked': body = <>{who} removed you from {crew}</>; break
    case 'daily_cash': body = (d.days ?? 1) > 1
      ? <>Daily cash for {d.days} days landed on hand — bank it before someone takes it</>
      : <>Daily cash landed on hand — bank it before someone takes it</>; break
    default: body = null
  }
  return <>{body}</>
}

export function ActivityRow({ a, fresh }: { a: ActivityItem; fresh?: boolean }) {
  const nav = useNavigate()
  const to = activityLink(a)
  const amt = amount(a)
  return (
    <div className={`row activity ${to ? 'link' : ''} ${fresh ? 'fresh' : ''}`} onClick={() => to && nav(to)}>
      <span className="ico">{icon[a.kind]}</span>
      <div className="grow">
        <div className="t2"><Sentence a={a} /></div>
        <div className="s">{ago(a.at)}</div>
      </div>
      {amt != null && <b className={`tabular ${amt > 0 ? 'gold' : 'red'}`}>{amt > 0 ? '+' : '−'}{money(Math.abs(amt))}</b>}
    </div>
  )
}
