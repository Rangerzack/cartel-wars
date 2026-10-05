import { useEffect, useRef, useState } from 'react'
import { Link, useNavigate } from 'react-router-dom'
import { useGame, useMe } from '../lib/game'
import { api } from '../lib/api'
import { ago, dropOdds, every, findIcon, money, num } from '../lib/format'
import { Btn, Card, Empty, Modal } from '../components/ui'
import { BailButton } from '../components/Bail'
import { HealButton } from '../components/Heal'
import type { ActionDef, RareFind, RecentFind } from '../lib/types'

type Sort = 'default' | 'cash' | 'rep'
type Result = { a: ActionDef; pay: number; rep: number; busted: boolean; heat: number; stamina: number }
type Flash = Result & { key: number }

export default function Actions() {
  const me = useMe()
  const { catalog, run, askRefill } = useGame()
  const nav = useNavigate()
  // Only jail / busts get the pop-up — they change what you can do next. Everything else shows in place.
  const [bust, setBust] = useState<Result | null>(null)
  const [flash, setFlash] = useState<Record<number, Flash>>({})
  const [session, setSession] = useState({ jobs: 0, cash: 0, rep: 0, finds: 0 })
  // what VoiceOver reads after a job: the flash on the row is drawn, not said
  const [said, setSaid] = useState('')
  const [found, setFound] = useState<{ item: RareFind; res: Result } | null>(null)
  const [finds, setFinds] = useState<RecentFind[] | null>(null)
  useEffect(() => { api.recentFinds(6).then(setFinds).catch(() => setFinds([])) }, [])
  // per-device view preferences
  const [onlyAvailable, setOnlyAvailableRaw] = useState(() => { try { return localStorage.getItem('cw.actions.available') === '1' } catch { return false } })
  const setOnlyAvailable = (v: boolean) => { setOnlyAvailableRaw(v); try { localStorage.setItem('cw.actions.available', v ? '1' : '0') } catch { /* private mode */ } }
  const [sort, setSortRaw] = useState<Sort>(() => { try { return (localStorage.getItem('cw.actions.sort') as Sort) || 'default' } catch { return 'default' } })
  const setSort = (v: Sort) => { setSortRaw(v); try { localStorage.setItem('cw.actions.sort', v) } catch { /* private mode */ } }
  const flashKey = useRef(0)
  const timers = useRef<Record<number, ReturnType<typeof setTimeout>>>({})
  useEffect(() => () => Object.values(timers.current).forEach(clearTimeout), [])
  if (!catalog) return <Empty><span className="spin" role="status" aria-label="Loading" /></Empty>

  const list = catalog.actions.filter(a => a.is_jail === me.jailed)
  const owned = new Set(me.inventory.map(i => i.item_id))
  const itemName = (id: number | null) => catalog.items.find(i => i.id === id)?.name ?? ''
  const crewSize = me.crew?.members ?? 0
  const blockedBy = (a: ActionDef) => {
    if (a.requires_item && !owned.has(a.requires_item)) return 'item'
    if (a.min_crew > crewSize) return 'crew'
    if (me.cash < a.cash_cost) return 'cash'
    return null
  }
  const perStamina = (a: ActionDef) => a.stamina_cost > 0 ? Math.round((a.pay_min + a.pay_max) / 2 / a.stamina_cost) : 0
  const repPerStamina = (a: ActionDef) => a.stamina_cost > 0 ? a.pay_rep / a.stamina_cost : 0
  const filtered = onlyAvailable ? list.filter(a => !blockedBy(a)) : list
  const by = me.jailed ? 'default' : sort   // jail has its own short list
  // best-paying jobs you can actually run first, then the ones still locked
  const locked = (a: ActionDef) => (blockedBy(a) ? 1 : 0)
  const shown = by === 'cash' ? [...filtered].filter(a => a.pay_rep === 0 && a.effect !== 'go_to_jail').sort((a, b) => locked(a) - locked(b) || perStamina(b) - perStamina(a))
    : by === 'rep' ? [...filtered].filter(a => a.pay_rep > 0).sort((a, b) => locked(a) - locked(b) || repPerStamina(b) - repPerStamina(a))
    : filtered

  async function go(a: ActionDef) {
    const r = await run(() => api.doAction(a.id), { silent: true })
    if (!r) return
    const res: Result = { a, pay: r.pay, rep: r.rep, busted: r.busted, heat: r.heat, stamina: r.stamina }
    // net cash: what the job paid less what it cost, so a reputation job that costs $8,000 reads −$8,000, not +$0
    setSession(s => ({ jobs: s.jobs + 1, cash: s.cash + (r.pay || 0) - a.cash_cost, rep: s.rep + (r.rep || 0), finds: s.finds + (r.found ? 1 : 0) }))
    if (r.found) { setFound({ item: r.found, res }); api.recentFinds(6).then(setFinds).catch(() => {}); return }
    if (r.busted || a.effect === 'go_to_jail') { setBust(res); return }
    const key = ++flashKey.current
    setFlash(f => ({ ...f, [a.id]: { ...res, key } }))
    setSaid(`${a.name}: ${r.rep > 0 ? `plus ${r.rep} reputation` : `plus ${money(r.pay)}`}. ${r.stamina} stamina left, heat ${r.heat}.`)
    clearTimeout(timers.current[a.id])
    timers.current[a.id] = setTimeout(() => setFlash(f => { const n = { ...f }; if (n[a.id]?.key === key) delete n[a.id]; return n }), 2600)
  }

  return (
    <div className="page">
      <h2>{me.jailed ? 'Jail Actions' : 'Actions'}</h2>
      <div className="sr-only" role="status">{said}</div>
      {me.jailed && <div className="notice red">Inside, the hustle is different. These are the only actions you can run until you're out.</div>}
      {/* bail paid right here, the way the hospital's Heal to Full is */}
      {me.jailed && <BailButton />}
      {me.hospital && <div className="notice red">You can't work from a hospital bed.</div>}
      {me.hospital && <HealButton />}
      {me.path_required && <div className="notice gold">{me.path_due === 'grow' ? 'Your grow houses have outgrown the starter rules' : "You've earned your stripes"} — time to pick Producer or Trader. <Link to="/economy">Choose your path →</Link></div>}
      {!me.hospital && me.stamina === 0 && <div className="notice blue">Out of stamina. It comes back {catalog.config.stamina_regen_amount ?? 2} {every(catalog.config.stamina_regen_minutes ?? 10)}, or <button type="button" className="linkbtn" onClick={() => askRefill()}>refill it →</button></div>}

      <div className="spread">
        {session.jobs > 0
          ? <div className="session-tally tabular">This session: <b>{num(session.jobs)}</b> {session.jobs === 1 ? 'job' : 'jobs'}{session.cash !== 0 && <> · <b className={session.cash > 0 ? 'gold' : 'red'}>{session.cash > 0 ? '+' : '−'}{money(Math.abs(session.cash))}</b></>}{session.rep > 0 && <> · <b className="dia">⭐ +{num(session.rep)}</b></>}{session.finds > 0 && <> · <b className="find-tag">🎁 {session.finds}</b></>}</div>
          : <div className="small muted">Tap Do It — results show right on the job.</div>}
        <label className="toggle small"><input type="checkbox" checked={onlyAvailable} onChange={e => setOnlyAvailable(e.target.checked)} /> Can do now</label>
      </div>
      {!me.jailed && (
        <div className="seg sm">
          {([['default', 'All jobs'], ['cash', 'Best $ per ⚡'], ['rep', 'Reputation']] as const).map(([v, l]) =>
            <button key={v} className={sort === v ? 'on' : ''} onClick={() => setSort(v)}>{l}</button>)}
        </div>
      )}

      <Card>
        {shown.length === 0 && <Empty>{onlyAvailable ? 'Nothing you can run right now — buy the gear or find a bigger crew.' : 'No jobs here.'}</Empty>}
        {shown.map(a => {
          const block = blockedBy(a)
          const tired = me.stamina < a.stamina_cost
          const cant = me.hospital || !!block   // short on stamina isn't a dead button: Do It offers a refill
          const f = flash[a.id]
          return (
            <div key={a.id} className={`row action ${f ? 'flashing' : ''}`}>
              <div className="grow">
                <div className="t">{a.name}</div>
                <div className="s">{a.description}</div>
                <div className="s tabular">
                  <span className="stam">⚡ {a.stamina_cost}</span>
                  {' · '}
                  {a.effect === 'go_to_jail' ? <span>🔒 jail until you post bail</span> : a.pay_rep > 0 ? <span className="dia">⭐ +{a.pay_rep} reputation</span> : <span className="gold">{money(a.pay_min)}–{money(a.pay_max)}</span>}
                  {a.heat_gain > 0 && <> · <span className="red">🔥 +{a.heat_gain}</span></>}
                  {a.cash_cost > 0 && <> · <span className={block === 'cash' ? 'red' : ''}>costs {money(a.cash_cost)}</span></>}
                  {a.requires_item && <> · <span className={block === 'item' ? 'red' : 'green'}>needs {itemName(a.requires_item)}</span></>}
                  {a.min_crew > 0 && <> · <span className={block === 'crew' ? 'red' : 'green'}>crew of {a.min_crew}</span></>}
                  {perStamina(a) > 0 && a.pay_rep === 0 && <span className="muted"> · ~{money(perStamina(a))}/⚡</span>}
                  {tired && !me.hospital && <> · <span className="red">need ⚡{a.stamina_cost} · tap to refill</span></>}
                </div>
                {a.drop_item && <div className="find-tag">🎁 Rare find: <b>{itemName(a.drop_item)}</b> · {dropOdds(a.stamina_cost, catalog.config.drop_stamina)}</div>}
                {f && (
                  <div key={f.key} className="action-result tabular">
                    {f.rep > 0 ? <b className="dia">⭐ +{f.rep} rep</b> : <b className="gold">+{money(f.pay)}</b>}
                    <span className="muted"> · ⚡ {num(f.stamina)} left · 🔥 {num(f.heat)}</span>
                  </div>
                )}
              </div>
              <div className="doit-wrap">
                <Btn className="doit" label={`Do It: ${a.name}`} disabled={!!cant} onClick={() => tired ? askRefill(a.stamina_cost) : go(a)}>Do It</Btn>
                {f && <span key={f.key} className="floater">{f.rep > 0 ? `⭐+${f.rep}` : `+${money(f.pay)}`}</span>}
              </div>
            </div>
          )
        })}
      </Card>
      <Card title="🎁 Rare finds" right={<small>bigger jobs, better odds</small>}>
        <div className="bd stack">
          <div className="small muted">Every job can turn up one of four items you can't buy — each the best of its kind: {catalog.items.filter(i => i.drop_only).map(i => `${i.name} (${[i.att ? `att ${i.att}` : '', i.def ? `def ${i.def}` : ''].filter(Boolean).join(' / ')})`).join(', ')}. Bigger jobs have better odds: a 12-stamina job is 1 in 500.</div>
          {finds && finds.length === 0 && <div className="small muted">Nobody's found one yet.</div>}
          {finds && finds.length > 0 && (
            <div className="finds-ticker">
              {finds.map((f, i) => <div key={i} className="small"><Link to={`/player/${f.player_id}`}>{f.player}</Link> found a <b className="find-tag">{f.item}</b>{f.action ? <> on {f.action}</> : null} <span className="muted">· {ago(f.at)}</span></div>)}
            </div>
          )}
        </div>
      </Card>
      {found && (
        <Modal title="Rare find" onClose={() => { const b = found.res; setFound(null); if (b.busted) setBust(b) }}>
          <div className="find-modal">
            <div className="big">{findIcon[found.item.category]}</div>
            <div className="name">{found.item.name}</div>
            <div className="small muted tabular">{found.item.att ? `att ${found.item.att}` : ''}{found.item.att && found.item.def ? ' · ' : ''}{found.item.def ? `def ${found.item.def}` : ''} · you own {num(found.item.owned)}</div>
            <div className="small">Turned up on {found.res.a.name}. The best {found.item.category === 'jail_weapon' ? 'jail weapon' : found.item.category === 'transport' ? 'vehicle' : found.item.category} in the game — it can't be bought or sold.</div>
            {found.res.busted && <div className="notice red">…and a patrol caught you on the way out. You're in jail.</div>}
            <Btn className="gold block" onClick={() => { setFound(null); nav(`/items?setup=${found.item.category === 'jail_weapon' ? 'jail' : 'offense'}`) }}>Equip it</Btn>
          </div>
        </Modal>
      )}
      {bust && (
        <Modal title={bust.a.effect === 'go_to_jail' ? bust.a.name : 'Busted'} onClose={() => setBust(null)}
          footer={bust.a.effect === 'go_to_jail' ? <button type="button" className="btn gold block" style={{ marginTop: 14 }} onClick={() => setBust(null)}>Stay inside</button> : undefined}>
          {bust.a.effect === 'go_to_jail' ? (
            <p>The cops took the money and the hint. You're in jail with your heat maxed out until you post bail, which clears it to 0 — check your jail setup.</p>
          ) : (
            <>
              {bust.pay > 0 && <p className="gold" style={{ fontSize: 22, fontWeight: 800, margin: '4px 0' }}>+{money(bust.pay)}</p>}
              <p className="red">Your heat was in the red and a patrol caught you. You're in jail with your heat maxed out until you post bail, which clears it to 0 — regular weapons are confiscated, jail setup is active.</p>
            </>
          )}
          {/* bail is paid right here; after a deliberate trip in it's the quiet option, and Stay inside closes the sheet */}
          <BailButton className={bust.a.effect === 'go_to_jail' ? 'ghost block' : 'gold block'} onDone={() => setBust(null)} />
        </Modal>
      )}
    </div>
  )
}
