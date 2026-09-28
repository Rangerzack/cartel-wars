import { useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { useGame, useMe } from '../lib/game'
import { api } from '../lib/api'
import { categoryLabel, money, num } from '../lib/format'
import { Btn, Card, Empty, Seg } from '../components/ui'
import type { ItemCategory, SetupKind } from '../lib/types'
import { BackBar } from '../components/BackBar'

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

  const inv = new Map(me.inventory.map(i => [i.item_id, i]))
  const equipped = new Map((me.setups[setup] ?? []).map(s => [s.item_id, s.qty]))
  const used = [...equipped.values()].reduce((a, b) => a + b, 0)
  const power = me.power[setup]
  const allowed = (c: ItemCategory) => (setup === 'jail' ? c !== 'weapon' : c !== 'jail_weapon')
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
          <Card title={<>Attack {power.att} · Defense {power.def} {power.combo && <span className="gold small">· combo bonus</span>}</>} right={<small>{used}/{me.inventory_slots} slots</small>}>
            <div className="bd stack">
              <div className="slots">{Array.from({ length: me.inventory_slots }, (_, i) => <span key={i} className={`slot ${i < used ? 'on' : ''}`} />)}</div>
              <div className="small muted">
                {setup === 'offense' && 'Used when you attack. '}
                {setup === 'defense' && 'Used when someone attacks you. '}
                {setup === 'jail' && 'Used for all fights while you are in jail — regular weapons are confiscated, jail weapons only work here. '}
                Both numbers matter: your attack goes against their defense, and their attack against your defense. Barehands baseline is 20/20. Only your single best vehicle counts. A weapon and protection with the same style give a combo bonus.
              </div>
            </div>
          </Card>
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
                    <div className="s">{i.att ? `att ${i.att} ` : ''}{i.def ? `def ${i.def} ` : ''}{i.capacity ? `cargo ${i.capacity} ` : ''}{i.combo_tag ? `· ${i.combo_tag}` : ''}</div>
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
          <Card>
            {catalog.items.filter(i => i.category === cat).map(i => {
              const have = inv.get(i.id)?.qty ?? 0
              const drop = !!i.drop_only
              return (
                <div key={i.id} className={`row ${drop ? 'drop-only' : ''}`}>
                  <div className="grow">
                    <div className="t">{drop && <span className="find-tag">🎁 </span>}{i.rep_price > 0 && <span className="dia">★ </span>}{i.name} {have > 0 && <span className="muted small">×{have}</span>}</div>
                    <div className="s">{i.att ? `att ${i.att} ` : ''}{i.def ? `def ${i.def} ` : ''}{i.capacity ? `cargo ${num(i.capacity)} ` : ''}{i.combo_tag ? `· ${i.combo_tag}` : ''}</div>
                  </div>
                  {have > 0 && i.rep_price === 0 && !drop && <Btn className="sm ghost" onClick={() => run(() => api.sellItem(i.id, 1), { ok: r => `Sold for ${money(r.refund)}` })}>Sell {money(i.price / 2)}</Btn>}
                  {drop
                    ? <Btn className="sm ghost" onClick={() => nav('/actions')}>Found on jobs</Btn>
                    : i.rep_price > 0
                    ? <Btn className="sm blue" disabled={me.reputation < i.rep_price} onClick={() => run(() => api.buyItem(i.id, 1), { ok: () => `Earned ${i.name}` })}>⭐ {num(i.rep_price)}</Btn>
                    : <Btn className="sm gold" disabled={me.cash < i.price} onClick={() => buy(i.id, i.category, i.name)}>{money(i.price)}</Btn>}
                </div>
              )
            })}
          </Card>
          <div className="small muted">You can own as many as you like; only equipped items count, and only within a setup's slots. Selling returns half the price and only works for unequipped units. ★ Rare items are bought with Reputation (you have ⭐ {num(me.reputation)}) from reputation actions, and can't be sold. 🎁 Rare finds are the best of each kind; they only turn up on jobs and can't be bought or sold.</div>
        </>
      )}
    </div>
  )
}
