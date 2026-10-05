import { useNavigate } from 'react-router-dom'
import { api } from '../lib/api'
import { useGame, useMe } from '../lib/game'
import { comboDef, comboFits, comboStyle, missingParts, partLabel, styleOf, tierName } from '../lib/combos'
import type { SetupKind } from '../lib/types'
import { Btn, Card } from './ui'

/** "💣 Grenadier", colored by its style. Unknown shows as a question mark. */
export function ComboPill({ code, unknown }: { code?: string | null; unknown?: boolean }) {
  const { catalog } = useGame()
  const c = comboDef(catalog, code)
  const s = styleOf(catalog, code)
  if (unknown) return <span className="combo-pill unknown">❔ Unknown combo</span>
  if (!c || !s) return <span className="combo-pill none">No combo</span>
  return <span className={`combo-pill st-${s.code}`}>{s.icon} {c.name}</span>
}

/** Style line: "Blitz beats Infantry and Blackout · loses to Armored and Anti-Tank". */
export function StyleLine({ style }: { style?: string }) {
  const { catalog } = useGame()
  const s = catalog?.combo_styles?.find(x => x.code === style)
  if (!s) return null
  const name = (c: string) => catalog?.combo_styles?.find(x => x.code === c)?.name ?? c
  const losesTo = (catalog?.combo_styles ?? []).filter(x => x.beats.includes(s.code)).map(x => x.name)
  return <span>{s.icon} <b>{s.name}</b> beats {s.beats.map(name).join(' and ')} · loses to {losesTo.join(' and ')}</span>
}

/** The combo panel on a setup: what it runs, a picker when it completes several, and the ones it's one item from. */
export function SetupCombo({ setup }: { setup: SetupKind }) {
  const me = useMe()
  const { catalog, run } = useGame()
  const nav = useNavigate()
  if (!catalog?.combos || !me.combos) return null
  const sc = me.combos[setup]
  const equipped = me.setups[setup] ?? []
  const active = comboDef(catalog, sc?.active)
  // combos this setup is one part away from (that it can run at all), best tier first
  const close = catalog.combos
    .filter(c => !sc?.complete.includes(c.code) && comboFits(catalog, c, setup))
    .map(c => ({ c, miss: missingParts(c, equipped) }))
    .filter(x => x.miss.length === 1 && x.miss.length < x.c.parts.length)
    .sort((a, b) => b.c.tier - a.c.tier)
    .slice(0, 3)
  return (
    <Card title="Combo" right={<button className="btn sm ghost" onClick={() => nav('/fight?tab=combos')}>How Combos Work ›</button>}>
      <div className="bd stack">
        {active
          ? <>
              <div className="hstack"><ComboPill code={active.code} /><span className="small muted">{tierName[active.tier]}</span></div>
              <div className="small"><StyleLine style={active.style} /></div>
              <div className="small muted">Countering the other side's combo rolls you 0–{catalog.config.combo_counter ?? 10}; an even matchup 0–{catalog.config.combo_neutral ?? 5}; being countered, nothing.</div>
            </>
          : <div className="small muted">No combo in this setup. Put a combo's items together — a weapon and the right vest, or a whole kit — and it adds up to +{catalog.config.combo_counter ?? 10} a fight.</div>}
        {sc && sc.complete.length > 1 && (
          <div className="stack">
            <div className="small muted">This setup completes {sc.complete.length} combos — pick the one it runs:</div>
            <div className="hstack combo-pick">
              {sc.complete.map(code => {
                const on = code === sc.active
                return (
                  <Btn key={code} className={`sm ${on ? 'gold' : 'ghost'}`} disabled={on}
                    onClick={() => run(() => api.setCombo(setup, code), { ok: () => `${comboDef(catalog, code)?.name} it is` })}>
                    {comboStyle(catalog, comboDef(catalog, code)?.style)?.icon} {comboDef(catalog, code)?.name}
                  </Btn>
                )
              })}
            </div>
            {sc.chosen && <button className="btn sm ghost" onClick={() => run(() => api.setCombo(setup, null), { ok: () => 'Back to the best one' })}>Let the Game Pick</button>}
          </div>
        )}
        {close.length > 0 && (
          <div className="stack combo-close">
            {close.map(({ c, miss }) => (
              <div key={c.code} className="small"><ComboPill code={c.code} /> needs a <b>{partLabel(catalog, miss[0])}</b></div>
            ))}
          </div>
        )}
      </div>
    </Card>
  )
}
