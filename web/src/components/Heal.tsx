import { Link } from 'react-router-dom'
import { api } from '../lib/api'
import { every, money } from '../lib/format'
import { useGame, useMe } from '../lib/game'
import { healthCost } from '../lib/perks'
import { Btn } from './ui'

/** Heal to full, wherever you're hurt (the hospital card, a fight's result, Actions from a hospital bed): health is
 *  only sold all the way to your max (Zack, 2026-10-02), so it's one price or wait till you have it. Paid from cash
 *  on hand; asks for your max so a tick of healing in between can't leave you a point short. */
export function HealButton({ className = 'gold block', onDone }: { className?: string; onDone?: () => void }) {
  const me = useMe()
  const { catalog, run } = useGame()
  if (!catalog) return null
  const cfg = catalog.config
  const missing = me.health_max - me.health
  if (missing <= 0) return null
  const cost = healthCost(me, cfg, missing)
  const short = me.cash < cost
  return (
    <>
      <Btn className={className} disabled={short} onClick={async () => {
        if (await run(() => api.buyHealth(me.health_max), { ok: r => `Healed to full for ${money(r.cost)}` })) onDone?.()
      }}>Heal to Full (+{missing}) · {money(cost)}</Btn>
      {short && (
        <div className="why">
          That's {money(cost)} — you have {money(me.cash)} on hand. Wait till you have it{me.hospital ? <>, or heal on your own: +{cfg.health_regen_amount} {every(cfg.health_regen_minutes)}</> : null}. <Link to="/services?focus=bank">Bank →</Link>
        </div>
      )}
    </>
  )
}
