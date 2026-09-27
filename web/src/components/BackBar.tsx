import type { ReactNode } from 'react'
import { useNavigate } from 'react-router-dom'

/**
 * "‹ Back" row for pages that aren't on the tab bar. Goes back one step when the app has history
 * (React Router keeps an index in history.state), otherwise to `fallback` — which is what happens when
 * the page was opened from a link, a refresh, or the home-screen app where there's no browser back button.
 */
export function BackBar({ fallback = '/', label = 'Back', right }: { fallback?: string; label?: string; right?: ReactNode }) {
  const nav = useNavigate()
  const canGoBack = typeof window !== 'undefined' && ((window.history.state as { idx?: number } | null)?.idx ?? 0) > 0
  return (
    <div className="backbar">
      <button className="back" onClick={() => (canGoBack ? nav(-1) : nav(fallback))}>‹ {label}</button>
      {right}
    </div>
  )
}
