/**
 * The game's clock: this device's clock corrected to the server's. Every deadline the server sends (stamina ticks,
 * jail, hustlers home, listings expiring, a poker move) is a server time, so a phone whose clock is a minute off
 * would otherwise show countdowns that hit zero early or late. get_me carries `server_time`; the gap between it and
 * the moment it arrived is the correction, applied to every countdown through useNow and the format helpers.
 */
let offset = 0

/** Called when a `me` lands: the server's clock against ours at that moment. */
export function setClock(serverIso: string | undefined, receivedAt: number) {
  const s = serverIso ? Date.parse(serverIso) : NaN
  if (Number.isFinite(s)) offset = s - receivedAt
}

/** Now, by the server's clock. */
export const now = () => Date.now() + offset
