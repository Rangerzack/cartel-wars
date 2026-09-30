-- Two changes (Zack, 2026-09-30):
--  * "for 50 diamonds you can go into jail": go_to_jail() spends 50 diamonds and locks you up for the usual 2 hours
--    (jail_minutes) — the same as the Bribe Police To Get In Jail job, without its 10 stamina and $1,000. It isn't an
--    action (no action count or milestone). Not while already jailed or in the hospital.
--  * "Diamonds on the slots should scale for a total of 2k diamonds spent": +1 diamond every 4 slots instead of every
--    25 — the 7th–10th cost 1, the 11th–14th 2 … the 127th–130th 31, 1,984 for all 124. Cash is unchanged ($20,000 x k,
--    $155M in all). Milestones stay as they are (Zack's call), so free players reach 130 over a longer stretch.

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
    when 'heat_yellow'        then 40     -- at base max heat; each heat upgrade moves both lines up by its amount
    when 'heat_red'           then 75
    when 'jail_minutes'       then 120
    when 'jail_diamonds'      then 50     -- turn yourself in: straight to jail for jail_minutes, no stamina or cash
    when 'bail_base'          then 2000
    when 'bail_per_minute'    then 50
    when 'bribe_per_heat'     then 40
    when 'heat_base'          then 100    -- everyone's max heat before upgrades
    when 'heat_upgrade_diamonds' then 30  -- a heat upgrade: +heat_upgrade_amount max heat, and the yellow/red lines move up
    when 'heat_upgrade_amount' then 50    --   with it (red at heat_red + the extra). Flat price, no cap.
    when 'hospital_per_point' then 40     -- base $ per health point
    when 'health_price_scale' then 100    -- price per point grows by 1x for every 100 points bought in 24h
    when 'refill_diamonds'    then 6
    when 'refill_full'        then 3      -- full-strength product refills a game day; each one after restores half the last
    when 'hustler_price'      then 400    -- per hustler, for players who haven't picked a path (Traders pay a cut instead)
    when 'hustler_hours'      then 4
    when 'trader_cut_pct'     then 10     -- Traders: their hustlers keep this % of the take, nothing up front
    when 'trader_markup_pct'  then 10     -- ... and Traders sell this % over street
    when 'listing_min'        then 25
    when 'listing_max'        then 1000
    when 'listing_max_pct'    then 150    -- listings and buy orders can be priced up to this % of street
    when 'market_fee_pct'     then 5      -- the seller pays this % of every Marketplace sale
    when 'order_max'          then 10000  -- most units one buy order can ask for
    when 'orders_open_max'    then 5      -- open buy orders a player can have at once
    when 'price_noise_pct'    then 15     -- street price wiggles at most this % either side of base ...
    when 'price_step_pct'     then 4      -- ... moving at most this much every 10 minutes ...
    when 'price_revert_pct'   then 10     -- ... and drifting this share of the way back to base each step
    when 'price_pressure_max_pct' then 60 -- hustler dumping can take at most this % off street
    when 'price_recover_hours' then 4     -- dumping pressure fades by half this often
    when 'crew_max'           then 12
    when 'immunity_hours'     then 0      -- new-player immunity removed
    when 'starter_cash'       then 10000
    when 'starter_diamonds'   then 25
    when 'extra_grow_diamonds' then 20
    when 'crew_fight_stamina' then 5
    when 'crew_fight_cooldown_min' then 60
    when 'crew_fight_stake_pct' then 5
    when 'path_rep'           then 100    -- lifetime reputation at which a player must pick Producer or Trader ...
    when 'path_grow_level'    then 5      -- ... or to take a grow house past this level
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
    -- Slots: the k-th past the base costs base + 1 more diamond every `every` slots, and step x k cash
    -- (1💎 for slots 7–10, 2💎 for 11–14 … 31💎 for 127–130; $20k for the 7th … $2.48M for the 130th — 💎1,984 + $155M in all)
    when 'slot_diamonds_base' then 1
    when 'slot_diamonds_every' then 4
    when 'slot_cash_step'     then 20000
    when 'boost_diamonds'     then 50     -- a boost: +boost_amount attack (Offense) or defense (Defense) for boost_hours
    when 'boost_amount'       then 50
    when 'boost_hours'        then 24
    else 0 end $$;

create or replace function go_to_jail() returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; cost int := _cfg('jail_diamonds')::int; until timestamptz;
begin
  pr := _tick(u);
  if _jailed(pr) then perform _fail('You are already in jail'); end if;
  if _hospital(pr) then perform _fail('You are in the hospital'); end if;
  if pr.diamonds < cost then perform _fail(format('Costs %s diamonds', cost)); end if;
  until := now() + make_interval(mins => _cfg('jail_minutes')::int);
  update profiles set diamonds = diamonds - cost, jail_until = until where id = u;
  return jsonb_build_object('cost', cost, 'until', until);
end $$;

create or replace function get_catalog() returns jsonb
language sql stable security definer set search_path = public as $$
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
    'milestones', (select jsonb_agg(to_jsonb(m) order by m.kind, m.n) from milestone_defs m),
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
      'boost_hours', _cfg('boost_hours')) || jsonb_build_object(   -- jsonb_build_object takes at most 100 arguments
      'refill_full', _cfg('refill_full'), 'path_grow_level', _cfg('path_grow_level'),
      'trader_cut_pct', _cfg('trader_cut_pct'), 'trader_markup_pct', _cfg('trader_markup_pct'),
      'listing_max_pct', _cfg('listing_max_pct'), 'market_fee_pct', _cfg('market_fee_pct'),
      'order_max', _cfg('order_max'), 'orders_open_max', _cfg('orders_open_max'),
      'price_pressure_max_pct', _cfg('price_pressure_max_pct'), 'price_recover_hours', _cfg('price_recover_hours'),
      'heat_base', _cfg('heat_base'), 'heat_upgrade_diamonds', _cfg('heat_upgrade_diamonds'), 'heat_upgrade_amount', _cfg('heat_upgrade_amount'),
      'jail_diamonds', _cfg('jail_diamonds'), 'slot_diamonds_base', _cfg('slot_diamonds_base'), 'slot_diamonds_every', _cfg('slot_diamonds_every'))
  ) $$;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
do $$ declare f record; begin
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('go_to_jail', 'get_catalog') loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('_cfg') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
end $$;
