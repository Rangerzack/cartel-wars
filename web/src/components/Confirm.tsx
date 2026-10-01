import { useGame } from '../lib/game'
import { Modal } from './ui'

/** The in-app "are you sure" (useGame().ask): the question, then Cancel and the action named on its own button. Escape,
 *  the × and a tap on the backdrop all mean no. Mounted once in Layout. */
export function ConfirmSheet() {
  const { confirmReq: r, answer } = useGame()
  if (!r) return null
  const tone = r.tone ?? 'doit'
  return (
    <Modal title={r.title ?? 'Are you sure?'} onClose={() => answer(false)}
      footer={
        <div className="confirm-actions">
          <button type="button" className="btn ghost" onClick={() => answer(false)}>Cancel</button>
          <button type="button" className={`btn ${tone}`} onClick={() => answer(true)}>{r.yes ?? 'Confirm'}</button>
        </div>
      }>
      <p className="confirm-msg">{r.message}</p>
    </Modal>
  )
}
