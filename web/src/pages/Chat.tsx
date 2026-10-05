import { useCallback, useEffect, useMemo, useRef, useState } from 'react'
import { Link, useNavigate, useParams } from 'react-router-dom'
import { useGame, useMe } from '../lib/game'
import { api } from '../lib/api'
import { supabase } from '../lib/supabase'
import { ago } from '../lib/format'
import { Btn, Card, Empty, Modal, RowLink } from '../components/ui'
import type { Conversation, Message, PublicPlayer } from '../lib/types'
import { features } from '../lib/features'
import { LinkedText, PlayerLink } from '../components/Linked'
import { useNow } from '../lib/useNow'
import { ReportModal } from '../components/Report'

export default function Chat() {
  const me = useMe()
  const { channel = 'global' } = useParams()
  const nav = useNavigate()
  const tabs = [
    { v: 'global', l: 'Live Chat' },
    ...(me.crew ? [{ v: `crew:${me.crew.id}`, l: 'Crew' }] : []),
    ...(me.cartel ? [{ v: `cartel:${me.cartel.id}`, l: 'Cartel' }] : []),
    // "DMs" (the word the admin queue uses too): with Forum › beside the seg, "Conversations" no longer fits at 375 px
    { v: 'dms', l: 'DMs' },
  ]
  const isDm = channel.startsWith('dm:')
  const valid = channel === 'global' || channel === 'dms' || /^(crew|cartel):[0-9a-f-]{36}$/.test(channel) || /^dm:[0-9a-f-]{36}:[0-9a-f-]{36}$/.test(channel) || /^table:[0-9]+$/.test(channel)
  useEffect(() => { if (!valid) nav('/chat', { replace: true }) }, [valid, nav])
  if (!valid) return null
  return (
    <div className="page" style={{ gap: 8 }}>
      {/* the seg switches channels in place; the forum is another page, so it's a link beside it rather than a tab in it */}
      <div className="chat-tabs">
        <div className="seg">
          {tabs.map(t => <button key={t.v} type="button" className={channel === t.v || (isDm && t.v === 'dms') ? 'on' : ''} aria-pressed={channel === t.v || (isDm && t.v === 'dms')} onClick={() => nav(`/chat/${t.v}`, { replace: true })}>
            {t.l}{t.v === 'dms' && (me.unread_dms ?? 0) > 0 && <span className="tbadge red inline">{me.unread_dms}</span>}
          </button>)}
        </div>
        {features.forum && <Link to="/forum" className="btn sm ghost">Forum ›</Link>}
      </div>
      {channel === 'dms' ? <Conversations /> : <Channel key={channel} channel={channel} />}
    </div>
  )
}

export function Channel({ channel, compact }: { channel: string; compact?: boolean }) {
  const me = useMe()
  const { toast, refresh, run, ask } = useGame()
  const [msgs, setMsgs] = useState<Message[] | null>(null)
  // the ⋯ sheet on someone else's line, and the report it opens
  const [menu, setMenu] = useState<Message | null>(null)
  const [reporting, setReporting] = useState<Message | null>(null)
  const [text, setText] = useState('')
  const [sending, setSending] = useState(false)
  const [other, setOther] = useState<PublicPlayer | null>(null)
  const logRef = useRef<HTMLDivElement>(null)
  // the log follows new lines only while you're reading the end of it; scrolled up to read history, it stays put
  const atEnd = useRef(true)
  // a dropped connection is said once, not on every poll
  const failing = useRef(false)
  // how far back the log reaches: 50 lines, 50 more per "Load older" (the server caps it at 200); the polls keep it
  const [limit, setLimit] = useState(50)
  const reach = useRef(50)   // the same number, for load() without restarting the subscription
  const [older, setOlder] = useState(false)
  const keepFromEnd = useRef(0)   // where the reader was, measured from the bottom, across a load of older lines
  const isDm = channel.startsWith('dm:')
  // Blocking: in group chats the lines of players I've blocked never render, whether they came with the history or
  // arrived live (the server already leaves them out of get_messages). A DM keeps its history, but either side's block
  // closes it. A line an admin deleted never renders either (it comes back flagged, without its text).
  const blocked = me.blocked
  const shown = useMemo(() => msgs?.filter(m => !m.deleted && (isDm || !blocked?.includes(m.sender_id))), [msgs, isDm, blocked])
  const cut = !!other && (other.blocked || other.blocked_me || !!blocked?.includes(other.id))
  // muted by an admin: the server refuses the post, so the composer gives way to when the mute ends
  const now = useNow(30_000)
  const mutedUntil = me.muted_until && new Date(me.muted_until).getTime() > now ? me.muted_until : null

  const load = useCallback(() => api.messages(channel, reach.current)
    .then(m => { setMsgs(m); failing.current = false })
    .catch(e => { if (!failing.current) toast(e.message, 'bad'); failing.current = true }), [channel, toast])
  useEffect(() => {
    load()
    const otherId = channel.startsWith('dm:') ? channel.split(':').slice(1).find(x => x !== me.id) : undefined
    if (otherId) api.player(otherId).then(setOther).catch(() => {})
    // realtime: new rows on this channel; poll fast until the subscription is confirmed, slowly after
    let live = false
    const sub = supabase.channel('chat:' + channel)
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'messages', filter: `channel=eq.${channel}` },
        payload => setMsgs(m => (m && !m.some(x => x.id === (payload.new as Message).id) ? [...m, payload.new as Message] : m)))
      // an admin deleting a line arrives as an update with deleted set
      .on('postgres_changes', { event: 'UPDATE', schema: 'public', table: 'messages', filter: `channel=eq.${channel}` },
        payload => setMsgs(m => m && m.map(x => (x.id === (payload.new as Message).id ? { ...x, ...(payload.new as Message) } : x))))
      .subscribe(status => { live = status === 'SUBSCRIBED' })
    // nothing polls in the background; with realtime up, a slow poll (every 32 s) catches anything it dropped
    let n = 0
    const poll = setInterval(() => { if (document.visibilityState !== 'visible') return; if (!live || ++n % 8 === 0) load() }, 4_000)
    return () => { supabase.removeChannel(sub); clearInterval(poll) }
  }, [channel, load, me.id])
  useEffect(() => {
    const el = logRef.current
    if (!el) return
    // older lines landed above: hold the reader's place instead of jumping
    if (keepFromEnd.current) { el.scrollTop = el.scrollHeight - keepFromEnd.current; keepFromEnd.current = 0; return }
    if (atEnd.current) el.scrollTo({ top: 1e9 })
  }, [msgs])
  const loadOlder = async () => {
    const el = logRef.current
    if (el) keepFromEnd.current = el.scrollHeight - el.scrollTop
    reach.current = Math.min(200, reach.current + 50)
    setLimit(reach.current)
    setOlder(true)
    await load()
    setOlder(false)
  }
  const more = !!msgs && msgs.length >= limit && limit < 200
  const onLogScroll = (el: HTMLDivElement) => { atEnd.current = el.scrollHeight - el.scrollTop - el.clientHeight < 80 }
  // Reading a DM clears its unread badge: mark it read whenever a message from them shows up here.
  const markedUpTo = useRef(0)
  useEffect(() => {
    if (!channel.startsWith('dm:') || !msgs) return
    const newest = msgs.reduce((m, x) => (x.sender_id !== me.id && x.id > m ? x.id : m), 0)
    if (newest > markedUpTo.current || markedUpTo.current === 0) {
      markedUpTo.current = Math.max(newest, 1)
      api.markRead(channel).then(() => refresh()).catch(() => {})
    }
  }, [channel, msgs, me.id, refresh])

  async function send(e: React.FormEvent) {
    e.preventDefault()
    const body = text.trim()
    if (!body || sending) return
    setSending(true)
    // the line clears only once it's through: a refused or dropped send leaves it in the box to fix or retry
    try { await api.sendMessage(channel, body); setText(''); atEnd.current = true; load() } catch (err) { toast((err as Error).message, 'bad') } finally { setSending(false) }
  }
  async function block(m: Message) {
    setMenu(null)
    if (!await ask(`Block ${m.sender_name}? They can't message you and their posts are hidden. You can undo this from your Profile.`, { title: `Block ${m.sender_name}?`, yes: 'Block', tone: 'red' })) return
    if (await run(() => api.blockPlayer(m.sender_id), { ok: () => `${m.sender_name} blocked` }) && other) api.player(other.id).then(setOther).catch(() => {})
  }

  const title = other ? `💬 ${other.name}` : channel.startsWith('table') ? 'Table Talk' : undefined
  return (
    <>
      {/* Live Chat, Crew and Cartel are named by the seg above them, so their card has no header and the log gets its
          room; a DM names who it's with, and table talk has no seg */}
      <Card className={`chat ${compact ? 'compact' : ''}`} title={title}>
        <div className="log" ref={logRef} onScroll={e => onLogScroll(e.currentTarget)}>
          {more && <button type="button" className="btn sm ghost load-older" disabled={older} onClick={loadOlder}>{older ? 'Loading…' : 'Load older messages'}</button>}
          {!shown && <Empty><span className="spin" role="status" aria-label="Loading" /></Empty>}
          {shown?.length === 0 && <Empty>Nobody's said anything yet.</Empty>}
          {shown?.map(m => (
            <div key={m.id} className={`msg ${m.sender_id === me.id ? 'me' : ''}`}>
              <PlayerLink id={m.sender_id} className="who">{m.sender_name}</PlayerLink><LinkedText text={m.body} />
              {/* time and ⋯ wrap together, so the ⋯ never sits alone on a line */}
              <span className="meta"><span className="when">{ago(m.created_at)}</span>
                {m.sender_id !== me.id && <button className="more" aria-label={`More for ${m.sender_name}'s message`} onClick={() => setMenu(m)}>⋯</button>}</span>
            </div>
          ))}
        </div>
        {mutedUntil ? <div className="chat-cut small muted">You're muted until {new Date(mutedUntil).toLocaleString()}.</div>
          : cut ? <div className="chat-cut small muted">You can't message each other.</div> : (
          <form onSubmit={send}>
            <input className="input" placeholder="Say something…" aria-label="Message" value={text} maxLength={500} onChange={e => setText(e.target.value)} />
            <button className="btn doit" type="submit" disabled={sending || !text.trim()}>{sending ? <span className="spin" role="img" aria-label="Working" /> : 'Send'}</button>
          </form>
        )}
      </Card>
      {menu && (
        <Modal title={menu.sender_name} onClose={() => setMenu(null)}>
          <div className="stack">
            <div className="report-quote small">“{menu.body}”</div>
            <Btn className="block" onClick={() => { setReporting(menu); setMenu(null) }}>🚩 Report</Btn>
            {!blocked?.includes(menu.sender_id) && <Btn className="block" onClick={() => block(menu)}>🚫 Block</Btn>}
          </div>
        </Modal>
      )}
      {reporting && <ReportModal kind="message" id={reporting.sender_id} name={reporting.sender_name} refId={reporting.id} quote={reporting.body} onClose={() => setReporting(null)} />}
    </>
  )
}

function Conversations() {
  const { toast } = useGame()
  const [list, setList] = useState<Conversation[] | null>(null)
  useEffect(() => { api.conversations().then(setList).catch(e => toast(e.message, 'bad')) }, [toast])
  return (
    <Card>
      {!list && <Empty><span className="spin" role="status" aria-label="Loading" /></Empty>}
      {list?.length === 0 && <Empty>No private conversations. Open a player's profile and tap Chat.</Empty>}
      {list?.map(c => (
        <RowLink key={c.channel} to={`/chat/${c.channel}`} className={c.unread ? 'unread' : ''}>
          <div className="grow"><div className="t">{c.other}</div><div className="s">{c.last}</div></div>
          <div className="stack" style={{ gap: 4, alignItems: 'flex-end' }}>
            <span className="small muted">{ago(c.at)}</span>
            {!!c.unread && <span className="tbadge red inline">{c.unread}</span>}
          </div>
        </RowLink>
      ))}
    </Card>
  )
}
