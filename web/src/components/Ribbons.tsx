import { accoladeMeta } from '../lib/format'
import type { Ribbon } from '../lib/types'

/** Weekly accolade stripes (top-3 finishes from last week). */
export function Ribbons({ list, empty }: { list: Ribbon[] | undefined; empty?: string }) {
  if (!list || list.length === 0) return empty ? <span className="small muted">{empty}</span> : null
  return (
    <div className="ribbons">
      {list.map(r => (
        <span key={r.kind} className={`ribbon r${r.rank}`} title={`#${r.rank} ${accoladeMeta[r.kind]?.label ?? r.kind} last week`}>
          {accoladeMeta[r.kind]?.icon} #{r.rank} {accoladeMeta[r.kind]?.label ?? r.kind}
        </span>
      ))}
    </div>
  )
}
