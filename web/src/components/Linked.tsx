import { Link } from 'react-router-dom'
import type { MouseEvent, ReactNode } from 'react'
import { splitNames, useNames, type NameKind } from '../lib/names'

const path: Record<NameKind, (id: string) => string> = {
  player: id => `/player/${id}`,
  crew: id => `/crew/${id}`,
  cartel: id => `/cartel/${id}`,
}

// Links often sit inside clickable rows; don't let a name tap also open the row.
const stop = (e: MouseEvent) => e.stopPropagation()

export function NameLink({ kind, id, children, className = '' }: { kind: NameKind; id: string | null | undefined; children: ReactNode; className?: string }) {
  if (!id) return <>{children}</>
  return <Link to={path[kind](id)} className={`nlink ${kind} ${className}`} onClick={stop}>{children}</Link>
}

/** A list row's title as a real link, for a row that can't be one RowLink because it holds name links or buttons of its
 *  own: keyboard and VoiceOver reach the row through its title, while a tap anywhere on the row still opens it. */
export function TitleLink({ to, children }: { to: string; children: ReactNode }) {
  return <Link to={to} className="tlink" onClick={stop}>{children}</Link>
}

export const PlayerLink = (p: { id: string | null | undefined; children: ReactNode; className?: string }) => <NameLink kind="player" {...p} />
export const CrewLink = (p: { id: string | null | undefined; children: ReactNode; className?: string }) => <NameLink kind="crew" {...p} />
export const CartelLink = (p: { id: string | null | undefined; children: ReactNode; className?: string }) => <NameLink kind="cartel" {...p} />

/** Text with every player, crew and cartel name in it turned into a link to that page. */
export function LinkedText({ text }: { text: string | null | undefined }) {
  const dir = useNames()
  if (!text) return null
  return (
    <>
      {splitNames(text, dir).map((s, i) => typeof s === 'string'
        ? s
        : <NameLink key={i} kind={s.thing.kind} id={s.thing.id} className="mention">{s.text}</NameLink>)}
    </>
  )
}
