# App Store screenshots

This folder is the 6.9" iPhone set, the one App Store Connect requires: 1320 × 2868, portrait, PNG, RGB with no alpha channel. Apple scales it down for the smaller phones. `../screenshots-6.7/` has the same eight screens at 1290 × 2796 for the optional 6.7" slot. Upload them in this order.

| File | Screen | What it shows |
|---|---|---|
| `01-home.png` | Home | The top bar (cash, diamonds, heat, stamina, health). "While you were away": an attack held off, a marketplace sale, a block taken for the crew. Last week's stripes, the stats, and the Daily Drop with two crates waiting. |
| `02-actions.png` | Actions → Reputation | The session tally, a job just done with its result on the row, and each job's stamina, reputation, cost, heat and rare-find odds. |
| `03-economy.png` | Economy → Production | The Producer path, storage with street prices and the Warehouse perk, and a level 8 herb grow house about 60% full with Collect and Upgrade. |
| `04-market.png` | Economy → Marketplace | Scrolled to the market itself: buy orders from other players (Wanted) and listings (For Sale). |
| `05-fight.png` | A rival's profile | The fight preview before an attack: odds, both sides' edges, gear, combos, and Attack, Chat, Report and Block. |
| `06-territory.png` | Territory | The 9×9 city map with your crew's hoods in green and a rival crew's in red, plus your thugs, mercs and spies. |
| `07-crew.png` | Your crew | Members, blocks, crew bank, crew attack and defense, the crew fight record and the bank ledger. |
| `08-profile.png` | Profile | Stripes, cash, bank, diamonds, reputation, actions, fight record, market volume and the three setups. |

## The 4+ rule

The app is 18+, but screenshots have to suit a 4+ rating (guideline 2.3.8). None of these show the casino, a weapon aimed at anyone, or anything gory. The Actions shot uses the Reputation sort: the cash jobs say "dime bags" at the top of the list and get rougher further down.

## Making them again

`scripts/app-store-shots.mjs` takes them from the local web build, signed in as `bot01@demo.local`. Before each set it dresses bot01 up as "Domino" (a settled producer with gear, fights, activity and stripes) and swaps the demo world's names for made-up ones, since the seed borrows real cartel names and TV characters. It only touches the local demo database.

```
scripts/local-db.sh reset && scripts/local-db.sh demo
node scripts/dev-server.mjs &
(cd web && VITE_SUPABASE_URL=http://127.0.0.1:54321 VITE_SUPABASE_ANON_KEY=local npx vite --port 5173 --strictPort &)
node scripts/app-store-shots.mjs            # both sets; SETS=6.9 for the required one only
```

`BASE` and `PGPORT` work as in the other scripts. The script checks every PNG's size and that it has no alpha channel, and fails if one is off.

Take them again after UI changes, and once purchases ship: the Daily Drop card on Home says "free plan" today. The fonts are whatever the machine running the script has. On Linux the headings come out in a condensed Helvetica; on an iPhone they're Helvetica Neue.
