import { useState } from 'react'
import { useGame } from '../lib/game'
import { api } from '../lib/api'
import { Btn, Modal, Seg } from './ui'
import type { ReportReason } from '../lib/types'

const reasons: { v: ReportReason; l: string }[] = [
  { v: 'name', l: 'Name' }, { v: 'avatar', l: 'Avatar' }, { v: 'bio', l: 'Bio' }, { v: 'other', l: 'Other' },
]

/** Report a profile to the admins: what's wrong, and an optional note. */
export function ReportModal({ id, name, onClose }: { id: string; name: string; onClose: () => void }) {
  const { run } = useGame()
  const [reason, setReason] = useState<ReportReason>('name')
  const [note, setNote] = useState('')
  return (
    <Modal title={`Report ${name}`} onClose={onClose}>
      <div className="stack">
        <div className="small muted">What's wrong with their profile? An admin will take a look — reports are private.</div>
        <Seg value={reason} onChange={setReason} options={reasons} />
        <textarea className="input" rows={2} maxLength={200} placeholder="Anything the admin should know (optional)" value={note} onChange={e => setNote(e.target.value)} />
        <Btn className="doit red block" onClick={async () => { const r = await run(() => api.reportProfile(id, reason, note), { ok: () => 'Thanks — an admin will take a look' }); if (r) onClose() }}>Send Report</Btn>
      </div>
    </Modal>
  )
}
