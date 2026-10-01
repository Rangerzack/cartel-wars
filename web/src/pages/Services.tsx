import { Fragment, useEffect, useState, type ReactNode } from 'react'
import { Link, useLocation, useNavigate, useSearchParams } from 'react-router-dom'
import { useGame, useMe } from '../lib/game'
import { api } from '../lib/api'
import { commodityIcon, hoodlumIcon, money, num, timeLeft, every, nextRollover } from '../lib/format'
import { useNow } from '../lib/useNow'
import { focusCard } from '../lib/scroll'
import { Btn, Card, Empty, Qty } from '../components/ui'
import { PerkTag } from '../components/Perk'
import { perk } from '../lib/perks'
import { refillShare, shareLabel } from '../lib/market'
import type { BusinessCode, MilestoneDef } from '../lib/types'

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
    const t = setTimeout(() => focusCard(focus), 150)
    return () => clearTimeout(t)
  }, [focus, key])
  const [bank, setBank] = useState(0)
  const [bribe, setBribe] = useState(10)
  const [hood, setHood] = useState<{ code: string; n: number }>({ code: 'thug', n: 10 })
  const [heal, setHeal] = useState(20)
  if (!catalog) return <Empty><span className="spin" /></Empty>
  const cfg = catalog.config
  const bribeN = Math.min(bribe, me.heat)
  const heatRed = me.heat_red ?? cfg.heat_red
  // prices mirror the server, business perks included (Law Office, Gym / Shooting Range, Clinic, Bent Cop, Pharmacy)
  const law = perk(me, 'law_office'), clinic = perk(me, 'clinic'), bent = perk(me, 'bent_cop'), pharmacy = perk(me, 'pharmacy')
  const bail = Math.ceil(cfg.bail_base * (1 - law))   // jail has no timer: you're in until you post this
  const owned = me.hoodlums[hood.code] ?? 0
  const hdef = catalog.hoodlums.find(h => h.code === hood.code)!
  const hoodPerk: BusinessCode | null = hood.code === 'thug' ? 'gym' : hood.code === 'mercenary' || hood.code === 'enforcer' ? 'shooting_range' : null
  const hoodCost = Math.ceil(Math.round(hdef.base_price * hood.n * (1 + (owned + hood.n / 2) / 2000)) * (1 - (hoodPerk ? perk(me, hoodPerk) : 0)))
  // mirrors _health_price: per-point price climbs with points bought in the last 24h
  const healthPrice = (n: number) => Math.ceil(Math.ceil(cfg.hospital_per_point * n * (1 + (me.health_bought + n / 2) / cfg.health_price_scale)) * (1 - clinic))
  const bribeCost = (n: number) => Math.ceil(n * cfg.bribe_per_heat * (1 - bent))
  const refillUnits = (units: number) => Math.ceil(units * (1 - pharmacy))
  const fullRefills = cfg.refill_full ?? 3
  const nextShare = refillShare(me, catalog)
  const missing = me.health_max - me.health
  const healN = Math.max(1, Math.min(heal, missing))
  const outAt = me.hospital_out_at ?? 20
  const outN = Math.max(0, outAt - me.health)
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
            : <div className="small muted">Health comes back {cfg.health_regen_amount} {every(cfg.health_regen_minutes)}. Get knocked under 20 and you're in the hospital until you're back to {cfg.hospital_release_pct ?? 80}%. Buy more here — the price per point climbs the more you buy in a day.</div>}
          {me.hospital && outN > 0 && (
            <Btn className="doit block" disabled={me.cash < healthPrice(outN)} onClick={() => run(api.hospitalCheckout, { ok: r => `Checked out for ${money(r.cost)}` })}>Check Out (+{outN}) · {money(healthPrice(outN))}</Btn>
          )}
          {missing > 0 ? (
            <>
              <div className="spread">
                <Qty value={healN} onChange={setHeal} min={1} max={Math.max(1, missing)} />
                <Btn className={me.hospital ? '' : 'doit'} disabled={me.cash < healthPrice(healN)} onClick={() => run(() => api.buyHealth(healN), { ok: r => `+${r.gain} health for ${money(r.cost)}` })}>Buy +{healN} · {money(healthPrice(healN))}</Btn>
              </div>
              <div className="hstack">
                <button className="btn sm ghost" onClick={() => setHeal(Math.max(1, Math.min(25, missing)))}>+25</button>
                <button className="btn sm ghost" onClick={() => setHeal(Math.max(1, Math.min(50, missing)))}>+50</button>
                <button className="btn sm ghost" onClick={() => setHeal(missing)}>Full · {money(healthPrice(missing))}</button>
              </div>
              {me.health_bought > 0 && <div className="small muted">{num(me.health_bought)} bought in the last 24h — the scale resets a day after your first buy.</div>}
            </>
          ) : <div className="small muted">You're at full health.</div>}
        </div>
      </Card>
    ),
    jail: me.jailed && (
      <Card id="jail" title="🔒 County Jail" right={<small>until you post bail</small>}>
        <div className="bd stack">
          <div className="small muted">There's no sentence to wait out — you're inside until you post bail: {money(cfg.bail_base)}{law > 0 ? `, less ${Math.round(law * 100)}% from your Law Office` : ''}, from cash on hand. Until then it's jail jobs, and fights with other inmates only.</div>
          <PerkTag code="law_office" />
          <Btn className="doit block" disabled={me.cash < bail} onClick={() => run(api.bailOut, { ok: r => `Bailed out for ${money(r.cost)}` })}>Post Bail · {money(bail)}</Btn>
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
          <div className="small muted">Heat cuts both ways: in a fight, whoever has more heat gets +1. Red ({heatRed}+) risks a bust on every job and attack, so you only need to bribe it back under {heatRed}.{me.heat_max > (cfg.heat_base ?? 100) ? <> Your heat upgrades moved it up from {cfg.heat_red}.</> : <> Heat upgrades (💎 {cfg.heat_upgrade_diamonds ?? 30} each, below) move it up.</>}</div>
          {!me.jailed && (
            <div className="spread turn-in">
              <div className="small">Want in? Turn yourself in to run jail jobs and fight other inmates — no stamina or cash needed. You stay until you post bail ({money(bail)}).</div>
              <Btn className="sm" disabled={me.hospital || me.diamonds < (cfg.jail_diamonds ?? 50)}
                onClick={async () => { if (await ask(`You stay until you post bail (${money(bail)}), and only fight other inmates with your jail setup.`, { title: `Go to jail for 💎 ${cfg.jail_diamonds ?? 50}?`, yes: 'Go to jail', tone: 'gold' })) return run(api.goToJail, { ok: () => "You're in County Jail — jail setup is active" }) }}>Go to Jail · 💎 {cfg.jail_diamonds ?? 50}</Btn>
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
      <Card id="refills" title="⚡ Refills" right={<small>{Math.min(fullRefills, me.refills_used)}/{fullRefills} full product refills today</small>}>
        {pharmacy > 0 && <div className="row"><PerkTag code="pharmacy" /></div>}
        {(['stamina', 'health'] as const).map(kind => {
          const cur = kind === 'stamina' ? me.stamina : me.health, max = kind === 'stamina' ? me.stamina_max : me.health_max
          return (
            <div key={kind} className="row" style={{ flexWrap: 'wrap' }}>
              <div className="grow t" style={{ textTransform: 'capitalize' }}>{kind} <span className="muted small">{num(cur)}/{num(max)}</span></div>
              {/* nothing to refill: one disabled "Full" instead of four live price buttons */}
              {cur >= max ? <button className="btn sm" disabled>Full</button> : <>
                {kind === 'stamina' && (me.free_refills ?? 0) > 0 && <Btn className="sm gold" onClick={() => run(() => api.refill('stamina', 'free'), { ok: r => `+${r.gain} stamina · ${(me.free_refills ?? 1) - 1} free left` })}>🎁 Free ×{me.free_refills}</Btn>}
                <Btn className="sm" disabled={me.diamonds < cfg.refill_diamonds} onClick={async () => { if (max - cur < max / 2 && !await ask(`Only ${max - cur} ${kind} is missing. A diamond refill always fills you up.`, { title: `Spend ${cfg.refill_diamonds} diamonds?`, yes: `Refill · 💎 ${cfg.refill_diamonds}`, tone: 'gold' })) return; return run(() => api.refill(kind, 'diamonds'), { ok: r => `+${r.gain} ${kind}` }) }}>💎 {cfg.refill_diamonds}</Btn>
                {catalog.commodities.map(c => {
                  const units = refillUnits(kind === 'stamina' ? c.refill_stamina : c.refill_health)
                  return <Btn key={c.code} className="sm" disabled={(me.storage[c.code] ?? 0) < units} onClick={() => run(() => api.refill(kind, c.code), { ok: r => `+${r.gain} ${kind}${r.next_share != null && r.next_share < 1 ? ` · the next one restores ${shareLabel(r.next_share)}` : ''}` })}>{commodityIcon[c.code]} {units}</Btn>
                })}
              </>}
            </div>
          )
        })}
        {(me.free_refills ?? 0) > 0 && <div className="row small muted">🎁 Free refills come from the Daily Drop: a full stamina refill each, and they don't count toward the three a day.</div>}
        <div className="row small muted refill-next"><div>After {fullRefills} product refills in a day, each one restores half as much as the one before (½, ¼, ⅛ …). Your next product refill restores <b>{nextShare >= 1 ? 'everything missing' : `${shareLabel(nextShare)} of what's missing`}</b>. The full ones come back at 00:00 UTC{me.refills_used > 0 ? <> — in {timeLeft(nextRollover(now), now)}</> : null}. Diamond and free refills are always full.</div></div>
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
        <Milestones />
      </Card>
    ),
    boost: me.boost && <BoostCard />,
    hoodlums: (
      <Card id="hoodlums" title="🧢 Hoodlums" right={<Btn className="sm ghost" onClick={() => nav('/territory')}>Territory ›</Btn>}>
        <div className="bd stack">
          <div className="seg">
            {catalog.hoodlums.map(h => <button key={h.code} className={hood.code === h.code ? 'on' : ''} onClick={() => setHood({ ...hood, code: h.code })}>{hoodlumIcon[h.code]} {h.name}</button>)}
          </div>
          <div className="small muted">{hdef.att ? `${hdef.att} attack` : ''}{hdef.att && hdef.def ? ' · ' : ''}{hdef.def ? `${hdef.def} defense` : ''}{hdef.intel ? 'Reveals a block\'s garrison before you attack' : ''} · base {money(hdef.base_price)} — price climbs with how many you hold. You have {num(owned)}.</div>
          {hoodPerk && <PerkTag code={hoodPerk} />}
          <div className="spread">
            <Qty value={hood.n} onChange={n => setHood({ ...hood, n })} min={1} max={1000} />
            <Btn className="doit" disabled={me.cash < hoodCost} onClick={() => run(() => api.buyHoodlums(hood.code, hood.n), { ok: r => `Hired for ${money(r.cost)}` })}>Hire · {money(hoodCost)}</Btn>
          </div>
        </div>
      </Card>
    ),
  }
  // What you came for first (P2-13): jail when you're in it, the hospital when you're hurt, the police when heat is
  // red; otherwise Bank, the card used most. The rest keep their order.
  const urgent = [me.jailed && 'jail', hurt && 'hospital', hot && 'police'].filter((k): k is string => !!k)
  const order = [...urgent, ...['bank', 'refills', 'upgrades', 'boost', 'hoodlums', 'police', 'hospital'].filter(k => !urgent.includes(k) && cards[k])]
  const label: Record<string, string> = { bank: 'Bank', refills: 'Refills', upgrades: 'Upgrades', boost: 'Boost', hoodlums: 'Hoodlums', police: 'Police', hospital: 'Hospital', jail: 'Jail' }

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

/** Diamonds come from milestones: the next action and fight-win steps, and the whole ladder on tap. */
function Milestones() {
  const me = useMe()
  const { catalog } = useGame()
  const ladder = catalog?.milestones ?? []
  if (ladder.length === 0) return null
  const have = (m: MilestoneDef) => (m.kind === 'actions' ? me.actions_done : me.fights_won)
  const next = (kind: MilestoneDef['kind']) => ladder.filter(m => m.kind === kind && have(m) < m.n).sort((a, b) => a.n - b.n)[0]
  const line = (m: MilestoneDef | undefined, label: string) => m
    ? <span className="nowrap">{num(m.n)} {label} → 💎 {m.reward} <span className="muted">({num(have(m))}/{num(m.n)})</span></span>
    : <span className="nowrap">every {label} milestone done</span>
  return (
    <div className="row small muted milestones">
      <div className="grow stack" style={{ gap: 4 }}>
        <div>Diamonds come from milestones. Next: {line(next('actions'), 'actions')} · {line(next('wins'), 'fight wins')}</div>
        <details>
          <summary>All milestones</summary>
          <div className="grid2 milestone-ladder">
            {(['actions', 'wins'] as const).map(kind => (
              <div key={kind} className="stack" style={{ gap: 2 }}>
                <b>{kind === 'actions' ? 'Actions' : 'Fight wins'}</b>
                {ladder.filter(m => m.kind === kind).sort((a, b) => a.n - b.n).map(m => (
                  <span key={m.key} className={have(m) >= m.n ? 'done' : ''}>{have(m) >= m.n ? '✓' : '·'} {num(m.n)} → 💎 {m.reward}</span>
                ))}
              </div>
            ))}
          </div>
        </details>
      </div>
    </div>
  )
}
