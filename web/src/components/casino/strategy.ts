// Basic strategy for this table: 6 decks, dealer stands on all 17s, double any two cards,
// double after split, split up to four hands, no surrender. Returns the textbook play.

export type BjMove = 'hit' | 'stand' | 'double' | 'split'

const value = (c: string) => (c[0] === 'A' ? 11 : 'TJQK'.includes(c[0]) ? 10 : Number(c[0]))

function total(cards: string[]): { total: number; soft: boolean } {
  let t = 0, aces = 0
  for (const c of cards) { const v = value(c); t += v; if (v === 11) aces++ }
  while (t > 21 && aces) { t -= 10; aces-- }
  return { total: t, soft: aces > 0 }
}

export function basicStrategy(cards: string[], dealerUp: string, canDouble: boolean, canSplit: boolean): BjMove {
  const up = value(dealerUp)
  const { total: t, soft } = total(cards)
  const dbl = (m: BjMove, fallback: BjMove): BjMove => (m === 'double' && !canDouble ? fallback : m)
  const vs = (lo: number, hi: number) => up >= lo && up <= hi

  if (canSplit && cards.length === 2) {
    const p = value(cards[0])
    if (p === 11 || p === 8) return 'split'
    if (p === 9 && (vs(2, 6) || up === 8 || up === 9)) return 'split'
    if (p === 7 && vs(2, 7)) return 'split'
    if (p === 6 && vs(2, 6)) return 'split'
    if (p === 4 && vs(5, 6)) return 'split'
    if ((p === 2 || p === 3) && vs(2, 7)) return 'split'
    // 10s never split; 5s play as a hard 10
  }

  if (soft && t <= 21) {
    if (t >= 20) return 'stand'
    if (t === 19) return up === 6 ? dbl('double', 'stand') : 'stand'
    if (t === 18) return vs(3, 6) ? dbl('double', 'stand') : up <= 8 ? 'stand' : 'hit'
    if (t === 17) return vs(3, 6) ? dbl('double', 'hit') : 'hit'
    if (t === 15 || t === 16) return vs(4, 6) ? dbl('double', 'hit') : 'hit'
    return vs(5, 6) ? dbl('double', 'hit') : 'hit'      // soft 13-14
  }

  if (t >= 17) return 'stand'
  if (t >= 13) return vs(2, 6) ? 'stand' : 'hit'
  if (t === 12) return vs(4, 6) ? 'stand' : 'hit'
  if (t === 11) return up === 11 ? 'hit' : dbl('double', 'hit')
  if (t === 10) return vs(2, 9) ? dbl('double', 'hit') : 'hit'
  if (t === 9) return vs(3, 6) ? dbl('double', 'hit') : 'hit'
  return 'hit'
}
