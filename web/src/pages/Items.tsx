import { useState } from 'react'
import { useGame, useMe } from '../lib/game'
import { api } from '../lib/api'
import { categoryLabel, money, num } from '../lib/format'
import { Btn, Card, Empty, Seg } from '../components/ui'
import type { ItemCategory, SetupKind } from '../lib/types'

const cats: ItemCategory[] = ['weapon', 'protection', 'transport', 'jail_weapon']

export default function Items() {
  const me = useMe()
  const { catalog, run } = useGame()
  const [tab, setTab] = useState<'setups' | 'shop'>('setups')
  const [setup, setSetup] = useState<SetupKind>('offense')
  const [cat, setCat] = useState<ItemCategory>('weapon')
  if (!catalog) return <Empty><span className="spin" /></Empty>

  const inv = new Map(me.inventory.map(i => [i.item_id, i]))
  const equipped = new Map((me.setups[setup] ?? []).map(s => [s.item_id, s.qty]))
  const used = [...equipped.values()].reduce((a, b) => a + b, 0)
  const power = me.power[setup]
  const allowed = (c: ItemCategory) => (setup === 'jail' ? c !== 'weapon' : c !== 'jail_weapon')

  return (
    <div className="page">
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
                Barehands baseline is 20/20. Only your single best vehicle counts. A weapon and protection with the same style give a combo bonus.
              </div>
            </div>
          </Card>
          <Card title="Owned items">
            {me.inventory.filter(i => allowed(i.category)).length === 0 && <Empty>Nothing usable in this setup. Buy something.</Empty>}
            {me.inventory.filter(i => allowed(i.category)).map(i => {
              const q = equipped.get(i.item_id) ?? 0
              const canAdd = q < i.qty && used < me.inventory_slots
              return (
                <div key={i.item_id} className="row">
                  <div className="grow">
                    <div className="t">{i.name} <span className="muted small">×{i.qty}</span></div>
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
              return (
                <div key={i.id} className="row">
                  <div className="grow">
                    <div className="t">{i.name} {have > 0 && <span className="muted small">×{have}</span>}</div>
                    <div className="s">{i.att ? `att ${i.att} ` : ''}{i.def ? `def ${i.def} ` : ''}{i.capacity ? `cargo ${num(i.capacity)} ` : ''}{i.combo_tag ? `· ${i.combo_tag}` : ''}</div>
                  </div>
                  {have > 0 && <Btn className="sm ghost" onClick={() => run(() => api.sellItem(i.id, 1), { ok: r => `Sold for ${money(r.refund)}` })}>Sell {money(i.price / 2)}</Btn>}
                  <Btn className="sm gold" disabled={me.cash < i.price} onClick={() => run(() => api.buyItem(i.id, 1), { ok: () => `Bought ${i.name}` })}>{money(i.price)}</Btn>
                </div>
              )
            })}
          </Card>
          <div className="small muted">You can own as many as you like; only equipped items count, and only within a setup's slots. Selling returns half the price and only works for unequipped units.</div>
        </>
      )}
    </div>
  )
}
