import { useEffect, useState } from 'react'
import { useGame, useMe } from '../lib/game'
import { num } from '../lib/format'
import { isNative } from '../lib/platform'
import { buyPack, getOfferings, restorePurchases, storeReady, waitForDelivery, type StoreProduct } from '../lib/store'
import { BackBar } from '../components/BackBar'
import { DailyDrop } from '../components/DailyDrop'
import { Btn, Card } from '../components/ui'

/**
 * The store (#15): diamond packs, then the Daily Drop. Purchases go through Apple in the iOS app only (guideline
 * 3.1.1), at StoreKit's price in the player's own currency. The web build lists the packs with no prices or buttons.
 */
export default function Store() {
  const me = useMe()
  const { catalog, toast, refresh } = useGame()
  const packs = catalog?.store?.packs ?? []
  const [products, setProducts] = useState<Record<string, StoreProduct> | null>(null)
  const [delivering, setDelivering] = useState<string | null>(null)
  const ids = packs.map(p => p.id).join(' ')
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
        {shown.map(p => (
          <div key={p.id} className="row store-pack">
            <span className="ico">💎</span>
            <div className="grow t tabular">{num(p.diamonds)} diamonds</div>
            {storeReady && (delivering === p.id
              ? <span className="small muted nowrap"><span className="spin" /> Delivering…</span>
              : <Btn className="gold sm" disabled={!products?.[p.id] || !!delivering} onClick={() => buy(p.id, p.diamonds)}>{products?.[p.id]?.priceString ?? '—'}</Btn>)}
          </div>
        ))}
        <div className="bd stack">
          {storeReady && products && !shown.length && <div className="notice blue">Nothing's on sale right now. Try again later.</div>}
          {!storeReady && <div className="notice blue">{isNative ? 'Purchases aren\'t available in this build.' : 'Diamonds are sold in the iPhone app.'}</div>}
          <div className="small muted">Diamonds buy refills, upgrades, setup slots, boosts and extra grow houses. Diamonds you buy never expire. Only diamonds you earn in the game can be sent to other players.</div>
          {storeReady && <Btn className="ghost sm" onClick={restore}>Restore purchases</Btn>}
        </div>
      </Card>
      <DailyDrop />
    </div>
  )
}
