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
| Health | 100 | 500 (upgrade with Diamonds) | +5 / 5 min *(ours — faster hospital exits)* | ≤19 = **Hospital**: no actions, no attacks. Buy health at the Hospital on a sliding scale: $40/pt base, and the per-point price rises by 1× for every 100 points bought in the last 24h (like hoodlums) *(ours)*. |
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

## Reputation (the 2011 "Reputation expansion")

Five **reputation actions** pay no cash but add Reputation (⭐). Reputation
buys six **rare items** (a gold-plated Desert Eagle, Escobar's Machete, an
armored limousine, …) that can't be bought with cash or sold. *(wiki: "actions
that pay reputation instead of cash, rewarded with traditional and Rare
weapons"; the specific items and numbers are ours.)*

Players have an avatar (emoji) and a short bio shown on their profile and in
lists *(wiki: profile avatar)*.

## Fighting

Attack from any player's profile (**One On One**). Requirements: attacker
Stamina ≥2 (not consumed), both players' Health >19, target not in Hospital.
No new-player immunity: new accounts can be attacked right away *(ours)*.

Damage dealt to defender (max 80 *(wiki)*):

- **Base 0–60**: from attacker's equipped Attack vs defender's equipped
  Defense. Barehands baseline is 20/20. `base = 60 * att / (att + def)`.
- **Situational 0–10**: random, nudged by comparative health, heat and stamina.
- **Bonus −10…+10**: weapon-combo bonus (a weapon + matching protection in the
  same setup).

The attacker takes a smaller counter-hit (`0.35 × mirror formula` *(ours)*).
The winner (higher damage) takes 5–10% of the loser's cash on hand *(ours)*;
after three hits on the same target within an hour the cash dries up (fights
still happen, no money moves) *(ours, anti-farming)*. Anyone dropping to ≤19 Health lands in
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
- **Producers and Traders** *(ours)*: once a player has earned 100 reputation
  (lifetime — spending rep on items doesn't reset it) they pick a path.
  Producers build, run and upgrade grow houses but can't send hustlers;
  Traders send hustlers but can't run grow houses (theirs stop; anything
  already grown can still be collected). Both use the Marketplace, where
  producers sell and traders buy. The first pick is free; switching costs 💎50.
- **Bank**: personal bank — deposit/withdraw, no fee (none found in sources).
  Crew Bank and Cartel Bank receive block bonuses and accept deposits; the
  Capo or Co-Capo / the Don can withdraw. Every movement (deposits,
  withdrawals, block bonuses, crew-fight stakes) is kept in a ledger that
  members can read.

## Crews and Cartels

- **Crew**: up to 12 members *(ours)*, leader is the **Capo**. Name, emblem
  (emoji), description. Players apply; Capo accepts/kicks. No invite codes.
  The Capo can name one **Co-Capo**, who can accept/kick members (not the
  Capo), withdraw from the crew bank, edit the crew and pull garrisons, and who
  takes over if the Capo leaves. Cartel business stays with the Capo.
- **Cartel**: an alliance of Crews. Leader is the **Don** — the founding Capo,
  replaceable by a vote: each member crew's Capo votes for a Capo, and a strict
  majority of crews elects *(wiki: "Don, voted by Capos")*. Cartels own the
  Cartel Bank and share hood bonuses. Cartel Chat.
- Chat: global Live Chat, Crew chat, Cartel chat, private conversations.

## Territory (the Cartel Wars expansion)

The city is a **9×9 grid of Hoods** (rows A–I are districts, columns 1–9
streets); each Hood is a **2×3 grid of 6 Blocks** (properties). Hoods toward
the center cost more, pay more and resist harder:

| Ring | Hoods | Hood price | Hood income/day | Block base resistance |
|---|---|---|---|---|
| center | 1 | $50,000 | $1,000,000 | 1,400 |
| 1 | 8 | $42,000 | $840,000 | 900 |
| 2 | 16 | $32,000 | $640,000 | 600 |
| 3 | 24 | $24,000 | $480,000 | 400 |
| edge | 32 | $16,000 | $320,000 | 250 |

- **Block bonus**: every held block pays its share of the hood's income
  (income ÷ 6) once every 24h — 80% to the holding Crew's bank, 20% to its
  Cartel's bank *(wiki split)*. Each block shows a countdown to its next bonus.
- Holding 4 of a hood's 6 blocks makes your Crew the **Hood owner** (shown on
  the map).
- **Hoodlums** *(wiki)* are bought in Services and stationed on a block or
  used to attack one. Price rises with quantity held.

  | Hoodlum | Att | Def | Intel | Price |
  |---|---|---|---|---|
  | Thug | 10 | 10 | 0 | $1,000 |
  | Spy | 0 | 0 | 7 | $500 |
  | Mercenary | 60 | 0 | 0 | $4,000 |
  | Enforcer | 0 | 60 | 0 | $4,000 |

- **Attack a block** (3 Stamina, at least **51 thugs**, mercenaries optional):
  your hoodlums' total Att vs the block's resistance (base resistance +
  stationed hoodlums' Def). You must bring at least a quarter of the
  resistance to get a fight. Both sides lose hoodlums proportional to the
  damage they took (rounded down).
  - An **empty block** is claimed with one successful attack plus its claim
    price (hood price ÷ 6).
  - A **held block** falls only after your Crew lands **50 successful attacks**
    on it (counted across the whole crew). **Every successful hit restarts the
    owner's bonus countdown** — the old trick of hitting a block when it's
    under an hour from paying out. When it falls, its garrison is wiped, all
    siege counts on it reset, and its bonus clock starts fresh for the new
    owner. Crews in the same Cartel can't attack each other's blocks.
- Every attack is logged per block (attacker, force, losses, siege count).
  Outsiders only see whether a block is garrisoned; Spies reveal the exact
  garrison and resistance.

## Accolades

Weekly ranked stripes *(wiki)*. Seven boards, reset Monday 00:00 UTC: Fights
won, Defenses (fights you were attacked in and won), Actions, Imports (units
hustlers brought back), Market (cash traded on the Marketplace, both sides),
Turf (blocks captured) and Gambler (net casino winnings) *(ours)*. Top three on each board wear a gold, silver or
bronze stripe on their profile for the following week. Everything is derived
from an `accolade_events` log written by the RPCs.

## Casino (the Cartel Reloaded expansion)

Cartel Reloaded added a casino *(wiki)*; the games and numbers below are our
design *(ours)*. Everything runs server-side (RNG, dealing, hand evaluation,
pots) in `20260922000001_casino.sql`; the client only calls RPCs. Bets come
from cash on hand, so a big session is a fat pocket for anyone who attacks
you afterwards. No gambling from jail or the hospital. Any single win of
$10,000+ over the stake adds 2 Heat. House bets are $100–$500,000.

- **Slots** — 3 reels, weighted symbols (🍒7 🍋10 🔔8 BAR6 💎4 7️⃣2 of 37).
  Triples pay 4/6/12/20/40/100×; one cherry returns the stake, two pay 2×.
  ≈96.5% RTP.
- **Roulette** — European single zero. Straight 35:1, dozens/columns 2:1,
  even-money outside bets 1:1. Up to 20 bets per spin, $500k table max.
- **Craps** — Pass / Don't Pass (12 pushes), Field (2 pays 2:1, 12 pays 3:1),
  Place 6 and 8 at 7:6, Any 7 at 4:1, Any Craps at 7:1. Line bets lock once
  the point is on; everything else can be taken down between rolls.
- **Blackjack** — six-deck shoe per hand, dealer stands on all 17s,
  blackjack pays 3:2, double on any first two cards, no splits/insurance.
- **No-Limit Hold'em** — live, against other players, 6-max. Tables at
  1k/2k (×2), 5k/10k (×2), 25k/50k (×2) and 250k/500k; buy-in 40–200 big
  blinds, top-ups allowed up to the max. 30-second action clock: out of
  time you check if you can, otherwise fold; three misses in a row sits you
  out (stack is safe, rebuy/sit-in to return). Rake 5% of the pot capped at
  3 big blinds, no flop no drop. Full side-pot handling; odd chips go to
  the first winner left of the dealer. Hands are settled in the DB and every
  player's net goes to the `gambler` accolade. Each table has its own chat
  channel (`table:<id>`), open to seated players.

## Forum *(ours)*

Seven boards: Game Updates (only admins start threads; anyone replies), New
Player, Market, General, War, Off Topic, Suggestions. Threads and replies are
plain text (4,000 characters), editable and deletable by their author;
admins can pin, lock, move and delete anything. Cooldowns: one new thread a
minute, one reply every ten seconds (admins exempt). Admins are the emails in
the `admins` table (flagged on `profiles.is_admin` at registration).

## Economy at a glance (for tuning)

With base stamina regen (+12/hour) and the seeded numbers:

| Income source | Cost | Return |
|---|---|---|
| Actions, low tier | 1 stamina | ~$180 → ~$2,200/hour of regen |
| Actions, top tier (Minigun, crew of 6) | 12 stamina | ~$26,500 → ~$26,000/hour of regen |
| Herb grow house L1 | $5,000 | 20 u/h × $60 = $1,200/hour (pays off in ~4h) |
| Dust grow house L1 | $15,000 + 💎20 | 8 u/h × $200 = $1,600/hour (~9h) |
| Pills grow house L1 | $40,000 + 💎20 | 3 u/h × $600 = $1,800/hour (~22h) |
| Hustler (herb) | $400 + 16 herb | $960 after 4h (≈$560 net per trip) |
| Marketplace | transport | up to street price, buyer pays |
| Block (crew) | claim + 51+ thugs (50 wins if held) | $53k–$167k/day per block, 80% crew bank / 20% cartel bank |

Territory is by far the biggest faucet, as in the original — it's what makes
crews and cartels matter. If solo play feels too slow, raise `grow_rate` or
action payouts in the seed; if crews feel unstoppable, lower `daily_income`
or raise `base_resistance`.

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
