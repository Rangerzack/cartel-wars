import { useEffect, useRef, useState } from 'react'
import { useLoad } from '../lib/useLoad'
import { useLocation } from 'react-router-dom'
import { useGame, useMe } from '../lib/game'
import { num } from '../lib/format'
import { isNative } from '../lib/platform'
import { buyPack, getOfferings, restorePurchases, storeReady, waitForDelivery, type StoreProduct } from '../lib/store'
import { focusCard } from '../lib/scroll'
import { BackBar } from '../components/BackBar'
import { DailyDrop } from '../components/DailyDrop'
import { Btn, Card, Loading } from '../components/ui'

/**
 * The store (#15): diamond packs, then the Daily Drop. Purchases go through Apple in the iOS app only (guideline
 * 3.1.1), at StoreKit's price in the player's own currency. The web build says so first, then lists the packs dimmed,
 * with no prices or buttons. Home's Daily Drop row links to /store#drop, the full pitch with the odds above Subscribe.
 */
export default function Store() {
  const me = useMe()
  const { catalog, toast, refresh } = useGame()
  const packs = catalog?.store?.packs ?? []
  const [delivering, setDelivering] = useState<string | null>(null)
  const alive = useRef(true)
  useEffect(() => () => { alive.current = false }, [])
  const ids = packs.map(p => p.id).join(' ')
  // StoreKit's prices; a failed ask (no connection to the App Store) gets a Retry, not an empty shop
  const { data: products, error, reload } = useLoad<Record<string, StoreProduct>>(() => (storeReady && ids ? getOfferings(ids.split(' ')) : Promise.resolve({})), ids)
  const { hash } = useLocation()
  const ready = !!catalog
  useEffect(() => {
    if (!hash || !ready) return
    const t = setTimeout(() => focusCard(hash.slice(1)), 150)
    return () => clearTimeout(t)
  }, [hash, ready])
  // In the app, once StoreKit has answered, only what the App Store actually sells (a pack whose product isn't live yet
  // would be a dead button); until then every pack, with its price still to come. On the web there is nothing to buy,
  // so the list stays out: the one line says where diamonds are sold.
  const shown = !storeReady ? [] : products ? packs.filter(p => products[p.id]) : packs

  const buy = async (id: string, diamonds: number) => {
    const before = me.diamonds
    let r
    try { r = await buyPack(id) } catch (e) { toast((e as Error).message, 'bad'); return }
    if (r === 'cancelled') { toast('Purchase cancelled', 'info'); return }
    if (r === 'pending') { toast('Waiting for approval. Your diamonds arrive once Apple approves it.', 'info'); return }
    setDelivering(id)
    const ok = await waitForDelivery(m => m.diamonds > before, () => alive.current)
    if (!alive.current) return
    setDelivering(null)
    await refresh()
    toast(ok ? `+${num(diamonds)} diamonds` : "Your diamonds are on their way. They'll show up in a minute.", ok ? 'ok' : 'info')
  }
  const restore = async () => {
    let r
    try { r = await restorePurchases() } catch (e) { toast((e as Error).message, 'bad'); return }
    await refresh()
    // diamond packs are used up when bought, so only a subscription can come back
    toast(r.active > 0 ? 'Your Daily Drop is back' : 'Nothing to restore: diamond packs are spent when bought, and no subscription is active', r.active > 0 ? 'ok' : 'info')
  }

  return (
    <div className="page">
      <BackBar fallback="/" />
      <h2>Store</h2>
      <Card id="diamonds" title="💎 Diamonds" right={<small className="dia tabular">💎 {num(me.diamonds)}</small>}>
        {!storeReady && <div className="bd"><div className="notice blue">{isNative ? 'Purchases aren\'t available in this build.' : 'Diamonds are sold in the iPhone app. Everything they buy can also be earned: milestones, the Daily Drop and the casino pay out in diamonds.'}</div></div>}
        {storeReady && error && !products && <Loading error={error} onRetry={reload} />}
        {shown.map(p => (
          <div key={p.id} className={`row store-pack${storeReady ? '' : ' off'}`}>
            <span className="ico">💎</span>
            <div className="grow t tabular">{num(p.diamonds)} diamonds</div>
            {storeReady && (delivering === p.id
              ? <span className="small muted nowrap"><span className="spin" aria-hidden /> Delivering…</span>
              : <Btn className="gold sm" disabled={!products?.[p.id] || !!delivering} onClick={() => buy(p.id, p.diamonds)}>{products?.[p.id]?.priceString ?? '—'}</Btn>)}
          </div>
        ))}
        <div className="bd stack">
          {storeReady && products && !error && !shown.length && <div className="notice blue">Nothing's on sale right now. Try again later.</div>}
          <div className="small muted">Diamonds buy refills, upgrades, setup slots, boosts and extra grow houses. Diamonds you buy never expire. Only diamonds you earn in the game can be sent to other players.</div>
          {storeReady && <div className="hstack"><Btn className="ghost sm" onClick={restore}>Restore purchases</Btn><span className="small muted">Brings back a Daily Drop bought on this Apple ID.</span></div>}
        </div>
      </Card>
      <DailyDrop />
    </div>
  )
}
