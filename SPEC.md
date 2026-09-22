# Cartel Wars — reconstructed design spec

A web clone of SMLSD's *The Cartel* / *Cartel Wars* (iPhone, 2009–2010; later
*Cartel Reloaded* under Roasted Brains). This is not a Mafia-Wars-style
"add me" mob game. It is a crime economy sim: produce and move product, fight
one-on-one with equipped gear, manage Heat and jail, band into Crews and
Cartels, and conquer Hoods and Blocks with hired hoodlums.

Everything below is reconstructed from the developer's App Store copy, the
Cartel Reloaded wiki, and 2010 forum posts. Numbers marked *(wiki)* come from
the Roasted Brains-era wiki and may have drifted from 2010 values; numbers
marked *(ours)* are our fill-ins where no source survived. Change anything
that doesn't match your memory — all tuning lives in `supabase/migrations/`.

## Core resources

| Resource | Base | Max | Regen | Notes |
|---|---|---|---|---|
| Stamina | 25 | 150 (upgrade with Diamonds) | +1 / 5 min *(wiki)* | Spent by Actions. Attacks require ≥2 but don't consume it. |
| Health | 100 | 500 (upgrade with Diamonds) | +1 / 5 min *(wiki)* | ≤19 = **Hospital**: no actions, no attacks. Pay $40/pt to check out *(wiki)*. |
| Heat | 0 | 100 | decays −1 / 10 min *(ours)* | Green 0–39, Yellow 40–74, Red 75+. Rises with Actions and Attacks. At Red each action/attack risks getting **Busted** (jail). |
| Cash ($) | tutorial grant | — | — | Cash on hand can be taken in fights. Banked cash is safe. |
| Diamonds | starter grant | — | — | Premium currency: refills, max-stat upgrades, inventory slots, extra grow houses. Earned via achievements; no real-money purchase in this clone. |

Refills *(wiki)*: full Stamina for 6 Diamonds or 400 Herb / 280 Dust / 100 Pills.
Full Health for 6 Diamonds or 200 Herb / 100 Dust / 50 Pills. Commodity refills
halve in effect after 3 in a rolling 24h.

Players can send cash and Diamonds to each other from a profile *(wiki:
"Send Money / Diamonds" buttons)*.

There are **no levels and no skill points**. Progression is cash, gear,
production capacity, territory and accolades.

## Actions (the "jobs")

Each Action costs Stamina, pays a cash range, and adds Heat. Some require an
equipped item or a minimum crew size. Press the black **Do It** button.
Separate **Jail Actions** are the only actions available while in jail.
The wiki notes payouts of roughly $140–$31,000 across the list; the seed
ships a 24-action ladder in that range plus 6 jail actions *(ours)*.

Special action: **Bribe Police To Get In Jail** — 10 Stamina, $1,000 *(wiki)*.
Players did this deliberately to use jail setups and jail actions.

## Fighting

Attack from any player's profile (**One On One**). Requirements: attacker
Stamina ≥2 (not consumed), both players' Health >19, target not under
new-player immunity (48h *(ours)*), target not in Hospital.

Damage dealt to defender (max 80 *(wiki)*):

- **Base 0–60**: from attacker's equipped Attack vs defender's equipped
  Defense. Barehands baseline is 20/20. `base = 60 * att / (att + def)`.
- **Situational 0–10**: random, nudged by comparative health, heat and stamina.
- **Bonus −10…+10**: weapon-combo bonus (a weapon + matching protection in the
  same setup).

The attacker takes a smaller counter-hit (`0.35 × mirror formula` *(ours)*).
The winner (higher damage) takes 5–10% of the loser's cash on hand *(ours)*;
after three hits on the same target within an hour the cash dries up (fights
still happen, no money moves) *(ours, anti-farming)*. Attacking while under
new-player immunity ends your immunity. Anyone dropping to ≤19 Health lands in
Hospital. Attacking adds Heat.

Setups: every player keeps an **Offensive**, **Defensive** and **Jail** setup.
Equipped items count only within the setup in use (offense when you attack,
defense when attacked, jail for both while jailed). Items are never consumed.
Slot count = Inventory slots (base 6 *(ours)*, upgradable with Diamonds).
Only the single best Transport's att/def counts *(wiki)*.

### Crew fights

Launched from a rival crew's page by any member (5 Stamina). Your crew's total
Attack (every member's active setup; hospitalized members sit out) against
their total Defense, each rolled ±15%. The winner takes 5% of the loser's
Crew Bank; everyone on the losing side loses 10–25 Health, the winners 3–8.
One hit per attacker→defender pair per hour; no fights inside a cartel, none
from jail. The initiator gains 3 Heat and rolls for a bust like any attack.
The defending crew gets a line in its Crew Chat. *(ours — the original had crew
fights "launched from crew profiles" but no surviving details.)*

## Heat, police and jail

- Police Station (Services): **Bribe** to lower Heat at $40 per point *(wiki)*.
- Getting Busted: when Heat is Red, every action/attack rolls
  `P(bust) = (heat − 74) / 40` *(ours)*. Busted = jailed for 2 hours *(ours)*
  and Heat resets to 40.
- In jail: only Jail Actions; you can still sell commodities, use bank and
  inventory, and attack / be attacked using your Jail setup with Jail Weapons.
- Leave jail early: Bail = $2,000 + $50/minute remaining *(ours)*.

## Economy

Commodities: **Herb**, **Dust**, **Pills** (cheap→expensive, bulky→compact).

- **Grow House** (Production Center): one per commodity, upgradeable.
  Produces `rate × level` units/hour up to `cap × level` uncollected.
  Start / Stop / Collect / Upgrade / Abandon. First one is cheap; extra
  houses cost Diamonds *(wiki: "extra grow houses")*.
- **Storage**: holds collected product; base capacity 500 units *(ours)*,
  upgradable with cash.
- **Street Price**: per-commodity price that random-walks every time it's
  read (bounded ±35% of base *(ours)*). The Marketplace can't list above it.
- **Hustlers** *(wiki)*: hire for $400 each; a hustler carries 16 Herb / 8 Dust
  / 4 Pills, is gone 4 hours, and returns with cash at the street price at
  departure. Collect when they're back.
- **Marketplace** *(wiki)*: list 25–1,000 units at ≤ street price; listing
  needs Transport capacity ≥ batch size and expires in 48h. Buyers pay cash
  and need storage room. Cancelled or expired product returns to storage up to
  the cap; the rest waits on the listing until you make room.
- **Bank**: personal bank — deposit/withdraw, no fee (none found in sources).
  Crew Bank and Cartel Bank receive hood income and accept deposits; the
  Capo / Don can withdraw.

## Crews and Cartels

- **Crew**: up to 12 members *(ours)*, leader is the **Capo**. Name, emblem
  (emoji), description. Players apply; Capo accepts/kicks. No invite codes.
- **Cartel**: an alliance of Crews. Leader is the **Don** (the founding Capo;
  Capos can vote to replace). Cartels own the Cartel Bank and share hood
  bonuses. Cartel Chat.
- Chat: global Live Chat, Crew chat, Cartel chat, private conversations.

## Territory (the Cartel Wars expansion)

The city has **four islands**, each with Hoods, each Hood with Blocks.

- A **Block** is held by a Crew. Holding a majority of a Hood's blocks makes
  your Crew the **Hood owner**; the Hood pays daily income: 80% to the owning
  Crew's bank, 20% to its Cartel's bank *(wiki)*. Hoods cost $16k–$50k and pay
  $320k–$1M/day *(wiki)*; here the price is split across the hood's four
  blocks, paid when you take an unclaimed block ($4k–$12.5k each).
- **Hoodlums** *(wiki)* are bought in Services and stationed on a block or
  used to attack one. Price rises with quantity held.

  | Hoodlum | Att | Def | Intel | Price |
  |---|---|---|---|---|
  | Thug | 10 | 10 | 0 | $1,000 |
  | Spy | 0 | 0 | 7 | $500 |
  | Mercenary | 60 | 0 | 0 | $4,000 |
  | Enforcer | 0 | 60 | 0 | $4,000 |

- **Attack a block** (3 Stamina): your attacking hoodlums' total Att vs the
  block's resistance (base resistance + stationed hoodlums' Def). You must
  bring at least a quarter of the resistance to get a fight. Both sides lose
  hoodlums proportional to the damage they took (rounded down); if attack >
  resistance the block flips to your crew and the hood's daily payout clock
  restarts. Outsiders only see whether a block is garrisoned; Spies reveal the
  exact garrison and resistance.

## Accolades

Weekly ranked stripes *(wiki)*. Six boards, reset Monday 00:00 UTC: Fights
won, Defenses (fights you were attacked in and won), Actions, Imports (units
hustlers brought back), Market (cash traded on the Marketplace, both sides)
and Turf (blocks captured). Top three on each board wear a gold, silver or
bronze stripe on their profile for the following week. Everything is derived
from an `accolade_events` log written by the RPCs.

## Screens (mobile-first, black "Do It" buttons)

Bottom bar: **Home · Actions · Economy · Fight · Services · Chat**.
Home shows stats, Heat gauge, crew/cartel, and links to Profile, Inventory,
Storage, Setups, Crew, Cartel, Territory, Top Users.

## Architecture

- **Supabase / Postgres**: every state change is a `SECURITY DEFINER` RPC
  (`do_action`, `attack`, `buy_item`, `equip`, …). Clients only ever call
  RPCs and read views. Regen (stamina, health, heat, production, hustler
  trips, listings expiry, hood income) is computed lazily from timestamps
  inside `tick_player()` — no cron needed.
- **Web**: Vite + React + TypeScript, `@supabase/supabase-js`,
  `react-router-dom`. One `useGame()` hook keeps the full player state
  (`get_me()`), refreshed after every RPC.
