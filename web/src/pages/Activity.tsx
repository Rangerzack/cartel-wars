import { useEffect, useRef, useState } from 'react'
import { api } from '../lib/api'
import { useGame } from '../lib/game'
import type { ActivityItem } from '../lib/types'
import { Card, Empty } from '../components/ui'
import { BackBar } from '../components/BackBar'
import { ActivityRow } from '../components/Activity'

/** Everything that happened to you lately. Opening it clears the Home badge; new lines stay highlighted for this visit. */
export default function Activity() {
  const { toast, refresh } = useGame()
  const [list, setList] = useState<ActivityItem[] | null>(null)
  const cleared = useRef(false)
  useEffect(() => {
    api.activity(60).then(l => {
      setList(l)
      if (!cleared.current && l.some(a => !a.seen)) { cleared.current = true; api.activitySeen().then(() => refresh()).catch(() => {}) }
    }).catch(e => { setList([]); toast(e.message, 'bad') })
  }, [toast, refresh])
  return (
    <div className="page">
      <BackBar fallback="/" />
      <h2>Activity</h2>
      <Card>
        {!list && <Empty><span className="spin" /></Empty>}
        {list?.length === 0 && <Empty>Quiet so far. Attacks on you, sales, sieges and crew news show up here.</Empty>}
        {list?.map(a => <ActivityRow key={a.id} a={a} fresh={!a.seen} />)}
      </Card>
      <div className="small muted center">Kept for 30 days.</div>
    </div>
  )
}
