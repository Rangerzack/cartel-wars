-- Faster hospital recovery.
--  * Health regenerates on its own clock: +5 every 5 minutes (stamina and heat keep the 10-minute tick).
--  * Health can be bought at the Hospital on a sliding scale, like hoodlums: the per-point price rises
--    with how many points you've bought in the last 24 hours.
-- Also adds the tunables used by the later migrations in this batch.

create or replace function _cfg(key text) returns numeric language sql immutable set search_path = public as $$
  select case key
    when 'regen_minutes'      then 10     -- every 10 min: +2 stamina, -1 heat
    when 'health_regen_minutes' then 5    -- every 5 min: +health_regen_amount health
    when 'health_regen_amount'  then 5
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
    else 0 end $$;

alter table profiles add column if not exists health_tick      timestamptz not null default now();
alter table profiles add column if not exists health_bought    integer     not null default 0;
alter table profiles add column if not exists health_bought_at timestamptz;

-- Player tick: lazy regen. Locks the row; returns the fresh profile.
create or replace function _tick(p uuid) returns profiles language plpgsql set search_path = public as $$
declare pr profiles; ticks int; hticks int;
        step  interval := make_interval(mins => _cfg('regen_minutes')::int);
        hstep interval := make_interval(mins => _cfg('health_regen_minutes')::int);
begin
  select * into pr from profiles where id = p for update;
  if pr.id is null then raise exception 'No such player'; end if;
  ticks := floor(extract(epoch from now() - pr.last_tick) / extract(epoch from step))::int;
  if ticks > 0 then
    pr.stamina   := least(pr.stamina_max, pr.stamina + 2 * ticks);
    pr.heat      := greatest(0, pr.heat - ticks);
    pr.last_tick := pr.last_tick + ticks * step;
  end if;
  hticks := floor(extract(epoch from now() - pr.health_tick) / extract(epoch from hstep))::int;
  if hticks > 0 then
    pr.health      := greatest(pr.health, least(pr.health_max, pr.health + _cfg('health_regen_amount')::int * hticks));
    pr.health_tick := pr.health_tick + hticks * hstep;
  end if;
  if pr.jail_until is not null and pr.jail_until <= now() then pr.jail_until := null; end if;
  if pr.refills_used > 0 and pr.refills_reset_at <= now() - interval '24 hours' then
    pr.refills_used := 0;
  end if;
  if pr.health_bought > 0 and pr.health_bought_at <= now() - interval '24 hours' then
    pr.health_bought := 0; pr.health_bought_at := null;
  end if;
  update profiles set stamina = pr.stamina, health = pr.health, heat = pr.heat, last_tick = pr.last_tick,
         health_tick = pr.health_tick, jail_until = pr.jail_until, refills_used = pr.refills_used,
         health_bought = pr.health_bought, health_bought_at = pr.health_bought_at
   where id = p;
  return pr;
end $$;

-- Price of n health points when `bought` points were already bought in the last 24h (like _hoodlum_price).
create or replace function _health_price(bought integer, n integer) returns bigint
language sql immutable set search_path = public as $$
  select ceil(_cfg('hospital_per_point') * n * (1 + (bought + n / 2.0) / _cfg('health_price_scale')))::bigint $$;

create or replace function buy_health(points integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; missing int; cost bigint;
begin
  perform _nn(points, 'points');
  pr := _tick(u);
  missing := pr.health_max - pr.health;
  if missing <= 0 then perform _fail('You are already at full health'); end if;
  if points < 1 then perform _fail('Buy at least 1 point'); end if;
  points := least(points, missing);
  cost := _health_price(pr.health_bought, points);
  if pr.cash < cost then perform _fail(format('%s health costs $%s', points, cost)); end if;
  update profiles set cash = cash - cost, health = health + points,
         health_bought = health_bought + points,
         health_bought_at = coalesce(health_bought_at, now())
   where id = u;
  return jsonb_build_object('cost', cost, 'gain', points, 'health', pr.health + points);
end $$;

-- Checkout = buy just enough to get out of the hospital (20 health), at the sliding-scale price.
create or replace function hospital_checkout() returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles;
begin
  pr := _tick(u);
  if not _hospital(pr) then perform _fail('You are not in the hospital'); end if;
  return buy_health(20 - pr.health);
end $$;

grant execute on function buy_health(integer) to authenticated;
