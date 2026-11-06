# Seasons: the rollover runbook

A season is about three months of the Personal Hood and Marcus's campaign. When it ends and the
next one begins, every player gets six fresh blocks on a new draw of businesses and the campaign
starts over. Nothing a player owns changes. This page is what to do on the day, and what happens
when you do it. Rehearsed in `scripts/season-test.sql` (the rollover case) and
`scripts/e2e-seasons.mjs`.

## What a rollover resets, and what it never touches

Reset (keyed by `season_id`, the old rows stay as history):

- The hood: six held blocks on the new draw, levels back to 1, no cash waiting, no boss.
- The hood's perks (`_home_perks` reads the running season only).
- The campaign: Marcus is back on Six Blocks; every mission can be claimed and paid again.
  Objectives that read permanent state (attack power, actions done, a grow house, a crew) are met
  on sight for a returning player, so for them the campaign is a reward track, not a tutorial.

Never touched: `profiles` (cash, bank, diamonds, reputation, slots, crew, cartel, boosts, stats),
inventories and setups, grow houses, hustlers, the marketplace, territory, the forum, chat.

The gate is a first-season thing. A player who had a hood in an earlier season keeps the whole
city open in the next one; only players seeing their first season have tabs locked until Marcus
opens them (`_unlocked`, migration 20261106000025). Without that rule every rollover would lock
Crew, Territory and Fight for every veteran until they replayed fourteen missions.

## The day: Admin › Seasons

Everything is on the Admin page's Seasons tab (`/admin?tab=seasons`), admins only.

1. **Before the end** (any time during the season): fill in *Next season* and tap *Schedule*. The
   start defaults to the exact moment the running season ends, so there is no gap, and the six
   businesses are drawn at that moment, not when you schedule. Name, months and the seven defender
   numbers (blocks 1–6, then the boss) are editable; 12 · 22 · 32 · 45 · 60 · 75 · 95 is the Season 1
   curve (SPEC has the odds table). A scheduled season shows with a Cancel button until it starts;
   a cancelled season stays in *Past seasons* marked cancelled and never runs.
2. **At the end**: nothing to do. `_season()` picks whatever season covers the current time, so at
   the scheduled instant the old one is over and the new one is on. Players see it on their next
   `get_me` (within a minute, or on their next load): a fresh hood on the next look, Marcus's first
   card on Home.
3. **Ending early** (a reset, a broken season): *End Season Now* on the running season sets its end
   to this moment. If nothing is scheduled the city plays with no season (every tab open, Getting
   Started on Home) until you start one. *Start … Now* on the form starts one immediately.

What players see between seasons, if there is a gap: no hood tile, no Marcus, every tab open,
the Territory card without its hood row. Nothing is lost; the next season just hasn't begun.

## If the admin page is out of reach

The same three calls from the Supabase SQL editor (they check `_is_admin`, so run them as the
service role or insert directly):

```sql
-- schedule the next season to start the moment the running one ends
insert into seasons (name, starts_at, ends_at, home_businesses, home_defenders)
select 'Season 2', s.ends_at, s.ends_at + make_interval(months => 3),
       (select array_agg(code) from (select code from business_defs order by random() limit 6) x),
       array[12, 22, 32, 45, 60, 75, 95]
  from seasons s where s.starts_at <= now() and s.ends_at > now();

-- end the running season now
update seasons set ends_at = now() where starts_at <= now() and ends_at > now();

-- move a season's dates (the clock, not the draw)
update seasons set starts_at = '2027-02-08 08:00+00', ends_at = '2027-05-08 08:00+00' where name = 'Season 2';
```

Two seasons must never overlap (`season_start` refuses; a direct insert won't, so check the dates).
A season with `cancelled_at` set is ignored everywhere: to cancel by hand, set it rather than
deleting the row.
A season's `home_defenders` and `home_businesses` can be updated in place at any time; the hoods
already made keep the businesses they were made with (`home_blocks.business`), so change the draw
only before a season starts.

## Checks after a rollover

- `select name, starts_at, ends_at from seasons order by starts_at desc limit 2` — the new one
  covers now, the old one ended when it should.
- Load the game as any player: Marcus on Six Blocks, Your Hood with six held tiles, the top-bar
  cash the same as before.
- Admin › Seasons: the old season in *Past seasons* with its player and boss counts.
