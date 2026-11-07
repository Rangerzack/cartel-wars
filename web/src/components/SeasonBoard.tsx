import { api } from '../lib/api'
import { useMe } from '../lib/game'
import { num } from '../lib/format'
import { useLoad } from '../lib/useLoad'
import { Card, Empty, Loading, RowLink } from './ui'
import { Icon } from './Icon'

/**
 * The season board (sprint 2): the ten furthest through the season — the boss down first, then blocks taken, then
 * missions claimed, then whoever got there first — and where I stand if I'm not among them. Under the campaign log.
 */
export function SeasonBoard() {
  const me = useMe()
  const { data, error, reload } = useLoad(() => api.seasonBoard(10), 'season-board')
  if (!me.season) return null
  if (!data) return <Loading error={error} onRetry={reload} />
  const total = me.mission?.total ?? 16   // the campaign's length this season, from my own card
  const line = (r: { boss: boolean; cleared: number; claimed: number }) =>
    r.boss ? `boss down · ${num(r.claimed)} of ${total}` : `${num(r.cleared)} of 6 blocks · ${num(r.claimed)} of ${total}`
  const inTop = data.rows.some(r => r.me)
  return (
    <Card title={`${data.season?.name ?? 'Season'} board`} className="season-board" right={<small className="tabular">{num(data.players)} player{data.players === 1 ? '' : 's'}</small>}>
      {data.rows.length === 0 && <Empty>Nobody on the board yet. Take a block.</Empty>}
      {data.rows.map(r => (
        <RowLink key={r.id} to={`/player/${r.id}`} className={r.me ? 'me' : ''} label={`${r.rank}. ${r.name}, ${line(r)}${r.me ? ', you' : ''}`}>
          <span className="muted tabular" style={{ width: 26 }}>{r.rank}.</span>
          <span aria-hidden>{r.avatar}</span>
          <div className="grow"><div className="t">{r.emblem ? `${r.emblem} ` : ''}{r.name}{r.me ? <span className="muted"> · you</span> : null}</div><div className="s">{line(r)}</div></div>
          {r.boss && <Icon name="crown" size={14} className="gold" label="boss down" />}
        </RowLink>
      ))}
      {data.me && !inTop && (
        <div className="row me" data-board="me">
          <span className="muted tabular" style={{ width: 26 }}>{num(data.me.rank)}.</span>
          <span aria-hidden>{me.avatar}</span>
          <div className="grow"><div className="t">{me.name}<span className="muted"> · you</span></div><div className="s">{line(data.me)}</div></div>
        </div>
      )}
    </Card>
  )
}
