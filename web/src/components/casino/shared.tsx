import { useState } from 'react'
import { chips, money } from '../../lib/format'

const SUIT: Record<string, string> = { s: '♠', h: '♥', d: '♦', c: '♣' }

/** "Ah" → a playing card. Pass null for a face-down card. */
export function PlayingCard({ c, size = 'md', dim }: { c: string | null | undefined; size?: 'sm' | 'md' | 'lg'; dim?: boolean }) {
  if (c === undefined) return <span className={`pcard slot ${size}`} />
  if (!c) return <span className={`pcard back ${size}`} />
  const r = c[0] === 'T' ? '10' : c[0], s = c[1]
  const red = s === 'h' || s === 'd'
  return (
    <span className={`pcard ${size} ${red ? 'red' : ''} ${dim ? 'dim' : ''}`}>
      <span className="r">{r}</span><span className="s">{SUIT[s]}</span>
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
