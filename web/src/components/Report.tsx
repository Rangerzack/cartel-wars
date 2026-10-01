import { useState } from 'react'
import { useGame } from '../lib/game'
import { api } from '../lib/api'
import { Btn, Modal, Seg } from './ui'
import type { ContentReason, ReportKind, ReportReason } from '../lib/types'

const profileReasons: { v: ReportReason; l: string }[] = [
  { v: 'name', l: 'Name' }, { v: 'avatar', l: 'Avatar' }, { v: 'bio', l: 'Bio' }, { v: 'other', l: 'Other' },
]
const contentReasons: { v: ContentReason; l: string }[] = [
  { v: 'harassment', l: 'Harassment' }, { v: 'hate', l: 'Hate' }, { v: 'spam', l: 'Spam' }, { v: 'threat', l: 'Threat' }, { v: 'other', l: 'Other' },
]
const what: Record<ReportKind, string> = { profile: 'their profile', message: 'this message', forum_thread: 'this thread', forum_post: 'this reply' }
const title: Record<ReportKind, (name: string) => string> = {
  profile: n => `Report ${n}`, message: n => `Report ${n}'s message`, forum_thread: n => `Report ${n}'s thread`, forum_post: n => `Report ${n}'s reply`,
}

/** Report a profile, or one of a player's chat messages, threads or replies, to the admins: what's wrong, and an optional
 *  note. id and name are the player's; refId is the message, thread or reply; quote shows what's being reported. */
export function ReportModal({ kind = 'profile', id, name, refId, quote, onClose }: {
  kind?: ReportKind; id: string; name: string; refId?: number; quote?: string; onClose: () => void
}) {
  const { run } = useGame()
  const [reason, setReason] = useState<ReportReason>('name')
  const [contentReason, setContentReason] = useState<ContentReason>('harassment')
  const [note, setNote] = useState('')
  const send = () => {
    if (kind === 'profile') return api.reportProfile(id, reason, note)
    if (kind === 'message') return api.reportMessage(refId!, contentReason, note)
    return api.reportForum(kind === 'forum_thread' ? 'thread' : 'post', refId!, contentReason, note)
  }
  return (
    <Modal title={title[kind](name)} onClose={onClose}>
      <div className="stack">
        {quote && <div className="report-quote small">“{quote}”</div>}
        <div className="small muted">What's wrong with {what[kind]}? An admin will take a look — reports are private.</div>
        {kind === 'profile' ? <Seg value={reason} onChange={setReason} options={profileReasons} /> : <Seg value={contentReason} onChange={setContentReason} options={contentReasons} />}
        <textarea className="input" rows={2} maxLength={200} placeholder="Anything the admin should know (optional)" value={note} onChange={e => setNote(e.target.value)} />
        <Btn className="doit red block" onClick={async () => { const r = await run(send, { ok: () => 'Thanks — an admin will take a look' }); if (r) onClose() }}>Send Report</Btn>
      </div>
    </Modal>
  )
}
