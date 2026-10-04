import { Link } from 'react-router-dom'
import { api } from '../lib/api'
import { useGame, useMe } from '../lib/game'
import { commodityIcon, every, num } from '../lib/format'
import { drugRefill } from '../lib/market'
import { perk } from '../lib/perks'
import { Btn, Modal } from './ui'

/** The sheet that opens when a job, a fight or a turf war needs more stamina than the player has: every way to refill,
 *  priced, with what each one restores, so the next tap is the refill rather than a trip to Services. The same rules as
 *  the Refills card (diamond and free refills fill you up; each drug fills you up 3 times a day, 5 on the Daily Drop,
 *  then restores half the bar; Pharmacy perk included); the server checks them again. Mounted once in Layout; opened
 *  through useGame().askRefill. */
export function RefillSheet() {
  const me = useMe()
  const { catalog, run, refillNeed, closeRefill, ask } = useGame()
  if (refillNeed == null || !catalog) return null
  const cfg = catalog.config
  const need = refillNeed
  const missing = me.stamina_max - me.stamina
  const pharmacy = perk(me, 'pharmacy')
  const after = (gain: number) => me.stamina + gain >= need
  const drugs = catalog.commodities.map(c => ({ c, units: Math.ceil(c.refill_stamina * (1 - pharmacy)), have: me.storage[c.code] ?? 0, d: drugRefill(me, catalog, c.code) }))
  // every drug you can afford is past its full refills and half the bar still isn't enough for this
  const halfShort = need > 0 && drugs.some(x => x.have >= x.units) && drugs.every(x => x.have < x.units || (x.d.left === 0 && !after(x.d.gain)))
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
        {need > me.stamina_max ? <div className="small muted">This takes more than your bar holds. <Link to="/services?focus=upgrades" onClick={closeRefill}>Raise max stamina ›</Link></div>
          : missing <= 0 ? <div className="small muted">You're full.</div> : (
          <div className="card refill-sheet">
            {(me.free_refills ?? 0) > 0 && (
              <RefillRow icon="🎁" label="Free refill" sub={`${me.free_refills} left from the Daily Drop · fills you up`} gain={missing}
                onClick={() => done(() => api.refill('stamina', 'free'), `${(me.free_refills ?? 1) - 1} free left`)} />
            )}
            <RefillRow icon="💎" label={`${cfg.refill_diamonds} diamonds`} sub={`fills you up · you have 💎 ${num(me.diamonds)}`} gain={missing}
              disabled={me.diamonds < cfg.refill_diamonds}
              onClick={async () => { if (missing < me.stamina_max / 2 && !await ask(`Only ${missing} stamina is missing. A diamond refill always fills you up.`, { title: `Spend ${cfg.refill_diamonds} diamonds?`, yes: `Refill · 💎 ${cfg.refill_diamonds}`, tone: 'gold' })) return; return done(() => api.refill('stamina', 'diamonds'), 'full') }} />
            {drugs.map(({ c, units, have, d }) => (
              <RefillRow key={c.code} icon={commodityIcon[c.code]} label={`${num(units)} ${c.name}`}
                sub={`${d.left > 0 ? `fills you up · ${d.left} of ${d.full} left today` : 'half your stamina · full again at 00:00 UTC'} · you have ${num(have)}`}
                gain={d.gain} disabled={have < units}
                onClick={() => done(() => api.refill('stamina', c.code), d.left > 1 ? `${d.left - 1} full ${c.name} left today` : d.left === 1 ? `last full ${c.name} today` : 'half refill')} />
            ))}
          </div>
        )}
        {missing > 0 && halfShort && (
          <div className="warn">Your drugs are past today's full refills, and half your stamina bar isn't enough for this. Diamond and free refills always fill you up.</div>
        )}
        <div className="small muted">
          {me.diamonds < cfg.refill_diamonds && <><Link to="/store" onClick={closeRefill}>Get diamonds ›</Link> · </>}
          <Link to="/services?focus=refills" onClick={closeRefill}>All refills ›</Link>
          {' '}· Each drug fills you up {me.refills?.full ?? cfg.refill_full ?? 3} times a day{me.drop?.subscribed ? '' : ` (${me.refills?.sub_full ?? 5} with the Daily Drop)`}, then restores half your stamina.
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
