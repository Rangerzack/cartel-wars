import { useRef } from 'react'
import { api } from '../lib/api'
import { useGame } from '../lib/game'
import { Card, Empty, Loading } from '../components/ui'
import { BackBar } from '../components/BackBar'
import { ActivityRow } from '../components/Activity'
import { useLoad } from '../lib/useLoad'

/** Everything that happened to you lately. Opening it clears the Home badge; new lines stay highlighted for this visit. */
export default function Activity() {
  const { refresh } = useGame()
  const cleared = useRef(false)
  // opening the page marks what it shows as seen (once), so the badge clears
  const { data: list, error, reload } = useLoad(() => api.activity(60).then(l => {
    if (!cleared.current && l.some(a => !a.seen)) { cleared.current = true; api.activitySeen().then(() => refresh()).catch(() => {}) }
    return l
  }))
  return (
    <div className="page">
      <BackBar fallback="/" />
      <h2>Activity</h2>
      <Card>
        {!list && <Loading error={error} onRetry={reload} />}
        {list?.length === 0 && <Empty>Quiet so far. Attacks on you, sales, sieges and crew news show up here.</Empty>}
        {list?.map(a => <ActivityRow key={a.id} a={a} fresh={!a.seen} />)}
      </Card>
      <div className="small muted center">Kept for 30 days.</div>
    </div>
  )
}
