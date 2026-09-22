import { useCallback, useEffect, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { useGame, useMe } from '../lib/game'
import { api } from '../lib/api'
import { commodityIcon, money, num, timeLeft } from '../lib/format'
import { useNow } from '../lib/useNow'
import { Btn, Card, Empty, Qty, Seg } from '../components/ui'
import type { Commodity, Market } from '../lib/types'

type Tab = 'grow' | 'hustlers' | 'market'

export default function Economy() {
  const [sp, setSp] = useSearchParams()
  const tab = (sp.get('tab') as Tab) || 'grow'
  const setTab = (t: Tab) => setSp({ tab: t })
  return (
    <div className="page">
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
  return (
    <>
      <Card title="Storage" right={<small>{num(me.storage_used)} / {num(me.storage_cap)} units</small>}>
        {catalog.commodities.map(c => (
          <div key={c.code} className="row">
            <span style={{ fontSize: 22, width: 30, textAlign: 'center' }}>{commodityIcon[c.code]}</span>
            <div className="grow"><div className="t">{c.name}</div><div className="s">street {money(me.prices[c.code])}/unit</div></div>
            <b className="tabular">{num(me.storage[c.code] ?? 0)}</b>
          </div>
        ))}
        <div className="row">
          <div className="grow s">Expand storage by 250 units</div>
          <Btn className="sm" onClick={() => run(api.storageUpgrade, { ok: r => `Storage is now ${num(r.storage_cap)} units` })}>{money(me.storage_cap * 20)}</Btn>
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
              <div className="bar"><div className="track"><div className="fill" style={{ width: (g.produced / g.cap) * 100 + '%', background: 'linear-gradient(#86efac, #22a34a)' }} /></div></div>
              <div className="hstack">
                <Btn className="doit" disabled={g.produced === 0} onClick={() => run(() => api.growCollect(g.id), { ok: r => `Collected ${num(r.collected)} ${c.name}${r.left ? ` (${num(r.left)} left — storage full)` : ''}` })}>Collect</Btn>
                <Btn className="sm" onClick={() => run(() => api.growToggle(g.id), { ok: r => (r.running ? 'Production started' : 'Production stopped') })}>{g.running ? 'Stop' : 'Start'}</Btn>
                <Btn className="sm gold" disabled={me.cash < g.upgrade_cost} onClick={() => run(() => api.growUpgrade(g.id), { ok: r => `Upgraded to level ${r.level}` })}>Upgrade {money(g.upgrade_cost)}</Btn>
                <Btn className="sm ghost" onClick={() => { if (confirm(`Abandon your ${c.name} grow house?`)) return run(() => api.growAbandon(g.id), { ok: () => 'Abandoned' }) }}>Abandon</Btn>
              </div>
            </div>
          </Card>
        )
      })}
      <Card title="Build">
        {catalog.commodities.filter(c => !have.has(c.code)).map(c => (
          <div key={c.code} className="row">
            <span style={{ fontSize: 22, width: 30, textAlign: 'center' }}>{commodityIcon[c.code]}</span>
            <div className="grow">
              <div className="t">{c.name} grow house</div>
              <div className="s">{c.grow_rate} units/hr · holds {c.grow_cap} · {money(c.grow_price)}{me.grow_houses.length > 0 ? ` + 💎 ${extraDia}` : ''}</div>
            </div>
            <Btn className="sm" disabled={me.cash < c.grow_price} onClick={() => run(() => api.growBuild(c.code), { ok: () => `${c.name} grow house is up and running` })}>Build</Btn>
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
  const units = c.hustler_units * n
  const back = me.hustlers.filter(h => h.back)
  const due = back.reduce((s, h) => s + h.cash_due, 0)
  return (
    <>
      <Card title="Hire Hustlers" right={<small>{money(price)} each · {catalog.config.hustler_hours}h trips</small>}>
        <div className="bd stack">
          <Seg value={com} onChange={setCom} options={catalog.commodities.map(x => ({ v: x.code, l: `${commodityIcon[x.code]} ${x.name}` }))} />
          <div className="spread">
            <Qty value={n} onChange={setN} min={1} max={100} />
            <div className="small muted center">carries {c.hustler_units} {c.name} each</div>
          </div>
          <div className="small">
            Takes <b>{num(units)} {c.name}</b> from storage (you have {num(me.storage[com] ?? 0)}), costs <b>{money(price * n)}</b>, returns about <b className="gold">{money(units * me.prices[com])}</b> at today's street price.
          </div>
          <Btn className="doit block" disabled={(me.storage[com] ?? 0) < units || me.cash < price * n} onClick={() => run(() => api.hireHustlers(com, n), { ok: r => `${n} hustler${n > 1 ? 's' : ''} out the door with ${num(r.units)} units` })}>Send Them Out</Btn>
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
  const minL = catalog.config.listing_min, maxL = catalog.config.listing_max
  return (
    <>
      <Card title="Sell" right={<small>truck capacity {num(me.transport_capacity)}</small>}>
        <div className="bd stack">
          <Seg value={sell.com} onChange={v => setSell({ com: v, n: sell.n, price: null })} options={catalog.commodities.map(x => ({ v: x.code, l: `${commodityIcon[x.code]} ${x.name}` }))} />
          <div className="grid2">
            <label className="f">Units ({minL}–{maxL})<input className="input" inputMode="numeric" value={sell.n} onChange={e => setSell({ ...sell, n: Number(e.target.value) || 0 })} /></label>
            <label className="f">Price / unit (street {money(street)})<input className="input" inputMode="numeric" value={sellPrice} onChange={e => setSell({ ...sell, price: Number(e.target.value) || 0 })} /></label>
          </div>
          <div className="small muted">In storage: {num(me.storage[sell.com] ?? 0)}. Listings need a vehicle that can carry the batch and expire in 48h. Total: <b className="gold">{money(sell.n * sellPrice)}</b></div>
          <Btn className="doit block" onClick={async () => { const r = await run(() => api.listProduct(sell.com, sell.n, sellPrice), { ok: () => 'Listed on the marketplace' }); if (r) load() }}>List It</Btn>
        </div>
      </Card>

      {me.listings.length > 0 && (
        <Card title="My Listings">
          {me.listings.map(l => (
            <div key={l.id} className="row">
              <span>{commodityIcon[l.commodity]}</span>
              <div className="grow"><div className="t">{num(l.qty)} @ {money(l.unit_price)}</div><div className="s">expires in {timeLeft(l.expires_at, now)}</div></div>
              <Btn className="sm ghost" onClick={async () => { await run(() => api.cancelListing(l.id), { ok: r => `${num(r.returned)} units back in storage` }); load() }}>Cancel</Btn>
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
