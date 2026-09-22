import { useCallback, useEffect, useState } from 'react'
import { Link, useNavigate, useParams, useSearchParams } from 'react-router-dom'
import { api } from '../lib/api'
import { useGame } from '../lib/game'
import { ago } from '../lib/format'
import type { ForumCategories, ForumCategory, ForumList, ForumThread } from '../lib/types'
import { Card, Empty, Modal } from '../components/ui'

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
const isBoard = (k: string | undefined): k is ForumCategory => !!k && BOARDS.some(b => b.key === k)

export default function Forum() {
  const { cat, id } = useParams()
  if (id) return <ThreadView id={Number(id)} />
  if (isBoard(cat)) return <BoardView cat={cat} />
  return <Boards />
}

function Boards() {
  const { toast } = useGame()
  const nav = useNavigate()
  const [data, setData] = useState<ForumCategories | null>(null)
  useEffect(() => { api.forumCategories().then(setData).catch(e => toast(e.message, 'bad')) }, [toast])
  return (
    <div className="page">
      <Card title="🗣 Forum" right={<small>{data?.is_admin ? 'you are an admin' : 'players talk here'}</small>}>
        {!data && <Empty><span className="spin" /></Empty>}
        {data?.categories.map(c => {
          const b = board(c.key)!
          return (
            <div key={c.key} className="row link" onClick={() => nav(`/forum/${c.key}`)}>
              <span style={{ fontSize: 22, width: 30, textAlign: 'center' }}>{b.icon}</span>
              <div className="grow">
                <div className="t">{b.name}</div>
                <div className="s">{c.last ? <>{c.last.title} · {c.last.last_poster ?? '—'}, {ago(c.last_post_at!)}</> : b.blurb}</div>
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
  const { toast, run } = useGame()
  const nav = useNavigate()
  const [params, setParams] = useSearchParams()
  const page = Number(params.get('p') ?? 0)
  const [data, setData] = useState<ForumList | null>(null)
  const [compose, setCompose] = useState(false)
  const [title, setTitle] = useState('')
  const [body, setBody] = useState('')
  const b = board(cat)!
  const load = useCallback(() => api.forumList(cat, page).then(setData).catch(e => toast(e.message, 'bad')), [cat, page, toast])
  useEffect(() => { load() }, [load])

  async function post() {
    const r = await run(() => api.forumCreateThread(cat, title, body), { silent: true })
    if (r) { setCompose(false); setTitle(''); setBody(''); nav(`/forum/t/${r.id}`) }
  }
  return (
    <div className="page">
      <div className="hstack" style={{ justifyContent: 'space-between' }}>
        <Link to="/forum" className="small">‹ All boards</Link>
        {data?.can_post && <button className="btn sm gold" onClick={() => setCompose(true)}>New thread</button>}
      </div>
      <Card title={<>{b.icon} {b.name}</>} right={<small>{data ? `${data.total} thread${data.total === 1 ? '' : 's'}` : ''}</small>}>
        {!data && <Empty><span className="spin" /></Empty>}
        {data?.threads.length === 0 && <Empty>{cat === 'updates' && !data.can_post ? 'No updates posted yet.' : 'Nothing here yet — start the first thread.'}</Empty>}
        {data?.threads.map(t => (
          <div key={t.id} className="row link" onClick={() => nav(`/forum/t/${t.id}`)}>
            <div className="grow">
              <div className="t">{t.pinned && <span title="Pinned">📌 </span>}{t.locked && <span title="Locked">🔒 </span>}{t.title}</div>
              <div className="s">{t.author.avatar} {t.author.name}{t.author.is_admin && <span className="pill blue" style={{ marginLeft: 4 }}>admin</span>} · {t.snippet}</div>
              <div className="s">{t.reply_count} {t.reply_count === 1 ? 'reply' : 'replies'} · last {t.last_poster ?? t.author.name}, {ago(t.last_post_at)}</div>
            </div>
          </div>
        ))}
      </Card>
      {data && data.pages > 1 && (
        <div className="hstack" style={{ justifyContent: 'center' }}>
          <button className="btn sm" disabled={page <= 0} onClick={() => setParams({ p: String(page - 1) })}>‹ Newer</button>
          <span className="small muted">page {page + 1} of {data.pages}</span>
          <button className="btn sm" disabled={page + 1 >= data.pages} onClick={() => setParams({ p: String(page + 1) })}>Older ›</button>
        </div>
      )}
      {compose && (
        <Modal title={`New thread · ${b.name}`} onClose={() => setCompose(false)}>
          <div className="stack">
            <input className="input" placeholder="Title" maxLength={120} value={title} onChange={e => setTitle(e.target.value)} />
            <textarea className="input" rows={6} placeholder="Say your piece…" maxLength={4000} value={body} onChange={e => setBody(e.target.value)} />
            <button className="btn gold block" disabled={title.trim().length < 3 || !body.trim()} onClick={post}>Post thread</button>
          </div>
        </Modal>
      )}
    </div>
  )
}

function ThreadView({ id }: { id: number }) {
  const { toast, run } = useGame()
  const nav = useNavigate()
  const [params, setParams] = useSearchParams()
  const page = Number(params.get('p') ?? 0)
  const [data, setData] = useState<ForumThread | null>(null)
  const [reply, setReply] = useState('')
  const [editing, setEditing] = useState<{ kind: 'thread' | 'post'; id: number; body: string; title?: string } | null>(null)
  const [gone, setGone] = useState(false)
  const load = useCallback(() => api.forumThread(id, page).then(setData).catch(e => { setGone(true); toast(e.message, 'bad') }), [id, page, toast])
  useEffect(() => { load() }, [load])

  async function send() {
    const r = await run(() => api.forumReply(id, reply), { silent: true })
    if (r) { setReply(''); if (r.page !== page) setParams({ p: String(r.page) }); else load() }
  }
  async function mod(action: 'pin' | 'unpin' | 'lock' | 'unlock') { if (await run(() => api.forumModerate(id, action), { silent: true })) load() }
  async function move(cat: ForumCategory) { if (await run(() => api.forumModerate(id, 'move', cat), { ok: () => `Moved to ${board(cat)!.name}` })) nav(`/forum/${cat}`) }
  async function del(kind: 'thread' | 'post', pid: number) {
    if (!confirm(kind === 'thread' ? 'Delete this whole thread?' : 'Delete this reply?')) return
    if (await run(() => api.forumDelete(kind, pid), { silent: true })) { if (kind === 'thread') nav(`/forum/${data?.thread.category ?? ''}`); else load() }
  }
  async function saveEdit() {
    if (!editing) return
    if (await run(() => api.forumEdit(editing.kind, editing.id, editing.body, editing.title), { silent: true })) { setEditing(null); load() }
  }

  if (gone) return <div className="page"><div className="notice red">That thread is gone.</div><Link to="/forum" className="btn">Back to the forum</Link></div>
  if (!data) return <Empty><span className="spin" /></Empty>
  const t = data.thread, b = board(t.category)!
  return (
    <div className="page">
      <div className="hstack" style={{ justifyContent: 'space-between' }}>
        <Link to={`/forum/${t.category}`} className="small">‹ {b.icon} {b.name}</Link>
        {data.is_admin && (
          <div className="hstack">
            <button className="btn sm ghost" onClick={() => mod(t.pinned ? 'unpin' : 'pin')}>{t.pinned ? 'Unpin' : 'Pin'}</button>
            <button className="btn sm ghost" onClick={() => mod(t.locked ? 'unlock' : 'lock')}>{t.locked ? 'Unlock' : 'Lock'}</button>
            <select className="input sm" style={{ width: 'auto' }} value="" onChange={e => { if (e.target.value) move(e.target.value as ForumCategory) }}>
              <option value="">Move…</option>
              {BOARDS.filter(x => x.key !== t.category).map(x => <option key={x.key} value={x.key}>{x.name}</option>)}
            </select>
          </div>
        )}
      </div>
      <Card>
        <div className="bd stack post">
          <h3 style={{ margin: 0 }}>{t.pinned && '📌 '}{t.locked && '🔒 '}{t.title}</h3>
          <PostMeta a={t.author} at={t.created_at} edited={t.edited_at} />
          <div className="body">{t.body}</div>
          {(t.mine || data.is_admin) && (
            <div className="hstack">
              <button className="btn sm ghost" onClick={() => setEditing({ kind: 'thread', id: t.id, body: t.body, title: t.title })}>Edit</button>
              <button className="btn sm ghost" onClick={() => del('thread', t.id)}>Delete</button>
            </div>
          )}
        </div>
        {data.posts.map(p => (
          <div key={p.id} className="bd stack post reply">
            <PostMeta a={p.author} at={p.created_at} edited={p.edited_at} />
            {p.deleted ? <div className="small muted"><i>[deleted]</i></div> : <div className="body">{p.body}</div>}
            {!p.deleted && (p.mine || data.is_admin) && (
              <div className="hstack">
                <button className="btn sm ghost" onClick={() => setEditing({ kind: 'post', id: p.id, body: p.body ?? '' })}>Edit</button>
                <button className="btn sm ghost" onClick={() => del('post', p.id)}>Delete</button>
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
      {data.can_reply ? (
        <Card title="Reply">
          <div className="bd stack">
            <textarea className="input" rows={4} placeholder="Write a reply…" maxLength={4000} value={reply} onChange={e => setReply(e.target.value)} />
            <button className="btn doit" disabled={!reply.trim()} onClick={send}>Post reply</button>
          </div>
        </Card>
      ) : <div className="notice gold">🔒 This thread is locked.</div>}
      {editing && (
        <Modal title={editing.kind === 'thread' ? 'Edit thread' : 'Edit reply'} onClose={() => setEditing(null)}>
          <div className="stack">
            {editing.kind === 'thread' && <input className="input" maxLength={120} value={editing.title} onChange={e => setEditing({ ...editing, title: e.target.value })} />}
            <textarea className="input" rows={6} maxLength={4000} value={editing.body} onChange={e => setEditing({ ...editing, body: e.target.value })} />
            <button className="btn gold block" disabled={!editing.body.trim()} onClick={saveEdit}>Save</button>
          </div>
        </Modal>
      )}
    </div>
  )
}

function PostMeta({ a, at, edited }: { a: ForumThread['thread']['author']; at: string; edited: string | null }) {
  return (
    <div className="small muted hstack" style={{ gap: 6 }}>
      <Link to={`/player/${a.id}`} style={{ fontWeight: 600 }}>{a.avatar} {a.name}</Link>
      {a.is_admin && <span className="pill blue">admin</span>}
      {a.crew && <span>{a.crew.emblem} {a.crew.name}</span>}
      <span>· {ago(at)}{edited ? ' · edited' : ''}</span>
    </div>
  )
}
