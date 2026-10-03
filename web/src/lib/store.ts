import type { PurchasesStoreProduct } from '@revenuecat/purchases-capacitor'
import { api } from './api'
import { isNative } from './platform'
import type { Me } from './types'

/**
 * In-app purchases (#15, #16): diamond packs and the Daily Drop subscription, through Apple in the iOS app only
 * (guideline 3.1.1); the web build sells nothing. RevenueCat runs StoreKit here and reports each purchase to the
 * iap-webhook edge function, which credits the player, so a purchase lands in get_me a moment after StoreKit says
 * it went through (waitForDelivery). The plugin is a dynamic import so the web build never loads it.
 */
const KEY = import.meta.env.VITE_REVENUECAT_IOS_KEY as string | undefined

/** Purchases work in this build: the iOS app, built with a RevenueCat key. */
export const storeReady = isNative && !!KEY

export type StoreProduct = PurchasesStoreProduct
/** pending: Ask to Buy or a payment Apple still has to approve; the webhook delivers once it does. */
export type BuyResult = 'bought' | 'cancelled' | 'pending'

const MANAGE_URL = 'https://apps.apple.com/account/subscriptions'
const rc = () => import('@revenuecat/purchases-capacitor')
let configured: Promise<void> | null = null
let user: string | null = null        // who RevenueCat is signed in as right now
let wanted: string | null = null      // who it should be: the signed-in player
let switching: Promise<void> | null = null
const products = new Map<string, StoreProduct>()

/** Sign RevenueCat in as the player: purchases carry this id to the webhook, which credits that Supabase user.
 *  `user` moves only once the SDK has confirmed, so a login that fails (a dropped connection right after sign-in) is
 *  known to have failed, and sdk() tries it again before any purchase goes out. */
export async function initStore(userId: string) {
  if (!storeReady) return
  wanted = userId
  const { Purchases } = await rc()
  if (!configured) {
    configured = Purchases.configure({ apiKey: KEY!, appUserID: userId }).then(() => { user = userId }, e => { configured = null; throw e })
    return configured
  }
  await configured
  if (user === userId) return
  if (!switching) switching = Purchases.logIn({ appUserID: userId }).then(() => { user = userId }).finally(() => { switching = null })
  await switching
  if (user !== userId) return initStore(userId)   // the switch that just finished was for someone else
}

/** On sign-out: RevenueCat forgets the player, so the next purchase can't land on their account. */
export async function logOutStore() {
  wanted = null
  if (!storeReady || !configured || !user) return
  const { Purchases } = await rc()
  await configured
  user = null
  await Purchases.logOut()
}

/** The SDK, signed in as the current player, or an error: never a purchase under the anonymous id (the webhook would
 *  credit nobody while Apple still charges). A failed earlier configure or login is retried here. */
async function sdk() {
  if (!storeReady) throw new Error('Purchases are only in the iPhone app')
  if (!wanted) throw new Error('Sign in to buy')
  if (!configured || user !== wanted) {
    try { await initStore(wanted) } catch { throw new Error("The store can't reach Apple right now. Check your connection and try again.") }
  }
  return rc()
}

/**
 * What the App Store sells for these product ids, with the price in the player's own currency (priceString).
 * Asked from StoreKit by id, so the pack list lives in one place (store_packs) and no RevenueCat Offering has to
 * mirror it. Ids the App Store doesn't know (not created yet, not approved) are left out.
 */
export async function getOfferings(ids: string[]): Promise<Record<string, StoreProduct>> {
  if (!storeReady || !ids.length) return {}
  const { Purchases } = await sdk()
  const { products: found } = await Purchases.getProducts({ productIdentifiers: ids })
  for (const p of found) products.set(p.identifier, p)
  return Object.fromEntries(ids.flatMap(id => (products.has(id) ? [[id, products.get(id)!]] : [])))
}

async function buy(productId: string): Promise<BuyResult> {
  const { Purchases, PURCHASES_ERROR_CODE: E } = await sdk()
  const product = products.get(productId) ?? (await getOfferings([productId]))[productId]
  if (!product) throw new Error("That isn't on sale in the App Store right now")
  try {
    await Purchases.purchaseStoreProduct({ product })
    return 'bought'
  } catch (e) {
    const x = e as { code?: unknown; message?: string; userCancelled?: boolean; data?: { userCancelled?: boolean } }
    if (String(x?.code) === E.PURCHASE_CANCELLED_ERROR || x?.userCancelled || x?.data?.userCancelled) return 'cancelled'
    if (String(x?.code) === E.PAYMENT_PENDING_ERROR) return 'pending'
    throw new Error(x?.message || 'The purchase didn\'t go through')
  }
}

/** Buy a diamond pack (a store_packs id). */
export const buyPack = (productId: string) => buy(productId)
/** Subscribe to the Daily Drop (the catalog's store.drop_product). */
export const buyDrop = (productId: string) => buy(productId)

/** Ask Apple again for what this Apple ID bought: brings back a Daily Drop subscription. Packs are used up when bought. */
export async function restorePurchases() {
  const { Purchases, PURCHASES_ERROR_CODE: E } = await sdk()
  try {
    await Purchases.restorePurchases()
  } catch (e) {
    const x = e as { code?: unknown; message?: string }
    if (String(x?.code) === E.RECEIPT_IN_USE_BY_OTHER_SUBSCRIBER_ERROR || String(x?.code) === E.RECEIPT_ALREADY_IN_USE_ERROR) {
      throw new Error('Those purchases belong to another Cartel Wars account')
    }
    throw new Error(x?.message || "Couldn't restore purchases")
  }
}

/**
 * Apple's subscription settings, where the Daily Drop is cancelled. The plugin has no showManageSubscriptions, so this
 * opens Apple's link: in the iOS app window.open hands it to iOS (Capacitor opens links that leave the app with the
 * system), which shows the App Store's Subscriptions page; in a browser it's a new tab.
 */
export function manageSubscriptions() {
  window.open(MANAGE_URL, '_blank', 'noopener')
}

/**
 * After StoreKit says yes, the diamonds or the subscription come through the webhook, not the purchase call: ask the
 * server every 1.5 s, for up to 20 s, until `arrived` holds. False if it's still on its way.
 */
export async function waitForDelivery(arrived: (m: Me) => boolean): Promise<boolean> {
  const end = Date.now() + 20_000
  while (Date.now() < end) {
    try { if (arrived(await api.me())) return true } catch { /* a dropped request: ask again */ }
    await new Promise(r => setTimeout(r, 1500))
  }
  return false
}
