-- Two tuning changes:
--  * Daily Drop: the thugs prize is 250 thugs (was 1,000, which at shop prices was worth more than the
--    $1,000,000 jackpot). Same 5% odds.
--  * Block bonuses are 25% lower: each held block now pays 75% of its sixth of the hood's daily income
--    (_cfg block_bonus_pct). Hoods keep their income figure; the payout and what the map shows both go
--    through _block_bonus, so they stay in step. Bonuses already due pay at the new rate.

-- ---------------------------------------------------------------------------
-- Daily Drop: 250 thugs
-- ---------------------------------------------------------------------------
-- Prize codes can be renamed from now on; past opens follow the rename (each open keeps the amount it paid).
alter table drop_opens drop constraint if exists drop_opens_prize_fkey;
alter table drop_opens add constraint drop_opens_prize_fkey foreign key (prize) references drop_prizes(code) on update cascade;
update drop_prizes set code = 'thugs_250', label = '250 Thugs', amount = 250 where code = 'thugs_1000';

-- ---------------------------------------------------------------------------
-- Tunables
-- ---------------------------------------------------------------------------
create or replace function _cfg(key text) returns numeric language sql immutable set search_path = public as $$
  select case key
    when 'regen_minutes'      then 10     -- heat cools 1 point every 10 min
    -- Regen boost (10x): stamina +2 every minute (was every 10), health +10 every minute (was +5 every 5).
    -- To go back: stamina_regen_minutes 10, health_regen_minutes 5, health_regen_amount 5.
    when 'stamina_regen_minutes' then 1
    when 'stamina_regen_amount'  then 2
    when 'health_regen_minutes' then 1
    when 'health_regen_amount'  then 10
    when 'hospital_release_pct' then 20   -- knocked out at 19 health or less; back out at this % of max health
    when 'heat_yellow'        then 40
    when 'heat_red'           then 75
    when 'jail_minutes'       then 120
    when 'bail_base'          then 2000
    when 'bail_per_minute'    then 50
    when 'bribe_per_heat'     then 40
    when 'hospital_per_point' then 40     -- base $ per health point
    when 'health_price_scale' then 100    -- price per point grows by 1x for every 100 points bought in 24h
    when 'refill_diamonds'    then 6
    when 'hustler_price'      then 400
    when 'hustler_hours'      then 4
    when 'listing_min'        then 25
    when 'listing_max'        then 1000
    when 'crew_max'           then 12
    when 'immunity_hours'     then 0      -- new-player immunity removed
    when 'starter_cash'       then 10000
    when 'starter_diamonds'   then 25
    when 'extra_grow_diamonds' then 20
    when 'crew_fight_stamina' then 5
    when 'crew_fight_cooldown_min' then 60
    when 'crew_fight_stake_pct' then 5
    when 'path_rep'           then 100    -- lifetime reputation at which a player must pick Producer or Trader
    when 'path_switch_diamonds' then 50   -- cost to switch paths afterwards
    when 'siege_wins'         then 50     -- successful hits a crew needs to take an owned block
    when 'siege_min_thugs'    then 51     -- thugs needed to launch a turf attack
    when 'block_bonus_hours'  then 24     -- each block pays its bonus on this cycle
    when 'block_bonus_pct'    then 75     -- ... this % of its sixth of the hood's daily income (was 100)
    when 'daily_cash'         then 50000  -- cash on hand every player account gets at 00:00 UTC
    when 'counter_pct'        then 35     -- the losing side's hit lands at this % of its score
    when 'bot_min_strength'   then 0.5    -- Thug 1 fights at this share of its gear, rising to 1.0 at Thug 200
    when 'drop_stamina'       then 6000   -- rare-find chance per action = stamina_cost / this (12 stamina → 1 in 500)
    when 'drop_max_crates'    then 7      -- Daily Drop: unopened crates stack up to this many
    when 'drop_price_cents'   then 299    -- Daily Drop: $2.99 a month once it's paid
    when 'drop_free'          then 1      -- Daily Drop: 1 = free to subscribe for now
    else 0 end $$;

-- ---------------------------------------------------------------------------
-- Block bonus: per block, per cycle
-- ---------------------------------------------------------------------------
create or replace function _block_bonus(daily_income integer) returns bigint language sql immutable set search_path = public as $$
  select floor(daily_income / 6.0 * _cfg('block_bonus_hours') / 24.0 * _cfg('block_bonus_pct') / 100.0)::bigint $$;

do $$ declare f record; begin
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('_cfg', '_block_bonus') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
end $$;
