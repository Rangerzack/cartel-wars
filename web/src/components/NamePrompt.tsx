import { useState } from 'react'
import { useGame, useMe } from '../lib/game'
import { api } from '../lib/api'
import { Btn } from './ui'

/** Asks for a street name when an admin reset yours, or the one you signed up with was taken or not allowed. */
export function NamePrompt() {
  const me = useMe()
  const { run } = useGame()
  const [nm, setNm] = useState('')
  if (!me.name_required) return null
  return (
    <div className="name-prompt">
      <div className="notice gold stack" style={{ gap: 8 }}>
        <b>{me.rename_pending ? 'An admin reset your name' : 'Pick your street name'}</b>
        <div className="small">
          {me.rename_pending
            ? "Your old name broke the rules. Pick a new one — it's free, and it's what everyone sees."
            : <>The name you signed up with was taken or isn't allowed, so you're <b>{me.name}</b> for now. Pick a real one.</>}
        </div>
        <div className="hstack" style={{ flexWrap: 'nowrap' }}>
          <input className="input" style={{ flex: 1 }} maxLength={20} placeholder="Street name" aria-label="New street name" value={nm} onChange={e => setNm(e.target.value)} />
          <Btn className="gold" disabled={nm.trim().length < 3} onClick={async () => { const r = await run(() => api.chooseName(nm), { ok: r => `You're ${r.name} now` }); if (r) setNm('') }}>Save</Btn>
        </div>
      </div>
    </div>
  )
}
