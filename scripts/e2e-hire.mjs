// Browser walkthrough for hiring hoodlums where they're used (components/Hire.tsx): Territory's Thugs tile opens a
// hire panel on the page, and a block's attack sheet with too few thugs hires the rest in place and puts them in the
// attack, so Attack comes alive without leaving the sheet. The Services card is covered by e2e.mjs and e2e-business.mjs.
// Usage (local stack running): node scripts/e2e-hire.mjs
import { chromium } from 'playwright'
import pg from 'pg'
const db = new pg.Pool({ host: 'localhost', port: Number(process.env.PGPORT || 54329), user: 'postgres', database: 'cartel' })

const BASE = process.env.BASE || 'http://127.0.0.1:5173'
const browser = await chromium.launch({ executablePath: process.env.CHROME || '/opt/pw-browsers/chromium' })
const errors = []
const RUN = Date.now().toString(36).slice(-4)
const N = (base) => `${base}${RUN}`
const one = async (sql, args = []) => (await db.query(sql, args)).rows[0]

try {
  const ctx = await browser.newContext({ viewport: { width: 390, height: 844 }, deviceScaleFactor: 2 })
  const p = await ctx.newPage()
  p.on('pageerror', e => errors.push(e.message))
  p.on('dialog', d => d.accept())
  await p.goto(BASE)
  await p.getByRole('button', { name: 'New Player' }).click()
  await p.getByLabel('Street name').fill(N('Rhee'))
  await p.getByLabel('Email').fill(`rhee${RUN}-${Date.now()}@test.local`)
  await p.getByLabel('Password').fill('secret123')
  await p.getByRole('button', { name: 'Enter the City' }).click()
  await p.locator('.topbar').waitFor()
  const me = (await one('select id from profiles where name = $1', [N('Rhee')])).id
  const crew = await one(`insert into crews (name, emblem, capo_id) values ($1, '🦂', $2) returning id`, [N('Sting '), me])
  await db.query('update profiles set crew_id = $1, cash = 5000000 where id = $2', [crew.id, me])
  const thugs = async () => Number((await one(`select coalesce((select qty from player_hoodlums where player_id = $1 and code = 'thug'), 0) n`, [me])).n)

  // the Thugs tile opens the hire panel right there, sized to a first turf attack
  await p.goto(`${BASE}/territory`)
  await p.locator('.hoodgrid').waitFor()
  await p.locator('.stat-btn', { hasText: 'Thugs' }).click()
  const panel = p.locator('.card', { hasText: 'Hire hoodlums' })
  if (await panel.locator('.qty input').inputValue() !== '51') throw new Error('the panel should start at the 51 thugs a turf attack needs')
  await panel.getByRole('button', { name: /Hire · / }).click()
  await p.locator('.toast', { hasText: /^Hired 51 thugs for \$/ }).waitFor()
  if (await thugs() !== 51) throw new Error('hiring from Territory should give 51 thugs, got ' + await thugs())
  await p.locator('.stat-btn', { hasText: 'Thugs' }).locator('.v', { hasText: '51' }).waitFor()

  // a block's attack sheet, 31 short: hire them in the sheet and they join the attack
  await db.query(`update player_hoodlums set qty = 20 where player_id = $1 and code = 'thug'`, [me])
  const blk = await one('select id, hood_id from blocks where owner_crew_id is null order by id limit 1')
  await p.goto(`${BASE}/territory?hood=${blk.hood_id}&block=${blk.id}`)
  const sheet = p.locator('.modal')
  const attack = sheet.getByRole('button', { name: 'Attack', exact: true })
  await sheet.locator('.hire-inline').waitFor()
  if (!(await attack.isDisabled())) throw new Error('Attack is off with 20 thugs')
  if (await sheet.locator('.hire-inline .qty input').inputValue() !== '31') throw new Error('the sheet should offer the 31 missing thugs')
  await sheet.locator('.hire-inline').getByRole('button', { name: /Hire · / }).click()
  await p.locator('.toast', { hasText: /^Hired 31 thugs for \$/ }).waitFor()
  await sheet.getByRole('button', { name: /Hire more thugs or mercs/ }).waitFor()
  if (await sheet.locator('label.f input').first().inputValue() !== '51') throw new Error('the new thugs should go into the attack')
  if (await attack.isDisabled()) throw new Error('Attack should be live once the thugs are hired')
  if (await thugs() !== 51) throw new Error('the sheet should have hired 31 thugs')

  if (errors.length) throw new Error(errors.join('\n'))
  console.log('e2e-hire PASSED: hire from the Territory tiles and inside a block sheet, and the new thugs join the attack')
} catch (e) {
  console.error('e2e-hire FAILED:', e.message)
  process.exitCode = 1
} finally {
  await browser.close()
  await db.end()
}
