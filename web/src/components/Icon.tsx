import type { CSSProperties } from 'react'
import { ICONS, iconFor, type IconName } from '../lib/icons'

/** The line icons as components: <Icon name> draws one; <Glyph e> draws the icon an emoji from a data map stands for,
 *  or the emoji itself when it isn't one of ours (a player's avatar, a crew's emblem). The set lives in lib/icons.ts. */
export function Icon({ name, size = 20, className = '', label, style, stroke }: { name: IconName; size?: number; className?: string; label?: string; style?: CSSProperties; stroke?: number }) {
  return (
    <svg className={`svgi ${className}`.trim()} width={size} height={size} viewBox="0 0 24 24" fill="none" stroke="currentColor" strokeWidth={stroke ?? 1.8}
      strokeLinecap="round" strokeLinejoin="round" aria-hidden={label ? undefined : true} role={label ? 'img' : undefined} aria-label={label} style={style} focusable="false">
      <path d={ICONS[name]} />
    </svg>
  )
}

/** An emoji from a data map drawn as its icon, or as itself when it isn't one of ours (a player's avatar, a crew's emblem). */
export function Glyph({ e, size = 20, className = '', label }: { e: string | null | undefined; size?: number; className?: string; label?: string }) {
  const name = iconFor(e)
  if (name) return <Icon name={name} size={size} className={className} label={label} />
  return <span className={`glyph ${className}`.trim()} aria-hidden={label ? undefined : true} aria-label={label} role={label ? 'img' : undefined}>{e}</span>
}

export type { IconName }
