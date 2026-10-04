import { useCallback } from 'react'
import { useSearchParams } from 'react-router-dom'

/**
 * A screen's tab or filter, kept in the URL (so a reload or Back lands on the same view, and links can open it)
 * and read back only from an allow-list, so `?tab=foo` shows the first tab rather than an empty screen. Setting it
 * replaces the current history entry: tapping through the tabs of one screen is one step for Back, not five.
 */
export function useParam<T extends string>(key: string, allowed: readonly T[], fallback: T): [T, (v: T) => void] {
  const [sp, setSp] = useSearchParams()
  const raw = sp.get(key)
  const value = (allowed as readonly string[]).includes(raw ?? '') ? (raw as T) : fallback
  const set = useCallback((v: T) => setSp(prev => {
    const n = new URLSearchParams(prev)
    if (v === fallback) n.delete(key); else n.set(key, v)
    return n
  }, { replace: true }), [key, fallback, setSp])
  return [value, set]
}

/** A whole number from the URL (a page index), 0 when missing or not a number. */
export function intParam(sp: URLSearchParams, key: string, fallback = 0): number {
  const n = Number(sp.get(key))
  return Number.isInteger(n) && n >= 0 ? n : fallback
}
