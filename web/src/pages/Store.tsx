import { useEffect, useState } from 'react'
import { useLocation } from 'react-router-dom'
import { useGame, useMe } from '../lib/game'
import { num } from '../lib/format'
import { isNative } from '../lib/platform'
import { buyPack, getOfferings, restorePurchases, storeReady, waitForDelivery, type StoreProduct } from '../lib/store'
import { focusCard } from '../lib/scroll'
import { BackBar } from '../components/BackBar'
import { DailyDrop } from '../components/DailyDrop'
import { Btn, Card } from '../components/ui'

/**
 * The store (#15): diamond packs, then the Daily Drop. Purchases go through Apple in the iOS app only (guideline
 * 3.1.1), at StoreKit's price in the player's own currency. The web build says so first, then lists the packs dimmed,
 * with no prices or buttons. Home's Daily Drop row links to /store#drop, the full pitch with the odds above Subscribe.
 */
export default function Store() {
  const me = useMe()
  const { catalog, toast, refresh } = useGame()
  const packs = catalog?.store?.packs ?? []
  const [products, setProducts] = useState<Record<string, StoreProduct> | null>(null)
  const [delivering, setDelivering] = useState<string | null>(null)
  const ids = packs.map(p => p.id).join(' ')
  const { hash } = useLocation()
  const ready = !!catalog
  useEffect(() => {
    if (!hash || !ready) return
    const t = setTimeout(() => focusCard(hash.slice(1)), 150)
    return () => clearTimeout(t)
  }, [hash, ready])
  // In the app, once StoreKit has answered, only what the App Store actually sells (a pack whose product isn't live yet
  // would be a dead button). Until then, and on the web, every pack.
  const shown = storeReady && products ? packs.filter(p => products[p.id]) : packs
  useEffect(() => {
    if (!storeReady || !ids) return
    getOfferings(ids.split(' ')).then(setProducts).catch(e => { setProducts({}); toast((e as Error).message, 'bad') })
  }, [ids, toast])

  const buy = async (id: string, diamonds: number) => {
    const before = me.diamonds
    let r
    try { r = await buyPack(id) } catch (e) { toast((e as Error).message, 'bad'); return }
    if (r === 'cancelled') { toast('Purchase cancelled', 'info'); return }
    if (r === 'pending') { toast('Waiting for approval. Your diamonds arrive once Apple approves it.', 'info'); return }
    setDelivering(id)
    const ok = await waitForDelivery(m => m.diamonds > before)
    setDelivering(null)
    await refresh()
    toast(ok ? `+${num(diamonds)} diamonds` : "Your diamonds are on their way. They'll show up in a minute.", ok ? 'ok' : 'info')
  }
  const restore = async () => {
    try { await restorePurchases() } catch (e) { toast((e as Error).message, 'bad'); return }
    await refresh()
    toast('Purchases restored', 'ok')
  }

  return (
    <div className="page">
      <BackBar fallback="/" />
      <h2>Store</h2>
      <Card id="diamonds" title="💎 Diamonds" right={<small className="dia tabular">💎 {num(me.diamonds)}</small>}>
        {!storeReady && <div className="bd"><div className="notice blue">{isNative ? 'Purchases aren\'t available in this build.' : 'Diamonds are sold in the iPhone app.'}</div></div>}
        {shown.map(p => (
          <div key={p.id} className={`row store-pack${storeReady ? '' : ' off'}`}>
            <span className="ico">💎</span>
            <div className="grow t tabular">{num(p.diamonds)} diamonds</div>
            {storeReady && (delivering === p.id
              ? <span className="small muted nowrap"><span className="spin" /> Delivering…</span>
              : <Btn className="gold sm" disabled={!products?.[p.id] || !!delivering} onClick={() => buy(p.id, p.diamonds)}>{products?.[p.id]?.priceString ?? '—'}</Btn>)}
          </div>
        ))}
        <div className="bd stack">
          {storeReady && products && !shown.length && <div className="notice blue">Nothing's on sale right now. Try again later.</div>}
          <div className="small muted">Diamonds buy refills, upgrades, setup slots, boosts and extra grow houses. Diamonds you buy never expire. Only diamonds you earn in the game can be sent to other players.</div>
          {storeReady && <Btn className="ghost sm" onClick={restore}>Restore purchases</Btn>}
        </div>
      </Card>
      <DailyDrop />
    </div>
  )
}
