import { useCallback, useEffect, useRef, useState } from 'react'
import { errorText } from './errors'

/**
 * A screen's own fetch: `data` once it lands, `error` when it fails (the screen shows a Retry where the spinner was,
 * instead of a spinner that never ends), `reload` to ask again, `set` to put an action's answer in its place.
 * `key` names what is being loaded (an id, a filter): when it changes the old data steps aside (or stays, dimmed, with
 * `keep`), and an answer that was still in flight for the old key is dropped, so a fast filter change can't leave the
 * old list under the new heading.
 */
export function useLoad<T>(fn: () => Promise<T>, key = '', opts: { keep?: boolean } = {}) {
  const [st, setSt] = useState<{ key: string; data: T | null; error: string | null }>({ key, data: null, error: null })
  const fnRef = useRef(fn)
  const keyRef = useRef(key)
  useEffect(() => { fnRef.current = fn; keyRef.current = key })
  const seq = useRef(0)
  const reload = useCallback(async () => {
    const n = ++seq.current, k = keyRef.current
    try {
      const r = await fnRef.current()
      if (n === seq.current) setSt({ key: k, data: r, error: null })
    } catch (e) {
      // a failed reload keeps what was already on screen (the Retry sits under it); a failed first load shows only the Retry
      if (n === seq.current) setSt(s => ({ key: k, data: s.key === k ? s.data : null, error: errorText(e) }))
    }
  }, [])
  useEffect(() => { reload() }, [key, reload])
  const set = useCallback((data: T) => setSt({ key: keyRef.current, data, error: null }), [])
  const current = st.key === key
  // `keep`: while the new key loads, the old data stays up and `stale` says so (a filtered list dims rather than blanks)
  const data = current || opts.keep ? st.data : null
  return { data, error: current ? st.error : null, reload, set, stale: !current && !!data }
}
