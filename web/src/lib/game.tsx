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
}

const Ctx = createContext<GameState | null>(null)

export function GameProvider({ children }: { children: ReactNode }) {
  const [session, setSession] = useState<Session | null>(null)
  const [authReady, setAuthReady] = useState(false)
  const [me, setMe] = useState<Me | null>(null)
  const [catalog, setCatalog] = useState<Catalog | null>(null)
  const [toasts, setToasts] = useState<Toast[]>([])
  const [busy, setBusy] = useState(false)
  const toastId = useRef(0)

  useEffect(() => {
    supabase.auth.getSession().then(({ data }) => { setSession(data.session); setAuthReady(true) })
    const { data: sub } = supabase.auth.onAuthStateChange((_e, s) => setSession(s))
    return () => sub.subscription.unsubscribe()
  }, [])

  const toast = useCallback((text: string, kind: Toast['kind'] = 'info') => {
    const id = ++toastId.current
    setToasts(t => [...t, { id, kind, text }])
    setTimeout(() => setToasts(t => t.filter(x => x.id !== id)), kind === 'bad' ? 4500 : 3200)
  }, [])

  const refresh = useCallback(async () => {
    try {
      const m = await api.me()
      setMe(m)
    } catch (e) {
      if (e instanceof GameError && /No such player|Not signed in/.test(e.message)) {
        // profile missing (trigger not installed?) — create it
        try { setMe(await api.ensureProfile()) } catch (e2) { toast((e2 as Error).message, 'bad') }
      } else {
        toast((e as Error).message, 'bad')
      }
    }
  }, [toast])

  useEffect(() => {
    if (!session) { setMe(null); return }
    refresh()
    api.catalog().then(setCatalog).catch(e => toast((e as Error).message, 'bad'))
    const t = setInterval(refresh, 60_000)
    const onVis = () => { if (document.visibilityState === 'visible') refresh() }
    document.addEventListener('visibilitychange', onVis)
    return () => { clearInterval(t); document.removeEventListener('visibilitychange', onVis) }
  }, [session, refresh, toast])

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

  const value = useMemo<GameState>(() => ({ session, authReady, me, catalog, toasts, refresh, toast, run, busy, signOut }),
    [session, authReady, me, catalog, toasts, refresh, toast, run, busy, signOut])

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
