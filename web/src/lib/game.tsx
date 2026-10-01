import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import type { Session } from '@supabase/supabase-js'
import { supabase } from './supabase'
import { api, GameError } from './api'
import { isNative, RESUME_EVENT } from './platform'
import { errorText, isNetworkError, NET_RE, OFFLINE_TEXT } from './errors'
import { initStore, logOutStore } from './store'
import type { Catalog, Me } from './types'

export interface Toast { id: number; kind: 'ok' | 'bad' | 'info'; text: string }

interface GameState {
  session: Session | null
  authReady: boolean
  me: Me | null
  catalog: Catalog | null
  toasts: Toast[]
  refresh: () => Promise<void>
  toast: (text: string, kind?: Toast['kind']) => void
  /** Run an RPC, toast on error, refresh state on success. Returns result or undefined on failure. */
  run: <T>(fn: () => Promise<T>, opts?: { ok?: (r: T) => string | void; silent?: boolean }) => Promise<T | undefined>
  busy: boolean
  /** Signed in and loaded, but the last poll or action couldn't reach the server; the top bar says so until a poll gets through. */
  netDown: boolean
  signOut: () => Promise<void>
  /** True after the player opens a password-reset link; the app asks for a new password before anything else. */
  recovery: boolean
  endRecovery: () => void
  /** The stamina refill sheet: `need` is what the action takes (null = closed); pages open it instead of a dead button,
   *  and `run` opens it when the server refuses for stamina. */
  refillNeed: number | null
  askRefill: (need?: number) => void
  closeRefill: () => void
}

const Ctx = createContext<GameState | null>(null)

/** Full-screen stop when the first load can't reach the server, instead of a spinner that never ends (#20). */
function CantReach({ onRetry }: { onRetry: () => void }) {
  return (
    <div className="auth">
      <div className="logo"><h1>Cartel Wars</h1></div>
      <div className="card">
        <div className="hd"><span>Can't reach the city</span></div>
        <div className="bd stack">
          <div className="small muted">Check your connection and try again.</div>
          <button className="btn gold block" onClick={onRetry}>Retry</button>
        </div>
      </div>
    </div>
  )
}

export function GameProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null)
  const [authReady, setAuthReady] = useState(false)
  const [me, setMe] = useState<Me | null>(null)
  const [catalog, setCatalog] = useState<Catalog | null>(null)
  const [toasts, setToasts] = useState<Toast[]>([])
  const [busy, setBusy] = useState(false)
  const [netDown, setNetDown] = useState(false)
  const [refillNeed, setRefillNeed] = useState<number | null>(null)
  const askRefill = useCallback((need = 0) => setRefillNeed(need), [])
  const closeRefill = useCallback(() => setRefillNeed(null), [])
  const netDownRef = useRef(false)
  const markNet = useCallback((down: boolean) => { netDownRef.current = down; setNetDown(down) }, [])
  // A reset link lands with #...type=recovery; catch it here too in case supabase fires PASSWORD_RECOVERY before we subscribe.
  const [recovery, setRecovery] = useState(() => /(^|[#&])type=recovery(&|$)/.test(window.location.hash))
  const toastId = useRef(0)
  const gotAt = useRef(0)
  // Start-up failed for want of a network; `boot` is bumped by Retry to run the start-up again.
  const [offline, setOffline] = useState(false)
  const [boot, setBoot] = useState(0)
  const loaded = useRef({ me: false, catalog: false })
  useEffect(() => { loaded.current = { me: !!me, catalog: !!catalog } }, [me, catalog])
  const retry = useCallback(() => { setOffline(false); setBoot(b => b + 1) }, [])

  // getSession refreshes an expired token; offline that fails, and it's the network to blame, not the account.
  useEffect(() => {
    if (authReady) return
    supabase.auth.getSession().then(({ data, error }) => {
      if (error && isNetworkError(error)) { setOffline(true); return }
      setSession(data.session); setAuthReady(true)
    })
  }, [authReady, boot])

  useEffect(() => {
    const { data: sub } = supabase.auth.onAuthStateChange((e, s) => {
      setSession(s)
      if (!s) setMe(null)
      if (e === 'PASSWORD_RECOVERY') setRecovery(true)
    })
    return () => sub.subscription.unsubscribe()
  }, [])

  // In the iOS app RevenueCat follows the signed-in player, so the webhook credits purchases to this user id (lib/store.ts).
  const uid = session?.user.id
  useEffect(() => {
    if (isNative) (uid ? initStore(uid) : logOutStore()).catch(() => {})
  }, [uid])

  const toast = useCallback((raw: string, kind: Toast['kind'] = 'info') => {
    // pages that toast an error's message themselves get the same plain line for a dropped connection
    const text = kind === 'bad' && NET_RE.test(raw) ? OFFLINE_TEXT : raw
    const id = ++toastId.current
    // the same words already on screen (a retried action, the poll) don't stack a second copy
    setToasts(t => (t.some(x => x.text === text) ? t : [...t, { id, kind, text }].slice(-3)))
    setTimeout(() => setToasts(t => t.filter(x => x.id !== id)), kind === 'bad' ? 4500 : 3200)
  }, [])

  // An expired or already-used reset link comes back as #error_description=… — say so instead of dropping them on sign-in.
  useEffect(() => {
    const why = new URLSearchParams(window.location.hash.slice(1)).get('error_description')
    if (why) { toast(why, 'bad'); history.replaceState(history.state, '', window.location.pathname + window.location.search) }
  }, [toast])

  // Until `me` and the catalog have both arrived, a network failure shows CantReach. After that a dropped connection is
  // toasted once and then held in the top bar ("Offline · retrying") instead of a fresh toast every poll; other errors toast.
  const failed = useCallback((e: unknown, what: 'me' | 'catalog') => {
    if (!isNetworkError(e)) { toast(errorText(e), 'bad'); return }
    if (!loaded.current[what]) { setOffline(true); return }
    if (!netDownRef.current) toast(OFFLINE_TEXT, 'bad')
    markNet(true)
  }, [toast, markNet])

  const refresh = useCallback(async () => {
    try {
      const m = await api.me()
      gotAt.current = Date.now()
      setMe(m)
      if (netDownRef.current) markNet(false)
    } catch (e) {
      if (e instanceof GameError && /No such player|Not signed in/.test(e.message)) {
        // profile missing (trigger not installed?) — create it
        try { const m = await api.ensureProfile(); gotAt.current = Date.now(); setMe(m) } catch (e2) { failed(e2, 'me') }
      } else {
        failed(e, 'me')
      }
    }
  }, [failed, markNet])

  useEffect(() => {
    if (!session) return
    refresh()
    api.catalog().then(setCatalog).catch(e => failed(e, 'catalog'))
    const t = setInterval(refresh, 60_000)
    const onVis = () => { if (document.visibilityState === 'visible') refresh() }
    document.addEventListener('visibilitychange', onVis)
    return () => { clearInterval(t); document.removeEventListener('visibilitychange', onVis) }
  }, [session, refresh, failed, boot])

  // The iOS app coming back to the foreground (lib/native.ts): retry a failed start, otherwise refresh.
  // The connection coming back retries a failed start too, so nobody has to find the button.
  useEffect(() => {
    const onResume = () => { if (offline) retry(); else if (session) refresh() }
    const onOnline = () => { if (offline) retry(); else if (session && netDownRef.current) refresh() }
    window.addEventListener(RESUME_EVENT, onResume)
    window.addEventListener('online', onOnline)
    return () => { window.removeEventListener(RESUME_EVENT, onResume); window.removeEventListener('online', onOnline) }
  }, [offline, session, refresh, retry])

  // While the connection is down, try every 10 s rather than waiting out the minute poll; the first success clears it.
  useEffect(() => {
    if (!netDown || !session) return
    const t = setInterval(() => { if (document.visibilityState === 'visible') refresh() }, 10_000)
    return () => clearInterval(t)
  }, [netDown, session, refresh])

  // Refresh the moment a timer runs out — stamina/heat tick, health tick, jail release, hustlers home —
  // so nothing sits on 0:00 waiting for the minute poll. Deadlines are server times; we measure from
  // server_time plus however long ago this state arrived, so a wrong phone clock doesn't matter.
  useEffect(() => {
    if (!me) return
    const server = Date.parse(me.server_time)
    if (!Number.isFinite(server)) return
    const ts = (v: string | null | undefined) => (v ? Date.parse(v) : NaN)
    const due: number[] = []
    if (me.stamina < me.stamina_max) due.push(ts(me.next_tick))
    if (me.heat > 0) due.push(ts(me.heat_next ?? me.next_tick))
    if (me.health < me.health_max) due.push(ts(me.health_next))
    if (me.jailed) due.push(ts(me.jail_until))
    for (const h of me.hustlers) if (!h.back) due.push(ts(h.returns_at))
    const next = Math.min(...due.filter(d => Number.isFinite(d) && d > server))
    if (!Number.isFinite(next)) return
    const wait = next - server - (Date.now() - gotAt.current) + 800
    if (wait > 60_000) return // the minute poll gets there first and this re-plans
    const t = setTimeout(() => { if (document.visibilityState === 'visible') refresh() }, Math.max(1000, wait))
    return () => clearTimeout(t)
  }, [me, refresh])

  const run = useCallback(async <T,>(fn: () => Promise<T>, opts?: { ok?: (r: T) => string | void; silent?: boolean }) => {
    setBusy(true)
    try {
      const r = await fn()
      if (!opts?.silent) {
        const msg = opts?.ok?.(r)
        if (msg) toast(msg, 'ok')
      }
      await refresh()
      return r
    } catch (e) {
      // "Not enough stamina", "You need at least 2 stamina to fight", "A turf war takes 3 stamina": offer a refill
      const m = /(?:^|\s)(?:(\d+) )?stamina\b/i.exec(errorText(e))
      if (m && !/free refills/i.test(errorText(e))) { setRefillNeed(m[1] ? Number(m[1]) : 0); await refresh(); return undefined }
      toast(errorText(e), 'bad')
      if (isNetworkError(e) && loaded.current.me) markNet(true)
      return undefined
    } finally {
      setBusy(false)
    }
  }, [refresh, toast, markNet])

  const signOut = useCallback(async () => { await supabase.auth.signOut(); setMe(null) }, [])
  const endRecovery = useCallback(() => setRecovery(false), [])

  const value = useMemo<GameState>(() => ({ session, authReady, me, catalog, toasts, refresh, toast, run, busy, netDown, signOut, recovery, endRecovery, refillNeed, askRefill, closeRefill }),
    [session, authReady, me, catalog, toasts, refresh, toast, run, busy, netDown, signOut, recovery, endRecovery, refillNeed, askRefill, closeRefill])

  return <Ctx.Provider value={value}>{offline ? <CantReach onRetry={retry} /> : children}</Ctx.Provider>
}

export function useGame(): GameState {
  const v = useContext(Ctx)
  if (!v) throw new Error('useGame outside GameProvider')
  return v
}

/** Non-null player state; only use inside authenticated routes once `me` is loaded. */
export function useMe(): Me {
  const { me } = useGame()
  if (!me) throw new Error('me not loaded')
  return me
}
