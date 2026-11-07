import { accoladeMeta } from '../lib/format'
import type { Ribbon } from '../lib/types'
import { Glyph } from './Icon'

/** Weekly accolade stripes (top-3 finishes from last week). */
export function Ribbons({ list, empty }: { list: Ribbon[] | undefined; empty?: string }) {
  if (!list || list.length === 0) return empty ? <span className="small muted">{empty}</span> : null
  return (
    <div className="ribbons">
      {list.map(r => (
        <span key={r.kind} className={`ribbon r${r.rank}`} title={`#${r.rank} ${accoladeMeta[r.kind]?.label ?? r.kind} last week`}>
          <Glyph e={accoladeMeta[r.kind]?.icon} size={12} /> #{r.rank} {accoladeMeta[r.kind]?.label ?? r.kind}
        </span>
      ))}
    </div>
  )
}
