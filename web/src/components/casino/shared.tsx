import { useState } from 'react'
import type React from 'react'

export const MIN_BET = 100

/**
 * Bet amount for one game: starts at the table minimum, then remembers the last amount you used
 * on this device (per game) so a big bet never surprises a new player.
 */
export function useBet(game: string): [number, (n: number) => void] {
  const key = `cw.bet.${game}`
  const [v, setV] = useState(() => {
    try { const n = Number(localStorage.getItem(key)); return n >= MIN_BET ? n : MIN_BET } catch { return MIN_BET }
  })
  const set = (n: number) => { setV(n); try { localStorage.setItem(key, String(n)) } catch { /* private mode */ } }
  return [v, set]
}
import { chips, money } from '../../lib/format'

const SUIT: Record<string, string> = { s: '♠', h: '♥', d: '♦', c: '♣' }

/** "Ah" → a playing card. Pass null for a face-down card. */
export function PlayingCard({ c, size = 'md', dim, className = '', style }: { c: string | null | undefined; size?: 'sm' | 'md' | 'lg' | 'xl'; dim?: boolean; className?: string; style?: React.CSSProperties }) {
  if (c === undefined) return <span className={`pcard slot ${size} ${className}`} style={style} />
  if (!c) return <span className={`pcard back ${size} ${className}`} style={style} />
  const r = c[0] === 'T' ? '10' : c[0], s = c[1]
  const red = s === 'h' || s === 'd'
  if (size === 'xl') {
    // table-sized card: corner indexes and a big center pip
    return (
      <span className={`pcard xl ${red ? 'red' : ''} ${dim ? 'dim' : ''} ${className}`} style={style} aria-label={`${r} of ${SUIT_NAME[s]}`}>
        <span className="corner tl">{r}<i>{SUIT[s]}</i></span>
        <span className="pip">{SUIT[s]}</span>
        <span className="corner br">{r}<i>{SUIT[s]}</i></span>
      </span>
    )
  }
  return (
    <span className={`pcard ${size} ${red ? 'red' : ''} ${dim ? 'dim' : ''} ${className}`} style={style}>
      <span className="r">{r}</span><span className="s">{SUIT[s]}</span>
    </span>
  )
}

const SUIT_NAME: Record<string, string> = { s: 'spades', h: 'hearts', d: 'diamonds', c: 'clubs' }

const DENOMS = [100000, 25000, 5000, 1000, 500, 100]
/** A little stack of casino chips showing an amount (up to 5 chips drawn), with the amount under it. */
export function ChipStack({ amount, label = true }: { amount: number; label?: boolean }) {
  const chipsList: number[] = []
  let left = amount
  for (const d of DENOMS) while (left >= d && chipsList.length < 5) { chipsList.push(d); left -= d }
  if (!chipsList.length && amount > 0) chipsList.push(100)
  return (
    <span className="chipstack" aria-label={money(amount)}>
      <span className="stack">{chipsList.reverse().map((d, i) => <span key={i} className={`tchip c${d}`} style={{ bottom: i * 3 }} />)}</span>
      {label && <b>{chips(amount)}</b>}
    </span>
  )
}

const PIPS: Record<number, number[]> = { 1: [4], 2: [0, 8], 3: [0, 4, 8], 4: [0, 2, 6, 8], 5: [0, 2, 4, 6, 8], 6: [0, 2, 3, 5, 6, 8] }
/** A die drawn with pips (the unicode die faces render tiny and different on every phone). */
export function Die({ n, rolling, size = 44 }: { n: number; rolling?: boolean; size?: number }) {
  const on = new Set(PIPS[n] ?? [])
  return (
    <span className={`die ${rolling ? 'rolling' : ''}`} aria-label={`die showing ${n}`}
      style={{ width: size, height: size, padding: Math.round(size * 0.13), gap: Math.max(1, Math.round(size * 0.05)), borderRadius: Math.round(size * 0.18) }}>
      {Array.from({ length: 9 }, (_, i) => <i key={i} className={on.has(i) ? 'on' : ''} />)}
    </span>
  )
}

export function Cards({ list, size, dim }: { list: (string | null | undefined)[]; size?: 'sm' | 'md' | 'lg'; dim?: boolean }) {
  return <span className="pcards">{list.map((c, i) => <PlayingCard key={i} c={c} size={size} dim={dim} />)}</span>
}

const PRESETS = [100, 500, 1000, 5000, 25000, 100000]

/** Wager picker: chip presets plus a free-form amount, clamped to what the player can afford. */
export function BetPicker({ value, onChange, max, min = 100, label = 'Bet' }: { value: number; onChange: (n: number) => void; max: number; min?: number; label?: string }) {
  const [text, setText] = useState<string | null>(null)
  const clamp = (n: number) => Math.max(min, Math.min(Math.max(min, max), Math.floor(n) || min))
  return (
    <div className="betpick">
      <div className="hstack" style={{ justifyContent: 'space-between' }}>
        <span className="small muted">{label}</span>
        <span className="small muted">max {money(Math.max(min, max))}</span>
      </div>
      <div className="chipsrow">
        {PRESETS.map(p => (
          <button key={p} className={`chip c${p} ${value === p ? 'on' : ''}`} disabled={p > max} onClick={() => { setText(null); onChange(clamp(p)) }}>{chips(p)}</button>
        ))}
      </div>
      <div className="hstack">
        <input className="input" inputMode="numeric" value={text ?? value} onChange={e => { setText(e.target.value); const n = Number(e.target.value.replace(/[^0-9]/g, '')); if (n) onChange(clamp(n)) }} onBlur={() => setText(null)} />
        <button className="btn sm" onClick={() => { setText(null); onChange(clamp(value * 2)) }}>×2</button>
        <button className="btn sm" onClick={() => { setText(null); onChange(clamp(Math.floor(value / 2))) }}>½</button>
        <button className="btn sm" onClick={() => { setText(null); onChange(clamp(max)) }}>Max</button>
      </div>
    </div>
  )
}

export function Net({ n }: { n: number }) {
  return <b className={`tabular ${n > 0 ? 'green' : n < 0 ? 'red' : 'muted'}`}>{n > 0 ? '+' : n < 0 ? '−' : ''}{money(Math.abs(n))}</b>
}
