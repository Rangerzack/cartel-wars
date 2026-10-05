import { useRef, useState } from 'react'
import { useNavigate } from 'react-router-dom'
import { api } from '../lib/api'
import { useGame } from '../lib/game'
import type { DropResult } from '../lib/types'
import { Modal } from './ui'
import { Prize } from './Prize'
import { haptic } from '../lib/haptics'

/** Opening a crate, wherever the button is (the Daily Drop card, Home's Next up): shake the crate while the server
 *  rolls, for at least a beat, then show what came out, with Open Another while more wait. `sheet` renders the reveal;
 *  closing it during the shake retires that open. */
export function useCrateOpener(onResult?: (r: DropResult) => void) {
  const { run } = useGame()
  const nav = useNavigate()
  const [reveal, setReveal] = useState<{ r?: DropResult } | null>(null)
  const opening = useRef(0)   // which open is in progress
  const open = async () => {
    const n = ++opening.current
    setReveal({})
    const t0 = Date.now()
    const r = await run(api.openCrate, { silent: true })
    if (!r) { if (n === opening.current) setReveal(null); return }
    await new Promise(res => setTimeout(res, Math.max(0, 1100 - (Date.now() - t0))))
    if (n === opening.current) { setReveal({ r }); haptic(r.jackpot ? 'success' : 'medium') }
    onResult?.(r)
  }
  const close = () => { opening.current++; setReveal(null) }
  const sheet = reveal && (
    <Modal title={reveal.r?.jackpot ? 'Jackpot' : 'Daily Drop'} onClose={close}>
      {!reveal.r ? (
        <div className="crate-open" role="status"><div className="crate-shake" aria-hidden>📦</div><div className="small muted">Cracking it open…</div></div>
      ) : (
        <Prize r={reveal.r} onOpen={open} onGo={to => { close(); nav(to) }} />
      )}
    </Modal>
  )
  return { open, sheet }
}
