/** The request never reached the server (offline, dead Wi-Fi), as opposed to an error the server sent back.
 *  supabase-js reports it as "TypeError: Failed to fetch" (Chrome), "Load failed" (Safari/iOS) or "NetworkError…" (Firefox). */
export const NET_RE = /Failed to fetch|Load failed|NetworkError|Network request failed/i
export const isNetworkError = (e: unknown) => !navigator.onLine || NET_RE.test((e as Error)?.message ?? '')

/** Postgres's own wording for a value it can't read, which only a pasted amount or an edited link reaches (Phase 6):
 *  a number ('value "…" is out of range for type integer', 'invalid input syntax for type bigint') or an id in a URL
 *  ('invalid input syntax for type uuid: "abc"', from /player/abc). */
const DB_NUMBER_RE = /(out of range for type|invalid input syntax for type) (integer|bigint|smallint|numeric)/i
const DB_ID_RE = /invalid input syntax for type uuid/i

/** What a failure says to the player: the server's own message, or one plain line when the request never got there
 *  (the browser's "TypeError: Failed to fetch" / "Load failed" means nothing to a player and differs per browser). */
export const OFFLINE_TEXT = "Can't reach the city. Check your connection."
export const errorText = (e: unknown) => {
  if (isNetworkError(e)) return OFFLINE_TEXT
  const m = (e as Error)?.message || 'Something went wrong'
  if (DB_NUMBER_RE.test(m)) return "That amount doesn't work. Try a smaller whole number."
  if (DB_ID_RE.test(m)) return "That link doesn't go anywhere."
  return m
}
