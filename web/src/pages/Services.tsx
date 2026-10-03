import { Fragment, useEffect, useState, type ReactNode } from 'react'
import { Link, useLocation, useNavigate, useSearchParams } from 'react-router-dom'
import { useGame, useMe } from '../lib/game'
import { api } from '../lib/api'
import { commodityIcon, money, num, timeLeft, every, nextRollover } from '../lib/format'
import { useNow } from '../lib/useNow'
import { focusCard } from '../lib/scroll'
import { Btn, Card, Empty, Qty } from '../components/ui'
import { HealButton } from '../components/Heal'
import { PerkTag } from '../components/Perk'
import { HireHoodlums } from '../components/Hire'
import { bailCost, perk } from '../lib/perks'
import { drugRefill } from '../lib/market'
import type { MilestoneKind } from '../lib/types'
import { milestoneLabel, milestoneTotal, nextRepeat } from '../lib/milestones'

export default function Services() {
  const me = useMe()
  const { catalog, run, ask } = useGame()
  const now = useNow()
  const nav = useNavigate()
  const [sp] = useSearchParams()
  const focus = sp.get('focus')
  const { key } = useLocation()
  // /services?focus=bank|refills|upgrades|boost|hoodlums|police|hospital|jail scrolls straight to that card; the chips
  // link here too, and the location key changes on every tap, so tapping the same chip again scrolls again
  useEffect(() => {
    if (!focus) return
    // on a cold load (a link from outside, the Pages 404 bounce) the cards wait for the catalog: keep trying for 3 s
    let tries = 0, t = 0
    const go = () => { if (!focusCard(focus) && ++tries < 20) t = window.setTimeout(go, 150) }
    t = window.setTimeout(go, 150)
    return () => clearTimeout(t)
  }, [focus, key])
  const [bank, setBank] = useState(0)
  const [bribe, setBribe] = useState(10)
  if (!catalog) return <Empty><span className="spin" /></Empty>
  const cfg = catalog.config
  const bribeN = Math.min(bribe, me.heat)
  const heatRed = me.heat_red ?? cfg.heat_red
  // prices mirror the server, business perks included (Law Office, Gym / Shooting Range, Bent Cop, Pharmacy; the Clinic in HealButton)
  const law = perk(me, 'law_office'), bent = perk(me, 'bent_cop'), pharmacy = perk(me, 'pharmacy')
  const bail = bailCost(me, cfg)   // jail has no timer: you're in until you post this
  const bribeCost = (n: number) => Math.ceil(n * cfg.bribe_per_heat * (1 - bent))
  const refillUnits = (units: number) => Math.ceil(units * (1 - pharmacy))
  // drug refills: each drug is full this many times a day (more on the Daily Drop), then half the stamina bar
  const fullN = me.refills?.full ?? cfg.refill_full ?? 3
  const subFull = me.refills?.sub_full ?? fullN + 2
  const subscribed = !!me.drop?.subscribed
  const lateGain = Math.ceil(me.stamina_max * (me.refills?.late_share ?? 0.5))
  const usedAny = Object.values(me.refills?.used ?? {}).some(n => (n ?? 0) > 0)
  const missing = me.health_max - me.health
  const outAt = me.hospital_out_at ?? 20
  const maxSlots = cfg.max_slots ?? 130
  const slotsMaxed = me.inventory_slots >= maxSlots

  // "hurt" is under half health: a scratch from one fight heals in minutes and shouldn't push Bank down the page
  const hurt = me.hospital || me.health < me.health_max / 2
  const hot = me.heat >= heatRed

  const cards: Record<string, ReactNode> = {
    hospital: (
      <Card id="hospital" title="🏥 Hospital" right={<small>{num(me.health)}/{num(me.health_max)} health</small>}>
        <div className="bd stack">
          <PerkTag code="clinic" />
          {me.hospital
            ? <div>You're laid up at {me.health} health. You heal {cfg.health_regen_amount} {every(cfg.health_regen_minutes)} — next in {timeLeft(me.health_next, now)} — and walk out at {outAt} ({cfg.hospital_release_pct ?? 80}% of your max).</div>
            : <div className="small muted">Health comes back {cfg.health_regen_amount} {every(cfg.health_regen_minutes)}. Get knocked under 20 and you're in the hospital until you're back to {cfg.hospital_release_pct ?? 80}%. Here you heal all the way to full in one go — the price per point climbs the more you buy in a day.</div>}
          {/* health is sold to full only: one price, or wait till you have it */}
          {missing > 0 ? (
            <>
              <HealButton className="doit block" />
              {me.health_bought > 0 && <div className="small muted">{num(me.health_bought)} bought in the last 24h — the scale resets a day after your first buy.</div>}
            </>
          ) : <div className="small muted">You're at full health.</div>}
        </div>
      </Card>
    ),
    jail: me.jailed && (
      <Card id="jail" title="🔒 County Jail" right={<small>until you post bail</small>}>
        <div className="bd stack">
          <div className="small muted">There's no sentence to wait out — you're inside until you post bail: {money(cfg.bail_base)}{law > 0 ? `, less ${Math.round(law * 100)}% from your Law Office` : ''}, from cash on hand. Until then it's jail jobs, and fights with other inmates only. Your heat maxed out when you went in; bail walks you out with zero heat.</div>
          <PerkTag code="law_office" />
          <Btn className="doit block" disabled={me.cash < bail} onClick={() => run(api.bailOut, { ok: r => `Bailed out for ${money(r.cost)} · heat back to 0` })}>Post Bail · {money(bail)}</Btn>
          {me.cash < bail && <div className="why">Bail comes out of cash on hand — you have {money(me.cash)}.</div>}
        </div>
      </Card>
    ),
    police: (
      <Card id="police" title="🚔 Police Station" right={<small>{money(cfg.bribe_per_heat * (1 - bent))} per heat point</small>}>
        <div className="bd stack">
          <div className="spread">
            <div>Heat: <b className={me.heat_level}>{me.heat}</b> / {me.heat_max} <span className="muted small">({me.heat_level})</span></div>
            <Qty value={bribe} onChange={setBribe} min={1} max={Math.max(1, me.heat)} />
          </div>
          <PerkTag code="bent_cop" />
          <Btn className="doit block" disabled={bribeN <= 0 || me.cash < bribeCost(bribeN)} onClick={() => run(() => api.bribePolice(bribeN), { ok: r => `Heat down to ${r.heat}` })}>Bribe · {money(bribeCost(bribeN))}</Btn>
          {me.jailed && <div className="small muted">You're inside: posting bail clears your heat to 0, so there's no need to bribe it down first.</div>}
          <div className="small muted">Heat cuts both ways: in a fight, whoever has more heat gets +1. Red ({heatRed}+) risks a bust on every job and attack, so you only need to bribe it back under {heatRed}.{me.heat_max > (cfg.heat_base ?? 100) ? <> Your heat upgrades moved it up from {cfg.heat_red}.</> : <> Heat upgrades (💎 {cfg.heat_upgrade_diamonds ?? 30} each, below) move it up.</>}</div>
          {!me.jailed && (
            <div className="spread turn-in">
              <div className="small">Want in? Turn yourself in to run jail jobs and fight other inmates — no stamina or cash needed. You stay until you post bail ({money(bail)}). Going in maxes your heat; bail clears it to 0.</div>
              <Btn className="sm" disabled={me.hospital || me.diamonds < (cfg.jail_diamonds ?? 50)}
                onClick={async () => { if (await ask(`You stay until you post bail (${money(bail)}), and only fight other inmates with your jail setup. Your heat goes to max (${me.heat_max}) while you're in, and back to 0 when you bail.`, { title: `Go to jail for 💎 ${cfg.jail_diamonds ?? 50}?`, yes: 'Go to jail', tone: 'gold' })) return run(api.goToJail, { ok: () => "You're in County Jail — jail setup is active" }) }}>Go to Jail · 💎 {cfg.jail_diamonds ?? 50}</Btn>
            </div>
          )}
        </div>
      </Card>
    ),
    bank: (
      <Card id="bank" title="🏦 Bank" right={<small>banked {money(me.bank)}</small>}>
        <div className="bd stack">
          <div className="small muted">Cash on hand can be taken in fights. Banked cash can't. Carrying more cash than the other side is worth +1 in a fight, though. {cfg.daily_cash ? <>Everyone gets {money(cfg.daily_cash)} on hand at 00:00 UTC — next in {timeLeft(nextRollover(now), now)}.</> : null}</div>
          <input className="input" inputMode="numeric" placeholder="Amount" aria-label="Amount to deposit or withdraw" value={bank || ''} onChange={e => setBank(Number(e.target.value) || 0)} />
          <div className="grid2">
            {/* the field clears after a move, so a second tap can't send the same amount again */}
            <Btn className="gold" disabled={bank <= 0 || bank > me.cash} onClick={async () => { if (await run(() => api.bankDeposit(bank), { ok: r => `Banked. Balance ${money(r.bank)}` })) setBank(0) }}>Deposit</Btn>
            <Btn disabled={bank <= 0 || bank > me.bank} onClick={async () => { if (await run(() => api.bankWithdraw(bank), { ok: r => `Withdrawn. Balance ${money(r.bank)}` })) setBank(0) }}>Withdraw</Btn>
          </div>
          <div className="hstack">
            <button className="btn sm ghost" onClick={() => setBank(me.cash)}>All cash</button>
            <button className="btn sm ghost" onClick={() => setBank(me.bank)}>All banked</button>
          </div>
        </div>
      </Card>
    ),
    refills: (
      <Card id="refills" title="⚡ Refills" right={<small>{fullN} full per drug a day</small>}>
        {pharmacy > 0 && <div className="row"><PerkTag code="pharmacy" /></div>}
        <div className="row" style={{ flexWrap: 'wrap' }}>
          <div className="grow t">Stamina <span className="muted small">{num(me.stamina)}/{num(me.stamina_max)}</span></div>
          {/* nothing to refill: one disabled "Full" instead of live price buttons */}
          {me.stamina >= me.stamina_max ? <button className="btn sm" disabled>Full</button> : <>
            {(me.free_refills ?? 0) > 0 && <Btn className="sm gold" onClick={() => run(() => api.refill('stamina', 'free'), { ok: r => `+${r.gain} stamina · ${(me.free_refills ?? 1) - 1} free left` })}>🎁 Free ×{me.free_refills}</Btn>}
            <Btn className="sm" disabled={me.diamonds < cfg.refill_diamonds} onClick={async () => { const gap = me.stamina_max - me.stamina; if (gap < me.stamina_max / 2 && !await ask(`Only ${gap} stamina is missing. A diamond refill always fills you up.`, { title: `Spend ${cfg.refill_diamonds} diamonds?`, yes: `Refill · 💎 ${cfg.refill_diamonds}`, tone: 'gold' })) return; return run(() => api.refill('stamina', 'diamonds'), { ok: r => `+${r.gain} stamina` }) }}>💎 {cfg.refill_diamonds}</Btn>
            {catalog.commodities.map(c => {
              const units = refillUnits(c.refill_stamina)
              return <Btn key={c.code} className="sm" disabled={(me.storage[c.code] ?? 0) < units} onClick={() => run(() => api.refill('stamina', c.code), { ok: r => `+${r.gain} stamina${r.full_left == null ? '' : r.full_left > 0 ? ` · ${r.full_left} full ${c.name} refill${r.full_left > 1 ? 's' : ''} left today` : ` · ${c.name} restores half your stamina until 00:00 UTC`}` })}>{commodityIcon[c.code]} {num(units)}</Btn>
            })}
          </>}
        </div>
        <div className="row small refill-left">
          <span className="muted">Full refills left today</span>
          {catalog.commodities.map(c => { const d = drugRefill(me, catalog, c.code); return <span key={c.code} className={`pill ${d.left ? '' : 'red'}`}>{commodityIcon[c.code]} {d.left}/{d.full}</span> })}
        </div>
        <div className="row" style={{ flexWrap: 'wrap' }}>
          <div className="grow t">Health <span className="muted small">{num(me.health)}/{num(me.health_max)}</span></div>
          {me.health >= me.health_max ? <button className="btn sm" disabled>Full</button>
            : <Btn className="sm" disabled={me.diamonds < cfg.refill_diamonds} onClick={async () => { const gap = me.health_max - me.health; if (gap < me.health_max / 2 && !await ask(`Only ${gap} health is missing. A diamond refill always fills you up.`, { title: `Spend ${cfg.refill_diamonds} diamonds?`, yes: `Refill · 💎 ${cfg.refill_diamonds}`, tone: 'gold' })) return; return run(() => api.refill('health', 'diamonds'), { ok: r => `+${r.gain} health` }) }}>💎 {cfg.refill_diamonds}</Btn>}
        </div>
        {(me.free_refills ?? 0) > 0 && <div className="row small muted">🎁 Free refills come from the Daily Drop: a full stamina refill each, on top of the drug ones.</div>}
        <div className="row small muted refill-next"><div>
          Each drug fills your stamina {fullN} times a day{subscribed ? ' (5 with your Daily Drop)' : <> — {subFull} with the <Link to="/store#drop">Daily Drop</Link></>}. After that, a refill of that drug restores half your stamina bar ({num(lateGain)}).
          {' '}They come back at 00:00 UTC{usedAny ? <> — in {timeLeft(nextRollover(now), now)}</> : null}. Drugs don't heal: health comes from the Hospital or diamonds. Diamond and free refills always fill you up.
        </div></div>
      </Card>
    ),
    upgrades: (
      <Card id="upgrades" title="💎 Upgrades" right={<Link className="small" to="/store">💎 {num(me.diamonds)} ›</Link>}>
        {[
          { k: 'stamina' as const, t: 'Max stamina +5', s: `${me.stamina_max}/150`, c: 10, cash: 0, dis: me.stamina_max >= 150 },
          { k: 'health' as const, t: 'Max health +25', s: `${me.health_max}/500`, c: 10, cash: 0, dis: me.health_max >= 500 },
          { k: 'heat' as const, t: `Max heat +${cfg.heat_upgrade_amount ?? 50}`, s: `${me.heat_max} max · red from ${heatRed} — ${cfg.heat_upgrade_amount ?? 50} more before a bust risk`, c: cfg.heat_upgrade_diamonds ?? 30, cash: 0, dis: false },
          { k: 'slots' as const, t: 'Setup slot +1', s: `${me.inventory_slots}/${maxSlots} slots · each one past ${cfg.base_slots ?? 6} costs more`, c: me.slot_cost?.diamonds ?? 15, cash: me.slot_cost?.cash ?? 0, dis: slotsMaxed },
        ].map(u => (
          <div key={u.k} className="row">
            <div className="grow"><div className="t">{u.t}</div><div className="s">{u.s}</div></div>
            {u.dis ? <span className="pill gold nowrap">Maxed</span> : <Btn className="sm" disabled={me.diamonds < u.c || me.cash < u.cash}
              onClick={() => run(() => api.upgradeStat(u.k), { ok: r => r.cash ? `Upgraded for 💎 ${r.cost} + ${money(r.cash)}` : u.k === 'heat' ? `+${cfg.heat_upgrade_amount ?? 50} max heat — red now starts at ${heatRed + (cfg.heat_upgrade_amount ?? 50)}` : 'Upgraded' })}>
              💎 {u.c}{u.cash > 0 && <> + {money(u.cash)}</>}
            </Btn>}
          </div>
        ))}
        {!slotsMaxed && (me.slot_cost?.cash ?? 0) > me.cash && <div className="row small muted">Slots take cash on hand — you have {money(me.cash)}.</div>}
        <div className="row small muted"><div>Diamonds come from <Link to="/services?focus=milestones">milestones</Link>, the Daily Drop and the Store.</div></div>
      </Card>
    ),
    milestones: <Milestones />,
    boost: me.boost && <BoostCard />,
    hoodlums: (
      <Card id="hoodlums" title="🧢 Hoodlums" right={<Btn className="sm ghost" onClick={() => nav('/territory')}>Territory ›</Btn>}>
        <div className="bd"><HireHoodlums /></div>
      </Card>
    ),
  }
  // What you came for first (P2-13): jail when you're in it, the hospital when you're hurt, the police when heat is
  // red; otherwise Bank, the card used most. The rest keep their order.
  const urgent = [me.jailed && 'jail', hurt && 'hospital', hot && 'police'].filter((k): k is string => !!k)
  const order = [...urgent, ...['bank', 'refills', 'upgrades', 'milestones', 'boost', 'hoodlums', 'police', 'hospital'].filter(k => !urgent.includes(k) && cards[k])]
  const label: Record<string, string> = { bank: 'Bank', refills: 'Refills', upgrades: 'Upgrades', milestones: 'Milestones', boost: 'Boost', hoodlums: 'Hoodlums', police: 'Police', hospital: 'Hospital', jail: 'Jail' }

  return (
    <div className="page">
      <nav className="svc-nav" aria-label="Services">
        {order.map(k => <Link key={k} to={`/services?focus=${k}`} replace className={focus === k ? 'on' : urgent.includes(k) ? 'alert' : ''}>{label[k]}</Link>)}
      </nav>
      {order.map(k => <Fragment key={k}>{cards[k]}</Fragment>)}
    </div>
  )
}

/** 24-hour +50: attack in the Offense setup or defense in the Defense setup — one side at a time while it runs. */
function BoostCard() {
  const me = useMe()
  const { catalog, run } = useGame()
  const now = useNow()
  const b = me.boost
  if (!b || !catalog) return null
  const cost = catalog.config.boost_diamonds ?? 50
  const hours = catalog.config.boost_hours ?? 24
  const label = (side: 'attack' | 'defense') => side === 'attack' ? `+${b.amount} Attack` : `+${b.amount} Defense`
  const where = (side: 'attack' | 'defense') => side === 'attack' ? 'your Offense setup' : 'your Defense setup'
  const other = (side: 'attack' | 'defense') => side === 'attack' ? 'defense' : 'attack'
  const buy = (side: 'attack' | 'defense') =>
    run(() => api.buyBoost(side), { ok: () => b.active ? `Boost extended another ${hours}h` : `${label(side)} for ${hours}h` })
  return (
    <Card id="boost" title="⚡ Boost" right={b.active && b.until ? <small className="gold">{timeLeft(b.until, now)} left</small> : <small>💎 {cost} · {hours}h</small>}>
      <div className="bd stack">
        {b.active && b.side ? (
          <>
            <div className="spread">
              <div>
                <div className="t">{label(b.side)} <span className="muted small">in {where(b.side)}</span></div>
                <div className="small muted">Running — {timeLeft(b.until, now)} left. Buying again adds another {hours} hours.</div>
              </div>
              <Btn className="sm" disabled={me.diamonds < cost} onClick={() => buy(b.side!)}>Extend · 💎 {cost}</Btn>
            </div>
            <div className="small muted">One side at a time: you can switch to {other(b.side)} once this one runs out.</div>
          </>
        ) : (
          <>
            <div className="small">{cost} diamonds buys {label('attack')} in your Offense setup <b>or</b> {label('defense')} in your Defense setup for {hours} hours. One side at a time — while a boost runs you can extend it, and when it runs out you can pick either side again.</div>
            <div className="grid2">
              <Btn className="gold" disabled={me.diamonds < cost} onClick={() => buy('attack')}>{label('attack')} · 💎 {cost}</Btn>
              <Btn className="blue" disabled={me.diamonds < cost} onClick={() => buy('defense')}>{label('defense')} · 💎 {cost}</Btn>
            </div>
            {b.side && <div className="small muted">Your last boost was {b.side}.</div>}
          </>
        )}
      </div>
    </Card>
  )
}

/** Diamonds from milestones (20261004000017): the repeating steps (💎30 every 250 actions, 500 wins, 500 turf attacks,
 *  $10M wagered), each with how far you are toward the next one, then the lifetime ladders on tap. */
function Milestones() {
  const me = useMe()
  const { catalog } = useGame()
  const defs = catalog?.milestones ?? []
  if (defs.length === 0) return null
  const order: MilestoneKind[] = ['actions', 'wins', 'fights', 'turf', 'wagered']
  const repeats = defs.filter(m => m.repeat).sort((a, b) => order.indexOf(a.kind) - order.indexOf(b.kind))
  const kinds: MilestoneKind[] = ['actions', 'wins', 'fights', 'wagered']
  const ladder = (k: MilestoneKind) => defs.filter(m => !m.repeat && m.kind === k).sort((a, b) => a.n - b.n)
  const amount = (k: MilestoneKind, n: number) => (k === 'wagered' ? money(n) : num(n))
  return (
    <Card id="milestones" title="🏅 Milestones" right={<small>💎 {num(me.diamonds)}</small>}>
      {repeats.map(m => {
        const total = milestoneTotal(me, m.kind), { at, from } = nextRepeat(m, total)
        return (
          <div key={m.key} className="row milestone-row">
            <div className="grow">
              <div className="t">Every {amount(m.kind, m.n)} {m.kind === 'wagered' ? 'wagered at the casino' : milestoneLabel[m.kind]}</div>
              <div className="s tabular">{amount(m.kind, total)} so far · next at {amount(m.kind, at)}</div>
              <div className="track"><div className="fill" style={{ width: `${Math.min(100, ((total - from) / m.n) * 100)}%` }} /></div>
            </div>
            <b className="dia nowrap">💎 {m.reward}</b>
          </div>
        )
      })}
      <div className="row small muted milestones">
        <details className="grow">
          <summary>Lifetime milestones, once each</summary>
          <div className="grid2 milestone-ladder">
            {kinds.filter(k => ladder(k).length).map(k => (
              <div key={k} className="stack" style={{ gap: 2 }}>
                <b>{k === 'actions' ? 'Actions' : k === 'wins' ? 'Fight wins' : k === 'fights' ? 'All fights' : 'Casino wagered'}</b>
                {ladder(k).map(m => {
                  const done = milestoneTotal(me, k) >= m.n
                  return <span key={m.key} className={done ? 'done' : ''}>{done ? '✓' : '·'} {k === 'wagered' ? money(m.n) : num(m.n)} → 💎 {m.reward}</span>
                })}
              </div>
            ))}
          </div>
        </details>
      </div>
    </Card>
  )
}
