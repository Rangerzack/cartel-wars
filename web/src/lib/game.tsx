import { createContext, useCallback, useContext, useEffect, useMemo, useRef, useState, type ReactNode } from 'react'
import type { Session } from '@supabase/supabase-js'
import { supabase } from './supabase'
import { api, GameError } from './api'
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
  signOut: () => Promise<void>
  /** True after the player opens a password-reset link; the app asks for a new password before anything else. */
  recovery: boolean
  endRecovery: () => void
}

const Ctx = createContext<GameState | null>(null)

export function GameProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null)
  const [authReady, setAuthReady] = useState(false)
  const [me, setMe] = useState<Me | null>(null)
  const [catalog, setCatalog] = useState<Catalog | null>(null)
  const [toasts, setToasts] = useState<Toast[]>([])
  const [busy, setBusy] = useState(false)
  // A reset link lands with #...type=recovery; catch it here too in case supabase fires PASSWORD_RECOVERY before we subscribe.
  const [recovery, setRecovery] = useState(() => /(^|[#&])type=recovery(&|$)/.test(window.location.hash))
  const toastId = useRef(0)
  const gotAt = useRef(0)

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => { setSession(data.session); setAuthReady(true) })
    const { data: sub } = supabase.auth.onAuthStateChange((e, s) => {
      setSession(s)
      if (!s) setMe(null)
      if (e === 'PASSWORD_RECOVERY') setRecovery(true)
    })
    return () => sub.subscription.unsubscribe()
  }, [])

  const toast = useCallback((text: string, kind: Toast['kind'] = 'info') => {
    const id = ++toastId.current
    setToasts(t => [...t, { id, kind, text }].slice(-3))
    setTimeout(() => setToasts(t => t.filter(x => x.id !== id)), kind === 'bad' ? 4500 : 3200)
  }, [])

  // An expired or already-used reset link comes back as #error_description=… — say so instead of dropping them on sign-in.
  useEffect(() => {
    const why = new URLSearchParams(window.location.hash.slice(1)).get('error_description')
    if (why) { toast(why, 'bad'); history.replaceState(history.state, '', window.location.pathname + window.location.search) }
  }, [toast])

  const refresh = useCallback(async () => {
    try {
      const m = await api.me()
      gotAt.current = Date.now()
      setMe(m)
    } catch (e) {
      if (e instanceof GameError && /No such player|Not signed in/.test(e.message)) {
        // profile missing (trigger not installed?) — create it
        try { const m = await api.ensureProfile(); gotAt.current = Date.now(); setMe(m) } catch (e2) { toast((e2 as Error).message, 'bad') }
      } else {
        toast((e as Error).message, 'bad')
      }
    }
  }, [toast])

  useEffect(() => {
    if (!session) return
    refresh()
    api.catalog().then(setCatalog).catch(e => toast((e as Error).message, 'bad'))
    const t = setInterval(refresh, 60_000)
    const onVis = () => { if (document.visibilityState === 'visible') refresh() }
    document.addEventListener('visibilitychange', onVis)
    return () => { clearInterval(t); document.removeEventListener('visibilitychange', onVis) }
  }, [session, refresh, toast])

  // Refresh the moment a timer runs out — stamina/heat tick, health tick, jail release, hustlers home —
  // so nothing sits on 0:00 waiting for the minute poll. Deadlines are server times; we measure from
  // server_time plus however long ago this state arrived, so a wrong phone clock doesn't matter.
  useEffect(() => {
    if (!me) return
    const server = Date.parse(me.server_time)
    if (!Number.isFinite(server)) return
    const ts = (v: string | null | undefined) => (v ? Date.parse(v) : NaN)
    const due: number[] = []
    if (me.stamina < me.stamina_max || me.heat > 0) due.push(ts(me.next_tick))
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
      toast((e as Error).message, 'bad')
      return undefined
    } finally {
      setBusy(false)
    }
  }, [refresh, toast])

  const signOut = useCallback(async () => { await supabase.auth.signOut(); setMe(null) }, [])
  const endRecovery = useCallback(() => setRecovery(false), [])

  const value = useMemo<GameState>(() => ({ session, authReady, me, catalog, toasts, refresh, toast, run, busy, signOut, recovery, endRecovery }),
    [session, authReady, me, catalog, toasts, refresh, toast, run, busy, signOut, recovery, endRecovery])

  return <Ctx.Provider value={value}>{children}</Ctx.Provider>
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
