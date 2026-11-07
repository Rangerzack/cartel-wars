import { api } from '../lib/api'
import { useMe } from '../lib/game'
import { ago, money, num } from '../lib/format'
import { useLoad } from '../lib/useLoad'
import { BackBar } from '../components/BackBar'
import { Card, Empty, Loading } from '../components/ui'
import { SeasonBoard } from '../components/SeasonBoard'
import { Icon } from '../components/Icon'
import { MarcusFace } from '../components/Faces'

/** The campaign log (Season 1): every mission in order, Marcus's lines for the ones behind you, the one you're on open, the rest locked. */
export default function Missions() {
  const me = useMe()
  const { data, error, reload } = useLoad(() => api.missionsState(), 'missions')
  if (!me.season) return <div className="page"><BackBar fallback="/" /><Empty>No season is running.</Empty></div>
  if (!data) return <div className="page"><BackBar fallback="/" /><Loading error={error} onRetry={reload} /></div>
  const current = data.current && !('finished' in data.current) ? data.current.key : null
  const done = data.missions.filter(m => m.claimed).length
  return (
    <div className="page">
      <BackBar fallback="/" right={<span className="muted small">{data.season?.name}</span>} />
      <Card title={<><span className="mring" aria-hidden><MarcusFace size={28} /></span>The campaign</>} right={<small className="tabular">{done} of {data.missions.length} done</small>}>
        {data.missions.map(m => {
          const state = m.claimed ? 'done' : m.key === current ? 'now' : 'later'
          return (
            <div key={m.key} className={`row mission ${state}`} data-mission={m.key}>
              <span className="check" aria-hidden><Icon name={state === 'done' ? 'checksquare' : state === 'now' ? 'arrow' : 'lock'} size={18} className={state === 'done' || state === 'now' ? 'gold' : 'muted'} /></span>
              <div className="grow">
                <div className="t"><span className="muted tabular">{num(m.n)}.</span> {m.title}</div>
                {state === 'done' && <div className="s">“{m.done}”{m.claimed_at ? <span className="muted"> · {ago(m.claimed_at)}</span> : null}</div>}
                {state === 'now' && <div className="s">“{m.intro}”</div>}
                {state === 'now' && <div className="small muted">{m.label}{m.qty > 1 ? ` · ${num(m.progress)} of ${num(m.qty)}` : ''}</div>}
                {state === 'later' && <div className="s muted">{m.label}</div>}
              </div>
              <span className="small tabular muted nowrap">{m.reward_cash ? money(m.reward_cash) : ''}{m.reward_cash && m.reward_diamonds ? ' + ' : ''}{m.reward_diamonds ? <span className="dia"><Icon name="gem" size={13} />{m.reward_diamonds}</span> : ''}</span>
            </div>
          )
        })}
      </Card>
      <SeasonBoard />
    </div>
  )
}
