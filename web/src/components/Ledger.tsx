import { useEffect, useState } from 'react'
import { api } from '../lib/api'
import { ago, money } from '../lib/format'
import type { LedgerEntry } from '../lib/types'
import { Card, Empty } from './ui'

const kindLabel: Record<LedgerEntry['kind'], { icon: string; label: string }> = {
  deposit: { icon: '⬆️', label: 'Deposit' },
  withdraw: { icon: '⬇️', label: 'Withdrawal' },
  bonus: { icon: '🏴', label: 'Block bonus' },
  fight_won: { icon: '⚔️', label: 'Crew fight won' },
  fight_lost: { icon: '💀', label: 'Crew fight lost' },
}

type Filter = 'all' | 'moves' | 'bonus'

/** Deposits, withdrawals, bonuses and fight stakes for the crew or cartel bank. `version` reloads it. */
export function Ledger({ scope, version = 0 }: { scope: 'crew' | 'cartel'; version?: number }) {
  const [rows, setRows] = useState<LedgerEntry[] | null>(null)
  const [err, setErr] = useState<string | null>(null)
  const [filter, setFilter] = useState<Filter>('all')
  useEffect(() => { api.bankLedger(scope, 100).then(r => { setRows(r); setErr(null) }).catch(e => setErr(e.message)) }, [scope, version])
  const shown = rows?.filter(r => filter === 'all' || (filter === 'bonus' ? r.kind === 'bonus' : r.kind === 'deposit' || r.kind === 'withdraw'))
  return (
    <Card title={scope === 'crew' ? 'Crew bank ledger' : 'Cartel bank ledger'} right={
      <span className="hstack" style={{ gap: 4 }}>
        {(['all', 'moves', 'bonus'] as const).map(f => (
          <button key={f} className={`btn sm ${filter === f ? '' : 'ghost'}`} onClick={() => setFilter(f)}>{f === 'all' ? 'All' : f === 'moves' ? 'In/Out' : 'Bonuses'}</button>
        ))}
      </span>
    }>
      {err && <Empty>{err}</Empty>}
      {!rows && !err && <Empty><span className="spin" /></Empty>}
      {shown?.length === 0 && <Empty>Nothing yet.</Empty>}
      {shown?.map(r => (
        <div key={r.id} className="row">
          <span>{kindLabel[r.kind].icon}</span>
          <div className="grow">
            <div className="t">{kindLabel[r.kind].label}{r.player ? <span className="muted"> · {r.player}</span> : null}</div>
            <div className="s">{r.note ? `${r.note} · ` : ''}{ago(r.at)} · balance {money(r.balance)}</div>
          </div>
          <b className={`tabular ${r.amount >= 0 ? 'gold' : 'red'}`}>{r.amount >= 0 ? '+' : '−'}{money(Math.abs(r.amount))}</b>
        </div>
      ))}
    </Card>
  )
}
