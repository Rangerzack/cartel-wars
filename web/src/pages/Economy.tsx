import { useEffect, useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { useGame, useMe } from '../lib/game'
import { api } from '../lib/api'
import { commodityIcon, money, num, timeLeft } from '../lib/format'
import { useNow } from '../lib/useNow'
import { Btn, Card, Empty, Loading, Qty, Seg } from '../components/ui'
import { useLoad } from '../lib/useLoad'
import type { Commodity, Me, StreetInfo } from '../lib/types'
import { PathCard, pathBlock } from '../components/Path'
import { PerkTag } from '../components/Perk'
import { perk } from '../lib/perks'
import { afterFee, hustleQuote, priceCap, streetMood } from '../lib/market'

const labFor: Record<Commodity, 'grow_house' | 'dust_lab' | 'pill_factory'> = { herb: 'grow_house', dust: 'dust_lab', pills: 'pill_factory' }

/** 3.6 → "3h 36m", the way every other duration in the game reads. */
const hoursMins = (h: number) => { const m = Math.round(h * 60); return m % 60 ? `${Math.floor(m / 60)}h ${m % 60}m` : `${m / 60}h` }
/** "a, b and c" */
const andList = (xs: string[]) => xs.length > 1 ? `${xs.slice(0, -1).join(', ')} and ${xs[xs.length - 1]}` : xs[0] ?? ''

type Tab = 'grow' | 'hustlers' | 'market'

export default function Economy() {
  const [sp, setSp] = useSearchParams()
  const tab = (sp.get('tab') as Tab) || 'grow'
  const setTab = (t: Tab) => setSp({ tab: t })
  return (
    <div className="page">
      {/* the path decides grow houses and hustlers; the Marketplace is open to both, so its tab starts with the offers */}
      {tab !== 'market' && <PathCard />}
      <Seg value={tab} onChange={setTab} options={[{ v: 'grow', l: 'Production' }, { v: 'hustlers', l: 'Hustlers' }, { v: 'market', l: 'Marketplace' }]} />
      {tab === 'grow' && <Grow />}
      {tab === 'hustlers' && <Hustlers />}
      {tab === 'market' && <MarketTab />}
    </div>
  )
}

/** "street $52 · −13% flooded" — where street sits against base, and whether hustler dumping put it there. */
function StreetTag({ s, price }: { s?: StreetInfo; price: number }) {
  const m = streetMood(s)
  return (
    <span className="street-tag">
      street {money(price)}
      {m && m.pct !== 0 && <span className={m.pct < 0 ? 'red' : 'green'}> {m.pct > 0 ? '+' : '−'}{Math.abs(m.pct)}%</span>}
      {m?.flooded && <span className="muted"> · flooded, recovering</span>}
    </span>
  )
}

function Grow() {
  const me = useMe()
  const { catalog, run, ask, meAt } = useGame()
  const now = useNow(10_000)
  // what a house holds right now: the server's count when `me` arrived, carried forward at the house's rate (the
  // server computes the same thing from started_at when you collect), so the number and Collect don't sit still
  // between polls
  const producedNow = (g: Me['grow_houses'][number]) => (g.running ? Math.min(g.cap, g.produced + Math.floor(Math.max(0, now - meAt) / 3_600_000 * g.rate)) : g.produced)
  if (!catalog) return <Empty><span className="spin" /></Empty>
  const have = new Set(me.grow_houses.map(g => g.commodity))
  const extraDia = catalog.config.extra_grow_diamonds ?? 20
  const blocked = pathBlock(me, 'producer')
  const lvlCap = me.path ? null : (catalog.config.path_grow_level ?? 5)
  const expandCost = (me.storage_base ?? me.storage_cap) * 20
  const nameOf = (c: Commodity) => catalog.commodities.find(x => x.code === c)?.name ?? c
  const ready = me.grow_houses.filter(g => producedNow(g) > 0)
  // every house with something ready, one after another, and one toast for the lot; a full storage ends the round
  const collectAll = () => run(async () => {
    const got: string[] = []
    let stop = ''
    for (const g of ready) {
      try {
        const r = await api.growCollect(g.id)
        if (r.collected > 0) got.push(`${num(r.collected)} ${nameOf(g.commodity)}`)
        if (r.left > 0) { stop = 'storage is full'; break }
      } catch (e) {
        if (!got.length) throw e
        stop = (e as Error).message.toLowerCase()
        break
      }
    }
    return { got, stop }
  }, { ok: r => `Collected ${andList(r.got)}${r.stop ? ` — ${r.stop}` : ''}` })
  return (
    <>
      {blocked && <div className="notice blue">{blocked} You can still collect what's already grown.</div>}
      <Card title="Storage" right={<small>{num(me.storage_used)} / {num(me.storage_cap)} units</small>}>
        {perk(me, 'warehouse') > 0 && <div className="row"><PerkTag code="warehouse" /></div>}
        {catalog.commodities.map(c => (
          <div key={c.code} className="row">
            <span className="ico">{commodityIcon[c.code]}</span>
            <div className="grow"><div className="t">{c.name}</div><div className="s"><StreetTag s={me.street?.[c.code]} price={me.prices[c.code]} /></div></div>
            <b className="tabular">{num(me.storage[c.code] ?? 0)}</b>
          </div>
        ))}
        <div className="row">
          <div className="grow s">Expand storage by 250 units</div>
          <Btn className="sm gold" disabled={me.cash < expandCost} onClick={async () => {
            // a new player's first expansion is all the cash they start with: ask before it goes
            if (expandCost > me.cash / 2 && !await ask(`That's ${money(expandCost)} of your ${money(me.cash)} on hand, for 250 more units of storage.`, { title: 'Expand storage?', yes: `Expand · ${money(expandCost)}`, tone: 'gold' })) return
            return run(api.storageUpgrade, { ok: () => 'Storage expanded by 250 units' })
          }}>Expand · {money(expandCost)}</Btn>
        </div>
        {me.cash < expandCost && <div className="row"><div className="why grow">Expanding costs {money(expandCost)} on hand — you have {money(me.cash)}.</div></div>}
      </Card>

      <div className="h2row">
        <h2>Grow Houses</h2>
        {ready.length >= 2 && <Btn className="sm doit" onClick={collectAll}>Collect All · {ready.length}</Btn>}
      </div>
      {me.grow_houses.map(g => {
        const c = catalog.commodities.find(x => x.code === g.commodity)!
        const produced = producedNow(g)
        const full = produced >= g.cap
        const capped = lvlCap != null && g.level >= lvlCap
        return (
          <Card key={g.id} title={<>{commodityIcon[g.commodity]} {c.name} · Lv {g.level}</>} right={<small>{g.running ? (full ? 'FULL' : 'running') : 'stopped'}</small>}>
            <div className="bd stack">
              <div className="spread">
                <div><b className="tabular" style={{ fontSize: 20 }}>{num(produced)}</b> <span className="muted">/ {num(g.cap)} ready</span></div>
                <div className="small muted">{num(g.rate)} units / hour</div>
              </div>
              {(perk(me, labFor[g.commodity]) > 0 || perk(me, 'utility') > 0) && <div className="hstack"><PerkTag code={labFor[g.commodity]} /><PerkTag code="utility" /></div>}
              <div className="bar"><div className="track"><div className="fill" style={{ width: (produced / Math.max(1, g.cap)) * 100 + '%', background: 'linear-gradient(#86efac, #22a34a)' }} /></div></div>
              {/* the everyday pair on top; stopping and abandoning are small and apart, so Abandon never sits beside Upgrade */}
              <div className="hstack" style={{ flexWrap: 'nowrap' }}>
                <Btn className="doit flex1" disabled={produced === 0} onClick={() => run(() => api.growCollect(g.id), { ok: r => `Collected ${num(r.collected)} ${c.name}${r.left ? ` (${num(r.left)} left — storage full)` : ''}` })}>Collect</Btn>
                <Btn className="gold" disabled={!!blocked || capped || me.cash < g.upgrade_cost} onClick={() => run(() => api.growUpgrade(g.id), { ok: r => `Upgraded to level ${r.level}` })}>Upgrade {money(g.upgrade_cost)}</Btn>
              </div>
              <div className="hstack">
                <Btn className="sm ghost" disabled={!g.running && !!blocked} onClick={() => run(() => api.growToggle(g.id), { ok: r => (r.running ? 'Production started' : 'Production stopped') })}>{g.running ? 'Stop' : 'Start'}</Btn>
                <span className="push-right"><Btn className="sm ghost red" onClick={async () => { if (await ask(`Its level and anything it has produced are gone for good.`, { title: `Abandon your ${c.name} grow house?`, yes: 'Abandon', tone: 'red' })) return run(() => api.growAbandon(g.id), { ok: () => 'Abandoned' }) }}>Abandon</Btn></span>
              </div>
              {capped && !blocked && <div className="why">Level {lvlCap} is as far as you go without a path — pick Producer above to keep upgrading.</div>}
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
              {!blocked && me.cash >= c.grow_price && me.grow_houses.length > 0 && me.diamonds < extraDia && <div className="why">Need 💎 {extraDia - me.diamonds} more diamonds · <Link to="/store">Diamonds ›</Link></div>}
            </div>
            <Btn className="sm gold" disabled={!!blocked || me.cash < c.grow_price || (me.grow_houses.length > 0 && me.diamonds < extraDia)} onClick={() => run(() => api.growBuild(c.code), { ok: () => `${c.name} grow house is up and running` })}>Build · {money(c.grow_price)}</Btn>
          </div>
        ))}
        {have.size === catalog.commodities.length && <Empty>You run every kind of grow house. Upgrade them.</Empty>}
      </Card>
      <div className="small muted">Grow houses produce while running, up to their cap. Collect into storage, then sell through Hustlers, the Marketplace or into buy orders — or burn it on refills.</div>
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
  // Strip Club: each hustler carries more · Night Club: trips come back sooner · Dispensary: sells over street
  const strip = perk(me, 'strip_club'), night = perk(me, 'night_club'), disp = perk(me, 'dispensary')
  const q = hustleQuote(me, catalog, com, n)
  const tripH = catalog.config.hustler_hours * (1 - night)
  const back = me.hustlers.filter(h => h.back)
  const due = back.reduce((s, h) => s + h.cash_due, 0)
  const blocked = pathBlock(me, 'trader')
  const cutPct = catalog.config.trader_cut_pct ?? 10, markupPct = catalog.config.trader_markup_pct ?? 10
  const have = me.storage[com] ?? 0
  return (
    <>
      {blocked && <div className="notice blue">{blocked} Trips already out still come back.</div>}
      {/* a producer can't hire: just the notice and the trips still out, not a form of disabled controls */}
      {!blocked && <Card title="Hire Hustlers" right={<small>{q.trader ? `no fee · they keep ${cutPct}%` : `${money(catalog.config.hustler_price)} each`} · {hoursMins(tripH)} trips</small>}>
        <div className="bd stack">
          {q.trader
            ? <div className="notice gold small">🚚 Trader terms: no hire fee — your hustlers keep {cutPct}% of the take — and you sell {markupPct}% over street.</div>
            : !me.path && <div className="small muted">Traders hire with no fee (the hustlers keep {cutPct}%) and sell {markupPct}% over street.</div>}
          {(me.free_hustlers ?? 0) > 0 && <div className="notice gold">🎁 {num(me.free_hustlers)} free hustler{me.free_hustlers === 1 ? '' : 's'} from the Daily Drop — {q.trader ? 'they don\'t take a cut' : 'no hire fee for them'}.</div>}
          {(strip > 0 || night > 0 || disp > 0) && <div className="hstack"><PerkTag code="strip_club" /><PerkTag code="night_club" /><PerkTag code="dispensary" /></div>}
          <Seg value={com} onChange={setCom} options={catalog.commodities.map(x => ({ v: x.code, l: `${commodityIcon[x.code]} ${x.name}` }))} />
          <div className="small"><StreetTag s={me.street?.[com]} price={me.prices[com]} /></div>
          <div className="spread">
            <Qty value={n} onChange={setN} min={1} max={100} />
            <div className="small muted center">carries {num(Math.floor(c.hustler_units * (1 + strip)))} {c.name} each</div>
          </div>
          <div className="small">
            Takes <b>{num(q.units)} {c.name}</b> from storage (you have {num(have)}){q.cost > 0 ? <>, costs <b>{money(q.cost)}</b></> : null}{q.comped > 0 ? <> ({q.comped} free)</> : null}, brings back about <b className="gold">{money(q.due)}</b>
            {q.trader && q.cut > 0 ? <> after their {money(q.cut)} cut</> : null}.
          </div>
          <div className="small muted">
            Selling pushes the street price down: this batch goes at about {money(q.each)} a unit{q.trader || disp > 0 ? ' before your markup' : ''} and leaves street at {money(q.after)}. The push fades by half every {catalog.config.price_recover_hours ?? 4} hours.
          </div>
          {have < q.units && <div className="why">You need {num(q.units)} {c.name} in storage — you have {num(have)}. Grow it, buy it on the Marketplace or post a buy order.</div>}
          {have >= q.units && me.cash < q.cost && <div className="why">Hiring costs {money(q.cost)} — you have {money(me.cash)}.</div>}
          <Btn className="doit block" disabled={have < q.units || me.cash < q.cost} onClick={() => run(() => api.hireHustlers(com, n), { ok: r => `${n} hustler${n > 1 ? 's' : ''} out the door with ${num(r.units)} units${r.free ? ` (${r.free} free)` : ''}` })}>Send Them Out</Btn>
        </div>
      </Card>}
      <Card title="On the Street" right={back.length > 0 && <Btn className="sm doit" onClick={() => run(api.collectHustlers, { ok: r => `Collected ${money(r.cash)}` })}>Collect {money(due)}</Btn>}>
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

type Draft = { com: Commodity; n: number; price: number | null }
type MTab = 'browse' | 'sell' | 'order' | 'mine'
const MTABS: MTab[] = ['browse', 'sell', 'order', 'mine']

function MarketTab() {
  const me = useMe()
  const { catalog, run } = useGame()
  const now = useNow()
  // Browse first, so what's for sale is on the first screen; the forms sit under their own tabs (?mtab=, Browse when absent)
  const [sp, setSp] = useSearchParams()
  const mtab = MTABS.find(t => t === sp.get('mtab')) ?? 'browse'
  const [filter, setFilter] = useState<Commodity | 'all'>('all')
  const [sell, setSell] = useState<Draft>({ com: 'herb', n: 25, price: null })
  const [want, setWant] = useState<Draft>({ com: 'herb', n: 500, price: null })
  const [buyQty, setBuyQty] = useState<Record<string, number>>({})
  const [fillQty, setFillQty] = useState<Record<string, number>>({})

  // the old rows stay up, dimmed, while a filter change loads; a failed load gets a Retry
  const { data: market, error: marketError, reload: load, stale } = useLoad(() => api.market(filter === 'all' ? undefined : filter), filter, { keep: true })
  // trades come and go while the page is open: ask again every 30 s so a row isn't gone by the time it's tapped
  useEffect(() => {
    const t = setInterval(() => { if (document.visibilityState === 'visible') load() }, 30_000)
    return () => clearInterval(t)
  }, [load])

  if (!catalog) return <Empty><span className="spin" /></Empty>
  const feePct = catalog.config.market_fee_pct ?? 5
  const capPct = catalog.config.listing_max_pct ?? 150
  const nameOf = (c: Commodity) => catalog.commodities.find(x => x.code === c)?.name ?? c

  // selling
  const street = me.prices[sell.com]
  const sellPrice = sell.price ?? street
  const sellCap = priceCap(catalog, street)
  const minL = catalog.config.listing_min, maxL = me.listing_max ?? catalog.config.listing_max
  const inStorage = me.storage[sell.com] ?? 0
  // say why before they tap, not after
  const sellWhyNot =
    inStorage < minL ? `You need at least ${num(minL)} ${nameOf(sell.com)} in storage to list (you have ${num(inStorage)}).`
    : sell.n < minL || sell.n > maxL ? `List between ${num(minL)} and ${num(maxL)} units.`
    : sell.n > inStorage ? `You only have ${num(inStorage)} ${nameOf(sell.com)}.`
    : me.transport_capacity < sell.n ? (me.transport_capacity === 0 ? 'You need a vehicle to haul product — buy one in the Transport shop.' : `Your best vehicle carries ${num(me.transport_capacity)} — list fewer units or buy a bigger ride.`)
    : sellPrice < 1 ? 'Set a price.'
    : sellPrice > sellCap ? `Listings can go up to ${capPct}% of street — ${money(sellCap)} a unit right now.`
    : null

  // buying to order
  const wStreet = me.prices[want.com]
  const wantPrice = want.price ?? Math.round(wStreet * 0.9)
  const wantCap = priceCap(catalog, wStreet)
  const orderMax = catalog.config.order_max ?? 10000
  const openMax = catalog.config.orders_open_max ?? 5
  const myOrders = me.orders ?? []
  const held = want.n * wantPrice
  const wantWhyNot =
    want.n < minL || want.n > orderMax ? `Order between ${num(minL)} and ${num(orderMax)} units.`
    : wantPrice < 1 ? 'Set a price.'
    : wantPrice > wantCap ? `Offers can go up to ${capPct}% of street — ${money(wantCap)} a unit right now.`
    : myOrders.length >= openMax ? `You can have ${openMax} open buy orders at a time.`
    : me.cash < held ? `This order holds ${money(held)} of your cash on hand — you have ${money(me.cash)}.`
    : null

  const listings = market?.listings ?? []
  const orders = market?.orders ?? []
  const mineCount = me.listings.length + myOrders.length
  const comSeg = catalog.commodities.map(x => ({ v: x.code, l: `${commodityIcon[x.code]} ${x.name}` }))
  return (
    <>
      <Seg value={mtab} onChange={t => setSp({ tab: 'market', mtab: t })}
        options={[{ v: 'browse', l: 'Browse' }, { v: 'sell', l: 'Sell' }, { v: 'order', l: 'Buy order' }, { v: 'mine', l: `Mine${mineCount ? ` (${mineCount})` : ''}` }]} />

      {mtab === 'browse' && <>
        {/* one filter for the whole tab, in the first card's header so the offers start on the first screen */}
        <Card title="Prices" right={
          <select className="input sm" style={{ width: 'auto' }} aria-label="Show" value={filter} onChange={e => setFilter(e.target.value as Commodity | 'all')}>
            <option value="all">All products</option>
            {catalog.commodities.map(c => <option key={c.code} value={c.code}>{c.name}</option>)}
          </select>
        }>
          {catalog.commodities.filter(c => filter === 'all' || c.code === filter).map(c => {
            const st = market?.stats?.[c.code]
            return (
              <div key={c.code} className="row">
                <span className="ico">{commodityIcon[c.code]}</span>
                <div className="grow">
                  <div className="t">{c.name}</div>
                  <div className="s"><StreetTag s={market?.street?.[c.code] ?? me.street?.[c.code]} price={market?.prices?.[c.code] ?? me.prices[c.code]} /></div>
                </div>
                <div className="small price-stats">
                  {st?.last != null ? <>last <b className="tabular">{money(st.last)}</b></> : <span className="muted">no trades yet</span>}
                  <div className="muted">{num(st?.units_24h ?? 0)} in 24h{st?.avg_24h != null ? ` · avg ${money(st.avg_24h)}` : ''}</div>
                </div>
              </div>
            )
          })}
        </Card>

        <Card title="Wanted" right={<small>best offer first</small>} className={stale ? 'stale' : ''}>
          {!market && <Loading error={marketError} onRetry={load} />}
          {market && orders.length === 0 && <Empty>No buy orders right now.</Empty>}
          {orders.map(o => {
            const mine = me.storage[o.commodity] ?? 0
            const fit = Math.max(0, Math.min(o.qty, mine, me.transport_capacity))
            const q = Math.min(fillQty[o.id] ?? (fit || Math.min(o.qty, 25)), o.qty)
            const why = mine < q ? `you have ${num(mine)}` : me.transport_capacity < q ? `your vehicle carries ${num(me.transport_capacity)}` : null
            return (
              <div key={o.id} className="row order-row">
                <span style={{ fontSize: 20 }}>{commodityIcon[o.commodity]}</span>
                <div className="grow">
                  <div className="t">{num(o.qty)} {nameOf(o.commodity)} wanted @ {money(o.unit_price)}</div>
                  <div className="s">{o.mine ? 'your order' : `by ${o.buyer}`} · {timeLeft(o.expires_at, now)} left{!o.mine && why ? <span className="red"> · {why}</span> : null}</div>
                </div>
                {!o.mine && (
                  <div className="hstack" style={{ flexWrap: 'nowrap' }}>
                    <input className="input sm" inputMode="numeric" aria-label={`Units of ${nameOf(o.commodity)} to sell`} value={q} onChange={e => setFillQty({ ...fillQty, [o.id]: Number(e.target.value) || 0 })} />
                    <Btn className="sm gold" disabled={q <= 0 || !!why} onClick={async () => { await run(() => api.fillOrder(o.id, q), { ok: r => `Sold ${num(r.units)} for ${money(r.cash)} (after ${money(r.fee)} fee)` }); load() }}>Sell {money(afterFee(catalog, q * o.unit_price))}</Btn>
                  </div>
                )}
              </div>
            )
          })}
        </Card>

        <Card title="For Sale" right={<small>cheapest first</small>} className={stale ? 'stale' : ''}>
          {!market && <Loading error={marketError} onRetry={load} />}
          {market && listings.length === 0 && <Empty>Nothing for sale right now.</Empty>}
          {listings.map(l => {
            const q = Math.max(0, Math.min(Math.floor(buyQty[l.id] ?? l.qty), l.qty))
            const room = Math.max(0, me.storage_cap - me.storage_used)
            const why = q <= 0 ? 'enter how many' : me.cash < q * l.unit_price ? `that's ${money(q * l.unit_price)} — you have ${money(me.cash)} on hand`
              : room < q ? `only ${num(room)} units of storage room` : null
            return (
              <div key={l.id} className="row">
                <span style={{ fontSize: 20 }}>{commodityIcon[l.commodity]}</span>
                <div className="grow">
                  <div className="t">{num(l.qty)} {nameOf(l.commodity)} @ {money(l.unit_price)}</div>
                  <div className="s">{l.mine ? 'your listing' : `by ${l.seller}`} · {timeLeft(l.expires_at, now)} left{!l.mine && why ? <span className="red"> · {why}</span> : null}</div>
                </div>
                {!l.mine && (
                  <div className="hstack" style={{ flexWrap: 'nowrap' }}>
                    <input className="input sm" inputMode="numeric" aria-label={`Units of ${nameOf(l.commodity)} to buy`} value={q} onChange={e => setBuyQty({ ...buyQty, [l.id]: Number(e.target.value) || 0 })} />
                    <Btn className="sm gold" disabled={!!why} onClick={async () => { await run(() => api.buyListing(l.id, q), { ok: r => `Bought ${num(r.units)} for ${money(r.cost)}` }); load() }}>Buy {money(q * l.unit_price)}</Btn>
                  </div>
                )}
              </div>
            )
          })}
        </Card>
        <div className="small muted">Sellers pay a {feePct}% fee on every sale. Listings and offers can go up to {capPct}% of street.</div>
      </>}

      {mtab === 'sell' && (
        <Card title="Sell" right={<small>truck capacity {num(me.transport_capacity)}</small>}>
          <div className="bd stack">
            {perk(me, 'trucking') > 0 && <PerkTag code="trucking" />}
            <Seg value={sell.com} onChange={v => setSell({ com: v, n: sell.n, price: null })} options={comSeg} />
            <div className="grid2">
              <label className="f">Units ({num(minL)}–{num(maxL)})<input className="input" inputMode="numeric" value={sell.n} onChange={e => setSell({ ...sell, n: Number(e.target.value) || 0 })} /></label>
              <label className="f">Price / unit (up to {money(sellCap)})<input className="input" inputMode="numeric" value={sellPrice} onChange={e => setSell({ ...sell, price: Number(e.target.value) || 0 })} /></label>
            </div>
            <div className="small muted">In storage: {num(inStorage)}. Street is {money(street)}; you can ask up to {capPct}% of it. Listings need a vehicle that can carry the batch and expire in 48h. Sells for <b className="gold">{money(sell.n * sellPrice)}</b> — you keep {money(afterFee(catalog, sell.n * sellPrice))} after the {feePct}% fee.</div>
            {sellWhyNot && <div className="why">{sellWhyNot}</div>}
            <Btn className="doit block" disabled={!!sellWhyNot} onClick={async () => { const r = await run(() => api.listProduct(sell.com, sell.n, sellPrice), { ok: () => 'Listed on the marketplace' }); if (r) load() }}>List It</Btn>
          </div>
        </Card>
      )}

      {mtab === 'order' && (
        <Card title="Buy Order" right={<small>{myOrders.length}/{openMax} open</small>}>
          <div className="bd stack">
            <div className="small muted">Post what you want and at what price; sellers fill it while you're away. The cash is held off your hand until it fills, and comes back if you cancel or it runs out after 48h. Product lands in storage even when it's full.</div>
            <Seg value={want.com} onChange={v => setWant({ com: v, n: want.n, price: null })} options={comSeg} />
            <div className="grid2">
              <label className="f">Units ({num(minL)}–{num(orderMax)})<input className="input" inputMode="numeric" value={want.n} onChange={e => setWant({ ...want, n: Number(e.target.value) || 0 })} /></label>
              <label className="f">Offer / unit (street {money(wStreet)})<input className="input" inputMode="numeric" value={wantPrice} onChange={e => setWant({ ...want, price: Number(e.target.value) || 0 })} /></label>
            </div>
            <div className="small">Holds <b className="gold">{money(held)}</b> of your cash on hand.</div>
            {wantWhyNot && <div className="why">{wantWhyNot}</div>}
            <Btn className="doit block" disabled={!!wantWhyNot} onClick={async () => { const r = await run(() => api.postOrder(want.com, want.n, wantPrice), { ok: () => `Posted: ${num(want.n)} ${nameOf(want.com)} wanted at ${money(wantPrice)}` }); if (r) load() }}>Post Order</Btn>
          </div>
        </Card>
      )}

      {mtab === 'mine' && (
        <Card title="Mine">
          {mineCount === 0 && <Empty>Nothing listed and no buy orders open. List product under Sell, or post a Buy order.</Empty>}
          {me.listings.map(l => (
            <div key={l.id} className="row">
              <span>{commodityIcon[l.commodity]}</span>
              <div className="grow"><div className="t">Selling {num(l.qty)} {nameOf(l.commodity)} @ {money(l.unit_price)}</div><div className="s">{l.held ? 'came back off the market — waiting for storage room' : `expires in ${timeLeft(l.expires_at, now)}`}</div></div>
              <Btn className={`sm ${l.held ? 'gold' : 'ghost'}`} onClick={async () => { await run(() => api.cancelListing(l.id), { ok: r => r.held ? `${num(r.returned)} back in storage, ${num(r.held)} still waiting for room` : `${num(r.returned)} units back in storage` }); load() }}>{l.held ? 'Reclaim' : 'Cancel'}</Btn>
            </div>
          ))}
          {myOrders.map(o => (
            <div key={o.id} className="row my-order">
              <span>{commodityIcon[o.commodity]}</span>
              <div className="grow">
                <div className="t">Wanted {num(o.qty)} {nameOf(o.commodity)} @ {money(o.unit_price)}</div>
                <div className="s">{o.filled > 0 ? `${num(o.filled)} in so far · ` : ''}{money(o.qty * o.unit_price)} held · expires in {timeLeft(o.expires_at, now)}</div>
              </div>
              <Btn className="sm ghost" onClick={async () => { await run(() => api.cancelOrder(o.id), { ok: r => `Order cancelled — ${money(r.returned)} back on hand` }); load() }}>Cancel</Btn>
            </div>
          ))}
        </Card>
      )}
    </>
  )
}
