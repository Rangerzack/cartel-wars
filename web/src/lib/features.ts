// Build-time feature flags. Live builds (main) leave VITE_STAGE unset; the staging build sets VITE_STAGE=staging.
export const stage: 'live' | 'staging' = import.meta.env.VITE_STAGE === 'staging' ? 'staging' : 'live'
export const features = {
  /** Which casino games are open — all of them, live and staging. Gate a new game here with `stage === 'staging'` until it's signed off. */
  casinoGames: ['poker', 'blackjack', 'craps', 'roulette', 'slots'] as const,
  /** Player forum — live everywhere. */
  forum: true,
}
export const isStaging = stage === 'staging'
