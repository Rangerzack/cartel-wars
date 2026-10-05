import type { ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { api } from '../lib/api'
import { useGame, useMe } from '../lib/game'
import { money, timeLeft } from '../lib/format'
import { collectHouses, collectedLine, producedNow } from '../lib/grow'
import { useNow } from '../lib/useNow'
import { BailButton } from './Bail'
import { HealButton } from './Heal'
import { useCrateOpener } from './CrateOpener'
import { Btn, Card } from './ui'

type Item = { key: string; ico: string; t: ReactNode; s?: ReactNode; tone: 'urgent' | 'ready' | 'info'; act: ReactNode; wide?: boolean }

/**
 * Home's first card: what needs you right now, most urgent first, each with the one thing to do about it, done in place
 * (Phase 3). It replaced six notices that stacked above the stats: jail, the hospital, open reports, trips back, crates
 * waiting and full grow houses. Paying (bail, healing) is a full-width gold button with its reason under it when you're
 * short; collecting and opening sit on the right of their line. Nothing waiting, no card.
 */
export function NextUp() {
  const me = useMe()
  const { catalog, run, meAt } = useGame()
  const now = useNow(10_000)
  const crate = useCrateOpener()
  const items: Item[] = []

  if (me.jailed) items.push({
    key: 'jail', ico: '🚔', tone: 'urgent', wide: true,
    t: "You're locked up",
    s: <>{me.jail_until ? <>Out in {timeLeft(me.jail_until, now)}</> : <>Out when you post bail</>}. Till then: jail jobs only, and fights with other inmates using your jail setup.</>,
    act: <BailButton />,
  })
  if (me.hospital) items.push({
    key: 'hospital', ico: '🏥', tone: 'urgent', wide: true,
    t: "You're in the hospital",
    s: <>{me.health} health · +{catalog?.config.health_regen_amount ?? 10} in {timeLeft(me.health_next, now)}, out at {me.hospital_out_at ?? 20}.</>,
    act: <HealButton />,
  })
  if (me.is_admin && (me.reports_open ?? 0) > 0) items.push({
    key: 'reports', ico: '🛡', tone: 'info',
    t: `${me.reports_open} open report${me.reports_open === 1 ? '' : 's'}`, s: 'Players waiting on a review',
    act: <Link to="/admin" className="btn sm">Review</Link>,
  })
  const crates = me.drop?.crates ?? 0
  if (crates > 0) items.push({
    key: 'crates', ico: '📦', tone: 'ready',
    t: crates === 1 ? 'A Daily Drop crate is waiting' : `${crates} Daily Drop crates are waiting`,
    s: me.drop && crates >= me.drop.max && me.drop.subscribed ? <span className="gold">Your stack is full — open one or tomorrow's is lost.</span> : undefined,
    act: <Btn className="sm doit" onClick={crate.open}>Open</Btn>,
  })
  const back = me.hustlers.filter(h => h.back)
  if (back.length > 0) items.push({
    key: 'hustlers', ico: '🚶', tone: 'ready',
    t: `${back.length} hustler trip${back.length > 1 ? 's are' : ' is'} back`, s: <>{money(back.reduce((n, h) => n + h.cash_due, 0))} to collect</>,
    act: <Btn className="sm doit" onClick={() => run(api.collectHustlers, { ok: r => `Collected ${money(r.cash)}` })}>Collect</Btn>,
  })
  const full = me.grow_houses.filter(g => g.running && producedNow(g, now, meAt) >= g.cap)
  if (full.length > 0 && catalog) items.push({
    key: 'grow', ico: '🌿', tone: 'ready',
    t: `${full.length} grow house${full.length > 1 ? 's are' : ' is'} full`, s: 'Production stops until you collect',
    act: <Btn className="sm doit" onClick={() => run(() => collectHouses(me.grow_houses.filter(g => producedNow(g, now, meAt) > 0), catalog), { ok: collectedLine })}>Collect</Btn>,
  })

  if (!items.length) return crate.sheet || null
  return (
    <>
      <Card title="Next up" className="next-up">
        {items.map(i => (
          <div key={i.key} className={`row ${i.tone}${i.wide ? ' wide' : ''}`} data-next={i.key}>
            <span className="ico" aria-hidden>{i.ico}</span>
            <div className="grow">
              <div className="t">{i.t}</div>
              {i.s && <div className="s">{i.s}</div>}
              {i.wide && <div className="act">{i.act}</div>}
            </div>
            {!i.wide && i.act}
          </div>
        ))}
      </Card>
      {crate.sheet}
    </>
  )
}
