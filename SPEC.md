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
| Health | 100 | 500 (upgrade with Diamonds) | +5 / 5 min *(ours — faster hospital exits)* | ≤19 = **Hospital**: no actions, no attacks. Buy health at the Hospital on a sliding scale: $40/pt base, and the per-point price rises by 1× for every 100 points bought in the last 24h (like hoodlums) *(ours)*. Health is sold **to full only** *(Zack, 2026-10-02)*: one Heal to Full price, or wait till you have the cash (or heal on your own). No point picker and no partial check-out. |
| Heat | 0 | 100 (+50 per 💎30 upgrade, no cap *(Zack)*) | decays −1 / 10 min *(ours)* | Green 0–39, Yellow 40–74, Red 75+ at base; each heat upgrade moves both lines up 50 with the max (one upgrade: max 150, yellow 90, red 125). Rises with Actions and Attacks. At Red each action/attack risks getting **Busted** (jail). More heat than your opponent is a +1 fight edge. |
| Cash ($) | tutorial grant | — | — | Cash on hand can be taken in fights. Banked cash is safe. More cash on hand than your opponent is a +1 fight edge. **Daily cash**: every account — players and the NPC thugs — gets $50,000 on hand at 00:00 UTC, online or not *(ours)*. A thug's daily cash sits on top of its stash until hunters take it. |
| Diamonds | starter grant (25) | — | — | Premium currency: refills, max-stat upgrades, inventory slots, extra grow houses, boosts. Earned via milestones (see Fighting) and the Daily Drop, or bought in the iOS app (see Store). |

Refills: full Stamina for 6 Diamonds or 400 Herb / 280 Dust / 100 Pills *(wiki)*;
full Health for 6 Diamonds *(wiki)*. **Drug refills** *(Zack, 2026-10-01)*: herb, dust
and pills refill stamina only (health comes from the Hospital or diamonds). Each drug
fills your stamina all the way **3 times a game day**, counted per drug, so 9 a day if
you hold all three; **Daily Drop subscribers get 5 of each** (`refill_sub_extra` = 2).
Past those, a refill of that drug restores **half your stamina bar** (50% of max, up to
full; `refill_late_share`). The counts reset at the 00:00 UTC rollover; diamond and
Daily Drop (free) refills are always full and don't count. *(Until 2026-10-01: 3 full
product refills a day across all drugs, health included, then ½, ¼, ⅛ … of what's
missing.)*

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
buys six **rare items** (a gold-plated Desert Eagle, Kingpin's Machete, an
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
appear on Top Users, the weekly boards or ribbons, and the **Players** tab lists them
only when you search for one by name (an empty search is real players only).
The Players tab *(Zack, 2026-10-02)* searches by name and filters with chips:
**All**, **Can fight** (out of the hospital and on your side of the bars, the same
checks as Attack), **Online** (seen in the last 5 minutes), **Hospital** and
**Jail**. Each chip shows how many players the search would list under it. It
sorts by last seen, most wins, most rep or name. Anyone you can't hit right now
is dimmed and says why, and the online ones have a green dot. The search, filter
and sort stay in the URL, so Back from a profile lands on the same list. The last
filter and sort you picked come back the next time you open the tab, on that
device. The list shows 50 at a time.
The winner takes 5–10% of the loser's cash on hand *(ours)*;
after three hits on the same target within an hour the cash dries up (fights
still happen, no money moves) *(ours, anti-farming)*. Anyone dropping to ≤19 Health lands in
Hospital. Attacking adds Heat.

Setups: every player keeps an **Offensive**, **Defensive** and **Jail** setup.
Equipped items count only within the setup in use (offense when you attack,
defense when attacked, jail for both while jailed). Items are never consumed.
Slot count = Inventory slots (base 6 *(ours)*). Each slot past six costs more
*(Zack)*: the k-th extra slot (k = 1 for the 7th) is 1 Diamond, plus one more every
4 slots *(Zack: "a total of 2k diamonds")*, **and** $20,000 × k cash on hand
*(Zack: the cash reachable by a free daily player in about six months)* — 7th 1💎 +
$20k, 11th 2💎 + $100k, 31st 7💎 + $500k, 100th 24💎 + $1.88M, 130th 31💎 + $2.48M;
💎1,984 + $155M for all 124 (it was 10 + 5k 💎 and $100,000 × k², $64B in all).
Slots already bought stay. Slots top out at **130** *(Zack, the original's cap)*.

**Milestones** pay the diamonds, once each *(ours; the ladder was lengthened with
the slot change — a daily player earns about 💎860 in six months. Zack kept it there
when slot diamonds went to ~2,000, so the diamonds for all 130 take a free player
longer than the cash does)*:

| Actions | 50 | 100 | 250 | 500 | 1k | 2.5k | 5k | 10k | 15k | 20k | 30k | 50k | 100k |
|---|---|---|---|---|---|---|---|---|---|---|---|---|---|
| 💎 | 5 | 10 | 15 | 25 | 50 | 50 | 100 | 100 | 100 | 125 | 150 | 200 | 250 |

| Fight wins | 10 | 100 | 250 | 500 | 1k | 2.5k | 5k | 10k | 25k |
|---|---|---|---|---|---|---|---|---|---|
| 💎 | 5 | 20 | 25 | 30 | 75 | 50 | 75 | 100 | 150 |

| All fights (won or lost) | 100 | 500 | 1k | 2.5k | 5k | 10k | 25k | 50k |
|---|---|---|---|---|---|---|---|---|
| 💎 | 5 | 15 | 30 | 50 | 75 | 100 | 150 | 200 |

| Casino wagered | $1M | $5M | $10M | $25M | $50M | $100M | $250M | $500M | $1B |
|---|---|---|---|---|---|---|---|---|---|
| 💎 | 5 | 10 | 20 | 30 | 50 | 75 | 100 | 150 | 250 |

**Repeating milestones** *(Zack, 2026-10-01)* pay **💎30 every time**, forever, on
top of the ladders: every **250 actions**, every **500 fight wins**, every **500
turf attacks** (any attack on a block, won or lost; spying isn't one) and every
**$10,000,000 wagered at the casino** (every game, poker included). Players already
past a step were paid for it when this shipped. Each payout puts one 🏅 line in the
activity feed per count (the highest step reached and the diamonds). The
Milestones card on Services shows each repeating step with a bar to the next one,
and the ladders on tap. Turf attacks and casino wagered are counted on the profile
by triggers on `territory_log` and `casino_bets`.

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
| F | Services | Clinic: hospital health −7.5% (→ −30%) · Law Office: bail −11.25% (→ −30%) · Bent Cop: bribes −7.5% (→ −30%) |

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

A subscription that leaves one crate a day. It will be a monthly App Store subscription
in the iOS app (see Store); for now it's free (`_cfg drop_free = 1`) and players subscribe
with a button on Home or in the Store.

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
  toward the drug refills a day. Hustlers are credits, one hustler each:
  they waive the $400 hire fee, or for a Trader that hustler's cut.
- The card shows this table, with each prize's odds, above the Subscribe button
  (Apple's rule for paid random prizes).
- Paid plan: the store webhook calls `_drop_subscribe(player, paid_through)` (see Store).
  Crates stop after the paid-through day.

## Heat, police and jail

- Police Station (Services): **Bribe** to lower Heat at $40 per point *(wiki)*.
- Getting Busted: when Heat is Red, every action/attack rolls
  `P(bust) = (heat − red + 1) / 40` *(ours; red is 75 plus any heat upgrades)*.
  Busted = jailed until you post bail *(Zack)*.
- **Heat upgrades** *(Zack)*: 💎30 buys +50 max heat and moves the yellow and red lines
  up 50 — 50 more heat before any bust risk. Flat price, no cap.
- **Going to jail on purpose**: the Bribe Police To Get In Jail job (10 stamina, $1,000),
  or turn yourself in at the Police Station for 💎50 *(Zack)* — no stamina or cash, and
  it isn't an action. Not while in the hospital. Either way you're in until you post bail.
- In jail: only Jail Actions; you can still sell commodities, use bank and
  inventory, and fight other inmates (only) using your Jail setup with Jail Weapons.
- **No sentences** *(Zack, 2026-09-30: "stay in jail until you pay to get out")*: every way
  in — busts, the job, the 💎50 turn-in — lasts until you post **bail: $8,000 flat**
  from cash on hand, less the Law Office (up to 30% off). (It used to be 2 hours, with
  bail at $2,000 + $50 a minute left.) Since only inmates can hit inmates, jail also
  works as a hideout for anyone willing to sit in it.
- **Heat in and out of jail** *(Zack, 2026-10-02)*: going in by any of those ways sets
  your heat to your max (100, or more with heat upgrades), and posting bail sets it to 0.
  (A bust used to drop you to your yellow line.) Heat keeps cooling while you're inside,
  and jail jobs and jail fights add their usual heat, so there's no point bribing the
  police in jail: bail clears it anyway.

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

## Moderation *(Zack, 2026-09-30)*

- **Names**: 3–20 characters, no control characters, not taken (in any case), not
  `player_…` (the placeholder) or `Thug N` (the NPCs), and nothing the word filter blocks.
  The sign-up form checks the name before creating the account. A name that still fails
  at sign-up becomes a `player_xxxxxxxx` placeholder, and the player gets a prompt to
  pick a real one. Otherwise names can't be changed, except after an admin resets them.
- **Word filter** (`banned_words`, editable by admins): new player, crew and cartel names,
  avatars, bios, crew emblems and descriptions, and forum thread titles can't contain a listed
  word. Matching undoes number and symbol swaps (0→o, 1→i, 3→e, 4→a,
  5→s, 7→t, @→a, $→s) and stretched letters (fuuuck). Each word matches one of three ways:
  - **anywhere**, even split up by spaces or dots: the worst slurs and swears;
  - **inside a word**, where camelCase splits words;
  - **whole word only**, so Assassin, Cocktail, Therapist and Dickens pass.
  Existing names aren't touched. Zack left DickBickGus and Str8Gey as they are.
- **Split-up words** *(Zack, 2026-10-01)*: before an "anywhere" word is matched, the text's words
  are grouped. Two neighbours join when either has 1–2 letters or both have 1–3, which is what a
  split-up word looks like: f.u.c.k, fu ck, fuc k, nig ger and nigg er each become one group. The
  word has to sit inside one group (xNiGGeRx, FuckBoy), or be spelled by whole groups in a row
  (white power, Sieg Heil). Two ordinary words stay apart, so "music until dawn", "panic until
  the cops leave" and a player called Music Until pass instead of reading as musi**c unt**il.
- **Chat and forum posts** *(Zack, 2026-10-01)*: chat messages, forum threads and replies are
  checked against the words that have their **chat** switch on, each matched its own way (a
  whole word only as a whole word of the message). Admins flip it per word on the Word Filter
  tab, on every tier; new words start with it on. Slurs and hate have it on, whole words
  included (coon, paki, spic, fag, dyke, homo, nazi, heil, rape, rapist, pedo), so "you fag" is
  refused. Crude words that aren't hate have it off — shit, bitch, whore, slut, porn, penis,
  vagina, asshole, jizz, dildo, blowjob, handjob, cumshot, and the whole words dick, cock, ass,
  arse, cum, anal, anus, tits, boob, pussy, twat, wank, prick — so "bullshit", "kiss my ass" and
  "son of a b1tch" go through in a crime game while names, avatars, bios, crew names and forum
  titles stay strict. Old messages and posts aren't touched.
- **Reports**: a 🚩 Report button on other players' profiles (not thugs). Players pick
  name, avatar, bio or other and can add a note. Each player can have one open report
  per person they've reported, and send 10 reports a day. A report keeps a snapshot of
  the profile at the time.
- **Reports of content** *(Zack, 2026-10-01)*: Apple wants reporting to cover what players
  post (guideline 1.2). Someone else's chat line has a ⋯ that opens Report and Block; forum
  threads and replies have a 🚩 Report button. The reasons are harassment, hate, spam, threat
  or other, plus an optional note. You can report only what you can read (a channel you're in,
  a DM you're part of, a post that's still up), never your own, never a thug's. One open report
  per message or post, and the 10 a day covers profiles and content together. The report keeps
  the text, where it was and who wrote it, so the admin sees it even after it's gone.
- **Admins** (`profiles.is_admin`) get:
  - a Home notice and an Admin page (from Profile) with the open reports, grouped by player,
    each marked Profile, Message, Thread or Reply, with the reported text;
  - four actions, also on any profile: reset the name (placeholder plus a free rename
    prompt), reset the avatar (🕶️), clear the bio, or dismiss the reports;
  - **Delete** on a reported message, thread or reply that's still up. A deleted chat line
    keeps its place but loses its text and is never shown again, in history or live. A deleted
    thread or reply is the forum's own delete: the reply shows [deleted], the thread is gone;
  - the **mute ladder** *(Zack, 2026-10-01)*: mute for 1 day, 7 days or 30 days, also on any
    profile, and Unmute. A muted player can't chat (DMs included), start threads, reply, edit
    posts, or rewrite their bio or crew description (clearing them is fine). The chat and reply
    boxes say "You're muted until …"; the server refuses with the time in UTC. A new mute
    replaces the old one. Everything else in the game works as usual.
  A delete closes the reports on that message or post; every other action except Unmute closes
  all of that player's open reports. Each goes in the moderation log (with the old text) and
  leaves the player an activity line ("An admin removed one of your messages", "An admin muted
  you until …", "An admin lifted your mute"). Adding and removing filter words and flipping
  their chat switch are logged too.

## Blocking *(Zack, 2026-10-01)*

Apple wants a way to block abusive players (guideline 1.2). A 🚫 Block button sits next to
🚩 Report on other players' profiles (not thugs) and in the ⋯ on their chat lines, with a
confirm; Profile lists who you've blocked, each with Unblock. Blocking is about talking, and
the server enforces all of it:
- **DMs** stop both ways: neither side can send, and the conversation drops out of both
  players' lists and unread counts. The old history stays readable if you open it.
- **Group chat** (Live, Crew, Cartel, table): their lines are left out for you, old and new,
  with no gap. One way only: they still see yours.
- **Forum**: their threads and replies show "Hidden — you blocked this player" in place of the
  text; titles and author lines stay so threads still make sense.
- **Crews and cartels**: they can't apply to a crew whose Capo or Co-Capo blocked them, and as
  Don they can't invite a crew whose Capo blocked them. Blocking declines anything of theirs
  still pending with you.
- Fights, trades, listings, sending cash and everything else work as before.

## Moderation routine *(Zack, 2026-10-01)*

Apple wants timely responses to reports (guideline 1.2), and the admin only saw the queue
when he opened the game. Now a new report pings him: one Discord post (or email) saying how
many players have open reports, how many reports that is, and what the latest one says, with
a link to the Admin page. At most one ping every 10 minutes, so a burst of reports (or one
player spamming them) sends one message, and the next ping carries the counts. The ping is
best-effort: if it fails, the report still goes in. The admin checks the queue once a day
regardless. Setup, the escalation ladder and adding a second admin are in `docs/ops.md`.

## Account deletion *(Zack, 2026-10-01)*

Apple wants an app that makes accounts to let people delete them in the app (guideline 5.1.1(v)). Profile → Account →
**Delete account** opens a sheet that says what goes and what stays; typing your street name (any case) unlocks
**Delete forever**, and the server checks the name again. It happens at once and signs you out. Thugs can't be deleted.
- **Your crew** carries on without you, with the same succession as leaving: the Co-Capo takes over, else the
  longest-standing member (oldest account). A crew of one disbands, freeing its blocks and dropping out of its cartel.
  A Don's title goes to the crew's new Capo; if the Don's crew disbands, the Capo of the cartel's oldest remaining crew
  becomes Don, and a cartel left with no crews dissolves. Crew and cartel banks stay with the crew and cartel.
- **Loose ends** are settled first, the usual way: open listings and buy orders are cancelled, and a poker seat is given
  up, folding a live hand so the table plays on (chips already in that pot go with the player).
- **Gone**: the sign-in, the profile and everything in it (cash, bank, diamonds, gear, product, grow houses, hustlers,
  hoodlums), chat lines, DMs (both sides of the conversation), forum threads (with their replies) and replies, casino
  history, reports and blocks.
- **Stays, without the name**: fights (the other player's log reads "Deleted player attacked you" with nothing to tap,
  so their win/loss record still adds up to it, and the city's combo stats keep counting them), market trades, crew and
  cartel ledger entries, the territory log and other players' activity lines ("A deleted player attacked you"). Threads
  that lost replies are recounted.
- **Deleting the user in the Supabase dashboard** runs the same crew succession (the profile delete trigger), so it works
  for Capos and crew members too. The other loose ends (listings, buy orders, a poker seat, DMs, thread counts, the
  tally) are only settled by the in-app delete.
- `deleted_accounts` keeps a tally — the date, days from sign-up, and whether the account ever paid (a paid Daily
  Drop, or diamonds bought and not refunded) — and nothing that identifies the player.
- Deleting doesn't cancel an Apple subscription; the sheet, Support and the Privacy Policy all say so.

## Store *(Zack, 2026-10-01)*

Diamond packs and the Daily Drop subscription are sold through Apple's in-app purchase in the iOS app (guideline
3.1.1). RevenueCat runs the purchase on the phone and tells the server through a webhook (the `iap-webhook` edge
function, which calls `iap_apply`); setup is in `docs/ops.md`. The web build sells nothing: its Store (Home →
Diamonds) lists the packs with "Diamonds are sold in the iPhone app" and no prices or buttons.

- **Packs are data.** `store_packs` holds each App Store product id, its diamonds and its place in the list. The
  suggested packs (#7) are 100, 550, 1,200, 2,600, 7,000 and 15,000 diamonds. Prices are set per product in App
  Store Connect and come from StoreKit on the phone, in the player's currency; the game never names one. In the app
  the Store shows only the packs the App Store actually sells. A pack switched off (`active`) leaves the Store, and a
  late purchase of it still pays out.
- **Buying**: StoreKit takes the payment, the webhook credits the pack, and Activity says "You bought N diamonds".
  The app watches for the diamonds for up to 20 seconds ("Delivering…"), then says they're on their way.
- **Purchased diamonds never expire and can't be gifted.** Send Diamonds only sends diamonds earned in the game
  (the starter 25, milestones, crates, gifts from others): "You can only send diamonds you earned in the game".
  That's Apple's rule on gifting purchases, and it closes the stolen card → alt account → chargeback loop.
  Spending takes purchased diamonds first, so as much as possible of what's left can be sent. The server keeps the
  count in `profiles.diamonds_bought_unspent`; a trigger on `profiles` takes every drop in diamonds off it (floored
  at 0) instead of changing the twenty-odd places diamonds are spent, and Send Diamonds puts the gift back because a
  gift is earned diamonds.
- **Refunds claw back.** When Apple refunds a pack, the diamonds that purchase gave come off the balance, never
  below 0: what was already spent stays spent. Activity says how many were taken back. `diamonds_bought` (lifetime)
  drops by the pack too.
- **The webhook is idempotent and on the record.** Every call writes one `iap_grants` row, keyed on (provider,
  transaction, event), so RevenueCat's retries change nothing; ignored calls (unknown products, unknown players,
  events we don't use) are recorded too. The rows stay, without the player, when an account is deleted.
- **The Daily Drop subscription** (`io.rangelab.cartelwars.drop.monthly`, monthly, renews until cancelled): a
  purchase, renewal, re-enabled renewal or plan change pays it through the end of the period Apple reports
  (`drop_until`), and a late event never moves that date back. Expiry lets it lapse; a refund ends it at once;
  turning off renewal or a billing problem changes nothing until Apple says it has expired (a billing problem gets
  Apple's grace period first). A paid plan is cancelled in the device settings, not in the game: the card says
  "paid through" and has Manage subscription where Cancel was. Crates already left stay either way.
- **Free until it goes live.** While `drop_free` is 1 anyone can take the free plan, in the app too. Zack sets it to
  0 when the subscription goes live: from then on the app's Subscribe button is the App Store purchase (with the
  price, "per month, renews until cancelled", and the Terms and Privacy links), the web says it's an iPhone
  subscription, and `subscribe_drop` refuses.
- **Odds before purchase.** The Daily Drop card always shows the prize table and each prize's odds above Subscribe
  (guideline 3.1.1 on paid random prizes), with Terms and Privacy links next to the button (3.1.2). Diamond packs
  are fixed amounts.
- **Restore purchases** in the Store brings back a subscription bought on the same Apple ID. Packs are used up when
  bought, so there's nothing to restore for them.

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
Home shows the notices, the stats (heat, bank, reputation, attack, defense,
storage), then a 3×3 grid to everything with no tab: Items, Crew, Cartel,
Territory, Casino, Forum, Activity, Accolades, Store. The top bar is tappable:
cash opens the bank, diamonds the store, heat the police, stamina the refills,
health the hospital, the name your profile. In jail the heat bar's corner is a red
**JAIL** tag instead (heat is maxed inside), which opens the jail card *(Zack, 2026-10-02)*.

**Interface rules** *(Zack, 2026-10-01)*: the thing a screen is for sits on its
first screen at 375 × 667 (Attack above the odds, the market offers above the
sell form, crew applications above the ledger, a casino table's chips and Roll
in a bar that stays in reach). Every tap target is at least 44 pt (small buttons
and tabs carry an invisible hit area). Text is at least 11 px and passes 4.5:1
on its background. Rows that navigate are real links or buttons, so they take
focus and VoiceOver calls them that. Toasts sit above the tab bar, not over the
cash they just changed; a lost connection says "Can't reach the city" once and
then shows an Offline pill until a poll succeeds. Sheets have a sticky title
with an ×, close on Escape and keep focus inside. Buttons: `doit` is the one
primary verb on a screen (Title Case), `gold` spends or confirms, red `doit` is
an attack, `red` deletes, `ghost` is secondary, `ghost red` leaves or kicks.
Copy: short, second person, no exclamation marks, emoji only as icons. A spend
that is irreversible or costs over half your cash asks first, in the game's own
sheet (title, one line, Cancel beside the action it names), never the browser's
`confirm()`, which some browsers and embedded web views mute or answer no by
themselves.
Landing in the hospital works the same way *(Zack, 2026-10-02)*: Actions from a hospital
bed, a player's page and a fight's result offer **Heal to Full** in place, at the
hospital's price. Short of cash, the button is off and says what you have.
Getting busted offers **Post Bail** right where it happened *(Zack, 2026-10-02)*: the
bust sheet after a job, a fight's result and a crew fight's result pay bail on the spot
(the same price as the jail card, from cash on hand) and leave you where you were. Short
of cash, the button is off and points at the bank. After the Bribe Police job, a
deliberate trip in, **Stay inside** is the main button and bail is the quiet one.
A fight's result sheet has Attack again under the result, with the same checks as
Attack (hospital, jail), so a streak is one tap per fight. Short on stamina is
never a dead button: Do It, Attack and a turf attack open the refill sheet (free,
diamonds, or product, each priced with what it restores), and so does any server
refusal for stamina (crew fights). The server still checks every refill.
Hoodlums are hired where they're used as well as at Services: Territory's Thugs,
Mercs and Spies tiles open a hire panel on the page, and a block's attack sheet
that is short of thugs offers the missing ones, which join that attack.

## iOS app *(Zack, 2026-10-01)*

The App Store build is the same React app inside a native shell (Capacitor 8,
`web/ios`). It ships its own copy of the web build and never loads the GitHub
Pages site (Apple guideline 4.2). It talks to the same Supabase project and has
the same features as the web build. iPhone only, portrait only, iOS 15 and up.

What differs from the web:
- **Links out of the app open in Safari.** A password-reset email requested in
  the app points at the live web app, because the app's own address
  (`capacitor://localhost`) can't be a Supabase redirect. The player sets the new
  password there and signs in to the app with it.
- Coming back to the app refreshes the player state at once. The tab bar hides
  while the keyboard is up.
- **Purchases**: diamond packs and the Daily Drop subscription go through Apple's
  in-app purchase inside the app (guideline 3.1.1); the web build sells nothing
  (see Store).

Both builds: if the first load can't reach the server (offline, dead Wi-Fi), the
game shows **Can't reach the city** with a Retry button instead of a spinner.
Once the player is in, failed requests are toasts as before.

**Versioning**: the version (`MARKETING_VERSION` in the Xcode project, 1.0.0 at
launch) goes up for every App Store release: the last number for fixes, the
middle one for new features. The build number is the GitHub Actions run number,
set at build time, so every TestFlight upload is higher than the one before. Tag
what ships `ios-v<version>`. Building, signing and the secrets are in `docs/ios.md`.

## Architecture

- **Supabase / Postgres**: every state change is a `SECURITY DEFINER` RPC
  (`do_action`, `attack`, `buy_item`, `equip`, …). Clients only ever call
  RPCs and read views. Regen (stamina, health, heat, production, hustler
  trips, listings expiry, hood income) is computed lazily from timestamps
  inside `tick_player()` — no cron needed.
- **Web**: Vite + React + TypeScript, `@supabase/supabase-js`,
  `react-router-dom`. One `useGame()` hook keeps the full player state
  (`get_me()`), refreshed after every RPC.
