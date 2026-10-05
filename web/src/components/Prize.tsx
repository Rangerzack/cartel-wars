import { useState } from 'react'
import { api } from '../lib/api'
import { useGame, useMe } from '../lib/game'
import { dropIcon, hoodlumIcon, money, num } from '../lib/format'
import type { DropResult } from '../lib/types'
import { Btn } from './ui'

/** What came out of a Daily Drop crate, where it went, and the one thing to do next with it. */
export function Prize({ r, onOpen, onGo }: { r: DropResult; onOpen: () => void; onGo: (to: string) => void }) {
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
      case 'refills': return <>A full stamina refill each, on top of your drug refills. You have {me.free_refills ?? r.amount}.</>
      case 'thugs': return <>They're with you now — {hoodlumIcon.thug} {num(me.hoodlums.thug ?? 0)} thugs.</>
      case 'hustlers': return <>Each one skips the hustler fee on your next hires (for a Trader, that hustler's cut). You have {num(me.free_hustlers ?? r.amount)}.</>
    }
  })()
  const go = r.kind === 'refills' ? { to: '/services?focus=refills', l: 'Use a Refill' }
    : r.kind === 'hustlers' && me.path !== 'producer' ? { to: '/economy?tab=hustlers', l: 'Send Hustlers' }
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
