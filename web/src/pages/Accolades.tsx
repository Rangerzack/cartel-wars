import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useGame } from '../lib/game'
import { api } from '../lib/api'
import { accoladeMeta, timeLeft } from '../lib/format'
import { useNow } from '../lib/useNow'
import { Card, Empty, Seg } from '../components/ui'
import { Ribbons } from '../components/Ribbons'
import type { Accolades as AccoladesT } from '../lib/types'

const KINDS = ['fight_win', 'defense', 'action', 'import', 'market', 'turf'] as const

export default function Accolades() {
  const { toast } = useGame()
  const nav = useNavigate()
  const now = useNow(30_000)
  const [data, setData] = useState<AccoladesT | null>(null)
  const [week, setWeek] = useState<'this_week' | 'last_week'>('this_week')
  useEffect(() => { api.accolades().then(setData).catch(e => toast(e.message, 'bad')) }, [toast])
  if (!data) return <Empty><span className="spin" /></Empty>
  const board = data[week]
  return (
    <div className="page">
      <Card title="Your stripes" right={<small>from last week</small>}>
        <div className="bd"><Ribbons list={data.mine} empty="No stripes yet. Finish top 3 in any category this week to wear one next week." /></div>
      </Card>
      <Seg value={week} onChange={setWeek} options={[{ v: 'this_week', l: `This week · ${timeLeft(data.week_end, now)} left` }, { v: 'last_week', l: 'Last week' }]} />
      {KINDS.map(k => {
        const rows = board[k] ?? []
        const m = accoladeMeta[k]
        return (
          <Card key={k} title={<>{m.icon} {m.label}</>}>
            {rows.length === 0 && <Empty>Nobody on the board yet.</Empty>}
            {rows.map((r, i) => (
              <div key={r.id} className="row link" onClick={() => nav(`/player/${r.id}`)}>
                <span className={`muted tabular ${i < 3 ? 'gold' : ''}`} style={{ width: 24 }}>{i + 1}.</span>
                <div className="grow t">{r.name}</div>
                <b className="tabular">{m.unit(r.value)}</b>
              </div>
            ))}
          </Card>
        )
      })}
      <div className="small muted">Weekly boards reset Monday 00:00 UTC. Top three in each category earn a gold, silver or bronze stripe for the following week.</div>
    </div>
  )
}
