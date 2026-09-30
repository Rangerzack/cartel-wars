-- Setup slots top out at 130, like the original game. The 130th costs 630 diamonds + $1.54B at the current curve.

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
    when 'combo_counter'      then 10     -- a combo that counters the other side's rolls 0–this
    when 'combo_neutral'      then 5      -- ... one that neither counters nor is countered rolls 0–this (countered: nothing)
    when 'base_slots'         then 6      -- setup slots everyone starts with
    when 'max_slots'          then 130    -- the most setup slots anyone can have (the original game's cap)
    when 'slot_diamonds_base' then 10     -- the k-th slot past the base costs base + step x k diamonds ...
    when 'slot_diamonds_step' then 5
    when 'slot_cash_step'     then 100000 -- ... and this x k² cash
    when 'boost_diamonds'     then 50     -- a boost: +boost_amount attack (Offense) or defense (Defense) for boost_hours
    when 'boost_amount'       then 50
    when 'boost_hours'        then 24
    else 0 end $$;

-- kind: stamina (+5 / 10💎, max 150) | health (+25 / 10💎, max 500) | slots (+1, scaling diamonds + cash, max 130)
create or replace function upgrade_stat(kind text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; cost int; price bigint := 0; sc record;
begin
  perform _nn(kind, 'upgrade');
  pr := _tick(u);
  if kind = 'slots' then
    if pr.inventory_slots >= _cfg('max_slots') then perform _fail(format('Slots are maxed at %s', _cfg('max_slots'))); end if;
    select * into sc from _slot_cost(pr.inventory_slots);
    cost := sc.diamonds; price := sc.cash;
  else
    cost := case kind when 'stamina' then 10 when 'health' then 10 else null end;
  end if;
  if cost is null then perform _fail('Bad upgrade'); end if;
  if pr.diamonds < cost then perform _fail(format('Costs %s diamonds', cost)); end if;
  if pr.cash < price then perform _fail(format('Costs $%s cash on hand', price)); end if;
  if kind = 'stamina' then
    if pr.stamina_max >= 150 then perform _fail('Stamina is maxed'); end if;
    update profiles set stamina_max = least(150, stamina_max + 5), stamina = stamina + 5 where id = u;
  elsif kind = 'health' then
    if pr.health_max >= 500 then perform _fail('Health is maxed'); end if;
    update profiles set health_max = least(500, health_max + 25), health = health + 25 where id = u;
  else
    update profiles set inventory_slots = inventory_slots + 1 where id = u;
  end if;
  update profiles set diamonds = diamonds - cost, cash = cash - price where id = u;
  return jsonb_build_object('cost', cost, 'cash', price);
end $$;

create or replace function get_catalog() returns jsonb
language sql security definer set search_path = public stable as $$
  select jsonb_build_object(
    'actions', (select jsonb_agg(to_jsonb(a) order by a.sort) from action_defs a),
    'items', (select jsonb_agg(to_jsonb(i) order by i.sort) from item_defs i),
    'commodities', (select jsonb_agg(to_jsonb(c) order by c.sort) from commodities c),
    'hoodlums', (select jsonb_agg(to_jsonb(h)) from hoodlum_defs h),
    'businesses', (select jsonb_agg(to_jsonb(b) order by b.sort) from business_defs b),
    'drop_prizes', (select jsonb_agg(to_jsonb(z) order by z.sort) from drop_prizes z),
    'combo_styles', (select jsonb_agg(jsonb_build_object('code', s.code, 'name', s.name, 'icon', s.icon, 'blurb', s.blurb,
                       'beats', (select coalesce(jsonb_agg(k.beats order by b.sort), '[]'::jsonb) from combo_counters k
                                   join combo_styles b on b.code = k.beats where k.style = s.code)) order by s.sort) from combo_styles s),
    'combos', (select jsonb_agg(jsonb_build_object('code', c.code, 'name', c.name, 'style', c.style, 'tier', c.tier,
                 'parts', (select jsonb_agg(p.items order by p.part) from (select part, jsonb_agg(item_id order by item_id) items
                             from combo_parts where combo = c.code group by part) p)) order by c.sort) from combo_defs c),
    'config', jsonb_build_object(
      'bribe_per_heat', _cfg('bribe_per_heat'), 'hospital_per_point', _cfg('hospital_per_point'),
      'refill_diamonds', _cfg('refill_diamonds'), 'hustler_price', _cfg('hustler_price'),
      'hustler_hours', _cfg('hustler_hours'), 'listing_min', _cfg('listing_min'), 'listing_max', _cfg('listing_max'),
      'crew_max', _cfg('crew_max'), 'bail_base', _cfg('bail_base'), 'bail_per_minute', _cfg('bail_per_minute'),
      'extra_grow_diamonds', _cfg('extra_grow_diamonds'), 'heat_yellow', _cfg('heat_yellow'), 'heat_red', _cfg('heat_red'),
      'health_price_scale', _cfg('health_price_scale'), 'health_regen_minutes', _cfg('health_regen_minutes'),
      'health_regen_amount', _cfg('health_regen_amount'), 'path_rep', _cfg('path_rep'),
      'path_switch_diamonds', _cfg('path_switch_diamonds'), 'siege_wins', _cfg('siege_wins'),
      'siege_min_thugs', _cfg('siege_min_thugs'), 'block_bonus_hours', _cfg('block_bonus_hours'),
      'stamina_regen_minutes', _cfg('stamina_regen_minutes'), 'stamina_regen_amount', _cfg('stamina_regen_amount'),
      'regen_minutes', _cfg('regen_minutes'), 'hospital_release_pct', _cfg('hospital_release_pct'),
      'daily_cash', _cfg('daily_cash'), 'counter_pct', _cfg('counter_pct'), 'drop_stamina', _cfg('drop_stamina'),
      'bot_min_strength', _cfg('bot_min_strength'), 'jail_minutes', _cfg('jail_minutes'),
      'drop_max_crates', _cfg('drop_max_crates'), 'drop_price_cents', _cfg('drop_price_cents'), 'drop_free', _cfg('drop_free'),
      'combo_counter', _cfg('combo_counter'), 'combo_neutral', _cfg('combo_neutral'),
      'base_slots', _cfg('base_slots'), 'max_slots', _cfg('max_slots'), 'boost_diamonds', _cfg('boost_diamonds'), 'boost_amount', _cfg('boost_amount'),
      'boost_hours', _cfg('boost_hours'))
  ) $$;

do $$ declare f record; begin
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('upgrade_stat', 'get_catalog') loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('_cfg') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
end $$;
