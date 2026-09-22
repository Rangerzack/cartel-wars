import { useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { useGame, useMe } from '../lib/game'
import { api } from '../lib/api'
import { commodityIcon, hoodlumIcon, money, num, timeLeft } from '../lib/format'
import { useNow } from '../lib/useNow'
import { Btn, Card, Empty, Qty } from '../components/ui'

export default function Services() {
  const me = useMe()
  const { catalog, run } = useGame()
  const now = useNow()
  const nav = useNavigate()
  const [bank, setBank] = useState(0)
  const [bribe, setBribe] = useState(10)
  const [hood, setHood] = useState<{ code: string; n: number }>({ code: 'thug', n: 10 })
  if (!catalog) return <Empty><span className="spin" /></Empty>
  const cfg = catalog.config
  const bribeN = Math.min(bribe, me.heat)
  const jailMins = me.jail_until ? Math.max(0, Math.ceil((new Date(me.jail_until).getTime() - now) / 60000)) : 0
  const bail = cfg.bail_base + jailMins * cfg.bail_per_minute
  const owned = me.hoodlums[hood.code] ?? 0
  const hdef = catalog.hoodlums.find(h => h.code === hood.code)!
  const hoodCost = Math.round(hdef.base_price * hood.n * (1 + (owned + hood.n / 2) / 2000))

  return (
    <div className="page">
      {me.hospital && (
        <Card title="🏥 Hospital">
          <div className="bd stack">
            <div>You're laid up at {me.health} health. Checking out gets you to 20 — enough to move, not enough to brawl.</div>
            <Btn className="doit block" onClick={() => run(api.hospitalCheckout, { ok: r => `Checked out for ${money(r.cost)}` })}>Check Out · {money((20 - me.health) * cfg.hospital_per_point)}</Btn>
          </div>
        </Card>
      )}
      {me.jailed && (
        <Card title="🔒 County Jail" right={<small>{timeLeft(me.jail_until, now)} left</small>}>
          <div className="bd stack">
            <div className="small muted">Bail is {money(cfg.bail_base)} plus {money(cfg.bail_per_minute)} per minute remaining.</div>
            <Btn className="doit block" disabled={me.cash < bail} onClick={() => run(api.bailOut, { ok: r => `Bailed out for ${money(r.cost)}` })}>Post Bail · {money(bail)}</Btn>
          </div>
        </Card>
      )}

      <Card title="🚔 Police Station" right={<small>{money(cfg.bribe_per_heat)} per heat point</small>}>
        <div className="bd stack">
          <div className="spread">
            <div>Heat: <b className={me.heat_level}>{me.heat}</b> / {me.heat_max} <span className="muted small">({me.heat_level})</span></div>
            <Qty value={bribe} onChange={setBribe} min={1} max={Math.max(1, me.heat)} />
          </div>
          <Btn className="doit block" disabled={bribeN <= 0 || me.cash < bribeN * cfg.bribe_per_heat} onClick={() => run(() => api.bribePolice(bribeN), { ok: r => `Heat down to ${r.heat}` })}>Bribe · {money(bribeN * cfg.bribe_per_heat)}</Btn>
        </div>
      </Card>

      <Card title="🏦 Bank" right={<small>banked {money(me.bank)}</small>}>
        <div className="bd stack">
          <div className="small muted">Cash on hand can be taken in fights. Banked cash can't.</div>
          <input className="input" inputMode="numeric" placeholder="Amount" value={bank || ''} onChange={e => setBank(Number(e.target.value) || 0)} />
          <div className="grid2">
            <Btn className="gold" disabled={bank <= 0 || bank > me.cash} onClick={() => run(() => api.bankDeposit(bank), { ok: r => `Banked. Balance ${money(r.bank)}` })}>Deposit</Btn>
            <Btn disabled={bank <= 0 || bank > me.bank} onClick={() => run(() => api.bankWithdraw(bank), { ok: r => `Withdrawn. Balance ${money(r.bank)}` })}>Withdraw</Btn>
          </div>
          <div className="hstack">
            <button className="btn sm ghost" onClick={() => setBank(me.cash)}>All cash</button>
            <button className="btn sm ghost" onClick={() => setBank(me.bank)}>All banked</button>
          </div>
        </div>
      </Card>

      <Card title="⚡ Refills" right={<small>{me.refills_used}/3 product refills today</small>}>
        {(['stamina', 'health'] as const).map(kind => (
          <div key={kind} className="row" style={{ flexWrap: 'wrap' }}>
            <div className="grow t" style={{ textTransform: 'capitalize' }}>{kind} <span className="muted small">{num(kind === 'stamina' ? me.stamina : me.health)}/{num(kind === 'stamina' ? me.stamina_max : me.health_max)}</span></div>
            <Btn className="sm" disabled={me.diamonds < cfg.refill_diamonds} onClick={() => { const cur = kind === 'stamina' ? me.stamina : me.health, max = kind === 'stamina' ? me.stamina_max : me.health_max; if (cur >= max) return; if (max - cur < max / 2 && !confirm(`Only ${max - cur} ${kind} missing — spend ${cfg.refill_diamonds} diamonds anyway?`)) return; return run(() => api.refill(kind, 'diamonds'), { ok: r => `+${r.gain} ${kind}` }) }}>💎 {cfg.refill_diamonds}</Btn>
            {catalog.commodities.map(c => {
              const units = kind === 'stamina' ? c.refill_stamina : c.refill_health
              return <Btn key={c.code} className="sm" disabled={(me.storage[c.code] ?? 0) < units} onClick={() => run(() => api.refill(kind, c.code), { ok: r => `+${r.gain} ${kind}` })}>{commodityIcon[c.code]} {units}</Btn>
            })}
          </div>
        ))}
        <div className="row small muted">After three product refills in a day, the next ones only restore half.</div>
      </Card>

      <Card title="💎 Upgrades" right={<small>{num(me.diamonds)} diamonds</small>}>
        {[
          { k: 'stamina' as const, t: 'Max stamina +5', s: `${me.stamina_max}/150`, c: 10, dis: me.stamina_max >= 150 },
          { k: 'health' as const, t: 'Max health +25', s: `${me.health_max}/500`, c: 10, dis: me.health_max >= 500 },
          { k: 'slots' as const, t: 'Setup slot +1', s: `${me.inventory_slots} slots`, c: 15, dis: false },
        ].map(u => (
          <div key={u.k} className="row">
            <div className="grow"><div className="t">{u.t}</div><div className="s">{u.s}</div></div>
            <Btn className="sm" disabled={u.dis || me.diamonds < u.c} onClick={() => run(() => api.upgradeStat(u.k), { ok: () => 'Upgraded' })}>💎 {u.c}</Btn>
          </div>
        ))}
        <div className="row small muted">Diamonds are earned through achievements — 50, 100, 500, 1,000 and 5,000 actions; 10, 100 and 1,000 fight wins.</div>
      </Card>

      <Card title="🧢 Hoodlums" right={<Btn className="sm ghost" onClick={() => nav('/territory')}>Territory ›</Btn>}>
        <div className="bd stack">
          <div className="seg">
            {catalog.hoodlums.map(h => <button key={h.code} className={hood.code === h.code ? 'on' : ''} onClick={() => setHood({ ...hood, code: h.code })}>{hoodlumIcon[h.code]} {h.name}</button>)}
          </div>
          <div className="small muted">{hdef.att ? `${hdef.att} attack` : ''}{hdef.att && hdef.def ? ' · ' : ''}{hdef.def ? `${hdef.def} defense` : ''}{hdef.intel ? 'Reveals a block\'s garrison before you attack' : ''} · base {money(hdef.base_price)} — price climbs with how many you hold. You have {num(owned)}.</div>
          <div className="spread">
            <Qty value={hood.n} onChange={n => setHood({ ...hood, n })} min={1} max={1000} />
            <Btn className="doit" disabled={me.cash < hoodCost} onClick={() => run(() => api.buyHoodlums(hood.code, hood.n), { ok: r => `Hired for ${money(r.cost)}` })}>Hire · {money(hoodCost)}</Btn>
          </div>
        </div>
      </Card>
    </div>
  )
}
