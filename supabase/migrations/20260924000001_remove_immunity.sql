-- Remove new-player immunity.
-- New accounts get immune_until = now() (0 hours), and anyone still protected loses it now.
-- The immune_until column and the checks that read it stay, but they never trigger.

create or replace function _cfg(key text) returns numeric language sql immutable set search_path = public as $$
  select case key
    when 'regen_minutes'      then 10     -- every 10 min: +2 stamina, +2 health, -1 heat
    when 'heat_yellow'        then 40
    when 'heat_red'           then 75
    when 'jail_minutes'       then 120
    when 'bail_base'          then 2000
    when 'bail_per_minute'    then 50
    when 'bribe_per_heat'     then 40
    when 'hospital_per_point' then 40
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
    else 0 end $$;

alter table profiles alter column immune_until set default now();

update profiles set immune_until = now() where immune_until > now();
