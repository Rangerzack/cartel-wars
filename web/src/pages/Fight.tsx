import { useState } from 'react'
import { Link, useSearchParams } from 'react-router-dom'
import { useGame, useMe } from '../lib/game'
import { api } from '../lib/api'
import { ago, money, num } from '../lib/format'
import { useNow } from '../lib/useNow'
import { Card, Empty, Loading, RowLink, Seg } from '../components/ui'
import type { FighterSort, FighterStatus, StyleCode, ThugRow } from '../lib/types'
import { ComboPill, StyleLine } from '../components/Combo'
import { comboDef, comboFits, partLabel, tierName } from '../lib/combos'
import { useLoad } from '../lib/useLoad'
import { useParam } from '../lib/useParam'

type Tab = 'players' | 'thugs' | 'log' | 'combos' | 'top'

export default function Fight() {
  const me = useMe()
  const [tab, setTab] = useParam<Tab>('tab', ['players', 'thugs', 'log', 'combos', 'top'], 'players')
  return (
    <div className="page">
      <Seg value={tab} onChange={setTab} options={[{ v: 'players', l: 'Players' }, { v: 'thugs', l: 'Thugs' }, { v: 'log', l: 'My Fights' }, { v: 'combos', l: 'Combos' }, { v: 'top', l: 'Top' }]} />
      {me.jailed && tab !== 'combos' && <div className="notice red">You're locked up: you can only fight other inmates, with your jail setup.</div>}
      {tab === 'players' && <Players />}
      {tab === 'thugs' && <Thugs />}
      {tab === 'log' && <Log />}
      {tab === 'combos' && <Combos />}
      {tab === 'top' && <Top />}
    </div>
  )
}

const FILTERS: { v: FighterStatus; l: string }[] = [
  { v: 'all', l: 'All' }, { v: 'fight', l: '⚔️ Can fight' }, { v: 'online', l: '🟢 Online' },
  { v: 'hospital', l: '🏥 Hospital' }, { v: 'jail', l: '🔒 Jail' },
]
const SORTS: { v: FighterSort; l: string }[] = [
  { v: 'seen', l: 'Last seen' }, { v: 'wins', l: 'Most wins' }, { v: 'rep', l: 'Most rep' }, { v: 'name', l: 'Name' },
]
const LIMIT = 50
// the last filter and sort you picked come back next time you open the tab (this device only)
const recall = (k: string) => { try { return localStorage.getItem(`fight.${k}`) } catch { return null } }
const remember = (k: string, v: string) => { try { localStorage.setItem(`fight.${k}`, v) } catch { /* private mode */ } }

/** Everyone you could fight: search by name, filter to who you can hit right now, who's online, who's in the hospital
 *  or in jail (find_fighters counts each), and sort. The search, filter and sort live in the URL, so Back from a
 *  player's page lands on the same list. */
function Players() {
  const me = useMe()
  const now = useNow(10_000)
  const [sp, setSp] = useSearchParams()
  const q = sp.get('q') ?? ''
  const pick = <T extends string>(k: string, opts: { v: T }[], d: T): T => {
    const v = sp.get(k) ?? recall(k)
    return opts.some(o => o.v === v) ? (v as T) : d
  }
  const show = pick<FighterStatus>('show', FILTERS, 'all')
  const sort = pick<FighterSort>('sort', SORTS, 'seen')
  const set = (k: string, v: string) => setSp(prev => {
    const n = new URLSearchParams(prev)
    if (v) n.set(k, v); else n.delete(k)
    return n
  }, { replace: true })
  // while a new search is on its way the old list stays up, dimmed; a short wait folds fast typing into one search
  const { data, error, reload, stale: loading } = useLoad(
    () => new Promise(r => setTimeout(r, 200)).then(() => api.findFighters(q.trim(), show, sort, LIMIT)), `${q.trim()}|${show}|${sort}`, { keep: true })
  const list = data?.players
  const empty = q.trim()
    ? <>Nobody named like “{q.trim()}”{show !== 'all' ? ' here' : ''}.</>
    : show === 'fight' ? (me.jailed ? 'No other inmates to fight right now.' : 'Nobody you can fight right now: everyone else is laid up or locked up.')
      : show === 'online' ? 'Nobody else is online right now.'
        : show === 'hospital' ? 'Nobody\'s in the hospital.'
          : show === 'jail' ? 'Nobody\'s locked up.'
            : 'Nobody\'s around. Quiet city.'
  return (
    <>
      <div className="fight-find">
        <input className="input" type="search" placeholder="Search by name…" aria-label="Search players by name" value={q}
          onChange={e => set('q', e.target.value)} />
        <select className="input" value={sort} aria-label="Sort players" onChange={e => { set('sort', e.target.value); remember('sort', e.target.value) }}>
          {SORTS.map(o => <option key={o.v} value={o.v}>{o.l}</option>)}
        </select>
      </div>
      <nav className="chip-nav" aria-label="Show players">
        {FILTERS.map(f => (
          <button key={f.v} type="button" className={show === f.v ? 'on' : ''} aria-pressed={show === f.v}
            onClick={() => { set('show', f.v); remember('show', f.v) }}>
            {f.l}{data && <span className="n tabular">{num(data.counts[f.v] ?? 0)}</span>}
          </button>
        ))}
      </nav>
      <Card className={loading && list ? 'stale' : ''}>
        {!list && <Loading error={error} onRetry={reload} />}
        {list?.length === 0 && (
          <Empty>
            {empty}
            {show !== 'all' && <> <button type="button" className="linkbtn" onClick={() => set('show', 'all')}>Show everyone</button></>}
          </Empty>
        )}
        {list?.map(p => (
          <RowLink key={p.id} to={`/player/${p.id}`} className={p.can_fight ? '' : 'cant'}>
            <span className="ico">{p.avatar}</span>
            <div className="grow">
              <div className="t">{p.online && <span className="online-dot" title="Online now" />}{p.name} {p.crew && <span className="muted small">{p.crew.emblem} {p.crew.name}</span>}</div>
              <div className="s">{p.fights_won}W · {p.fights - p.fights_won}L · {p.online ? <span className="green">online now</span> : <>seen {ago(p.last_seen, now)}</>}</div>
            </div>
            {p.hospital && <span className="pill red nowrap">🏥 Hospital</span>}
            {p.jailed && <span className="pill red nowrap">🔒 Jail</span>}
            <span className="chev">›</span>
          </RowLink>
        ))}
      </Card>
      {list && list.length >= LIMIT && <div className="small muted center">Showing the first {LIMIT}. Search a name to find anyone else.</div>}
    </>
  )
}

/** The 200 NPC thugs, ranked by what a hit is worth to you right now: your odds × their stash × the 7.5% average take. */
function Thugs() {
  const { catalog } = useGame()
  const cfg = catalog?.config ?? {}
  const { data: list, error, reload } = useLoad(() => api.findThugs())
  const [all, setAll] = useState(false)
  if (!list) return <Card><Loading error={error} onRetry={reload} /></Card>
  const worth = (t: ThugRow) => (t.dry || t.hospital ? 0 : t.win_pct / 100 * t.stash * 0.075)
  const beatable = list.filter(t => t.win_pct >= 60)
  const shown = all ? list : [...beatable].sort((a, b) => worth(b) - worth(a)).slice(0, 30)
  const top = beatable.length ? Math.max(...beatable.map(t => t.level)) : 0
  const label = (p: number) => (p >= 80 ? ['green', 'Favored'] : p >= 60 ? ['green', 'Likely'] : p >= 40 ? ['gold', 'Coin flip'] : ['red', 'Long shot'])
  return (
    <>
      <div className="small muted">
        {beatable.length
          ? <>With your offensive setup you're favored up to about <b>Thug {top}</b>. A win takes 5–10% of the stash. Stashes refill over an hour, every thug also gets the {money(cfg.daily_cash ?? 50000)} daily cash at 00:00 UTC, and three hits on one thug in an hour dries it up for you.</>
          : <>Nobody here is an easy win yet — gear up under Items first.</>}
      </div>
      <div className="seg sm">
        <button className={!all ? 'on' : ''} onClick={() => setAll(false)}>Best paydays</button>
        <button className={all ? 'on' : ''} onClick={() => setAll(true)}>All 200</button>
      </div>
      <Card>
        {shown.length === 0 && <Empty>No thug you're likely to beat right now.</Empty>}
        {shown.map(t => {
          const [cls, l] = label(t.win_pct)
          return (
            <RowLink key={t.id} to={`/player/${t.id}`} className={`thug-row ${t.dry ? 'dry' : ''}`}>
              <span className="ico">{t.avatar}</span>
              <div className="grow">
                <div className="t">{t.name}{t.combo ? <> <ComboPill code={t.combo} /></> : null}</div>
                <div className="s"><span className={cls}>{l} · {t.win_pct >= 100 ? '>99' : t.win_pct <= 0 ? '<1' : t.win_pct}%</span> · stash {money(t.stash)}{t.dry ? ' · dry for you this hour' : t.hits ? ` · hit ${t.hits}× this hour` : ''}</div>
              </div>
              {t.hospital ? <span className="pill red">🏥</span> : <b className="tabular gold pay">~{money(worth(t))}</b>}
              <span className="chev">›</span>
            </RowLink>
          )
        })}
      </Card>
    </>
  )
}

function Log() {
  const now = useNow(10_000)
  const { data: list, error, reload } = useLoad(() => api.fights())
  return (
    <Card>
      {!list && <Loading error={error} onRetry={reload} />}
      {list?.length === 0 && <Empty>No fights yet. The <Link to="/fight?tab=thugs">Thugs tab</Link> lists easy first wins.</Empty>}
      {list?.map(f => {
        const otherId = f.i_attacked ? f.defender_id : f.attacker_id
        // a player who deleted their account has no profile to open
        const other = otherId ? (f.i_attacked ? f.defender : f.attacker) : <span className="muted">Deleted player</span>
        const body = <>
          <span style={{ fontSize: 18 }}>{f.won ? '🏆' : '💀'}</span>
          <div className="grow">
            <div className="t">{f.i_attacked ? <>You attacked {other}</> : <>{other} attacked you</>}</div>
            <div className="s">{f.won ? 'Won' : 'Lost'} · dealt {f.i_attacked ? f.attacker_dmg : f.defender_dmg}, took {f.i_attacked ? f.defender_dmg : f.attacker_dmg} · {ago(f.at, now)}</div>
            {(f.attacker_combo || f.defender_combo) && (
              <div className="s combo-vs">
                {f.i_attacked ? 'You' : 'They'} ran <ComboPill code={f.attacker_combo} /> · {f.i_attacked ? 'they' : 'you'} ran <ComboPill code={f.defender_combo} />
              </div>
            )}
          </div>
          {f.cash === 0 ? <span className="tabular muted">$0</span> : <b className={`tabular ${f.won ? 'gold' : 'red'}`}>{f.won ? '+' : '−'}{money(f.cash)}</b>}
        </>
        return otherId ? <RowLink key={f.id} to={`/player/${otherId}`}>{body}</RowLink> : <div key={f.id} className="row">{body}</div>
      })}
    </Card>
  )
}

function Top() {
  const { data: top, error, reload } = useLoad(() => api.topUsers())
  if (!top) return <Loading error={error} onRetry={reload} />
  const board = (title: string, rows: { id: string; name: string; value: number; emblem?: string }[], fmt: (n: number) => string, link: (id: string) => string) => (
    <Card title={title}>
      {(rows ?? []).length === 0 && <Empty>Nobody on the board yet.</Empty>}
      {(rows ?? []).map((r, i) => (
        <RowLink key={r.id} to={link(r.id)}>
          <span className="muted tabular" style={{ width: 22 }}>{i + 1}.</span>
          <div className="grow t">{r.emblem ? r.emblem + ' ' : ''}{r.name}</div>
          <b className="tabular">{fmt(r.value)}</b>
        </RowLink>
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

/** The counter wheel, every combo and what it takes, and what the city runs. */
function Combos() {
  const me = useMe()
  const { catalog } = useGame()
  const { data: meta, error: metaError, reload: reloadMeta } = useLoad(() => api.comboMeta())
  if (!catalog?.combo_styles || !catalog.combos) return <Card><Empty><span className="spin" /></Empty></Card>
  const styles = catalog.combo_styles
  const cfg = catalog.config
  const owns = (part: number[]) => part.some(id => me.inventory.some(i => i.item_id === id && i.qty > 0))
  const runs = (code: string) => (['offense', 'defense', 'jail'] as const).filter(s => me.combos?.[s]?.active === code)
  const byStyle = (counts: Record<string, number> | undefined, st: StyleCode) =>
    Object.entries(counts ?? {}).reduce((n, [code, k]) => n + (comboDef(catalog, code)?.style === st ? k : 0), 0)
  const totalOff = Object.values(meta?.offense ?? {}).reduce((a, b) => a + b, 0)
  const totalDef = Object.values(meta?.defense ?? {}).reduce((a, b) => a + b, 0)
  const setupName = { offense: 'Offense', defense: 'Defense', jail: 'Jail' }
  return (
    <>
      <Card title="The counter wheel">
        <div className="bd stack">
          <div className="small">Every combo has a style, and every style beats two others and loses to the other two. In a fight, a combo that <b className="green">counters</b> the other side's rolls 0–{cfg.combo_counter ?? 10} on top of your score; an <b className="gold">even</b> matchup (same style, no counter, or they run none) rolls 0–{cfg.combo_neutral ?? 5}; a combo that's <b className="red">countered</b> rolls nothing.</div>
          <div className="small muted">Which combo someone defends with is hidden until you hit them — then your fight preview remembers it. You see what hit you in My Fights, so you can switch to whatever beats it.</div>
        </div>
        {styles.map(st => (
          <div key={st.code} className="row wheel-row">
            <div className="grow">
              <div className="t"><StyleLine style={st.code} /></div>
              <div className="s">{st.blurb}</div>
            </div>
          </div>
        ))}
      </Card>

      <Card title="What the city runs" right={meta && <small>{num(meta.players)} active this week</small>}>
        {!meta && <Loading error={metaError} onRetry={reloadMeta} />}
        {meta && styles.map(st => {
          const o = byStyle(meta.offense, st.code), d = byStyle(meta.defense, st.code)
          const att = Object.entries(meta.attacks).filter(([code]) => comboDef(catalog, code)?.style === st.code)
          const n = att.reduce((a, [, v]) => a + v.n, 0), won = att.reduce((a, [, v]) => a + v.won, 0)
          return (
            <div key={st.code} className="row meta-row">
              <span className="ico">{st.icon}</span>
              <div className="grow">
                <div className="t">{st.name}</div>
                <div className="meta-bars">
                  <span className="k">offense</span><div className="bar"><div className="fill off" style={{ width: `${totalOff ? (100 * o) / totalOff : 0}%` }} /></div><b className="tabular">{o}</b>
                  <span className="k">defense</span><div className="bar"><div className="fill def" style={{ width: `${totalDef ? (100 * d) / totalDef : 0}%` }} /></div><b className="tabular">{d}</b>
                </div>
                {n > 0 && <div className="s">{num(n)} attack{n === 1 ? '' : 's'} this week · won {Math.round((100 * won) / n)}%</div>}
              </div>
            </div>
          )
        })}
        {meta && totalOff + totalDef === 0 && <div className="row small muted">Nobody's running a combo yet.</div>}
      </Card>

      {styles.map(st => (
        <Card key={st.code} title={<>{st.icon} {st.name} combos</>}>
          {catalog.combos!.filter(c => c.style === st.code).map(c => {
            const mine = runs(c.code)
            return (
              <div key={c.code} className="row combo-row">
                <div className="grow">
                  <div className="t">{c.name} <span className="muted small">{tierName[c.tier]}{!comboFits(catalog, c, 'offense') ? ' · jail only' : comboFits(catalog, c, 'jail') ? ' · works in jail too' : ''}</span>{mine.map(s => <span key={s} className="pill gold nowrap">{setupName[s]}</span>)}</div>
                  <div className="s combo-parts">
                    {c.parts.map((part, i) => <span key={i} className={owns(part) ? 'have' : ''}>{i > 0 && ' + '}{owns(part) ? '✓ ' : ''}{partLabel(catalog, part)}</span>)}
                  </div>
                </div>
              </div>
            )
          })}
        </Card>
      ))}
    </>
  )
}
