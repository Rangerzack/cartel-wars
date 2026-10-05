import { useEffect, useRef, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { api } from '../lib/api'
import { useGame, useMe } from '../lib/game'
import { ago, dropIcon, nextRollover, num, timeLeft } from '../lib/format'
import { policyUrl, type PolicyPage } from '../lib/pages'
import { isNative, openExternal } from '../lib/platform'
import { buyDrop, getOfferings, manageSubscriptions, storeReady, waitForDelivery, type StoreProduct } from '../lib/store'
import { useNow } from '../lib/useNow'
import type { DropPrize, RecentDrop } from '../lib/types'
import { Btn, Card, RowLink } from './ui'
import { useCrateOpener } from './CrateOpener'
import { errorText } from '../lib/errors'

// 70 of 1,000 → "7%", 5 of 1,000 → "0.5%" (rounded to a tenth, no float noise)
const pct = (weight: number, total: number) => `${Math.round((weight / total) * 1000) / 10}%`

/**
 * The Daily Drop card (Home and the Store): subscribe, the crate stack, opening a crate, and the odds. The odds sit
 * above the subscribe button whenever it shows: Apple wants the odds of a paid random prize shown before purchase
 * (guideline 3.1.1). While drop_free is 1 everyone gets the free plan; in the iOS app, once drop_free is 0 or the
 * player has had a paid plan, Subscribe is an App Store purchase at StoreKit's price. The web never shows a price.
 * `compact` (Home): a player who isn't subscribed gets one row to the Store's card instead of the pitch, odds and
 * Subscribe, which were 1,000 px of a new player's Home. Crates still waiting and free credits still show here.
 */
export function DailyDrop({ compact = false }: { compact?: boolean }) {
  const me = useMe()
  const { catalog, run, toast, refresh, ask } = useGame()
  const now = useNow()
  const nav = useNavigate()
  const [showOdds, setShowOdds] = useState(false)
  const [jackpots, setJackpots] = useState<RecentDrop[] | null>(null)
  const [product, setProduct] = useState<StoreProduct | null>(null)
  const [priceFailed, setPriceFailed] = useState(false)
  const [priceTry, setPriceTry] = useState(0)
  const [delivering, setDelivering] = useState(false)
  const d = me.drop
  const prizes = catalog?.drop_prizes
  const free = !!catalog?.config.drop_free
  const dropProduct = catalog?.store?.drop_product ?? ''
  // the App Store plan: in the iOS app once the subscription is for sale, or for a player who already paid for one
  const viaStore = storeReady && !!dropProduct && (!free || !!d?.drop_paid)
  const wantPrice = viaStore && !d?.subscribed
  useEffect(() => {
    if (!wantPrice) return
    getOfferings([dropProduct]).then(r => { setProduct(r[dropProduct] ?? null); setPriceFailed(false) }).catch(() => { setProduct(null); setPriceFailed(true) })
  }, [wantPrice, dropProduct, priceTry])
  const crate = useCrateOpener(r => { if (r.jackpot) api.recentDrops(5).then(setJackpots).catch(() => {}) })
  const alive = useRef(true)
  useEffect(() => () => { alive.current = false }, [])
  if (!d || !prizes?.length || !catalog) return null
  const price = product?.priceString
  const total = prizes.reduce((s, p) => s + p.weight, 0)
  const jack = prizes.filter(p => p.jackpot)
  const full = d.crates >= d.max
  const credits = (me.free_refills ?? 0) > 0 || (me.free_hustlers ?? 0) > 0
  const pitch = !d.subscribed && !compact
  if (compact && !d.subscribed && d.crates === 0 && !credits) {
    return (
      <Card id="drop" className="drop-card">
        <RowLink to="/store#drop">
          <span className="ico">🎁</span>
          <div className="grow"><div className="t">Daily Drop</div><div className="s">{free ? 'Free · a crate every day' : 'A crate every day'}</div></div>
          <span className="chev">›</span>
        </RowLink>
      </Card>
    )
  }

  const toggleOdds = () => {
    const next = !showOdds
    setShowOdds(next)
    if (next && !jackpots) api.recentDrops(5).then(setJackpots).catch(() => setJackpots([]))
  }
  const subscribe = () => run(api.subscribeDrop, { ok: r => `Subscribed — ${r.crates === 1 ? 'your first crate is here' : `${r.crates} crates waiting`}` })
  // An App Store purchase: StoreKit takes the payment, then the webhook turns the plan on, so wait for get_me to show it.
  const subscribePaid = async () => {
    let r
    try { r = await buyDrop(dropProduct) } catch (e) { toast(errorText(e), 'bad'); return }
    if (r === 'cancelled') { toast('Purchase cancelled', 'info'); return }
    if (r === 'pending') { toast('Waiting for approval. The Daily Drop starts once Apple approves it.', 'info'); return }
    setDelivering(true)
    const ok = await waitForDelivery(m => !!m.drop?.subscribed && !!m.drop.drop_paid, () => alive.current)
    if (!alive.current) return
    setDelivering(false)
    await refresh()
    toast(ok ? 'Subscribed to the Daily Drop' : "Your subscription is on its way. It'll show up in a minute.", ok ? 'ok' : 'info')
  }
  const cancel = async () => {
    if (!await ask(`No more crates after today.${d.crates ? ` Your ${d.crates} unopened crate${d.crates > 1 ? 's stay' : ' stays'} yours to open.` : ''}`, { title: 'Cancel the Daily Drop?', yes: 'Cancel it', tone: 'red' })) return
    return run(api.unsubscribeDrop, { ok: () => 'Daily Drop cancelled' })
  }
  return (
    <>
      <Card id="drop" title="🎁 Daily Drop" className={`drop-card${d.crates > 0 ? ' has-crates' : ''}`}
        right={d.subscribed ? <small className="tabular">{d.crates}/{d.max} crates</small>
          : viaStore ? <small className="drop-price tabular">{price ? `${price}/mo` : ''}</small>
          : free ? <small className="drop-price"><b>FREE</b></small> : undefined}>
        {(d.crates > 0 || d.subscribed || pitch) && <div className="bd stack">
          {d.crates > 0 ? (
            <>
              <div className="crate-stack" aria-label={`${d.crates} crate${d.crates > 1 ? 's' : ''} waiting`}>
                {Array.from({ length: d.max }, (_, i) => <span key={i} className={i < d.crates ? 'on' : ''}>📦</span>)}
              </div>
              <Btn className="doit block" onClick={crate.open}>Open Crate{d.crates > 1 ? ` · ${d.crates} waiting` : ''}</Btn>
              {full && d.subscribed && <div className="small gold">Your stack is full — open one or tomorrow's crate is lost.</div>}
            </>
          ) : d.subscribed ? (
            <div className="crate-empty"><span>📦</span><div><div className="t">Next crate in {timeLeft(nextRollover(now), now)}</div><div className="small muted">One lands every day at 00:00 UTC. Unopened crates stack up to {d.max}.</div></div></div>
          ) : pitch && (
            <div className="crate-pitch">
              <div className="crate-hero">📦</div>
              <div>A crate every day at 00:00 UTC — product, diamonds, cash, thugs, hustlers or free refills. Miss a day and it waits: unopened crates stack up to {d.max}. Subscribers also get {me.refills?.sub_full ?? 5} full stamina refills of each drug a day instead of {catalog?.config.refill_full ?? 3}.</div>
              <div className="small">Jackpots: {jack.map((p, i) => <span key={p.code}>{i ? ' or ' : ''}<b className="gold">{dropIcon[p.kind]} {p.label}</b></span>)}</div>
            </div>
          )}
        </div>}
        {pitch && <>
          <div className="row small muted">What can drop? See the odds below.</div>
          <Odds prizes={prizes} total={total} jackpots={null} />
        </>}
        {(pitch || d.last || credits) && <div className="bd stack">
          {pitch && (
            viaStore ? <>
                <Btn className="gold block" disabled={!price || delivering} onClick={subscribePaid}>{delivering ? 'Starting Your Daily Drop…' : 'Subscribe'}</Btn>
                {priceFailed
                  ? <div className="why">Couldn't get the price from the App Store. <button type="button" className="linkbtn" onClick={() => setPriceTry(n => n + 1)}>Try again</button></div>
                  : <div className="small muted center">{price ? `${price} per month, renews until cancelled. Cancel any time in your device settings.` : 'Getting the price from the App Store…'}</div>}
                <PolicyLinks />
              </>
            : free ? <>
                <Btn className="gold block" onClick={subscribe}>Subscribe — Free for Now</Btn>
                <div className="small muted center">The Daily Drop is free while the game is in early access. {isNative ? 'Later it will be a monthly subscription.' : 'In the iPhone app it will be a monthly subscription.'}</div>
                <PolicyLinks />
              </>
            : <div className="small muted center">The Daily Drop is a monthly subscription in the iPhone app.</div>
          )}
          {d.last && <div className="small muted">Last crate: <b className={d.last.jackpot ? 'gold' : ''}>{dropIcon[d.last.kind]} {d.last.label}</b> · {ago(d.last.at, now)}</div>}
          {credits && (
            <div className="hstack drop-credits">
              {(me.free_refills ?? 0) > 0 && <button className="btn sm ghost" onClick={() => nav('/services?focus=refills')}>⚡ {me.free_refills} Free Refill{me.free_refills === 1 ? '' : 's'} ›</button>}
              {(me.free_hustlers ?? 0) > 0 && me.path !== 'producer' && <button className="btn sm ghost" onClick={() => nav('/economy?tab=hustlers')}>🚶 {num(me.free_hustlers)} Free Hustler{me.free_hustlers === 1 ? '' : 's'} ›</button>}
            </div>
          )}
        </div>}
        {compact && !d.subscribed && (
          <RowLink to="/store#drop"><div className="grow small muted">Subscribe for a crate every day</div><span className="chev">›</span></RowLink>
        )}
        {d.subscribed && <>
          <RowLink onClick={toggleOdds}>
            <div className="grow small muted">{showOdds ? 'Hide the odds' : 'What can drop? See the odds'}</div><span className="chev" style={showOdds ? { transform: 'rotate(90deg)' } : undefined}>›</span>
          </RowLink>
          {showOdds && <Odds prizes={prizes} total={total} jackpots={jackpots} />}
          <div className="row small muted">
            <div className="grow">Subscribed {d.since ? ago(d.since, now) : ''}{d.opened ? ` · ${num(d.opened)} crate${d.opened > 1 ? 's' : ''} opened` : ''}{d.drop_paid ? (d.until ? ` · paid through ${new Date(d.until).toLocaleDateString()}` : '') : ' · free plan'}</div>
            {d.drop_paid
              ? <button className="btn sm ghost" onClick={manageSubscriptions}>Manage Subscription</button>
              : <Btn className="sm ghost" onClick={cancel}>Cancel</Btn>}
          </div>
        </>}
      </Card>
      {crate.sheet}
    </>
  )
}

const legal: [PolicyPage, string][] = [['terms', 'Terms of service'], ['privacy', 'Privacy policy']]

/** Terms and privacy next to Subscribe: Apple wants both linked where a subscription is sold (guideline 3.1.2). */
function PolicyLinks() {
  return (
    <div className="small muted center">
      {legal.map(([page, label], i) => (
        <span key={page}>{i ? ' · ' : ''}<a href={policyUrl(page)} target="_blank" rel="noopener" style={{ color: 'inherit' }}
          onClick={e => { e.preventDefault(); openExternal(policyUrl(page)) }}>{label}</a></span>
      ))}
    </div>
  )
}

function Odds({ prizes, total, jackpots }: { prizes: DropPrize[]; total: number; jackpots: RecentDrop[] | null }) {
  return (
    <div className="drop-odds">
      {prizes.map(p => (
        <div key={p.code} className={`row${p.jackpot ? ' jackpot' : ''}`}>
          <span className="ico">{dropIcon[p.kind]}</span>
          <div className="grow t">{p.label}{p.jackpot && <span className="pill nowrap">jackpot</span>}</div>
          <b className="tabular">{pct(p.weight, total)}</b>
        </div>
      ))}
      <div className="row small muted">Each crate is one roll on this table. Product goes straight into storage, even past your cap.</div>
      {jackpots && jackpots.length > 0 && (
        <div className="row"><div className="grow finds-ticker">
          <div className="small muted">Latest jackpots</div>
          {jackpots.map((j, i) => <div key={i} className="small"><Link to={`/player/${j.player_id}`}>{j.player}</Link> hit <b className="gold">{dropIcon[j.kind]} {j.label}</b> <span className="muted">· {ago(j.at)}</span></div>)}
        </div></div>
      )}
    </div>
  )
}
