import { useEffect, useState } from 'react'
import { useNavigate, useSearchParams } from 'react-router-dom'
import { useGame, useMe } from '../lib/game'
import { api } from '../lib/api'
import { ago, money, num } from '../lib/format'
import { useNow } from '../lib/useNow'
import { Card, Empty, Seg } from '../components/ui'
import type { FightLog, PlayerSummary, TopUsers } from '../lib/types'

type Tab = 'players' | 'log' | 'top'

export default function Fight() {
  const me = useMe()
  const [sp, setSp] = useSearchParams()
  const tab = (sp.get('tab') as Tab) || 'players'
  return (
    <div className="page">
      <Seg value={tab} onChange={t => setSp({ tab: t })} options={[{ v: 'players', l: 'Players' }, { v: 'log', l: 'My Fights' }, { v: 'top', l: 'Top Users' }]} />
      {me.jailed && <div className="notice red">You fight with your jail setup while locked up.</div>}
      {tab === 'players' && <Players />}
      {tab === 'log' && <Log />}
      {tab === 'top' && <Top />}
    </div>
  )
}

function Players() {
  const { toast } = useGame()
  const nav = useNavigate()
  const now = useNow(10_000)
  const [q, setQ] = useState('')
  const [list, setList] = useState<PlayerSummary[] | null>(null)
  useEffect(() => {
    const t = setTimeout(() => api.findPlayers(q).then(setList).catch(e => toast(e.message, 'bad')), 200)
    return () => clearTimeout(t)
  }, [q, toast])
  return (
    <>
      <input className="input" placeholder="Search by name…" value={q} onChange={e => setQ(e.target.value)} />
      <Card>
        {!list && <Empty><span className="spin" /></Empty>}
        {list?.length === 0 && <Empty>Nobody's around. Quiet city.</Empty>}
        {list?.map(p => (
          <div key={p.id} className="row link" onClick={() => nav(`/player/${p.id}`)}>
            <span style={{ fontSize: 20, width: 26, textAlign: 'center' }}>{p.avatar}</span>
            <div className="grow">
              <div className="t">{p.name} {p.crew && <span className="muted small">{p.crew.emblem} {p.crew.name}</span>}</div>
              <div className="s">{p.fights_won}W · {p.fights - p.fights_won}L · seen {ago(p.last_seen, now)}</div>
            </div>
            {p.hospital && <span className="pill red">🏥</span>}
            {p.jailed && <span className="pill red">🔒</span>}
            {p.immune && <span className="pill blue">🛡</span>}
            <span className="chev">›</span>
          </div>
        ))}
      </Card>
    </>
  )
}

function Log() {
  const { toast } = useGame()
  const nav = useNavigate()
  const now = useNow(10_000)
  const [list, setList] = useState<FightLog[] | null>(null)
  useEffect(() => { api.fights().then(setList).catch(e => toast(e.message, 'bad')) }, [toast])
  return (
    <Card>
      {!list && <Empty><span className="spin" /></Empty>}
      {list?.length === 0 && <Empty>No fights yet.</Empty>}
      {list?.map(f => {
        const other = f.i_attacked ? f.defender : f.attacker
        const otherId = f.i_attacked ? f.defender_id : f.attacker_id
        return (
          <div key={f.id} className="row link" onClick={() => nav(`/player/${otherId}`)}>
            <span style={{ fontSize: 18 }}>{f.won ? '🏆' : '💀'}</span>
            <div className="grow">
              <div className="t">{f.i_attacked ? `You attacked ${other}` : `${other} attacked you`}</div>
              <div className="s">{f.won ? 'Won' : 'Lost'} · dealt {f.i_attacked ? f.attacker_dmg : f.defender_dmg}, took {f.i_attacked ? f.defender_dmg : f.attacker_dmg} · {ago(f.at, now)}</div>
            </div>
            <b className={`tabular ${f.won ? 'gold' : 'red'}`}>{f.won ? '+' : '−'}{money(f.cash)}</b>
          </div>
        )
      })}
    </Card>
  )
}

function Top() {
  const { toast } = useGame()
  const nav = useNavigate()
  const [top, setTop] = useState<TopUsers | null>(null)
  useEffect(() => { api.topUsers().then(setTop).catch(e => toast(e.message, 'bad')) }, [toast])
  if (!top) return <Empty><span className="spin" /></Empty>
  const board = (title: string, rows: { id: string; name: string; value: number; emblem?: string }[], fmt: (n: number) => string, link: (id: string) => string) => (
    <Card title={title}>
      {(rows ?? []).length === 0 && <Empty>—</Empty>}
      {(rows ?? []).map((r, i) => (
        <div key={r.id} className="row link" onClick={() => nav(link(r.id))}>
          <span className="muted tabular" style={{ width: 22 }}>{i + 1}.</span>
          <div className="grow t">{r.emblem ? r.emblem + ' ' : ''}{r.name}</div>
          <b className="tabular">{fmt(r.value)}</b>
        </div>
      ))}
    </Card>
  )
  return (
    <>
      {board('Top Fighters', top.fighters, n => `${num(n)} wins`, id => `/player/${id}`)}
      {board('Top Hustlers', top.hustlers, n => `${num(n)} actions`, id => `/player/${id}`)}
      {board('Top Traders', top.traders, n => money(n), id => `/player/${id}`)}
      {board('Top Crews', top.crews, n => `${num(n)} blocks`, id => `/crew/${id}`)}
    </>
  )
}
