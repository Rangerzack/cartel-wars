import { Component, type ErrorInfo, type ReactNode } from 'react'

/** Set when a stale screen reloaded the app; App clears it once every screen has loaded fine. */
const RELOADED = 'cw.reloadedForUpdate'

/** A screen's script that can't be fetched: after a deploy, the old file names are gone from the server. */
const isStaleChunk = (e: unknown) => /dynamically imported module|Importing a module script failed|error loading dynamically imported|Failed to fetch/i.test(String((e as Error)?.message ?? e))

/**
 * Catches a screen that fails to draw, so one broken screen isn't a blank app (Phase 5). The top bar and the tab bar
 * stay, and the screen says what happened with a way out. A screen whose script went away in a new deploy reloads the
 * app once, onto the new build, instead of showing the error. Keyed by the path in Layout, so leaving the screen
 * clears it.
 */
export class ScreenBoundary extends Component<{ children: ReactNode }, { error: Error | null }> {
  state = { error: null as Error | null }
  static getDerivedStateFromError(error: Error) { return { error } }
  componentDidCatch(error: Error, info: ErrorInfo) {
    if (isStaleChunk(error)) {
      let again = false
      try { again = sessionStorage.getItem(RELOADED) === '1'; sessionStorage.setItem(RELOADED, '1') } catch { /* private mode */ }
      if (!again) { location.reload(); return }
    }
    console.error('Screen failed to draw', error, info.componentStack)
  }
  render() {
    if (!this.state.error) return this.props.children
    return (
      <div className="page">
        <div className="card">
          <div className="hd"><span>Something went wrong</span></div>
          <div className="bd stack">
            <div className="small muted">This screen couldn't be shown. Your game is fine — nothing was lost.</div>
            <button type="button" className="btn doit block" onClick={() => location.reload()}>Reload</button>
          </div>
        </div>
      </div>
    )
  }
}
