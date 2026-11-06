import { useState } from 'react'
import { Link } from 'react-router-dom'
import { useGame, useMe } from '../lib/game'
import { api } from '../lib/api'
import { ago, num } from '../lib/format'
import { Btn, Card, Empty, Loading, Seg } from '../components/ui'
import { PlayerLink } from '../components/Linked'
import { BackBar } from '../components/BackBar'
import { BOARDS } from './Forum'
import type { BannedWord, ModAction, ModQueueItem, ModReport, ReportKind, SeasonRow, WordMatch } from '../lib/types'
import { useLoad } from '../lib/useLoad'
import { useParam } from '../lib/useParam'
import { useNow } from '../lib/useNow'

type Tab = 'reports' | 'log' | 'words' | 'seasons'

const kindLabel: Record<ReportKind, string> = { profile: 'Profile', message: 'Message', forum_thread: 'Thread', forum_post: 'Reply' }
const reasonLabel: Record<string, string> = {
  name: 'Name', avatar: 'Avatar', bio: 'Bio', other: 'Other', harassment: 'Harassment', hate: 'Hate', spam: 'Spam', threat: 'Threat',
}
const actionLabel: Record<string, string> = {
  reset_name: 'reset the name of', reset_avatar: 'reset the avatar of', clear_bio: 'cleared the bio of', dismiss: 'dismissed reports on',
  delete_message: 'removed a message from', delete_post: 'removed a reply from', delete_thread: 'removed a thread from',
  mute_1d: 'muted', mute_7d: 'muted', mute_30d: 'muted', unmute: 'lifted the mute on',
  add_word: 'added a filter word', remove_word: 'removed a filter word', set_word: 'changed a filter word',
}
const wordActions: string[] = ['add_word', 'remove_word', 'set_word']
const muteActions: string[] = ['mute_1d', 'mute_7d', 'mute_30d', 'unmute']
// deleting what a report is about: the action, the confirm, the toast
const deleteAction: Record<Exclude<ReportKind, 'profile'>, [ModAction, string, string]> = {
  message: ['delete_message', 'Delete this message? It disappears from chat for everyone.', 'Message deleted'],
  forum_post: ['delete_post', 'Delete this reply? It shows as [deleted] in the thread.', 'Reply deleted'],
  forum_thread: ['delete_thread', 'Delete this whole thread?', 'Thread deleted'],
}
const matchLabel: Record<WordMatch, string> = { squash: 'Anywhere', part: 'Inside a word', word: 'Whole word' }
const matchHelp: Record<WordMatch, string> = {
  squash: 'even split up by spaces or dots (f.u.c.k) — for the worst words',
  part: 'inside any one word (SH1THEAD) — careful, catches longer words that contain it',
  word: 'only on its own (Big Ass), so Assassin and Classic are fine',
}
const when = (at: string) => new Date(at).toLocaleString()

/** Admin tools: reported profiles, the moderation log and the word filter. */
export default function Admin() {
  const me = useMe()
  const [tab, setTab] = useParam<Tab>('tab', ['reports', 'log', 'words', 'seasons'], 'reports')
  if (!me.is_admin) return <div className="page"><BackBar fallback="/" /><Empty>Admins only.</Empty></div>
  return (
    <div className="page">
      <BackBar fallback="/" />
      <Seg value={tab} onChange={setTab} options={[{ v: 'reports', l: `Reports${me.reports_open ? ` (${me.reports_open})` : ''}` }, { v: 'log', l: 'Log' }, { v: 'words', l: 'Word Filter' }, { v: 'seasons', l: 'Seasons' }]} />
      {tab === 'reports' && <Reports />}
      {tab === 'log' && <Log />}
      {tab === 'words' && <Words />}
      {tab === 'seasons' && <Seasons />}
    </div>
  )
}

/** The three resets and the mute ladder, each with a confirm — shared by the queue and a player's profile. */
export function ModButtons({ id, name, onDone, dismiss, mutedUntil }: { id: string; name: string; onDone: () => void; dismiss?: boolean; mutedUntil?: string | null }) {
  const { run, ask } = useGame()
  const act = (action: ModAction, question: string, ok: string) => async () => {
    if (!await ask(question, { title: `${name}: are you sure?`, yes: 'Do it', tone: 'red' })) return
    const r = await run(() => api.modAction(id, action), { ok: () => ok })
    if (r) onDone()
  }
  const mute = (action: ModAction, span: string) =>
    act(action, `Mute ${name} for ${span}? They can't chat, post in the forum or change their bio until then.`, `${name} is muted for ${span}`)
  const muted = !!mutedUntil   // the server only sends a mute that hasn't ended
  return (
    <div className="stack" style={{ gap: 6 }}>
      <div className="hstack mod-buttons">
        <Btn className="sm red" onClick={act('reset_name', `Reset ${name}'s name? They get a placeholder and pick a new one.`, `${name}'s name reset — they'll pick a new one`)}>Reset Name</Btn>
        <Btn className="sm" onClick={act('reset_avatar', `Reset ${name}'s avatar to 🕶️?`, 'Avatar reset')}>Reset Avatar</Btn>
        <Btn className="sm" onClick={act('clear_bio', `Clear ${name}'s bio?`, 'Bio cleared')}>Clear Bio</Btn>
        {dismiss && <Btn className="sm ghost" onClick={act('dismiss', `Dismiss the reports on ${name}? Nothing on their profile changes.`, 'Reports dismissed')}>Dismiss</Btn>}
      </div>
      <div className="hstack mod-buttons">
        {muted && <span className="k">Muted until {when(mutedUntil!)}</span>}
        <Btn className="sm" onClick={mute('mute_1d', 'a day')}>Mute 1d</Btn>
        <Btn className="sm" onClick={mute('mute_7d', 'a week')}>Mute 7d</Btn>
        <Btn className="sm" onClick={mute('mute_30d', '30 days')}>Mute 30d</Btn>
        {muted && <Btn className="sm ghost" onClick={act('unmute', `Lift ${name}'s mute? They can chat and post again.`, `${name} can talk again`)}>Unmute</Btn>}
      </div>
    </div>
  )
}

/** Where a reported message, thread or reply was. */
function Where({ r }: { r: ModReport }) {
  const s = r.snapshot
  if (r.kind === 'message') {
    const ch = s.channel ?? ''
    return <>in {ch === 'global' ? 'Live Chat' : ch.startsWith('crew:') ? 'crew chat' : ch.startsWith('cartel:') ? 'cartel chat' : ch.startsWith('table:') ? 'table talk' : 'a DM'}</>
  }
  // a thread: its board; a reply: its thread's title. Linked while it's still up.
  const tid = r.kind === 'forum_thread' ? r.ref_id : s.thread_id
  const label = r.kind === 'forum_post' ? `“${s.title}”` : BOARDS.find(b => b.key === s.category)?.name ?? 'the forum'
  return <>{r.kind === 'forum_post' ? 'a reply in ' : 'in '}{r.live && tid ? <Link to={`/forum/t/${tid}`}>{label}</Link> : label}</>
}

function Reports() {
  const { run, ask } = useGame()
  const { data: q, error, reload: load } = useLoad(() => api.modQueue())
  const remove = (t: ModQueueItem, r: ModReport) => async () => {
    const [action, question, ok] = deleteAction[r.kind as Exclude<ReportKind, 'profile'>]
    if (!await ask(question, { title: 'Delete it?', yes: 'Delete', tone: 'red' })) return
    if (await run(() => api.modAction(t.id, action, r.ref_id!), { ok: () => ok })) load()
  }
  if (!q) return <Loading error={error} onRetry={load} />
  if (q.length === 0) return <Card><Empty>No open reports.</Empty></Card>
  return (
    <>
      {q.map(t => (
        <Card key={t.id} className="mod-item" title={<><span style={{ fontSize: 20 }}>{t.avatar}</span> <PlayerLink id={t.id}>{t.name}</PlayerLink></>}
              right={<small>{t.reports.length} report{t.reports.length > 1 ? 's' : ''}</small>}>
          <div className="bd stack">
            {t.rename_pending && <div className="small muted">Name already reset — waiting for them to pick a new one.</div>}
            {t.reports.some(r => r.kind === 'profile') && (t.bio ? <div className="small" style={{ fontStyle: 'italic' }}>“{t.bio}”</div> : <div className="small muted">No bio.</div>)}
            <div className="stack" style={{ gap: 6 }}>
              {t.reports.map(r => (
                <div key={r.id} className="mod-report small">
                  <span className="pill">{kindLabel[r.kind]}</span>{' '}<span className="pill red">{reasonLabel[r.reason]}</span>{' '}
                  {r.note ? <>“{r.note}”</> : <span className="muted">no note</span>}
                  <span className="muted"> · {r.reporter ? <PlayerLink id={r.reporter_id}>{r.reporter}</PlayerLink> : 'someone'} · {ago(r.at)}</span>
                  {r.kind === 'profile' ? <>
                    {r.snapshot?.name && r.snapshot.name !== t.name && <div className="muted">Name then: {r.snapshot.name}</div>}
                    {r.snapshot?.avatar && r.snapshot.avatar !== t.avatar && <div className="muted">Avatar then: {r.snapshot.avatar}</div>}
                    {r.snapshot?.bio && r.snapshot.bio !== t.bio && <div className="muted">Bio then: “{r.snapshot.bio}”</div>}
                  </> : (
                    <div className="stack" style={{ gap: 4, marginTop: 4 }}>
                      <div className="muted"><Where r={r} /></div>
                      {r.kind === 'forum_thread' && r.snapshot.title && <b>{r.snapshot.title}</b>}
                      <div className="report-quote">“{r.text}”</div>
                      {r.live ? <div><Btn className="sm red" onClick={remove(t, r)}>Delete</Btn></div> : <div className="muted">Already removed.</div>}
                    </div>
                  )}
                </div>
              ))}
            </div>
            <ModButtons id={t.id} name={t.name} onDone={load} dismiss mutedUntil={t.muted_until} />
          </div>
        </Card>
      ))}
    </>
  )
}

function Log() {
  const { data: log, error, reload } = useLoad(() => api.modLog(100))
  if (!log) return <Loading error={error} onRetry={reload} />
  return (
    <Card title="Moderation log" right={<small>newest first</small>}>
      {log.length === 0 && <Empty>Nothing yet.</Empty>}
      {log.map(l => (
        <div key={l.id} className="row">
          <div className="grow">
            <div className="t2 small">
              <b>{l.admin ?? 'An admin'}</b> {actionLabel[l.action]}{' '}
              {l.target_id ? <PlayerLink id={l.target_id} className="strong">{l.target}</PlayerLink> : null}
              {wordActions.includes(l.action) && <b> {l.new ?? l.old}</b>}
              {muteActions.includes(l.action) && l.new && <span className="muted"> until {when(l.new)}</span>}
              {!wordActions.includes(l.action) && !muteActions.includes(l.action) && l.old ? <span className="muted"> (was “{l.old}”)</span> : null}
            </div>
            <div className="s">{ago(l.at)}{l.reports ? ` · closed ${l.reports} report${l.reports > 1 ? 's' : ''}` : ''}</div>
          </div>
        </div>
      ))}
    </Card>
  )
}

function Words() {
  const { run, ask } = useGame()
  const [word, setWord] = useState('')
  const [how, setHow] = useState<WordMatch>('word')
  const [chat, setChat] = useState(true)
  const { data: words, error, reload, set: setWords } = useLoad(() => api.modWords())
  if (!words) return <Loading error={error} onRetry={reload} />
  // Every word carries the chat switch: on, it also blocks chat messages and forum posts (matched the word's own way).
  const flipChat = (w: BannedWord) => async () => {
    if (!await ask(w.chat ? `Let “${w.word}” through in chat and forum posts? It still guards names, bios and titles.` : `Block “${w.word}” in chat and forum posts too?`, { title: 'Change the chat filter?', yes: w.chat ? 'Let it through' : 'Block it' })) return
    const r = await run(() => api.modWords('chat', w.word), { ok: () => (w.chat ? `“${w.word}” no longer blocks chat` : `“${w.word}” now blocks chat`) })
    if (r) setWords(r)
  }
  return (
    <>
      <Card title="Add a word">
        <div className="bd stack">
          <div className="small muted">New player, crew and cartel names, avatars, bios and forum titles can't contain these. Swaps like 0 for o or 3 for e and stretched letters (fuuuck) are caught too. Existing names aren't changed.</div>
          <div className="small muted">Words marked chat also block chat and forum posts; the rest only guard names, bios and titles.</div>
          <input className="input" placeholder="word" maxLength={30} value={word} onChange={e => setWord(e.target.value.toLowerCase().replace(/[^a-z]/g, ''))} />
          <Seg value={how} onChange={setHow} options={(['word', 'part', 'squash'] as const).map(v => ({ v, l: matchLabel[v] }))} />
          <div className="small muted">{matchLabel[how]}: {matchHelp[how]}.</div>
          <label className="toggle small"><input type="checkbox" checked={chat} onChange={e => setChat(e.target.checked)} /> Chat — also blocks chat and forum posts</label>
          <Btn className="doit block" disabled={word.length < 2} onClick={async () => { const r = await run(() => api.modWords('add', word, how, chat), { ok: () => `“${word}” added` }); if (r) { setWords(r); setWord('') } }}>Add Word</Btn>
        </div>
      </Card>
      {(['squash', 'part', 'word'] as const).map(m => (
        <Card key={m} title={matchLabel[m]} right={<small>{words.filter(w => w.match === m).length}</small>}>
          <div className="bd hstack word-list">
            {words.filter(w => w.match === m).map(w => (
              <span key={w.word} className="pill word-pill">{w.word}
                <button className={`chat-tag${w.chat ? '' : ' off'}`} aria-pressed={w.chat} aria-label={`Chat ${w.chat ? 'on' : 'off'} for ${w.word}`} onClick={flipChat(w)}>chat</button>
                <button className="x" aria-label={`Remove ${w.word}`} onClick={async () => { if (!await ask(`Names, bios, titles and chat can use “${w.word}” again.`, { title: `Remove “${w.word}”?`, yes: 'Remove', tone: 'red' })) return; const r = await run(() => api.modWords('remove', w.word), { ok: () => `“${w.word}” removed` }); if (r) setWords(r) }}>×</button>
              </span>
            ))}
          </div>
        </Card>
      ))}
    </>
  )
}

// ---------------------------------------------------------------------------------------------------------------------
// Seasons: the one running, the next one scheduled, the ones over (docs/seasons.md is the runbook)
// ---------------------------------------------------------------------------------------------------------------------
const DEFENDERS = '12, 22, 32, 45, 60, 75, 95'
const day = (iso: string) => new Date(iso).toLocaleDateString(undefined, { month: 'short', day: 'numeric', year: 'numeric' })
/** A datetime-local value (local time, to the minute) for an instant. */
const local = (d: Date) => { const p = (n: number) => String(n).padStart(2, '0'); return `${d.getFullYear()}-${p(d.getMonth() + 1)}-${p(d.getDate())}T${p(d.getHours())}:${p(d.getMinutes())}` }
const parseDefenders = (s: string) => s.split(/[\s,·]+/).filter(Boolean).map(Number)

function SeasonLine({ s }: { s: SeasonRow }) {
  return (
    <>
      <div className="small muted">{day(s.starts_at)} – {day(s.ends_at)} · {num(s.players)} player{s.players === 1 ? '' : 's'} with a hood · {num(s.bosses)} took the boss</div>
      <div className="hstack wrap">{s.businesses.map((b, i) => <span key={b.code} className="pill"><span aria-hidden>{b.icon}</span> {i + 1} · {b.name}</span>)}</div>
      <div className="small muted tabular">Defenders {s.defenders.slice(0, 6).join(' · ')} · boss {s.defenders[6]}</div>
    </>
  )
}

function Seasons() {
  const { run, ask } = useGame()
  const now = useNow(30_000)
  const { data: list, error, reload, set } = useLoad(() => api.seasonList())
  const running = list?.find(s => s.status === 'running')
  const scheduled = list?.find(s => s.status === 'scheduled')
  const [name, setName] = useState('')
  const [from, setFrom] = useState('')
  const [months, setMonths] = useState(3)
  const [defs, setDefs] = useState(DEFENDERS)
  if (!list) return <Loading error={error} onRetry={reload} />
  const nextName = name || `Season ${list.filter(s => s.status !== 'cancelled').length + 1}`
  // the next season starts the moment this one ends (to the second, so the two never overlap), unless the form says otherwise
  const fromAt = from ? new Date(from) : running ? new Date(running.ends_at) : new Date(now)
  const fromValue = from || local(fromAt)
  const startsNow = fromAt.getTime() <= now + 60_000
  const defenders = parseDefenders(defs)
  const defsOk = defenders.length === 7 && defenders.every(n => Number.isInteger(n) && n > 0)
  const start = async () => {
    const when = startsNow ? 'now' : `on ${day(fromAt.toISOString())}`
    if (!await ask(`${startsNow ? 'Start' : 'Schedule'} ${nextName} ${when}? Six businesses are drawn at random; every player gets a fresh hood and Marcus starts over. Nobody's cash, gear or crew changes.`, { title: `${startsNow ? 'Start' : 'Schedule'} ${nextName}?`, yes: startsNow ? 'Start It' : 'Schedule It', tone: 'gold' })) return
    const r = await run(() => api.seasonStart(nextName, (startsNow ? new Date() : fromAt).toISOString(), months, defenders), { ok: () => `${nextName} ${startsNow ? 'is on' : 'scheduled'}` })
    if (r) { setName(''); setFrom(''); reload() }
  }
  const end = async (s: SeasonRow) => {
    if (!await ask(`End ${s.name} now? Hoods and campaign progress stop counting from this moment; profiles, cash and gear are untouched. ${scheduled ? `${scheduled.name} will take over when its date comes.` : 'With nothing scheduled the city plays with no season (every tab open) until the next one starts.'}`, { title: `End ${s.name}?`, yes: 'End It', tone: 'red' })) return
    const r = await run(() => api.seasonEnd(s.id), { ok: () => `${s.name} is over` })
    if (r) reload()
  }
  const cancel = async (s: SeasonRow) => {
    if (!await ask(`Cancel ${s.name}? It hasn't started; nothing else changes.`, { title: `Cancel ${s.name}?`, yes: 'Cancel It', tone: 'red' })) return
    const r = await run(() => api.seasonCancel(s.id), { ok: () => `${s.name} cancelled` })
    if (r) set(list.map(x => (x.id === s.id ? { ...x, status: 'cancelled' as const, cancelled_at: r.season.cancelled_at } : x)))
  }
  return (
    <>
      {running ? (
        <Card title={running.name} right={<small>running · ends {day(running.ends_at)}</small>} className="season-row" id="season-running">
          <div className="bd stack">
            <SeasonLine s={running} />
            <Btn className="sm ghost red" onClick={() => end(running)}>End Season Now</Btn>
          </div>
        </Card>
      ) : (
        <div className="notice blue"><span className="small">No season is running: every tab is open and Home shows Getting Started. Start one below.</span></div>
      )}
      {scheduled ? (
        <Card title={scheduled.name} right={<small>starts {day(scheduled.starts_at)}</small>} className="season-row" id="season-scheduled">
          <div className="bd stack">
            <SeasonLine s={scheduled} />
            <Btn className="sm ghost" onClick={() => cancel(scheduled)}>Cancel</Btn>
          </div>
        </Card>
      ) : (
        <Card title="Next season" id="season-next">
          <div className="bd stack">
            <div className="small muted">Starts {running ? `the moment ${running.name} ends unless you pick a time` : 'now unless you pick a time'}. The six businesses are drawn when it starts.</div>
            <label className="small stack" style={{ gap: 4 }}>Name<input className="input" placeholder={nextName} maxLength={40} value={name} onChange={e => setName(e.target.value)} /></label>
            <label className="small stack" style={{ gap: 4 }}>Starts<input className="input" type="datetime-local" value={fromValue} onChange={e => setFrom(e.target.value)} /></label>
            <label className="small stack" style={{ gap: 4 }}>Months<input className="input" type="number" min={1} max={12} value={months} onChange={e => setMonths(Math.max(1, Math.min(12, Math.floor(Number(e.target.value) || 1))))} /></label>
            <label className="small stack" style={{ gap: 4 }}>Defenders, blocks 1–6 and the boss<input className="input" value={defs} onChange={e => setDefs(e.target.value)} aria-invalid={!defsOk} /></label>
            {!defsOk && <div className="why">Seven whole numbers above zero.</div>}
            <Btn className="doit block" disabled={!defsOk || !Number.isFinite(fromAt.getTime())} onClick={start}>{startsNow ? `Start ${nextName} Now` : `Schedule ${nextName}`}</Btn>
          </div>
        </Card>
      )}
      <Card title="Past seasons" right={<small>{list.filter(s => s.status === 'over').length}</small>}>
        {list.filter(s => s.status === 'over' || s.status === 'cancelled').length === 0 && <Empty>None yet.</Empty>}
        {list.filter(s => s.status === 'over' || s.status === 'cancelled').map(s => (
          <div key={s.id} className="row">
            <div className="grow"><div className="t">{s.name}{s.status === 'cancelled' && <span className="muted"> · cancelled</span>}</div>
              <div className="s">{s.status === 'cancelled' ? `was to start ${day(s.starts_at)}` : `${day(s.starts_at)} – ${day(s.ends_at)} · ${num(s.players)} players · ${num(s.bosses)} took the boss`}</div></div>
          </div>
        ))}
      </Card>
      <div className="small muted">A rollover resets each player's hood, missions and hood perks. It never touches cash, bank, diamonds, gear, slots, crews, reputation, grow houses or territory. The old season's rows stay as history.</div>
    </>
  )
}
