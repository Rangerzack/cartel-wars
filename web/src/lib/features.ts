// Build-time feature flags. Live builds (main) leave VITE_STAGE unset; the staging build sets VITE_STAGE=staging.
export const stage: 'live' | 'staging' = import.meta.env.VITE_STAGE === 'staging' ? 'staging' : 'live'
export const features = {
  /** Which casino games are open — all of them, live and staging. Gate a new game here with `stage === 'staging'` until it's signed off. */
  casinoGames: ['poker', 'blackjack', 'craps', 'roulette', 'slots'] as const,
  /** Player forum — live everywhere. */
  forum: true,
  /** The Daily Drop is paused until 1.1 (Zack, 2026-11-25): no subscribing; crates already left still open. The server
   *  enforces it (app_text drop_paused, 20261125000029_launch_fixes); this just stops the app offering it. */
  dropPaused: true,
}
export const isStaging = stage === 'staging'
