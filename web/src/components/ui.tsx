import { useCallback, useEffect, useId, useLayoutEffect, useRef, useState, type ReactNode } from 'react'
import { Link } from 'react-router-dom'
import { useGame } from '../lib/game'

export function Card({ title, right, children, className = '', id }: { title?: ReactNode; right?: ReactNode; children: ReactNode; className?: string; id?: string }) {
  return (
    <div className={`card ${className}`} id={id}>
      {title !== undefined && <div className="hd"><span>{title}</span>{right}</div>}
      {children}
    </div>
  )
}

/** Always mounted, so screen readers announce what lands in it; errors interrupt (role=alert), the rest waits its turn. */
export function Toasts() {
  const { toasts } = useGame()
  return (
    <div className="toasts" role="status" aria-live="polite">
      {toasts.map(t => <div key={t.id} className={`toast ${t.kind}`} role={t.kind === 'bad' ? 'alert' : undefined}>{t.text}</div>)}
    </div>
  )
}

/** Open sheets, newest last: Escape closes only the top one. */
const openSheets: object[] = []

/** A bottom sheet (P2-9): a dialog with its title and an × that stay at the top while the body scrolls, plus the Close
 *  at the end. Escape and a tap on the backdrop close it; focus moves into it and goes back where it was afterwards. */
export function Modal({ title, onClose, children }: { title: string; onClose: () => void; children: ReactNode }) {
  const sheet = useRef<HTMLDivElement>(null)
  const close = useRef(onClose)
  const titleId = useId()
  const [scrolled, setScrolled] = useState(false)
  useEffect(() => { close.current = onClose })
  useEffect(() => {
    const me = {}
    openSheets.push(me)
    const back = document.activeElement as HTMLElement | null
    if (!sheet.current?.contains(document.activeElement)) sheet.current?.focus({ preventScroll: true })   // unless a field in it took focus itself
    const onKey = (e: KeyboardEvent) => {
      if (openSheets[openSheets.length - 1] !== me) return
      if (e.key === 'Escape') { e.preventDefault(); close.current(); return }
      // aria-modal: Tab stays inside the sheet
      if (e.key !== 'Tab' || !sheet.current) return
      const f = [...sheet.current.querySelectorAll<HTMLElement>('button, a[href], input, select, textarea, summary, [tabindex]:not([tabindex="-1"])')].filter(el => !el.hasAttribute('disabled'))
      if (!f.length) return
      const first = f[0], last = f[f.length - 1], at = document.activeElement
      if (e.shiftKey && (at === first || at === sheet.current)) { e.preventDefault(); last.focus() }
      else if (!e.shiftKey && at === last) { e.preventDefault(); first.focus() }
    }
    document.addEventListener('keydown', onKey)
    return () => {
      document.removeEventListener('keydown', onKey)
      openSheets.splice(openSheets.indexOf(me), 1)
      if (back?.isConnected) back.focus({ preventScroll: true })
    }
  }, [])
  return (
    <div className="modal-bg" onClick={onClose}>
      <div ref={sheet} className={`modal${scrolled ? ' scrolled' : ''}`} role="dialog" aria-modal="true" aria-labelledby={titleId} tabIndex={-1}
        onClick={e => e.stopPropagation()} onScroll={e => setScrolled(e.currentTarget.scrollTop > 4)}>
        <div className="modal-hd">
          <h3 id={titleId}>{title}</h3>
          <button type="button" className="modal-x" aria-label="Close" onClick={onClose}>×</button>
        </div>
        {children}
        <button className="btn block" style={{ marginTop: 14 }} onClick={onClose}>Close</button>
      </div>
    </div>
  )
}

export function Seg<T extends string>({ value, onChange, options }: { value: T; onChange: (v: T) => void; options: { v: T; l: string }[] }) {
  return (
    <div className="seg">
      {options.map(o => <button key={o.v} type="button" className={o.v === value ? 'on' : ''} aria-pressed={o.v === value} onClick={() => onChange(o.v)}>{o.l}</button>)}
    </div>
  )
}

export function Qty({ value, onChange, min = 1, max = 999999 }: { value: number; onChange: (n: number) => void; min?: number; max?: number }) {
  const clamp = (n: number) => Math.max(min, Math.min(max, Math.floor(n) || min))
  return (
    <span className="qty">
      <button type="button" className="btn sm" aria-label="One less" onClick={() => onChange(clamp(value - 1))}>−</button>
      <input className="input sm" inputMode="numeric" aria-label="Quantity" value={value} onChange={e => onChange(clamp(Number(e.target.value)))} />
      <button type="button" className="btn sm" aria-label="One more" onClick={() => onChange(clamp(value + 1))}>+</button>
    </span>
  )
}

/** Sizes a stat value steps down through, largest first, when it's wider than its tile (P1-1). */
const STAT_STEPS = [16, 14, 12.5]

/** A stat tile. A value too wide for its tile (seven-figure money or "1,640/10,936" in a third of a 375 px screen) steps
 *  down to the largest size that fits, measured, so a value that fits keeps the full size; past the last step it ends
 *  in an ellipsis. Re-measured when the text changes, the window resizes or the display face finishes loading. */
export function Stat({ k, v, cls = '' }: { k: string; v: ReactNode; cls?: string }) {
  const ref = useRef<HTMLDivElement>(null)
  const fitted = useRef<string | null>(null)
  const fit = useCallback(() => {
    const el = ref.current
    if (!el) return
    el.style.fontSize = ''
    const cs = getComputedStyle(el)
    const room = el.clientWidth - parseFloat(cs.paddingLeft) - parseFloat(cs.paddingRight)
    const text = document.createRange()
    text.selectNodeContents(el)
    const base = parseFloat(cs.fontSize)
    for (const size of STAT_STEPS.filter(s => s < base)) {
      if (text.getBoundingClientRect().width <= room + 0.5) return
      el.style.fontSize = size + 'px'
    }
  }, [])
  useLayoutEffect(() => {
    if (fitted.current === ref.current?.textContent) return
    fitted.current = ref.current?.textContent ?? null
    fit()
  })
  useEffect(() => {
    window.addEventListener('resize', fit)
    document.fonts?.ready.then(fit)
    return () => window.removeEventListener('resize', fit)
  }, [fit])
  const title = typeof v === 'string' || typeof v === 'number' ? String(v) : undefined
  return <div className="stat"><div className="k">{k}</div><div ref={ref} className={`v ${cls}`} title={title}>{v}</div></div>
}

export function Empty({ children }: { children: ReactNode }) { return <div className="empty">{children}</div> }

/** A list row that navigates: a real link (with `to`) or button (with `onClick`), so it takes keyboard focus and
 *  VoiceOver calls it a link or button, not text. Looks exactly like `div.row.link` did. Only for rows without their own
 *  buttons inside (a button can't nest a button); a row with its own controls stays a div and links its title instead. */
export function RowLink({ to, onClick, className = '', label, children }:
  { to?: string; onClick?: () => void; className?: string; label?: string; children: ReactNode }) {
  const cls = `row link ${className}`.trim()
  if (to) return <Link to={to} className={cls} onClick={onClick} aria-label={label}>{children}</Link>
  return <button type="button" className={cls} onClick={onClick} aria-label={label}>{children}</button>
}

/** Button that shows a spinner while its async handler runs. */
export function Btn({ onClick, children, className = '', disabled }: { onClick: () => Promise<unknown> | void; children: ReactNode; className?: string; disabled?: boolean }) {
  const [busy, setBusy] = useState(false)
  return (
    <button className={`btn ${className}`} disabled={disabled || busy} onClick={async () => { setBusy(true); try { await onClick() } finally { setBusy(false) } }}>
      {busy ? <span className="spin" /> : children}
    </button>
  )
}
