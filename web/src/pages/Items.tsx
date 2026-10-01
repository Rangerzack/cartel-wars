import { useState } from 'react'
import { Link, useNavigate, useSearchParams } from 'react-router-dom'
import { useGame, useMe } from '../lib/game'
import { api } from '../lib/api'
import { categoryLabel, money, num } from '../lib/format'
import { Btn, Card, Empty, Seg } from '../components/ui'
import type { ItemCategory, SetupKind } from '../lib/types'
import { BackBar } from '../components/BackBar'
import { PerkTag } from '../components/Perk'
import { discounted, perk } from '../lib/perks'
import { itemCombos } from '../lib/combos'
import { SetupCombo } from '../components/Combo'

const cats: ItemCategory[] = ['weapon', 'protection', 'transport', 'jail_weapon']

export default function Items() {
  const me = useMe()
  const { catalog, run, toast } = useGame()
  const [sp] = useSearchParams()
  const nav = useNavigate()
  // deep links: /items?tab=shop&cat=weapon, /items?setup=defense (and the old /items#shop)
  const [tab, setTab] = useState<'setups' | 'shop'>(sp.get('tab') === 'shop' || window.location.hash === '#shop' ? 'shop' : 'setups')
  const [setup, setSetup] = useState<SetupKind>((['offense', 'defense', 'jail'] as const).find(s => s === sp.get('setup')) ?? 'offense')
  const [cat, setCat] = useState<ItemCategory>(cats.find(c => c === sp.get('cat')) ?? 'weapon')
  if (!catalog) return <Empty><span className="spin" /></Empty>
  const shopPerk = cat === 'transport' ? 'chop_shop' as const : 'pawn_shop' as const

  const inv = new Map(me.inventory.map(i => [i.item_id, i]))
  const equipped = new Map((me.setups[setup] ?? []).map(s => [s.item_id, s.qty]))
  const used = [...equipped.values()].reduce((a, b) => a + b, 0)
  const power = me.power[setup]
  const allowed = (c: ItemCategory) => (setup === 'jail' ? c !== 'weapon' : c !== 'jail_weapon')
  // an active boost counts in its own setup: attack in Offense, defense in Defense
  const boosted = !!me.boost?.active && ((me.boost.side === 'attack' && setup === 'offense') || (me.boost.side === 'defense' && setup === 'defense'))
  // weapons and protection count in both fight setups; jail weapons only inside
  const homeSetups: Partial<Record<ItemCategory, SetupKind[]>> = { weapon: ['offense', 'defense'], protection: ['offense', 'defense'], jail_weapon: ['jail'] }
  const setupName: Record<SetupKind, string> = { offense: 'Offensive', defense: 'Defensive', jail: 'Jail' }
  /** Buy one and equip it straight away wherever it has a free slot — new players shouldn't need a second screen. */
  async function buy(itemId: number, category: ItemCategory, name: string) {
    const r = await run(() => api.buyItem(itemId, 1), { silent: true })
    if (!r) return
    const targets = homeSetups[category] ?? []
    const into: string[] = [], full: string[] = []
    for (const s of targets) {
      const inSetup = me.setups[s] ?? []
      if (inSetup.reduce((a, x) => a + x.qty, 0) >= me.inventory_slots) { full.push(setupName[s]); continue }
      const q = inSetup.find(x => x.item_id === itemId)?.qty ?? 0
      if (await run(() => api.equip(s, itemId, q + 1), { silent: true })) into.push(setupName[s])
    }
    const list = (xs: string[]) => xs.join(' and ') + (xs.length > 1 ? ' setups' : ' setup')
    toast(into.length ? `Bought ${name} and equipped it in your ${list(into)}`
      : full.length ? `Bought ${name} — your ${list(full)} ${full.length > 1 ? 'are' : 'is'} full, swap it in under Setups`
      : `Bought ${name}`, 'ok')
  }

  return (
    <div className="page">
      <BackBar fallback="/" />
      <Seg value={tab} onChange={setTab} options={[{ v: 'setups', l: 'Setups' }, { v: 'shop', l: 'Buy Items' }]} />

      {tab === 'setups' && (
        <>
          <Seg value={setup} onChange={setSetup} options={[{ v: 'offense', l: 'Offensive' }, { v: 'defense', l: 'Defensive' }, { v: 'jail', l: 'Jail' }]} />
          <Card title={<>Attack {power.att} · Defense {power.def}</>} right={<small>{used}/{me.inventory_slots} slots</small>}>
            {boosted && <div className="row small"><span className="gold">⚡ Includes your +{me.boost!.amount} {me.boost!.side} boost</span><span className="grow" /><button className="btn sm ghost" onClick={() => nav('/services?focus=boost')}>Boost ›</button></div>}
            <div className="bd stack">
              <div className="slots">{Array.from({ length: me.inventory_slots }, (_, i) => <span key={i} className={`slot ${i < used ? 'on' : ''}`} />)}</div>
              {used >= me.inventory_slots && me.slot_cost && me.inventory_slots < (catalog.config.max_slots ?? 130) && <div className="small muted">Setup full. The next slot costs 💎 {me.slot_cost.diamonds} + {money(me.slot_cost.cash)} — <Link to="/services?focus=upgrades">Services ›</Link></div>}
              <div className="small muted">
                {setup === 'offense' && 'Used when you attack. '}
                {setup === 'defense' && 'Used when someone attacks you. '}
                {setup === 'jail' && 'Used for fights while you are in jail — only against other inmates. Regular weapons are confiscated, jail weapons only work here. '}
                Both numbers matter: your attack goes against their defense, and their attack against your defense. Barehands baseline is 20/20. Only your single best vehicle counts, but vehicles complete some combos.
              </div>
            </div>
          </Card>
          <SetupCombo setup={setup} />
          <Card title="Owned items">
            {me.inventory.filter(i => allowed(i.category)).length === 0 && (
              <Empty>
                <div>Nothing usable in this setup yet.</div>
                <button className="btn gold sm" style={{ marginTop: 10 }} onClick={() => { setTab('shop'); setCat(setup === 'jail' ? 'jail_weapon' : setup === 'defense' ? 'protection' : 'weapon') }}>Go to the shop</button>
              </Empty>
            )}
            {me.inventory.filter(i => allowed(i.category)).map(i => {
              const q = equipped.get(i.item_id) ?? 0
              const canAdd = q < i.qty && used < me.inventory_slots
              return (
                <div key={i.item_id} className="row">
                  <div className="grow">
                    <div className="t">{catalog.items.find(d => d.id === i.item_id)?.drop_only && <span className="find-tag">🎁 </span>}{i.name} <span className="muted small">×{i.qty}</span></div>
                    <div className="s">{i.att ? `att ${i.att} ` : ''}{i.def ? `def ${i.def} ` : ''}{i.capacity ? `cargo ${i.capacity} ` : ''}<ComboTags id={i.item_id} /></div>
                  </div>
                  <div className="hstack" style={{ flexWrap: 'nowrap' }}>
                    <Btn className="sm" disabled={q === 0} onClick={() => run(() => api.equip(setup, i.item_id, q - 1), { silent: true })}>−</Btn>
                    <b className="tabular" style={{ width: 22, textAlign: 'center' }}>{q}</b>
                    <Btn className="sm" disabled={!canAdd} onClick={() => run(() => api.equip(setup, i.item_id, q + 1), { silent: true })}>+</Btn>
                  </div>
                </div>
              )
            })}
          </Card>
        </>
      )}

      {tab === 'shop' && (
        <>
          <div className="seg">{cats.map(c => <button key={c} className={cat === c ? 'on' : ''} onClick={() => setCat(c)}>{categoryLabel[c]}</button>)}</div>
          {(perk(me, shopPerk) > 0 || perk(me, 'repo') > 0) && <div className="hstack"><PerkTag code={shopPerk} /><PerkTag code="repo" /></div>}
          <Card>
            {catalog.items.filter(i => i.category === cat).map(i => {
              const have = inv.get(i.id)?.qty ?? 0
              const drop = !!i.drop_only
              const cost = discounted(i.price, perk(me, shopPerk))
              const resale = Math.floor(i.price * (0.5 + perk(me, 'repo')))
              return (
                <div key={i.id} className={`row ${drop ? 'drop-only' : ''}`}>
                  <div className="grow">
                    <div className="t">{drop && <span className="find-tag">🎁 </span>}{i.rep_price > 0 && <span className="dia">★ </span>}{i.name} {have > 0 && <span className="muted small">×{have}</span>}</div>
                    <div className="s">{i.att ? `att ${i.att} ` : ''}{i.def ? `def ${i.def} ` : ''}{i.capacity ? `cargo ${num(i.capacity)} ` : ''}<ComboTags id={i.id} /></div>
                  </div>
                  {have > 0 && i.rep_price === 0 && !drop && <Btn className="sm ghost" onClick={() => {
                    // it sits next to the gold Buy and goes back at about half price: ask first
                    if (!confirm(`Sell one ${i.name} for ${money(resale)}?`)) return
                    return run(() => api.sellItem(i.id, 1), { ok: r => `Sold for ${money(r.refund)}` })
                  }}>Sell {money(resale)}</Btn>}
                  {drop
                    ? <Btn className="sm ghost" onClick={() => nav('/actions')}>Found on jobs</Btn>
                    : i.rep_price > 0
                    ? <Btn className="sm blue" disabled={me.reputation < i.rep_price} onClick={() => run(() => api.buyItem(i.id, 1), { ok: () => `Earned ${i.name}` })}>⭐ {num(i.rep_price)}</Btn>
                    : <Btn className="sm gold" disabled={me.cash < cost} onClick={() => buy(i.id, i.category, i.name)}>{cost < i.price && <s className="was">{money(i.price)}</s>}{money(cost)}</Btn>}
                </div>
              )
            })}
          </Card>
          <div className="small muted">You can own as many as you like; only equipped items count, and only within a setup's slots. Selling returns half the price (more with a Repo Co) and only works for unequipped units. ★ Rare items are bought with Reputation (you have ⭐ {num(me.reputation)}) from reputation actions, and can't be sold. 🎁 Rare finds are the best of each kind; they only turn up on jobs and can't be bought or sold.</div>
        </>
      )}
    </div>
  )
}

/** The combos an item is part of, e.g. "· Grenadier". */
function ComboTags({ id }: { id: number }) {
  const { catalog } = useGame()
  const list = itemCombos(catalog, id)
  if (!list.length) return null
  const icon = (st: string) => catalog?.combo_styles?.find(x => x.code === st)?.icon ?? ''
  return <span className="combo-tags">· {list.map(c => `${icon(c.style)} ${c.name}`).join(', ')}</span>
}
