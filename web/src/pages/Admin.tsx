import { useCallback, useEffect, useState } from 'react'
import { useSearchParams } from 'react-router-dom'
import { useGame, useMe } from '../lib/game'
import { api } from '../lib/api'
import { ago } from '../lib/format'
import { Btn, Card, Empty, Seg } from '../components/ui'
import { PlayerLink } from '../components/Linked'
import { BackBar } from '../components/BackBar'
import type { BannedWord, ModAction, ModLogEntry, ModQueueItem, WordMatch } from '../lib/types'

type Tab = 'reports' | 'log' | 'words'

const reasonLabel: Record<string, string> = { name: 'Name', avatar: 'Avatar', bio: 'Bio', other: 'Other' }
const actionLabel: Record<string, string> = {
  reset_name: 'reset the name of', reset_avatar: 'reset the avatar of', clear_bio: 'cleared the bio of', dismiss: 'dismissed reports on',
  add_word: 'added a filter word', remove_word: 'removed a filter word',
}
const matchLabel: Record<WordMatch, string> = { squash: 'Anywhere', part: 'Inside a word', word: 'Whole word' }
const matchHelp: Record<WordMatch, string> = {
  squash: 'even split up by spaces or dots (f.u.c.k) — for the worst words',
  part: 'inside any one word (SH1THEAD) — careful, catches longer words that contain it',
  word: 'only on its own (Big Ass), so Assassin and Classic are fine',
}

/** Admin tools: reported profiles, the moderation log and the word filter. */
export default function Admin() {
  const me = useMe()
  const [sp, setSp] = useSearchParams()
  const tab = (sp.get('tab') as Tab) || 'reports'
  if (!me.is_admin) return <div className="page"><BackBar fallback="/" /><Empty>Admins only.</Empty></div>
  return (
    <div className="page">
      <BackBar fallback="/" />
      <Seg value={tab} onChange={t => setSp({ tab: t })} options={[{ v: 'reports', l: `Reports${me.reports_open ? ` (${me.reports_open})` : ''}` }, { v: 'log', l: 'Log' }, { v: 'words', l: 'Word Filter' }]} />
      {tab === 'reports' && <Reports />}
      {tab === 'log' && <Log />}
      {tab === 'words' && <Words />}
    </div>
  )
}

/** The three resets, with a confirm — shared by the queue and a player's profile. */
export function ModButtons({ id, name, onDone, dismiss }: { id: string; name: string; onDone: () => void; dismiss?: boolean }) {
  const { run } = useGame()
  const act = (action: ModAction, ask: string, ok: string) => async () => {
    if (!confirm(ask)) return
    const r = await run(() => api.modAction(id, action), { ok: () => ok })
    if (r) onDone()
  }
  return (
    <div className="hstack mod-buttons">
      <Btn className="sm red" onClick={act('reset_name', `Reset ${name}'s name? They get a placeholder and pick a new one.`, `${name}'s name reset — they'll pick a new one`)}>Reset name</Btn>
      <Btn className="sm" onClick={act('reset_avatar', `Reset ${name}'s avatar to 🕶️?`, 'Avatar reset')}>Reset avatar</Btn>
      <Btn className="sm" onClick={act('clear_bio', `Clear ${name}'s bio?`, 'Bio cleared')}>Clear bio</Btn>
      {dismiss && <Btn className="sm ghost" onClick={act('dismiss', `Dismiss the reports on ${name}? Nothing on their profile changes.`, 'Reports dismissed')}>Dismiss</Btn>}
    </div>
  )
}

function Reports() {
  const { toast } = useGame()
  const [q, setQ] = useState<ModQueueItem[] | null>(null)
  const load = useCallback(() => api.modQueue().then(setQ).catch(e => toast(e.message, 'bad')), [toast])
  useEffect(() => { load() }, [load])
  if (!q) return <Empty><span className="spin" /></Empty>
  if (q.length === 0) return <Card><Empty>No open reports. 🎉</Empty></Card>
  return (
    <>
      {q.map(t => (
        <Card key={t.id} className="mod-item" title={<><span style={{ fontSize: 20 }}>{t.avatar}</span> <PlayerLink id={t.id}>{t.name}</PlayerLink></>}
              right={<small>{t.reports.length} report{t.reports.length > 1 ? 's' : ''}</small>}>
          <div className="bd stack">
            {t.rename_pending && <div className="small muted">Name already reset — waiting for them to pick a new one.</div>}
            {t.bio ? <div className="small" style={{ fontStyle: 'italic' }}>“{t.bio}”</div> : <div className="small muted">No bio.</div>}
            <div className="stack" style={{ gap: 6 }}>
              {t.reports.map(r => (
                <div key={r.id} className="mod-report small">
                  <span className="pill red">{reasonLabel[r.reason]}</span>{' '}
                  {r.note ? <>“{r.note}”</> : <span className="muted">no note</span>}
                  <span className="muted"> · {r.reporter ? <PlayerLink id={r.reporter_id}>{r.reporter}</PlayerLink> : 'someone'} · {ago(r.at)}</span>
                  {r.snapshot?.name && r.snapshot.name !== t.name && <div className="muted">Name then: {r.snapshot.name}</div>}
                  {r.snapshot?.avatar && r.snapshot.avatar !== t.avatar && <div className="muted">Avatar then: {r.snapshot.avatar}</div>}
                  {r.snapshot?.bio && r.snapshot.bio !== t.bio && <div className="muted">Bio then: “{r.snapshot.bio}”</div>}
                </div>
              ))}
            </div>
            <ModButtons id={t.id} name={t.name} onDone={load} dismiss />
          </div>
        </Card>
      ))}
    </>
  )
}

function Log() {
  const { toast } = useGame()
  const [log, setLog] = useState<ModLogEntry[] | null>(null)
  useEffect(() => { api.modLog(100).then(setLog).catch(e => toast(e.message, 'bad')) }, [toast])
  if (!log) return <Empty><span className="spin" /></Empty>
  return (
    <Card title="Moderation log" right={<small>newest first</small>}>
      {log.length === 0 && <Empty>Nothing yet.</Empty>}
      {log.map(l => (
        <div key={l.id} className="row">
          <div className="grow">
            <div className="t2 small">
              <b>{l.admin ?? 'An admin'}</b> {actionLabel[l.action]}{' '}
              {l.target_id ? <PlayerLink id={l.target_id} className="strong">{l.target}</PlayerLink> : null}
              {(l.action === 'add_word' || l.action === 'remove_word') && <b> {l.new ?? l.old}</b>}
              {l.action !== 'add_word' && l.action !== 'remove_word' && l.old ? <span className="muted"> (was “{l.old}”)</span> : null}
            </div>
            <div className="s">{ago(l.at)}{l.reports ? ` · closed ${l.reports} report${l.reports > 1 ? 's' : ''}` : ''}</div>
          </div>
        </div>
      ))}
    </Card>
  )
}

function Words() {
  const { run, toast } = useGame()
  const [words, setWords] = useState<BannedWord[] | null>(null)
  const [word, setWord] = useState('')
  const [how, setHow] = useState<WordMatch>('word')
  useEffect(() => { api.modWords().then(setWords).catch(e => toast(e.message, 'bad')) }, [toast])
  if (!words) return <Empty><span className="spin" /></Empty>
  return (
    <>
      <Card title="Add a word">
        <div className="bd stack">
          <div className="small muted">New names, avatars and bios can't contain these. Swaps like 0 for o or 3 for e and stretched letters (fuuuck) are caught too. Existing names aren't changed.</div>
          <input className="input" placeholder="word" maxLength={30} value={word} onChange={e => setWord(e.target.value.toLowerCase().replace(/[^a-z]/g, ''))} />
          <Seg value={how} onChange={setHow} options={(['word', 'part', 'squash'] as const).map(v => ({ v, l: matchLabel[v] }))} />
          <div className="small muted">{matchLabel[how]}: {matchHelp[how]}.</div>
          <Btn className="doit block" disabled={word.length < 2} onClick={async () => { const r = await run(() => api.modWords('add', word, how), { ok: () => `“${word}” added` }); if (r) { setWords(r); setWord('') } }}>Add Word</Btn>
        </div>
      </Card>
      {(['squash', 'part', 'word'] as const).map(m => (
        <Card key={m} title={matchLabel[m]} right={<small>{words.filter(w => w.match === m).length}</small>}>
          <div className="bd hstack word-list">
            {words.filter(w => w.match === m).map(w => (
              <span key={w.word} className="pill word-pill">{w.word}
                <button className="x" aria-label={`Remove ${w.word}`} onClick={async () => { if (!confirm(`Remove “${w.word}” from the filter?`)) return; const r = await run(() => api.modWords('remove', w.word), { ok: () => `“${w.word}” removed` }); if (r) setWords(r) }}>×</button>
              </span>
            ))}
          </div>
        </Card>
      ))}
    </>
  )
}
