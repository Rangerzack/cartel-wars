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
| Heat | 0 | 100 | decays −1 / 10 min *(ours)* | Green 0–39, Yellow 40–74, Red 75+. Rises with Actions and Attacks. At Red each action/attack risks getting **Busted** (jail). More heat than your opponent is a +1 fight edge. |
| Cash ($) | tutorial grant | — | — | Cash on hand can be taken in fights. Banked cash is safe. More cash on hand than your opponent is a +1 fight edge. **Daily cash**: every account — players and the NPC thugs — gets $50,000 on hand at 00:00 UTC, online or not *(ours)*. A thug's daily cash sits on top of its stash until hunters take it. |
| Diamonds | starter grant | — | — | Premium currency: refills, max-stat upgrades, inventory slots, extra grow houses. Earned via achievements; no real-money purchase in this clone. |

Refills *(wiki)*: full Stamina for 6 Diamonds or 400 Herb / 280 Dust / 100 Pills.
Full Health for 6 Diamonds or 200 Herb / 100 Dust / 50 Pills. Commodity refills
halve in effect after 3 in a game day *(wiki)* — and each one after that halves again
(½, ¼, ⅛ … of what's missing) *(ours, 2026-09-30: unlimited half refills made product
worth far more burned than sold)*. The count resets at the 00:00 UTC rollover; diamond
and Daily Drop refills are always full and don't count.

The **game day** rolls over at 00:00 UTC, the same clock as the weekly boards: refills
come back and daily cash lands.

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

**Rare finds** *(Zack, from the original: "specialized weapons … only through
actions, very rare drop rate")*: four items you can't buy or sell, each the best of
its kind — TOW Missile (weapon, att 185), EOD Bomb Suit (protection, def 115),
MRAP (vehicle, 15/40) and Zip Gun (jail weapon, att 60). Every job names the one it
can turn up; the chance is `stamina_cost / 6000`, so a 12-stamina job is 1 in 500
and spamming the 1-stamina job isn't a shortcut *(ours)*.

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
Stamina ≥2 (not consumed — intended), both players' Health >19, target not in
Hospital, and both on the same side of the bars: jailed players only fight
jailed players, and nobody outside can attack someone inside *(Zack)*.
No new-player immunity: new accounts can be attacked right away *(ours)*.

Fights are **head-to-head**: both sides score the same way, and the higher score
wins (max 80 *(wiki)*; a tie goes to the defender):

- **Base 0–60**: your Attack against their Defense. Barehands baseline is 20/20.
  `base = 60 * att / (att + their def)`. The defender's base uses their defensive
  setup's Attack against your offensive setup's Defense.
- **Situational 0–10**: a 0–6 roll plus **+1 edges** *(Zack, from the original)*:
  the defender always gets +1; whoever has more cash on hand gets +1; whoever has
  more heat gets +1. Ties give nobody the edge.
- **Combo 0–10**: see Combos below. Countering the other side's combo rolls 0–10,
  an even matchup 0–5, being countered nothing.

Gear decides lopsided fights and the edges decide close ones (each +1 is worth
roughly 10% win chance in an even fight). The winner's hit lands in full; the
loser's lands at 35% *(ours)*. NPC thugs fight at half their gear at Thug 1,
rising to full at Thug 200, so new players can farm the first forty or so. The
Player page shows exact odds (every roll enumerated) and both sides' edges; the
Fight page's **Thugs** tab ranks all 200 by what a hit is worth to you. Thugs don't
appear on Top Users, the weekly boards or ribbons.
The winner takes 5–10% of the loser's cash on hand *(ours)*;
after three hits on the same target within an hour the cash dries up (fights
still happen, no money moves) *(ours, anti-farming)*. Anyone dropping to ≤19 Health lands in
Hospital. Attacking adds Heat.

Setups: every player keeps an **Offensive**, **Defensive** and **Jail** setup.
Equipped items count only within the setup in use (offense when you attack,
defense when attacked, jail for both while jailed). Items are never consumed.
Slot count = Inventory slots (base 6 *(ours)*). Each slot past six costs more
*(Zack)*: the k-th extra slot (k = 1 for the 7th) is 10 + 5k Diamonds **and**
$100,000 × k² cash on hand — 7th 15💎 + $100k, 12th 40💎 + $3.6M, 18th 70💎 +
$14.4M, 24th 100💎 + $32.4M. Slots bought before the change stay. Slots top out
at **130** *(Zack, the original's cap)*.

**Boost** *(Zack)*: 50 Diamonds buys +50 for 24 hours — +50 Attack in the
Offensive setup or +50 Defense in the Defensive setup (never jail). One side at
a time: while a boost runs the other side is locked out and buying the same side
adds another 24 hours; once it runs out, either side can be bought again. It counts
everywhere that setup does (fights, the preview, crew fights).
Only the single best Transport's att/def counts *(wiki)*.

### Combos *(Zack: "our own combos, max +10, that counter popular combos")*

A combo is a set of items in one setup. Every combo has a **style**, and the
styles sit on a counter wheel — each beats two and loses to two:

| Style | Beats | Loses to |
|---|---|---|
| 🚙 Armored | Infantry, Blitz | Anti-Tank, Blackout |
| 🚀 Anti-Tank | Armored, Blitz | Infantry, Blackout |
| 🪖 Infantry | Anti-Tank, Blackout | Armored, Blitz |
| 💣 Blitz | Infantry, Blackout | Armored, Anti-Tank |
| 🔦 Blackout | Anti-Tank, Armored | Blitz, Infantry |

| Combo | Style | Tier | Items (one from each part) |
|---|---|---|---|
| Back Alley | Blackout | Street | any melee weapon + Leather Jacket or Helmet |
| Street Soldier | Infantry | Street | Glock 18 or Desert Eagle + Kevlar Vest or Cartel Plate Carrier |
| Riot Squad | Armored | Street | Sawed-off Shotgun + Riot Shield |
| Spray and Pray | Blitz | Street | Uzi or MAC-10 + Tactical Vest |
| Fireteam | Infantry | Pro | AK-47, M4, Sniper, MIL-Spec Rifle or LMG + Body Armor or Kevlar Jacket |
| Heavy Weapons | Anti-Tank | Pro | RPG, Minigun or TOW + Bulletproof Plate or EOD Bomb Suit |
| Armored Escort | Armored | Pro | Armored SUV, Limousine or MRAP + Body Armor, Plate or EOD |
| Blackout | Blackout | Elite | Dazzler Gun + Flashbang + Smoke Grenade |
| Kevlar Squad | Infantry | Elite | Kevlar Vest + Shorts + Pads + Jacket (works in jail too) |
| HUMVEE Convoy | Armored | Elite | HUMVEE Armour + Bullbar + HUMVEE Stinger or 50mm Cannon |
| Grenadier | Blitz | Elite | Grenade + Grenade Launcher + Striker GMG |
| Tank Hunters | Anti-Tank | Elite | Stinger + Rocket Launcher + Metal Storm or TOW |
| Yard Muscle | Armored | Jail | any shiv + Prison Yard Muscle |
| Lights Out | Blackout | Jail | Sock of Batteries or Cell Block Pipe + Leather Jacket or Helmet |

- A setup that completes several combos runs the one the player picks (Items →
  Setups), else the highest tier.
- In a fight, a combo that counters the other side's rolls 0–10; one that's
  countered rolls nothing; otherwise (mirror, no counter, other side has none)
  0–5. At even gear that's ~35% for the attacker in a mirror, ~78% countering,
  ~6% countered; a 20% gear edge that's countered drops to a coin flip.
- Which combo someone defends with is hidden (whether they run one isn't). The
  fight preview uses what they ran the last time you hit them; the defender sees
  the attacker's combo in My Fights and Activity. Thugs' combos are public.
- Fight → **Combos** shows the wheel, every combo (✓ for parts you own) and what
  the city runs (active players' offense and defense combos, the week's attacks).
- Jail has its own triangle: Yard Muscle (Armored) beats Kevlar Squad (Infantry),
  which beats Lights Out (Blackout), which beats Yard Muscle.

**The military tier** — the items from the original game's top setups: Striker
GMG, Grenade Launcher, LMG, MIL-Spec Rifle, Dazzler Gun, HUMVEE 50mm Cannon,
Rocket Launcher, Stinger, HUMVEE Stinger, Metal Storm; Kevlar Shorts, Pads and
Jacket, Smoke Grenade, Flashbang, HUMVEE Bullbar, HUMVEE Armour; and the Grenade
(was "Grenades", 20/10). Each slot is worth about a Minigun (att + def 90–170);
the att/def split is fitted to ten of the original's top setups, which come out
at about twice their original totals here with the same balance. $6,000 per
point. The EOD Bomb Suit went to 140 defense so the rare finds stay the best
per slot.

### Crew fights

Launched from a rival crew's page by any member (5 Stamina). Your crew's total
Attack (every member's active setup; hospitalized members sit out) against
their total Defense, each rolled ±15%. The winner takes 5% of the loser's
Crew Bank; everyone on the losing side loses 10–25 Health, the winners 3–8.
One hit per attacker→defender pair per hour; no fights inside a cartel, none
from jail. The initiator gains 3 Heat and rolls for a bust like any attack.
The defending crew gets a line in its Crew Chat. *(ours — the original had crew
fights "launched from crew profiles" but no surviving details.)*

## Businesses *(Zack's idea; numbers ours)*

Every block is a business, and every member of the crew holding it gets its perk.
Each hood's blocks A–F are one of each category, and within a category the
business rotates hood to hood:

| Slot | Category | Businesses (perk from one outer block → ceiling) |
|---|---|---|
| A | Production | Grow House / Dust Lab / Pill Factory: that product +7.5% (→ +37.5%) · Utility Co: all three +3.75% (→ +18.75%) |
| B | Transport | Chop Shop: vehicles −7.5% (→ −30%) · Trucking Co: cargo and listing size +18.75% (→ +75%) · Repo Co: resale 53.75% (→ 57.5%) |
| C | Nightlife | Strip Club: hustlers carry +7.5% (→ +30%) · Night Club: trips 7.5% sooner (→ 30%) · Dispensary: +3.75% over street (→ +15%) |
| D | Muscle | Gym: thugs −7.5% (→ −30%) · Shooting Range: mercs and enforcers −7.5% (→ −30%) · Security Firm: crew garrisons +7.5% (→ +30%) |
| E | Retail | Pawn Shop: weapons and protection −3.75% (→ −15%) · Pharmacy: product refills −7.5% (→ −30%) · Warehouse: storage +7.5% (→ +30%) |
| F | Services | Clinic: hospital health −7.5% (→ −30%) · Law Office: bail and bust jail time −11.25% (→ −30%) · Bent Cop: bribes −7.5% (→ −30%) |

These are 75% of the launch values (cut 2026-10-01 along with block bonuses).

- One block's perk doubles from the outer ring to the center hood, ×1.5 when the
  crew holds all six blocks of that hood, ×1.75 if that crew is also in a cartel.
- Several of the same business stack: the best counts in full, each extra adds a
  quarter of its own value, up to double the best one; then the ceiling.
- Perks are personal (prices, speed, amounts), never crew-bank money. At most a
  vehicle costs 70% (Chop Shop) and resells for 57.5% (Repo Co), so nothing sells
  back at a profit.
- The Territory map filters by business; each block shows its perk at that spot,
  with the full hood and with a cartel; the Crew page lists the crew's perks.

## Daily Drop *(Zack's idea and odds)*

A subscription that leaves one crate a day. It will be $2.99 a month; for now
it's free (`_cfg drop_free = 1`) and players subscribe with a button on Home.

- A crate lands at every 00:00 UTC rollover while subscribed, and one straight
  away on subscribing (once per game day, so re-subscribing doesn't farm crates).
- Unopened crates stack up to 7; a day that lands on a full stack is lost.
  Cancelling stops new crates; crates already left can still be opened.
- Each crate is one roll on this table (out of 1,000):

| Prize | Odds | | Prize | Odds |
|---|---|---|---|---|
| 1,000 Herb | 10% | | $100,000 cash | 10% |
| 700 Dust | 10% | | 250 Thugs | 5% |
| 250 Pills | 10% | | 100 Hustlers | 5% |
| 5 Diamonds | 20% | | **Jackpot:** 25 Diamonds | 7% |
| 10 Diamonds | 10% | | **Jackpot:** $1,000,000 cash | 3% |
| 2 Free Refills | 10% | | | |

- Product goes into storage even past the cap (you just can't add more until
  you're back under). Cash lands on hand, with a Bank button on the reveal.
- Free Refills are stamina refill credits: a full refill each that doesn't count
  toward the three product refills a day. Hustlers are credits, one hustler each:
  they waive the $400 hire fee, or for a Trader that hustler's cut.
- Paid plan, later: the payment webhook calls `_drop_subscribe(player, paid_through)`
  and `drop_free` goes to 0. Crates stop after the paid-through day.

## Heat, police and jail

- Police Station (Services): **Bribe** to lower Heat at $40 per point *(wiki)*.
- Getting Busted: when Heat is Red, every action/attack rolls
  `P(bust) = (heat − 74) / 40` *(ours)*. Busted = jailed for 2 hours *(ours)*
  and Heat resets to 40.
- In jail: only Jail Actions; you can still sell commodities, use bank and
  inventory, and fight other inmates (only) using your Jail setup with Jail Weapons.
- Leave jail early: Bail = $2,000 + $50/minute remaining *(ours)*.

## Economy

Commodities: **Herb**, **Dust**, **Pills** (cheap→expensive, bulky→compact).

- **Grow House** (Production Center): one per commodity, upgradeable.
  Produces `rate × level` units/hour up to `cap × level` uncollected.
  Start / Stop / Collect / Upgrade / Abandon. First one is cheap; extra
  houses cost Diamonds *(wiki: "extra grow houses")*.
- **Storage**: holds collected product; base capacity 500 units *(ours)*,
  upgradable with cash.
- **Street Price** *(ours, reworked 2026-09-30)*: base × a small wiggle × what
  hustler dumping has knocked off.
  - The wiggle takes one random step (±4%) every 10 minutes, drifts 10% of the
    way back to base each step, and stays within ±15% (it used to be a ±35% walk).
  - Every unit hustlers sell adds `units / market_depth` of pressure (depth:
    Herb 50,000, Dust 15,000, Pills 5,000 — about $3M of each). Pressure takes up
    to 60% off street and fades by half every 4 hours; stored pressure caps at
    1.5, so a flood clears in hours, not days.
  - A batch sells at the price halfway through its own push, so dumping a
    mountain at once pays less per unit.
- **Hustlers** *(wiki)*: a hustler carries 16 Herb / 8 Dust / 4 Pills, is gone
  4 hours, and returns with cash at the street price at departure. Collect when
  they're back. Without a path they cost $400 each. **Traders** pay nothing up
  front: their hustlers keep 10% of the take, and Traders sell 10% over street
  (stacking with the Dispensary) *(ours)*.
- **Marketplace** *(wiki, extended)*: list 25–1,000 units at up to 150% of
  street *(was: ≤ street)*; listing needs Transport capacity ≥ batch size and
  expires in 48h. Buyers pay cash and need storage room. The seller pays a 5%
  fee on every sale *(ours: a cash sink, and it stops free back-and-forth trades
  for the Market board)*. Cancelled or expired product returns to storage up to
  the cap; the rest waits on the listing until you make room.
- **Buy orders** *(ours)*: post "Wanted: 2,000 Dust at $170" (25–10,000 units,
  up to 150% of street, 5 open at a time). The cash for what's still wanted is
  held off your hand; sellers fill any amount (they need the product and a
  vehicle that carries the lot, and pay the 5% fee); the product lands in your
  storage even past the cap. Cancel any time, or it expires in 48h — what's
  left comes back. The buyer gets a feed line per seller.
- **Prices board**: street per product (and whether dumping is behind it), the
  last trade, and 24-hour volume and average from a trade log.
- **Producers and Traders** *(ours)*: pick a path any time. Until you do you
  can run grow houses up to level 5 and send hustlers at the $400 fee; taking
  a grow house past level 5, or earning 100 reputation (lifetime — spending rep
  doesn't reset it), means picking one. Producers build, run and upgrade grow
  houses but can't send hustlers; Traders send hustlers on the terms above but
  can't run grow houses (theirs stop; anything already grown can still be
  collected). Producers sell on the Marketplace and into buy orders; Traders
  buy there. The first pick is free; switching costs 💎50.
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

- **Block bonus**: every held block pays 75% of its share of the hood's income
  (income ÷ 6 × 0.75, `_cfg block_bonus_pct`; cut from 100%) once every 24h —
  80% to the holding Crew's bank, 20% to its
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

With the original stamina regen (+12/hour) and the seeded numbers. (Regen is currently
boosted 10×, to +120/hour — see `_cfg` — which multiplies the action rows by 10.)

| Income source | Cost | Return |
|---|---|---|
| Actions, low tier | 1 stamina | ~$180 → ~$2,200/hour of regen |
| Actions, top tier (Minigun, crew of 6) | 12 stamina | ~$26,500 → ~$26,000/hour of regen |
| Herb grow house L1 | $5,000 | 20 u/h × $60 = $1,200/hour (pays off in ~4h) |
| Dust grow house L1 | $15,000 + 💎20 | 8 u/h × $200 = $1,600/hour (~9h) |
| Pills grow house L1 | $40,000 + 💎20 | 3 u/h × $600 = $1,800/hour (~22h) |
| Hustler (herb), no path | $400 + 16 herb | $960 after 4h (≈$560 net per trip) |
| Hustler (herb), Trader | 16 herb | $960 × 1.10 × 0.90 ≈ $950 after 4h |
| Marketplace / buy orders | transport | up to 150% of street, buyer pays, seller keeps 95% |
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
