import { useEffect, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { api } from '../lib/api'
import { useGame, useMe } from '../lib/game'
import { ago, dropIcon, hoodlumIcon, money, nextRollover, num, timeLeft } from '../lib/format'
import { policyUrl, type PolicyPage } from '../lib/pages'
import { isNative, openExternal } from '../lib/platform'
import { buyDrop, getOfferings, manageSubscriptions, storeReady, waitForDelivery, type StoreProduct } from '../lib/store'
import { useNow } from '../lib/useNow'
import type { DropPrize, DropResult, RecentDrop } from '../lib/types'
import { Btn, Card, Modal } from './ui'

// 70 of 1,000 → "7%", 5 of 1,000 → "0.5%" (rounded to a tenth, no float noise)
const pct = (weight: number, total: number) => `${Math.round((weight / total) * 1000) / 10}%`

/**
 * The Daily Drop card (Home and the Store): subscribe, the crate stack, opening a crate, and the odds. The odds sit
 * above the subscribe button whenever it shows: Apple wants the odds of a paid random prize shown before purchase
 * (guideline 3.1.1). While drop_free is 1 everyone gets the free plan; in the iOS app, once drop_free is 0 or the
 * player has had a paid plan, Subscribe is an App Store purchase at StoreKit's price. The web never shows a price.
 */
export function DailyDrop() {
  const me = useMe()
  const { catalog, run, toast, refresh } = useGame()
  const now = useNow()
  const nav = useNavigate()
  const [showOdds, setShowOdds] = useState(false)
  const [jackpots, setJackpots] = useState<RecentDrop[] | null>(null)
  const [reveal, setReveal] = useState<{ r?: DropResult } | null>(null)
  const [product, setProduct] = useState<StoreProduct | null>(null)
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
    getOfferings([dropProduct]).then(r => setProduct(r[dropProduct] ?? null)).catch(() => setProduct(null))
  }, [wantPrice, dropProduct])
  if (!d || !prizes?.length || !catalog) return null
  const price = product?.priceString
  const total = prizes.reduce((s, p) => s + p.weight, 0)
  const jack = prizes.filter(p => p.jackpot)
  const full = d.crates >= d.max
  const credits = (me.free_refills ?? 0) > 0 || (me.free_hustlers ?? 0) > 0

  const toggleOdds = () => {
    const next = !showOdds
    setShowOdds(next)
    if (next && !jackpots) api.recentDrops(5).then(setJackpots).catch(() => setJackpots([]))
  }
  const subscribe = () => run(api.subscribeDrop, { ok: r => `Subscribed — ${r.crates === 1 ? 'your first crate is here' : `${r.crates} crates waiting`}` })
  // An App Store purchase: StoreKit takes the payment, then the webhook turns the plan on, so wait for get_me to show it.
  const subscribePaid = async () => {
    let r
    try { r = await buyDrop(dropProduct) } catch (e) { toast((e as Error).message, 'bad'); return }
    if (r === 'cancelled') { toast('Purchase cancelled', 'info'); return }
    if (r === 'pending') { toast('Waiting for approval. The Daily Drop starts once Apple approves it.', 'info'); return }
    setDelivering(true)
    const ok = await waitForDelivery(m => !!m.drop?.subscribed && !!m.drop.drop_paid)
    setDelivering(false)
    await refresh()
    toast(ok ? 'Subscribed to the Daily Drop' : "Your subscription is on its way. It'll show up in a minute.", ok ? 'ok' : 'info')
  }
  const cancel = () => {
    if (!confirm(`Cancel the Daily Drop? No more crates after today.${d.crates ? ` Your ${d.crates} unopened crate${d.crates > 1 ? 's stay' : ' stays'} yours to open.` : ''}`)) return
    return run(api.unsubscribeDrop, { ok: () => 'Daily Drop cancelled' })
  }
  // Shake the crate while the server rolls, for at least a beat, then show what came out.
  const open = async () => {
    setReveal({})
    const t0 = Date.now()
    const r = await run(api.openCrate, { silent: true })
    if (!r) { setReveal(null); return }
    await new Promise(res => setTimeout(res, Math.max(0, 1100 - (Date.now() - t0))))
    setReveal({ r })
    if (r.jackpot) api.recentDrops(5).then(setJackpots).catch(() => {})
  }

  return (
    <>
      <Card id="drop" title="🎁 Daily Drop" className={`drop-card${d.crates > 0 ? ' has-crates' : ''}`}
        right={d.subscribed ? <small className="tabular">{d.crates}/{d.max} crates</small>
          : viaStore ? <small className="drop-price tabular">{price ? `${price}/mo` : ''}</small>
          : free ? <small className="drop-price"><b>FREE</b></small> : undefined}>
        <div className="bd stack">
          {d.crates > 0 ? (
            <>
              <div className="crate-stack" aria-label={`${d.crates} crate${d.crates > 1 ? 's' : ''} waiting`}>
                {Array.from({ length: d.max }, (_, i) => <span key={i} className={i < d.crates ? 'on' : ''}>📦</span>)}
              </div>
              <Btn className="doit block" onClick={open}>Open Crate{d.crates > 1 ? ` · ${d.crates} waiting` : ''}</Btn>
              {full && d.subscribed && <div className="small gold">Your stack is full — open one or tomorrow's crate is lost.</div>}
            </>
          ) : d.subscribed ? (
            <div className="crate-empty"><span>📦</span><div><div className="t">Next crate in {timeLeft(nextRollover(now), now)}</div><div className="small muted">One lands every day at 00:00 UTC. Unopened crates stack up to {d.max}.</div></div></div>
          ) : (
            <div className="crate-pitch">
              <div className="crate-hero">📦</div>
              <div>A crate every day at 00:00 UTC — product, diamonds, cash, thugs, hustlers or free refills. Miss a day and it waits: unopened crates stack up to {d.max}.</div>
              <div className="small">Jackpots: {jack.map((p, i) => <span key={p.code}>{i ? ' or ' : ''}<b className="gold">{dropIcon[p.kind]} {p.label}</b></span>)}</div>
            </div>
          )}
        </div>
        {!d.subscribed && <>
          <div className="row small muted">What can drop? See the odds below.</div>
          <Odds prizes={prizes} total={total} jackpots={null} onPlayer={id => nav(`/player/${id}`)} />
        </>}
        {(!d.subscribed || d.last || credits) && <div className="bd stack">
          {!d.subscribed && (
            viaStore ? <>
                <Btn className="gold block" disabled={!price || delivering} onClick={subscribePaid}>{delivering ? 'Starting your Daily Drop…' : 'Subscribe'}</Btn>
                <div className="small muted center">{price ?? '—'} per month, renews until cancelled. Cancel any time in your device settings.</div>
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
              {(me.free_refills ?? 0) > 0 && <button className="btn sm ghost" onClick={() => nav('/services?focus=refills')}>⚡ {me.free_refills} free refill{me.free_refills === 1 ? '' : 's'} ›</button>}
              {(me.free_hustlers ?? 0) > 0 && <button className="btn sm ghost" onClick={() => nav('/economy?tab=hustlers')}>🚶 {num(me.free_hustlers)} free hustler{me.free_hustlers === 1 ? '' : 's'} ›</button>}
            </div>
          )}
        </div>}
        {d.subscribed && <>
          <div className="row link" onClick={toggleOdds}>
            <div className="grow small muted">{showOdds ? 'Hide the odds' : 'What can drop? See the odds'}</div><span className="chev" style={showOdds ? { transform: 'rotate(90deg)' } : undefined}>›</span>
          </div>
          {showOdds && <Odds prizes={prizes} total={total} jackpots={jackpots} onPlayer={id => nav(`/player/${id}`)} />}
          <div className="row small muted">
            <div className="grow">Subscribed {d.since ? ago(d.since, now) : ''}{d.opened ? ` · ${num(d.opened)} crate${d.opened > 1 ? 's' : ''} opened` : ''}{d.drop_paid ? (d.until ? ` · paid through ${new Date(d.until).toLocaleDateString()}` : '') : ' · free plan'}</div>
            {d.drop_paid
              ? <button className="btn sm ghost" onClick={manageSubscriptions}>Manage subscription</button>
              : <button className="btn sm ghost" onClick={cancel}>Cancel</button>}
          </div>
        </>}
      </Card>
      {reveal && (
        <Modal title={reveal.r?.jackpot ? 'Jackpot!' : 'Daily Drop'} onClose={() => setReveal(null)}>
          {!reveal.r ? (
            <div className="crate-open"><div className="crate-shake">📦</div><div className="small muted">Cracking it open…</div></div>
          ) : (
            <Prize r={reveal.r} onOpen={open} onGo={to => { setReveal(null); nav(to) }} />
          )}
        </Modal>
      )}
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

function Odds({ prizes, total, jackpots, onPlayer }: { prizes: DropPrize[]; total: number; jackpots: RecentDrop[] | null; onPlayer: (id: string) => void }) {
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
          {jackpots.map((j, i) => <div key={i} className="small"><a onClick={() => onPlayer(j.player_id)}>{j.player}</a> hit <b className="gold">{dropIcon[j.kind]} {j.label}</b> <span className="muted">· {ago(j.at)}</span></div>)}
        </div></div>
      )}
    </div>
  )
}

function Prize({ r, onOpen, onGo }: { r: DropResult; onOpen: () => void; onGo: (to: string) => void }) {
  const me = useMe()
  const { run } = useGame()
  const [banked, setBanked] = useState(false)
  const over = me.storage_used > me.storage_cap
  const where = (() => {
    switch (r.kind) {
      case 'herb': case 'dust': case 'pills':
        return <>Into storage — {num(me.storage_used)}/{num(me.storage_cap)}.{over ? ' That puts you over your cap: sell or use some before you can store more.' : ''}</>
      case 'diamonds': return <>You have 💎 {num(me.diamonds)}.</>
      case 'cash': return banked ? <>Banked. It's safe.</> : <>It's on hand — bank it so nobody takes it off you in a fight.</>
      case 'refills': return <>A full stamina refill each, on top of your three a day. You have {me.free_refills ?? r.amount}.</>
      case 'thugs': return <>They're with you now — {hoodlumIcon.thug} {num(me.hoodlums.thug ?? 0)} thugs.</>
      case 'hustlers': return <>Each one skips the hustler fee on your next hires (for a Trader, that hustler's cut). You have {num(me.free_hustlers ?? r.amount)}.</>
    }
  })()
  const go = r.kind === 'refills' ? { to: '/services?focus=refills', l: 'Use a Refill' }
    : r.kind === 'hustlers' ? { to: '/economy?tab=hustlers', l: 'Send Hustlers' }
    : r.kind === 'thugs' ? { to: '/territory', l: 'Territory' }
    : null
  return (
    <div className={`find-modal drop-prize${r.jackpot ? ' jackpot' : ''}`}>
      <div className="big">{dropIcon[r.kind]}</div>
      <div className="name">{r.label}</div>
      <div className="small">{where}</div>
      {r.kind === 'cash' && !banked && me.cash >= r.amount && (
        <Btn className="gold block" onClick={async () => { if (await run(() => api.bankDeposit(r.amount), { ok: () => `Banked ${money(r.amount)}` })) setBanked(true) }}>Bank {money(r.amount)}</Btn>
      )}
      {go && <button className="btn block" onClick={() => onGo(go.to)}>{go.l} ›</button>}
      {r.crates > 0 && <Btn className="doit block" onClick={onOpen}>Open Another · {r.crates} left</Btn>}
    </div>
  )
}
