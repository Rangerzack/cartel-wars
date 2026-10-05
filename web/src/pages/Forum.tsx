import { useEffect, useState } from 'react'
import { Link, useNavigate, useParams, useSearchParams } from 'react-router-dom'
import { api } from '../lib/api'
import { useGame, useMe } from '../lib/game'
import { ago } from '../lib/format'
import type { ForumAuthor, ForumCategory, ForumThread } from '../lib/types'
import { Btn, Card, Empty, Loading, Modal } from '../components/ui'
import { CrewLink, LinkedText, PlayerLink, TitleLink } from '../components/Linked'
import { BackBar } from '../components/BackBar'
import { ReportModal } from '../components/Report'
import { useNow } from '../lib/useNow'
import { useLoad } from '../lib/useLoad'
import { intParam } from '../lib/useParam'

export const BOARDS: { key: ForumCategory; icon: string; name: string; blurb: string }[] = [
  { key: 'updates', icon: '📣', name: 'Game Updates', blurb: 'Patch notes and announcements from the game team. Reply with feedback.' },
  { key: 'new_player', icon: '🌱', name: 'New Player', blurb: 'Questions, guides and help getting started.' },
  { key: 'market', icon: '💰', name: 'Market', blurb: 'Buying, selling, prices, trade offers.' },
  { key: 'general', icon: '💬', name: 'General', blurb: 'Anything about the game.' },
  { key: 'war', icon: '⚔️', name: 'War', blurb: 'Crews, cartels, turf, callouts and grudges.' },
  { key: 'off_topic', icon: '🎲', name: 'Off Topic', blurb: 'Anything else.' },
  { key: 'suggestions', icon: '💡', name: 'Suggestions', blurb: 'Ideas and requests for the game.' },
]
const board = (k: string) => BOARDS.find(b => b.key === k)
// what shows in place of a blocked player's thread or reply (the server sends it without its text)
const HIDDEN = 'Hidden — you blocked this player'
// forum rows go with a deleted account today, but an author that comes back missing reads as this rather than crashing
const DELETED = 'Deleted player'
const isBoard = (k: string | undefined): k is ForumCategory => !!k && BOARDS.some(b => b.key === k)

/** When an admin's mute ends, or null: the server refuses posts until then, so composers give way to this. */
function useMutedUntil(): string | null {
  const me = useMe()
  const now = useNow(30_000)
  return me.muted_until && new Date(me.muted_until).getTime() > now ? me.muted_until : null
}
const Muted = ({ until }: { until: string }) => <div className="notice gold">You're muted until {new Date(until).toLocaleString()}.</div>

export default function Forum() {
  const { cat, id } = useParams()
  const nav = useNavigate()
  // /forum/foo or /forum/t/abc: the URL is put right (replaced, so Back doesn't return to it)
  const bad = (id !== undefined && !Number.isInteger(Number(id))) || (cat !== undefined && !isBoard(cat))
  useEffect(() => { if (bad) nav('/forum', { replace: true }) }, [bad, nav])
  if (bad) return null
  if (id) return <ThreadView id={Number(id)} />
  if (isBoard(cat)) return <BoardView cat={cat} />
  return <Boards />
}

function Boards() {
  const nav = useNavigate()
  const { data, error, reload } = useLoad(() => api.forumCategories())
  return (
    <div className="page">
      <BackBar fallback="/" />
      <Card title="🗣 Forum" right={<small>{data?.is_admin ? 'you are an admin' : 'players talk here'}</small>}>
        {!data && <Loading error={error} onRetry={reload} />}
        {data?.categories.map(c => {
          const b = board(c.key)!
          return (
            <div key={c.key} className="row link" onClick={() => nav(`/forum/${c.key}`)}>
              <span className="ico">{b.icon}</span>
              <div className="grow">
                <div className="t"><TitleLink to={`/forum/${c.key}`}>{b.name}</TitleLink></div>
                <div className="s">{c.last ? <><LinkedText text={c.last.title} /> · {c.last.last_poster ? <LinkedText text={c.last.last_poster} /> : '—'}, {ago(c.last_post_at!)}</> : b.blurb}</div>
              </div>
              <div className="small muted tabular" style={{ textAlign: 'right' }}>{c.threads}<br />{c.threads === 1 ? 'thread' : 'threads'}</div>
            </div>
          )
        })}
      </Card>
      <div className="small muted">Be decent. Admins can pin, lock, move or remove threads. You can edit or delete your own posts.</div>
    </div>
  )
}

function BoardView({ cat }: { cat: ForumCategory }) {
  const { run } = useGame()
  const nav = useNavigate()
  const [params, setParams] = useSearchParams()
  const page = intParam(params, 'p')
  const [compose, setCompose] = useState(false)
  const [title, setTitle] = useState('')
  const [body, setBody] = useState('')
  const muted = useMutedUntil()
  const b = board(cat)!
  const { data, error, reload: load } = useLoad(() => api.forumList(cat, page), `${cat}|${page}`)

  async function post() {
    const r = await run(() => api.forumCreateThread(cat, title, body), { silent: true })
    if (r) { setCompose(false); setTitle(''); setBody(''); nav(`/forum/t/${r.id}`) }
  }
  return (
    <div className="page">
      <BackBar fallback="/forum" right={data?.can_post && !muted && <button type="button" className="btn sm doit" onClick={() => setCompose(true)}>New Thread</button>} />
      {data?.can_post && muted && <Muted until={muted} />}
      <Card title={<>{b.icon} {b.name}</>} right={<small>{data ? `${data.total} thread${data.total === 1 ? '' : 's'}` : ''}</small>}>
        {!data && <Loading error={error} onRetry={load} />}
        {data?.threads.length === 0 && <Empty>{cat === 'updates' && !data.can_post ? 'No updates posted yet.' : 'Nothing here yet — start the first thread.'}</Empty>}
        {data?.threads.map(t => (
          <div key={t.id} className="row link" onClick={() => nav(`/forum/t/${t.id}`)}>
            <div className="grow">
              {/* the title is the row's link (names in it link inside the thread); pinned and locked say so in words */}
              <div className="t">{t.pinned && <span className="pill gold xs">📌 Pinned</span>}{t.locked && <span className="pill xs">🔒 Locked</span>}<TitleLink to={`/forum/t/${t.id}`}>{t.title}</TitleLink></div>
              <div className="s">{t.author ? <PlayerLink id={t.author.id}>{t.author.avatar} {t.author.name}</PlayerLink> : DELETED}{t.author?.is_admin && <span className="pill blue" style={{ marginLeft: 4 }}>admin</span>} · {t.hidden ? <i>{HIDDEN}</i> : <LinkedText text={t.snippet} />}</div>
              <div className="s">{t.reply_count} {t.reply_count === 1 ? 'reply' : 'replies'} · last {t.last_poster ? <LinkedText text={t.last_poster} /> : t.author ? <PlayerLink id={t.author.id}>{t.author.name}</PlayerLink> : DELETED}, {ago(t.last_post_at)}</div>
            </div>
          </div>
        ))}
      </Card>
      {data && data.pages > 1 && (
        <div className="hstack" style={{ justifyContent: 'center' }}>
          <button className="btn sm" disabled={page <= 0} onClick={() => setParams({ p: String(page - 1) })}>‹ Prev</button>
          <span className="small muted">page {page + 1} of {data.pages}</span>
          <button className="btn sm" disabled={page + 1 >= data.pages} onClick={() => setParams({ p: String(page + 1) })}>Next ›</button>
        </div>
      )}
      {compose && (
        <Modal title={`New thread · ${b.name}`} onClose={() => setCompose(false)}>
          <div className="stack">
            <input className="input" placeholder="Title" maxLength={120} value={title} onChange={e => setTitle(e.target.value)} />
            <textarea className="input" rows={6} placeholder="Say your piece…" maxLength={4000} value={body} onChange={e => setBody(e.target.value)} />
            <Btn className="doit block" disabled={title.trim().length < 3 || !body.trim()} onClick={post}>Post Thread</Btn>
          </div>
        </Modal>
      )}
    </div>
  )
}

function ThreadView({ id }: { id: number }) {
  const { run, ask } = useGame()
  const nav = useNavigate()
  const [params, setParams] = useSearchParams()
  const page = intParam(params, 'p')
  const [reply, setReply] = useState('')
  const [editing, setEditing] = useState<{ kind: 'thread' | 'post'; id: number; body: string; title?: string } | null>(null)
  const [reporting, setReporting] = useState<{ kind: 'forum_thread' | 'forum_post'; id: number; author: ForumAuthor; body: string } | null>(null)
  const muted = useMutedUntil()
  const { data, error, reload: load } = useLoad(() => api.forumThread(id, page), `${id}|${page}`)
  // the server says "No such thread" for one that was deleted; anything else (a dropped connection) gets a Retry
  const gone = !data && !!error && /no such|not found|gone/i.test(error)

  async function send() {
    const r = await run(() => api.forumReply(id, reply), { silent: true })
    if (r) { setReply(''); if (r.page !== page) setParams({ p: String(r.page) }); else load() }
  }
  async function mod(action: 'pin' | 'unpin' | 'lock' | 'unlock') { if (await run(() => api.forumModerate(id, action), { silent: true })) load() }
  async function move(cat: ForumCategory) { if (await run(() => api.forumModerate(id, 'move', cat), { ok: () => `Moved to ${board(cat)!.name}` })) nav(`/forum/${cat}`) }
  async function del(kind: 'thread' | 'post', pid: number) {
    if (!await ask(kind === 'thread' ? 'Every reply goes with it. This can\'t be undone.' : 'This can\'t be undone.', { title: kind === 'thread' ? 'Delete this whole thread?' : 'Delete this reply?', yes: 'Delete', tone: 'red' })) return
    if (await run(() => api.forumDelete(kind, pid), { silent: true })) { if (kind === 'thread') nav(`/forum/${data?.thread.category ?? ''}`); else load() }
  }
  async function saveEdit() {
    if (!editing) return
    if (await run(() => api.forumEdit(editing.kind, editing.id, editing.body, editing.title), { silent: true })) { setEditing(null); load() }
  }

  if (gone) return <div className="page"><div className="notice red">That thread is gone.</div><Link to="/forum" className="btn">Back to the Forum</Link></div>
  if (!data) return <div className="page"><BackBar fallback="/forum" /><Loading error={error} onRetry={load} /></div>
  const t = data.thread, b = board(t.category)!
  return (
    <div className="page">
      <BackBar fallback={`/forum/${t.category}`} right={data.is_admin && (
        <div className="hstack">
          <button className="btn sm ghost" onClick={() => mod(t.pinned ? 'unpin' : 'pin')}>{t.pinned ? 'Unpin' : 'Pin'}</button>
          <button className="btn sm ghost" onClick={() => mod(t.locked ? 'unlock' : 'lock')}>{t.locked ? 'Unlock' : 'Lock'}</button>
          <select className="input sm" style={{ width: 'auto' }} value="" onChange={e => { if (e.target.value) move(e.target.value as ForumCategory) }}>
            <option value="">Move…</option>
            {BOARDS.filter(x => x.key !== t.category).map(x => <option key={x.key} value={x.key}>{x.name}</option>)}
          </select>
        </div>
      )} />
      {/* Back follows history, so the board this thread lives in gets its own link */}
      <div className="small muted">in <Link to={`/forum/${t.category}`}>{b.icon} {b.name}</Link></div>
      <Card>
        <div className="bd stack post">
          <h3 style={{ margin: 0 }} aria-level={2}>{t.pinned && '📌 '}{t.locked && '🔒 '}<LinkedText text={t.title} /></h3>
          <PostMeta a={t.author} at={t.created_at} edited={t.edited_at} />
          {t.hidden ? <div className="small muted">{HIDDEN}</div> : <div className="body"><LinkedText text={t.body} /></div>}
          {(t.mine || data.is_admin || !t.hidden) && (
            <div className="hstack">
              {(t.mine || data.is_admin) && !t.hidden && <button className="btn sm ghost" onClick={() => setEditing({ kind: 'thread', id: t.id, body: t.body, title: t.title })}>Edit</button>}
              {(t.mine || data.is_admin) && <button className="btn sm ghost" onClick={() => del('thread', t.id)}>Delete</button>}
              {!t.mine && !t.hidden && t.author && <button className="btn sm ghost" onClick={() => setReporting({ kind: 'forum_thread', id: t.id, author: t.author, body: `${t.title}: ${t.body}` })}>🚩 Report</button>}
            </div>
          )}
        </div>
        {data.posts.map(p => (
          <div key={p.id} className="bd stack post reply">
            <PostMeta a={p.author} at={p.created_at} edited={p.edited_at} />
            {p.deleted ? <div className="small muted"><i>[deleted]</i></div> : p.hidden ? <div className="small muted">{HIDDEN}</div> : <div className="body"><LinkedText text={p.body} /></div>}
            {!p.deleted && (p.mine || data.is_admin || !p.hidden) && (
              <div className="hstack">
                {(p.mine || data.is_admin) && !p.hidden && <button className="btn sm ghost" onClick={() => setEditing({ kind: 'post', id: p.id, body: p.body ?? '' })}>Edit</button>}
                {(p.mine || data.is_admin) && <button className="btn sm ghost" onClick={() => del('post', p.id)}>Delete</button>}
                {!p.mine && !p.hidden && p.author && <button className="btn sm ghost" onClick={() => setReporting({ kind: 'forum_post', id: p.id, author: p.author, body: p.body ?? '' })}>🚩 Report</button>}
              </div>
            )}
          </div>
        ))}
      </Card>
      {data.pages > 1 && (
        <div className="hstack" style={{ justifyContent: 'center' }}>
          <button className="btn sm" disabled={page <= 0} onClick={() => setParams({ p: String(page - 1) })}>‹ Prev</button>
          <span className="small muted">page {page + 1} of {data.pages}</span>
          <button className="btn sm" disabled={page + 1 >= data.pages} onClick={() => setParams({ p: String(page + 1) })}>Next ›</button>
        </div>
      )}
      {muted ? <Muted until={muted} /> : data.can_reply ? (
        <Card title="Reply">
          <div className="bd stack">
            <textarea className="input" rows={4} placeholder="Write a reply…" maxLength={4000} value={reply} onChange={e => setReply(e.target.value)} />
            <Btn className="doit" disabled={!reply.trim()} onClick={send}>Post Reply</Btn>
          </div>
        </Card>
      ) : <div className="notice gold">🔒 This thread is locked.</div>}
      {editing && (
        <Modal title={editing.kind === 'thread' ? 'Edit thread' : 'Edit reply'} onClose={() => setEditing(null)}>
          <div className="stack">
            {editing.kind === 'thread' && <input className="input" maxLength={120} value={editing.title} onChange={e => setEditing({ ...editing, title: e.target.value })} />}
            <textarea className="input" rows={6} maxLength={4000} value={editing.body} onChange={e => setEditing({ ...editing, body: e.target.value })} />
            <Btn className="gold block" disabled={!editing.body.trim()} onClick={saveEdit}>Save</Btn>
          </div>
        </Modal>
      )}
      {reporting && <ReportModal kind={reporting.kind} id={reporting.author.id} name={reporting.author.name} refId={reporting.id} quote={reporting.body} onClose={() => setReporting(null)} />}
    </div>
  )
}

function PostMeta({ a, at, edited }: { a: ForumThread['thread']['author'] | null; at: string; edited: string | null }) {
  return (
    <div className="small muted hstack" style={{ gap: 6 }}>
      {a ? <PlayerLink id={a.id} className="strong">{a.avatar} {a.name}</PlayerLink> : <span className="strong">{DELETED}</span>}
      {a?.is_admin && <span className="pill blue">admin</span>}
      {a?.crew && <CrewLink id={a.crew.id}>{a.crew.emblem} {a.crew.name}</CrewLink>}
      <span>· {ago(at)}{edited ? ' · edited' : ''}</span>
    </div>
  )
}
