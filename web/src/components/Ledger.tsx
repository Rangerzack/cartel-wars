import { useState } from 'react'
import { api } from '../lib/api'
import { ago, money } from '../lib/format'
import type { LedgerEntry } from '../lib/types'
import { Card, Empty, Loading, Seg } from './ui'
import { useLoad } from '../lib/useLoad'
import { useNow } from '../lib/useNow'

const kindLabel: Record<LedgerEntry['kind'], { icon: string; label: string }> = {
  deposit: { icon: '⬆️', label: 'Deposit' },
  withdraw: { icon: '⬇️', label: 'Withdrawal' },
  bonus: { icon: '🏴', label: 'Block bonus' },
  fight_won: { icon: '⚔️', label: 'Crew fight won' },
  fight_lost: { icon: '💀', label: 'Crew fight lost' },
}

type Filter = 'all' | 'moves' | 'bonus'
// the newest few; the rest behind "Show all" so the ledger doesn't push a crew page's members and fights screens down
const FIRST = 5

/** Deposits, withdrawals, bonuses and fight stakes for the crew or cartel bank. `version` reloads it. */
export function Ledger({ scope, version = 0 }: { scope: 'crew' | 'cartel'; version?: number }) {
  // keyed by version: an action's reload keeps the rows up while it answers, and a failed one gets a Retry
  const { data: rows, error: err, reload } = useLoad(() => api.bankLedger(scope, 100), `${scope}|${version}`, { keep: true })
  const now = useNow(30_000)
  const [filter, setFilter] = useState<Filter>('all')
  const [all, setAll] = useState(false)
  const shown = rows?.filter(r => filter === 'all' || (filter === 'bonus' ? r.kind === 'bonus' : r.kind === 'deposit' || r.kind === 'withdraw'))
  return (
    <Card title={scope === 'crew' ? 'Crew bank ledger' : 'Cartel bank ledger'} right={<small>newest first</small>}>
      <div className="bd ledger-seg">
        <Seg value={filter} onChange={f => { setFilter(f); setAll(false) }} options={[{ v: 'all', l: 'All' }, { v: 'moves', l: 'In / Out' }, { v: 'bonus', l: 'Bonuses' }]} />
      </div>
      {!rows && <Loading error={err} onRetry={reload} />}
      {shown?.length === 0 && <Empty>Nothing yet.</Empty>}
      {shown?.slice(0, all ? undefined : FIRST).map(r => (
        <div key={r.id} className="row">
          <span>{kindLabel[r.kind].icon}</span>
          <div className="grow">
            <div className="t">{kindLabel[r.kind].label}{r.player ? <span className="muted"> · {r.player}</span> : r.kind !== 'bonus' ? <span className="muted"> · Deleted player</span> : null}</div>
            <div className="s">{r.note ? `${r.note} · ` : ''}{ago(r.at, now)} · balance {money(r.balance)}</div>
          </div>
          <b className={`tabular ${r.amount >= 0 ? 'gold' : 'red'}`}>{r.amount >= 0 ? '+' : '−'}{money(Math.abs(r.amount))}</b>
        </div>
      ))}
      {shown && shown.length > FIRST && <div className="row"><button type="button" className="btn sm ghost block" onClick={() => setAll(!all)}>{all ? 'Show fewer' : `Show all ${shown.length}`}</button></div>}
    </Card>
  )
}
