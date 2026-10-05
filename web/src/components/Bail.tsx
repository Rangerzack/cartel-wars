import { Link } from 'react-router-dom'
import { api } from '../lib/api'
import { money } from '../lib/format'
import { useGame, useMe } from '../lib/game'
import { bailCost } from '../lib/perks'
import { Btn } from './ui'

/** Post bail right where you got busted (the bust sheet after a job, a fight's result): pays the same bail as the jail
 *  card, from cash on hand, and leaves you on the screen you were on. Short of cash, it says so and points at the bank.
 *  `onDone` runs once you're out (the bust sheet closes itself). */
export function BailButton({ className = 'gold block', onDone }: { className?: string; onDone?: () => void }) {
  const me = useMe()
  const { catalog, run } = useGame()
  if (!catalog) return null
  const cost = bailCost(me, catalog.config)
  const short = me.cash < cost
  return (
    <>
      <Btn className={className} disabled={short} onClick={async () => {
        if (await run(api.bailOut, { ok: r => `Bailed out for ${money(r.cost)} · heat back to 0` })) onDone?.()
      }}>Post Bail · {money(cost)}</Btn>
      {short && <div className="why">Bail comes out of cash on hand — you have {money(me.cash)}. <Link to="/services?focus=bank">Bank →</Link></div>}
    </>
  )
}
