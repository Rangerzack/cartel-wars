import { useCallback, useEffect, useRef, useState } from 'react'
import { useNavigate, useParams } from 'react-router-dom'
import { useGame, useMe } from '../lib/game'
import { api } from '../lib/api'
import { supabase } from '../lib/supabase'
import { ago } from '../lib/format'
import { Card, Empty } from '../components/ui'
import type { Conversation, Message } from '../lib/types'
import { features } from '../lib/features'

export default function Chat() {
  const me = useMe()
  const { channel = 'global' } = useParams()
  const nav = useNavigate()
  const tabs = [
    { v: 'global', l: 'Live Chat' },
    ...(me.crew ? [{ v: `crew:${me.crew.id}`, l: 'Crew' }] : []),
    ...(me.cartel ? [{ v: `cartel:${me.cartel.id}`, l: 'Cartel' }] : []),
    { v: 'dms', l: 'Conversations' },
  ]
  const isDm = channel.startsWith('dm:')
  const valid = channel === 'global' || channel === 'dms' || /^(crew|cartel):[0-9a-f-]{36}$/.test(channel) || /^dm:[0-9a-f-]{36}:[0-9a-f-]{36}$/.test(channel) || /^table:[0-9]+$/.test(channel)
  useEffect(() => { if (!valid) nav('/chat', { replace: true }) }, [valid, nav])
  if (!valid) return null
  return (
    <div className="page" style={{ gap: 8 }}>
      <div className="seg">
        {tabs.map(t => <button key={t.v} className={channel === t.v || (isDm && t.v === 'dms') ? 'on' : ''} onClick={() => nav(`/chat/${t.v}`)}>{t.l}</button>)}
        {features.forum && <button onClick={() => nav('/forum')}>Forum</button>}
      </div>
      {channel === 'dms' ? <Conversations /> : <Channel key={channel} channel={channel} />}
    </div>
  )
}

export function Channel({ channel, compact }: { channel: string; compact?: boolean }) {
  const me = useMe()
  const { toast } = useGame()
  const [msgs, setMsgs] = useState<Message[] | null>(null)
  const [text, setText] = useState('')
  const [other, setOther] = useState<string | null>(null)
  const logRef = useRef<HTMLDivElement>(null)

  const load = useCallback(() => api.messages(channel).then(setMsgs).catch(e => toast(e.message, 'bad')), [channel, toast])
  useEffect(() => {
    load()
    const otherId = channel.startsWith('dm:') ? channel.split(':').slice(1).find(x => x !== me.id) : undefined
    if (otherId) api.player(otherId).then(p => setOther(p.name)).catch(() => {})
    // realtime: new rows on this channel; poll fast until the subscription is confirmed, slowly after
    let live = false
    const sub = supabase.channel('chat:' + channel)
      .on('postgres_changes', { event: 'INSERT', schema: 'public', table: 'messages', filter: `channel=eq.${channel}` },
        payload => setMsgs(m => (m && !m.some(x => x.id === (payload.new as Message).id) ? [...m, payload.new as Message] : m)))
      .subscribe(status => { live = status === 'SUBSCRIBED' })
    const poll = setInterval(() => { if (!live || document.visibilityState === 'visible') load() }, 4_000)
    return () => { supabase.removeChannel(sub); clearInterval(poll) }
  }, [channel, load, me.id])
  useEffect(() => { logRef.current?.scrollTo({ top: 1e9 }) }, [msgs])

  async function send(e: React.FormEvent) {
    e.preventDefault()
    const body = text.trim()
    if (!body) return
    setText('')
    try { await api.sendMessage(channel, body); load() } catch (err) { toast((err as Error).message, 'bad') }
  }

  return (
    <Card className={`chat ${compact ? 'compact' : ''}`} title={other ? `💬 ${other}` : channel === 'global' ? 'Live Chat' : channel.startsWith('crew') ? 'Crew Chat' : channel.startsWith('table') ? 'Table Talk' : 'Cartel Chat'}>
      <div className="log" ref={logRef}>
        {!msgs && <Empty><span className="spin" /></Empty>}
        {msgs?.length === 0 && <Empty>Nobody's said anything yet.</Empty>}
        {msgs?.map(m => (
          <div key={m.id} className={`msg ${m.sender_id === me.id ? 'me' : ''}`}>
            <span className="who">{m.sender_name}</span>{m.body}<span className="when">{ago(m.created_at)}</span>
          </div>
        ))}
      </div>
      <form onSubmit={send}>
        <input className="input" placeholder="Say something…" value={text} maxLength={500} onChange={e => setText(e.target.value)} />
        <button className="btn doit" type="submit">Send</button>
      </form>
    </Card>
  )
}

function Conversations() {
  const { toast } = useGame()
  const nav = useNavigate()
  const [list, setList] = useState<Conversation[] | null>(null)
  useEffect(() => { api.conversations().then(setList).catch(e => toast(e.message, 'bad')) }, [toast])
  return (
    <Card>
      {!list && <Empty><span className="spin" /></Empty>}
      {list?.length === 0 && <Empty>No private conversations. Open a player's profile and tap Chat.</Empty>}
      {list?.map(c => (
        <div key={c.channel} className="row link" onClick={() => nav(`/chat/${c.channel}`)}>
          <div className="grow"><div className="t">{c.other}</div><div className="s">{c.last}</div></div>
          <span className="small muted">{ago(c.at)}</span>
        </div>
      ))}
    </Card>
  )
}
