import { useEffect, useState } from 'react'
import { now as clockNow } from './clock'

/** Ticks every second (by the server's clock, see lib/clock.ts) so countdowns re-render. */
export function useNow(intervalMs = 1000): number {
  const [now, setNow] = useState(clockNow)
  useEffect(() => {
    const t = setInterval(() => setNow(clockNow()), intervalMs)
    return () => clearInterval(t)
  }, [intervalMs])
  return now
}
