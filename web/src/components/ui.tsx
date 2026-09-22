import { useState, type ReactNode } from 'react'
import { useGame } from '../lib/game'

export function Card({ title, right, children, className = '' }: { title?: ReactNode; right?: ReactNode; children: ReactNode; className?: string }) {
  return (
    <div className={`card ${className}`}>
      {title !== undefined && <div className="hd"><span>{title}</span>{right}</div>}
      {children}
    </div>
  )
}

export function Toasts() {
  const { toasts } = useGame()
  return (
    <div className="toasts">
      {toasts.map(t => <div key={t.id} className={`toast ${t.kind}`}>{t.text}</div>)}
    </div>
  )
}

export function Modal({ title, onClose, children }: { title: string; onClose: () => void; children: ReactNode }) {
  return (
    <div className="modal-bg" onClick={onClose}>
      <div className="modal" onClick={e => e.stopPropagation()}>
        <h3>{title}</h3>
        {children}
        <button className="btn block" style={{ marginTop: 14 }} onClick={onClose}>Close</button>
      </div>
    </div>
  )
}

export function Seg<T extends string>({ value, onChange, options }: { value: T; onChange: (v: T) => void; options: { v: T; l: string }[] }) {
  return (
    <div className="seg">
      {options.map(o => <button key={o.v} className={o.v === value ? 'on' : ''} onClick={() => onChange(o.v)}>{o.l}</button>)}
    </div>
  )
}

export function Qty({ value, onChange, min = 1, max = 999999 }: { value: number; onChange: (n: number) => void; min?: number; max?: number }) {
  const clamp = (n: number) => Math.max(min, Math.min(max, Math.floor(n) || min))
  return (
    <span className="qty">
      <button className="btn sm" onClick={() => onChange(clamp(value - 1))}>−</button>
      <input className="input sm" inputMode="numeric" value={value} onChange={e => onChange(clamp(Number(e.target.value)))} />
      <button className="btn sm" onClick={() => onChange(clamp(value + 1))}>+</button>
    </span>
  )
}

export function Stat({ k, v, cls = '' }: { k: string; v: ReactNode; cls?: string }) {
  return <div className="stat"><div className="k">{k}</div><div className={`v ${cls}`}>{v}</div></div>
}

export function Empty({ children }: { children: ReactNode }) { return <div className="empty">{children}</div> }

/** Button that shows a spinner while its async handler runs. */
export function Btn({ onClick, children, className = '', disabled }: { onClick: () => Promise<unknown> | void; children: ReactNode; className?: string; disabled?: boolean }) {
  const [busy, setBusy] = useState(false)
  return (
    <button className={`btn ${className}`} disabled={disabled || busy} onClick={async () => { setBusy(true); try { await onClick() } finally { setBusy(false) } }}>
      {busy ? <span className="spin" /> : children}
    </button>
  )
}
