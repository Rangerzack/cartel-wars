import { Link } from 'react-router-dom'
import { api } from '../lib/api'
import { useGame, useMe } from '../lib/game'
import { money, num } from '../lib/format'
import { goLabel } from '../lib/gate'
import { haptic } from '../lib/haptics'
import { Btn, Card } from './ui'
import { Icon } from './Icon'
import { MarcusFace } from './Faces'

const MARCUS = { name: 'Marcus' }
/** Marcus's face (components/Faces.tsx) in the amber ring. */
const Mark = ({ size = 32 }: { size?: number }) => <span className="mring" aria-hidden><MarcusFace size={size} /></span>

/**
 * Marcus, your right-hand man, and the mission you're on (Season 1): one card at the top of Home. His line, the
 * objective with its progress, and one button to where the job gets done. When the objective is met the card flips:
 * his done line, the reward, Claim. Claiming pays and the next card slides in. Never a popup. Campaign done: one row
 * to the log.
 */
export function Marcus() {
  const me = useMe()
  const { run } = useGame()
  const m = me.mission
  if (!me.season || !m) return null
  if ('finished' in m) {
    return (
      <Link to="/missions" className="card row link marcus done" data-marcus="finished">
        <Mark size={36} />
        <div className="grow"><div className="t">Campaign complete · {me.season.name}</div><div className="s">The hood's yours and the city's open. Every line, in the log.</div></div>
        <span className="chev">›</span>
      </Link>
    )
  }
  const claim = async () => {
    const r = await run(() => api.missionClaim(m.key), { ok: r => `+${money(r.reward_cash)}${r.reward_diamonds ? ` and ${r.reward_diamonds} diamonds` : ''}` })
    if (r) haptic('success')
  }
  const reward = <>{m.reward_cash ? money(m.reward_cash) : ''}{m.reward_cash && m.reward_diamonds ? ' + ' : ''}{m.reward_diamonds ? <span className="dia nowrap"><Icon name="gem" size={13} />{m.reward_diamonds}</span> : ''}</>
  return (
    <Card key={m.key} id={`mission-${m.key}`} className={`marcus ${m.complete ? 'complete' : ''}`} title={<><Mark />{m.title}</>}
      right={<small className="tabular"><Link to="/missions" className="hd-link">{num(m.n)} of {num(m.total)} ›</Link></small>}>
      <div className="bd stack">
        <p className="line">“{m.complete ? m.done : m.intro}”<span className="small muted"> — {MARCUS.name}</span></p>
        {m.complete ? (
          <Btn className="gold block" onClick={claim} label={`Claim ${m.reward_cash ? money(m.reward_cash) : ''}${m.reward_diamonds ? ` and ${m.reward_diamonds} diamonds` : ''}`}>Claim {reward}</Btn>
        ) : (
          <>
            {m.parts ? (
              <ul className="parts">
                {m.parts.map(p => <li key={p.label} className={p.done ? 'done' : ''}><Icon name={p.done ? 'checksquare' : 'square'} size={15} className={p.done ? 'gold' : ''} /> {p.label}</li>)}
              </ul>
            ) : (
              <div className="objective small">
                <span className="muted">{m.label}</span>
                {m.qty > 1 ? <span className="tabular">{num(m.progress)} of {num(m.qty)}</span> : <span className="pay">Pays {reward}</span>}
              </div>
            )}
            {m.qty > 1 && !m.parts && <div className="bar mini"><div className="track"><div className="fill" style={{ width: `${Math.min(100, (m.progress / m.qty) * 100)}%` }} /></div></div>}
            {(m.qty > 1 || m.parts) && <div className="small muted">Pays {reward}</div>}
            <Link to={m.link} className="btn gold block" data-marcus="go">{goLabel(m.link)} <Icon name="arrow" size={17} stroke={2.2} /></Link>
          </>
        )}
      </div>
    </Card>
  )
}
