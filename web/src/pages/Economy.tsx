import { useCallback, useEffect, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { useGame, useMe } from '../lib/game'
import { api } from '../lib/api'
import { commodityIcon, money, num, timeLeft } from '../lib/format'
import { useNow } from '../lib/useNow'
import { Btn, Card, Empty, Qty, Seg } from '../components/ui'
import type { Commodity, Market } from '../lib/types'
import { PathCard, pathBlock } from '../components/Path'
import { PerkTag } from '../components/Perk'
import { perk } from '../lib/perks'

const labFor: Record<Commodity, 'grow_house' | 'dust_lab' | 'pill_factory'> = { herb: 'grow_house', dust: 'dust_lab', pills: 'pill_factory' }

type Tab = 'grow' | 'hustlers' | 'market'

export default function Economy() {
  const [sp, setSp] = useSearchParams()
  const tab = (sp.get('tab') as Tab) || 'grow'
  const setTab = (t: Tab) => setSp({ tab: t })
  return (
    <div className="page">
      <PathCard />
      <Seg value={tab} onChange={setTab} options={[{ v: 'grow', l: 'Production' }, { v: 'hustlers', l: 'Hustlers' }, { v: 'market', l: 'Marketplace' }]} />
      {tab === 'grow' && <Grow />}
      {tab === 'hustlers' && <Hustlers />}
      {tab === 'market' && <MarketTab />}
    </div>
  )
}

function Grow() {
  const me = useMe()
  const { catalog, run } = useGame()
  if (!catalog) return <Empty><span className="spin" /></Empty>
  const have = new Set(me.grow_houses.map(g => g.commodity))
  const extraDia = catalog.config.extra_grow_diamonds ?? 20
  const blocked = pathBlock(me, 'producer')
  return (
    <>
      {blocked && <div className="notice blue">{blocked} You can still collect what's already grown.</div>}
      <Card title="Storage" right={<small>{num(me.storage_used)} / {num(me.storage_cap)} units</small>}>
        {perk(me, 'warehouse') > 0 && <div className="row"><PerkTag code="warehouse" /></div>}
        {catalog.commodities.map(c => (
          <div key={c.code} className="row">
            <span className="ico">{commodityIcon[c.code]}</span>
            <div className="grow"><div className="t">{c.name}</div><div className="s">street {money(me.prices[c.code])}/unit</div></div>
            <b className="tabular">{num(me.storage[c.code] ?? 0)}</b>
          </div>
        ))}
        <div className="row">
          <div className="grow s">Expand storage by 250 units</div>
          <Btn className="sm" onClick={() => run(api.storageUpgrade, { ok: () => 'Storage expanded by 250 units' })}>{money((me.storage_base ?? me.storage_cap) * 20)}</Btn>
        </div>
      </Card>

      <h2>Grow Houses</h2>
      {me.grow_houses.map(g => {
        const c = catalog.commodities.find(x => x.code === g.commodity)!
        const full = g.produced >= g.cap
        return (
          <Card key={g.id} title={<>{commodityIcon[g.commodity]} {c.name} · Lv {g.level}</>} right={<small>{g.running ? (full ? 'FULL' : 'running') : 'stopped'}</small>}>
            <div className="bd stack">
              <div className="spread">
                <div><b className="tabular" style={{ fontSize: 20 }}>{num(g.produced)}</b> <span className="muted">/ {num(g.cap)} ready</span></div>
                <div className="small muted">{num(g.rate)} units / hour</div>
              </div>
              {(perk(me, labFor[g.commodity]) > 0 || perk(me, 'utility') > 0) && <div className="hstack"><PerkTag code={labFor[g.commodity]} /><PerkTag code="utility" /></div>}
              <div className="bar"><div className="track"><div className="fill" style={{ width: (g.produced / g.cap) * 100 + '%', background: 'linear-gradient(#86efac, #22a34a)' }} /></div></div>
              <div className="hstack">
                <Btn className="doit" disabled={g.produced === 0} onClick={() => run(() => api.growCollect(g.id), { ok: r => `Collected ${num(r.collected)} ${c.name}${r.left ? ` (${num(r.left)} left — storage full)` : ''}` })}>Collect</Btn>
                <Btn className="sm" disabled={!g.running && !!blocked} onClick={() => run(() => api.growToggle(g.id), { ok: r => (r.running ? 'Production started' : 'Production stopped') })}>{g.running ? 'Stop' : 'Start'}</Btn>
                <Btn className="sm gold" disabled={!!blocked || me.cash < g.upgrade_cost} onClick={() => run(() => api.growUpgrade(g.id), { ok: r => `Upgraded to level ${r.level}` })}>Upgrade {money(g.upgrade_cost)}</Btn>
                <Btn className="sm ghost" onClick={() => { if (confirm(`Abandon your ${c.name} grow house?`)) return run(() => api.growAbandon(g.id), { ok: () => 'Abandoned' }) }}>Abandon</Btn>
              </div>
            </div>
          </Card>
        )
      })}
      <Card title="Build">
        {catalog.commodities.filter(c => !have.has(c.code)).map(c => (
          <div key={c.code} className="row">
            <span className="ico">{commodityIcon[c.code]}</span>
            <div className="grow">
              <div className="t">{c.name} grow house</div>
              <div className="s">{num(c.grow_rate * (1 + perk(me, labFor[c.code]) + perk(me, 'utility')))} units/hr · holds {num(Math.floor(c.grow_cap * (1 + perk(me, labFor[c.code]) + perk(me, 'utility'))))} · {money(c.grow_price)}{me.grow_houses.length > 0 ? ` + 💎 ${extraDia}` : ''}</div>
              {!blocked && me.cash < c.grow_price && <div className="why">Need {money(c.grow_price - me.cash)} more cash</div>}
              {!blocked && me.cash >= c.grow_price && me.grow_houses.length > 0 && me.diamonds < extraDia && <div className="why">Need 💎 {extraDia - me.diamonds} more diamonds</div>}
            </div>
            <Btn className="sm" disabled={!!blocked || me.cash < c.grow_price} onClick={() => run(() => api.growBuild(c.code), { ok: () => `${c.name} grow house is up and running` })}>Build</Btn>
          </div>
        ))}
        {have.size === catalog.commodities.length && <Empty>You run every kind of grow house. Upgrade them.</Empty>}
      </Card>
      <div className="small muted">Grow houses produce while running, up to their cap. Collect into storage, then sell through Hustlers or the Marketplace.</div>
    </>
  )
}

function Hustlers() {
  const me = useMe()
  const { catalog, run } = useGame()
  const now = useNow()
  const [com, setCom] = useState<Commodity>('herb')
  const [n, setN] = useState(1)
  if (!catalog) return <Empty><span className="spin" /></Empty>
  const c = catalog.commodities.find(x => x.code === com)!
  const price = catalog.config.hustler_price
  // Strip Club: each hustler carries more · Night Club: trips come back sooner · Dispensary: sells over street
  const strip = perk(me, 'strip_club'), night = perk(me, 'night_club'), disp = perk(me, 'dispensary')
  const units = Math.floor(c.hustler_units * n * (1 + strip))
  const tripH = catalog.config.hustler_hours * (1 - night)
  const back = me.hustlers.filter(h => h.back)
  const due = back.reduce((s, h) => s + h.cash_due, 0)
  const blocked = pathBlock(me, 'trader')
  // Daily Drop hustler credits waive the fee, one hustler each
  const comped = Math.min(n, me.free_hustlers ?? 0)
  const cost = price * (n - comped)
  return (
    <>
      {blocked && <div className="notice blue">{blocked} Trips already out still come back.</div>}
      <Card title="Hire Hustlers" right={<small>{money(price)} each · {Math.round(tripH * 10) / 10}h trips</small>}>
        <div className="bd stack">
          {(me.free_hustlers ?? 0) > 0 && <div className="notice gold">🎁 {num(me.free_hustlers)} free hustler{me.free_hustlers === 1 ? '' : 's'} from the Daily Drop — no hire fee for them.</div>}
          {(strip > 0 || night > 0 || disp > 0) && <div className="hstack"><PerkTag code="strip_club" /><PerkTag code="night_club" /><PerkTag code="dispensary" /></div>}
          <Seg value={com} onChange={setCom} options={catalog.commodities.map(x => ({ v: x.code, l: `${commodityIcon[x.code]} ${x.name}` }))} />
          <div className="spread">
            <Qty value={n} onChange={setN} min={1} max={100} />
            <div className="small muted center">carries {Math.round(c.hustler_units * (1 + strip) * 10) / 10} {c.name} each</div>
          </div>
          <div className="small">
            Takes <b>{num(units)} {c.name}</b> from storage (you have {num(me.storage[com] ?? 0)}), costs <b>{money(cost)}</b>{comped > 0 ? <> ({comped} free)</> : null}, returns about <b className="gold">{money(Math.floor(units * me.prices[com] * (1 + disp)))}</b> at today's street price{disp > 0 ? ' plus your Dispensary markup' : ''}.
          </div>
          {!blocked && (me.storage[com] ?? 0) < units && <div className="why">You need {num(units)} {c.name} in storage — you have {num(me.storage[com] ?? 0)}. Grow it or buy it on the Marketplace.</div>}
          {!blocked && (me.storage[com] ?? 0) >= units && me.cash < cost && <div className="why">Hiring costs {money(cost)} — you have {money(me.cash)}.</div>}
          <Btn className="doit block" disabled={!!blocked || (me.storage[com] ?? 0) < units || me.cash < cost} onClick={() => run(() => api.hireHustlers(com, n), { ok: r => `${n} hustler${n > 1 ? 's' : ''} out the door with ${num(r.units)} units${r.free ? ` (${r.free} free)` : ''}` })}>Send Them Out</Btn>
        </div>
      </Card>
      <Card title="On the Street" right={back.length > 0 && <Btn className="sm gold" onClick={() => run(api.collectHustlers, { ok: r => `Collected ${money(r.cash)}` })}>Collect {money(due)}</Btn>}>
        {me.hustlers.length === 0 && <Empty>No hustlers out. Product doesn't move itself.</Empty>}
        {me.hustlers.map(h => (
          <div key={h.id} className="row">
            <span style={{ fontSize: 20 }}>{commodityIcon[h.commodity]}</span>
            <div className="grow"><div className="t">{h.count} hustler{h.count > 1 ? 's' : ''} · {num(h.units)} units</div><div className="s">{h.back ? 'Back — cash in hand' : `Back in ${timeLeft(h.returns_at, now)}`}</div></div>
            <b className="gold tabular">{money(h.cash_due)}</b>
          </div>
        ))}
      </Card>
    </>
  )
}

function MarketTab() {
  const me = useMe()
  const { catalog, run, toast } = useGame()
  const now = useNow()
  const [market, setMarket] = useState<Market | null>(null)
  const [filter, setFilter] = useState<Commodity | 'all'>('all')
  const [sell, setSellRaw] = useState<{ com: Commodity; n: number; price: number | null }>({ com: 'herb', n: 25, price: null })
  const setSell = (v: { com: Commodity; n: number; price: number | null }) => setSellRaw(v)
  const [buyQty, setBuyQty] = useState<Record<string, number>>({})

  const load = useCallback(() => api.market(filter === 'all' ? undefined : filter).then(setMarket).catch(e => toast(e.message, 'bad')), [filter, toast])
  useEffect(() => { load() }, [load])

  if (!catalog) return <Empty><span className="spin" /></Empty>
  const street = me.prices[sell.com]
  const sellPrice = sell.price ?? street
  const minL = catalog.config.listing_min, maxL = me.listing_max ?? catalog.config.listing_max
  const inStorage = me.storage[sell.com] ?? 0
  const sellName = catalog.commodities.find(x => x.code === sell.com)?.name ?? sell.com
  // say why before they tap, not after
  const sellWhyNot =
    inStorage < minL ? `You need at least ${num(minL)} ${sellName} in storage to list (you have ${num(inStorage)}).`
    : sell.n < minL || sell.n > maxL ? `List between ${num(minL)} and ${num(maxL)} units.`
    : sell.n > inStorage ? `You only have ${num(inStorage)} ${sellName}.`
    : me.transport_capacity < sell.n ? (me.transport_capacity === 0 ? 'You need a vehicle to haul product — buy one in the Transport shop.' : `Your best vehicle carries ${num(me.transport_capacity)} — list fewer units or buy a bigger ride.`)
    : sellPrice < 1 ? 'Set a price.'
    : sellPrice > street ? `The Marketplace won't take listings above street price (${money(street)}).`
    : null
  return (
    <>
      <Card title="Sell" right={<small>truck capacity {num(me.transport_capacity)}</small>}>
        <div className="bd stack">
          {perk(me, 'trucking') > 0 && <PerkTag code="trucking" />}
          <Seg value={sell.com} onChange={v => setSell({ com: v, n: sell.n, price: null })} options={catalog.commodities.map(x => ({ v: x.code, l: `${commodityIcon[x.code]} ${x.name}` }))} />
          <div className="grid2">
            <label className="f">Units ({minL}–{maxL})<input className="input" inputMode="numeric" value={sell.n} onChange={e => setSell({ ...sell, n: Number(e.target.value) || 0 })} /></label>
            <label className="f">Price / unit (street {money(street)})<input className="input" inputMode="numeric" value={sellPrice} onChange={e => setSell({ ...sell, price: Number(e.target.value) || 0 })} /></label>
          </div>
          <div className="small muted">In storage: {num(me.storage[sell.com] ?? 0)}. Listings need a vehicle that can carry the batch and expire in 48h. Total: <b className="gold">{money(sell.n * sellPrice)}</b></div>
          {sellWhyNot && <div className="why">{sellWhyNot}</div>}
          <Btn className="doit block" disabled={!!sellWhyNot} onClick={async () => { const r = await run(() => api.listProduct(sell.com, sell.n, sellPrice), { ok: () => 'Listed on the marketplace' }); if (r) load() }}>List It</Btn>
        </div>
      </Card>

      {me.listings.length > 0 && (
        <Card title="My Listings">
          {me.listings.map(l => (
            <div key={l.id} className="row">
              <span>{commodityIcon[l.commodity]}</span>
              <div className="grow"><div className="t">{num(l.qty)} @ {money(l.unit_price)}</div><div className="s">{l.held ? 'came back off the market — waiting for storage room' : `expires in ${timeLeft(l.expires_at, now)}`}</div></div>
              <Btn className={`sm ${l.held ? 'gold' : 'ghost'}`} onClick={async () => { await run(() => api.cancelListing(l.id), { ok: r => r.held ? `${num(r.returned)} back in storage, ${num(r.held)} still waiting for room` : `${num(r.returned)} units back in storage` }); load() }}>{l.held ? 'Reclaim' : 'Cancel'}</Btn>
            </div>
          ))}
        </Card>
      )}

      <div className="spread"><h2>Marketplace</h2>
        <select className="input sm" style={{ width: 'auto' }} value={filter} onChange={e => setFilter(e.target.value as Commodity | 'all')}>
          <option value="all">All</option>
          {catalog.commodities.map(c => <option key={c.code} value={c.code}>{c.name}</option>)}
        </select>
      </div>
      <Card>
        {!market && <Empty><span className="spin" /></Empty>}
        {market && market.listings.length === 0 && <Empty>Nothing for sale right now.</Empty>}
        {market?.listings.map(l => {
          const q = Math.min(buyQty[l.id] ?? l.qty, l.qty)
          return (
            <div key={l.id} className="row">
              <span style={{ fontSize: 20 }}>{commodityIcon[l.commodity]}</span>
              <div className="grow">
                <div className="t">{num(l.qty)} {l.commodity} @ {money(l.unit_price)}</div>
                <div className="s">{l.mine ? 'your listing' : `by ${l.seller}`} · {timeLeft(l.expires_at, now)} left</div>
              </div>
              {!l.mine && (
                <div className="hstack" style={{ flexWrap: 'nowrap' }}>
                  <input className="input sm" inputMode="numeric" value={q} onChange={e => setBuyQty({ ...buyQty, [l.id]: Number(e.target.value) || 0 })} />
                  <Btn className="sm gold" disabled={me.cash < q * l.unit_price} onClick={async () => { await run(() => api.buyListing(l.id, q), { ok: r => `Bought ${num(r.units)} for ${money(r.cost)}` }); load() }}>{money(q * l.unit_price)}</Btn>
                </div>
              )}
            </div>
          )
        })}
      </Card>
    </>
  )
}
