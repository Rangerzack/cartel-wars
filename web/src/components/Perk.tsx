import { useGame, useMe } from '../lib/game'
import { businessDef, perk, perkLabel } from '../lib/perks'
import type { BusinessCode } from '../lib/types'
import { Glyph } from './Icon'

/** "🏋️ Gym −40%" — shown next to a price or number a business perk changed. Nothing when you don't have it. */
export function PerkTag({ code, v }: { code: BusinessCode; v?: number }) {
  const { catalog } = useGame()
  const me = useMe()
  const val = v ?? perk(me, code)
  const d = businessDef(catalog, code)
  if (!val || !d) return null
  return <span className="perk-tag" title={`${d.name}: ${d.perk}`}><Glyph e={d.icon} size={12} /> {d.name} {perkLabel(code, val)}</span>
}
