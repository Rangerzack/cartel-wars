/** The request never reached the server (offline, dead Wi-Fi), as opposed to an error the server sent back.
 *  supabase-js reports it as "TypeError: Failed to fetch" (Chrome), "Load failed" (Safari/iOS) or "NetworkError…" (Firefox). */
export const NET_RE = /Failed to fetch|Load failed|NetworkError|Network request failed/i
export const isNetworkError = (e: unknown) => !navigator.onLine || NET_RE.test((e as Error)?.message ?? '')

/** What a failure says to the player: the server's own message, or one plain line when the request never got there
 *  (the browser's "TypeError: Failed to fetch" / "Load failed" means nothing to a player and differs per browser). */
export const OFFLINE_TEXT = "Can't reach the city. Check your connection."
export const errorText = (e: unknown) => (isNetworkError(e) ? OFFLINE_TEXT : (e as Error)?.message || 'Something went wrong')
