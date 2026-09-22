// Build-time feature flags. Live builds (main) leave VITE_STAGE unset; the staging build sets VITE_STAGE=staging.
export const stage: 'live' | 'staging' = import.meta.env.VITE_STAGE === 'staging' ? 'staging' : 'live'
export const features = {
  /** Which casino games are open. Live shows slots only until the rest is signed off on staging. */
  casinoGames: stage === 'staging' ? (['poker', 'blackjack', 'craps', 'roulette', 'slots'] as const) : (['slots'] as const),
  forum: stage === 'staging',
}
export const isStaging = stage === 'staging'
