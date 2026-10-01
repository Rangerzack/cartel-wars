import { Link } from 'react-router-dom'
import { api } from '../lib/api'
import { useGame, useMe } from '../lib/game'
import { commodityIcon, every, num } from '../lib/format'
import { refillShare, shareLabel } from '../lib/market'
import { perk } from '../lib/perks'
import { Btn, Modal } from './ui'

/** The sheet that opens when a job, a fight or a turf war needs more stamina than the player has: every way to refill,
 *  priced, with what each one restores, so the next tap is the refill rather than a trip to Services. The same rules as
 *  the Refills card (diamond and free refills fill you up; a product refill restores the day's share of what's missing,
 *  Pharmacy perk included); the server checks them again. Mounted once in Layout; opened through useGame().askRefill. */
export function RefillSheet() {
  const me = useMe()
  const { catalog, run, refillNeed, closeRefill } = useGame()
  if (refillNeed == null || !catalog) return null
  const cfg = catalog.config
  const need = refillNeed
  const missing = me.stamina_max - me.stamina
  const share = refillShare(me, catalog)
  const pharmacy = perk(me, 'pharmacy')
  const productGain = Math.ceil(missing * share)
  const after = (gain: number) => me.stamina + gain >= need
  const done = async (fn: () => Promise<{ gain: number }>, what: string) => {
    if (await run(fn, { ok: r => `+${r.gain} stamina · ${what}` })) closeRefill()
  }
  return (
    <Modal title={me.stamina <= 0 ? 'Out of stamina' : 'Not enough stamina'} onClose={closeRefill}>
      <div className="stack">
        <div className="small">
          You have <b className="tabular">⚡ {num(me.stamina)}/{num(me.stamina_max)}</b>{need > 0 && <> and this takes <b className="tabular">⚡ {need}</b></>}.
          {' '}It comes back {cfg.stamina_regen_amount ?? 2} {every(cfg.stamina_regen_minutes ?? 10)}, or refill now.
        </div>
        {missing <= 0 ? <div className="small muted">You're full.</div> : (
          <div className="card refill-sheet">
            {(me.free_refills ?? 0) > 0 && (
              <RefillRow icon="🎁" label="Free refill" sub={`${me.free_refills} left from the Daily Drop · fills you up`} gain={missing}
                onClick={() => done(() => api.refill('stamina', 'free'), `${(me.free_refills ?? 1) - 1} free left`)} />
            )}
            <RefillRow icon="💎" label={`${cfg.refill_diamonds} diamonds`} sub={`fills you up · you have 💎 ${num(me.diamonds)}`} gain={missing}
              disabled={me.diamonds < cfg.refill_diamonds}
              onClick={() => { if (missing < me.stamina_max / 2 && !confirm(`Only ${missing} stamina missing — spend ${cfg.refill_diamonds} diamonds anyway?`)) return; return done(() => api.refill('stamina', 'diamonds'), 'full') }} />
            {catalog.commodities.map(c => {
              const units = Math.ceil(c.refill_stamina * (1 - pharmacy))
              const have = me.storage[c.code] ?? 0
              return (
                <RefillRow key={c.code} icon={commodityIcon[c.code]} label={`${num(units)} ${c.name}`}
                  sub={`restores ${share >= 1 ? 'everything missing' : `${shareLabel(share)} of what's missing`} · you have ${num(have)}`}
                  gain={productGain} disabled={have < units}
                  onClick={() => done(() => api.refill('stamina', c.code), share < 1 ? `${shareLabel(share)} refill` : 'full')} />
              )
            })}
          </div>
        )}
        {missing > 0 && need > 0 && share < 1 && !after(productGain) && (
          <div className="warn">A product refill restores {shareLabel(share)} of what's missing today ({num(productGain)}), which isn't enough for this on its own. Diamond and free refills always fill you up.</div>
        )}
        <div className="small muted">
          {me.diamonds < cfg.refill_diamonds && <><Link to="/store" onClick={closeRefill}>Get diamonds ›</Link> · </>}
          <Link to="/services?focus=refills" onClick={closeRefill}>All refills ›</Link>
          {' '}· After {cfg.refill_full ?? 3} product refills a day each one restores half as much as the one before.
        </div>
      </div>
    </Modal>
  )
}

function RefillRow({ icon, label, sub, gain, disabled, onClick }: { icon: string; label: string; sub: string; gain: number; disabled?: boolean; onClick: () => Promise<unknown> | void }) {
  return (
    <div className={`row ${disabled ? 'dim' : ''}`}>
      <span className="ico">{icon}</span>
      <div className="grow"><div className="t">{label}</div><div className="s">{sub}</div></div>
      <Btn className="sm gold" disabled={disabled} onClick={onClick}>+{num(gain)} ⚡</Btn>
    </div>
  )
}
