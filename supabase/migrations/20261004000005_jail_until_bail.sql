-- Jail lasts until you pay (Zack, 2026-09-30: "You should stay in jail until you pay to get out not times based";
-- all jail — busts, the Bribe Police job and the 💎50 turn-in — and bail is $8,000 flat).
--  * Every way in sets jail_until to 'infinity'. Anyone inside right now stays until they post bail too.
--  * Bail is a flat $8,000 (what a full 2-hour sentence used to cost), less the Law Office (up to 30% off).
--    The Law Office no longer shortens sentences — there's nothing left to shorten.
--  * get_me sends jail_until as null while the stay is open-ended; `jailed` says whether you're inside.

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
    -- Jail has no timer: you're inside until you post bail (bail_base, less the Law Office). bail_per_minute stays at 0
    -- only so pages from before the change still show the right bail.
    when 'jail_diamonds'      then 50     -- turn yourself in: straight to jail, no stamina or cash
    when 'bail_base'          then 8000
    when 'bail_per_minute'    then 0
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

create or replace function _bust_roll(pr profiles) returns profiles
language plpgsql set search_path = public as $$
begin
  if _jailed(pr) then return pr; end if;
  if pr.heat >= _heat_red(pr) and random() < (pr.heat - _heat_red(pr) + 1) / 40.0 then
    pr.jail_until := 'infinity';                                 -- inside until you post bail
    pr.heat := _heat_yellow(pr);
  end if;
  return pr;
end $$;

create or replace function go_to_jail() returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; cost int := _cfg('jail_diamonds')::int;
begin
  pr := _tick(u);
  if _jailed(pr) then perform _fail('You are already in jail'); end if;
  if _hospital(pr) then perform _fail('You are in the hospital'); end if;
  if pr.diamonds < cost then perform _fail(format('Costs %s diamonds', cost)); end if;
  update profiles set diamonds = diamonds - cost, jail_until = 'infinity' where id = u;
  return jsonb_build_object('cost', cost, 'bail', ceil(_cfg('bail_base') * (1 - _pk(_perks(u), 'law_office')))::int);
end $$;

create or replace function bail_out() returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; cost int;
begin
  pr := _tick(u);
  if not _jailed(pr) then perform _fail('You are not in jail'); end if;
  cost := ceil(_cfg('bail_base') * (1 - _pk(_perks(u), 'law_office')))::int;
  if pr.cash < cost then perform _fail(format('Bail costs $%s', cost)); end if;
  update profiles set cash = cash - cost, jail_until = null where id = u;
  return jsonb_build_object('cost', cost);
end $$;

create or replace function do_action(action_id integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; a action_defs; pay int; busted boolean := false; crew_n int; was_jailed boolean; found jsonb;
begin
  perform _nn(action_id, 'action');
  pr := _tick(u);
  was_jailed := _jailed(pr);
  select * into a from action_defs where id = action_id;
  if a.id is null then perform _fail('Unknown action'); end if;
  if _hospital(pr) then perform _fail('You are in the hospital'); end if;
  if _jailed(pr) and not a.is_jail then perform _fail('You are in jail — only jail actions are available'); end if;
  if not _jailed(pr) and a.is_jail then perform _fail('Jail actions can only be done in jail'); end if;
  if pr.stamina < a.stamina_cost then perform _fail('Not enough stamina'); end if;
  if pr.cash < a.cash_cost then perform _fail('Not enough cash'); end if;
  if a.requires_item is not null and not exists (select 1 from inventory where player_id = u and item_id = a.requires_item and qty > 0) then
    perform _fail('Requires ' || (select name from item_defs where id = a.requires_item));
  end if;
  if a.min_crew > 0 then
    select count(*) into crew_n from profiles where crew_id = pr.crew_id and pr.crew_id is not null;
    if coalesce(crew_n, 0) < a.min_crew then perform _fail(format('Requires a crew of at least %s', a.min_crew)); end if;
  end if;

  pr.stamina := pr.stamina - a.stamina_cost;
  pr.cash := pr.cash - a.cash_cost;
  pr.actions_done := pr.actions_done + 1;

  if a.effect = 'go_to_jail' then
    pr.jail_until := 'infinity';                                 -- inside until you post bail
    pay := 0; busted := true;
  else
    pay := _rand_between(a.pay_min, a.pay_max);
    pr.cash := pr.cash + pay;
    pr.reputation := pr.reputation + a.pay_rep;
    pr.heat := least(pr.heat_max, pr.heat + a.heat_gain);
    pr := _bust_roll(pr);
    busted := _jailed(pr) and not was_jailed;
    found := _rare_roll(u, a, random());
  end if;

  update profiles set stamina = pr.stamina, cash = pr.cash, heat = pr.heat, jail_until = pr.jail_until,
         actions_done = pr.actions_done, reputation = pr.reputation where id = u;
  perform _event(u, 'action');
  perform _award_milestones(u);
  return jsonb_build_object('pay', pay, 'rep', a.pay_rep, 'busted', busted, 'heat', pr.heat, 'stamina', pr.stamina, 'cash', pr.cash,
                            'found', found);
end $$;

create or replace function get_me() returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; po record; pd record; pj record; pk jsonb;
begin
  perform _refresh_prices();
  perform _tick_world();
  pr := _tick(u);
  update profiles set last_seen = now() where id = u;
  select * into po from _power(u, 'offense');
  select * into pd from _power(u, 'defense');
  select * into pj from _power(u, 'jail');
  pk := _perks(u);
  return jsonb_build_object(
    'id', pr.id, 'name', pr.name, 'created_at', pr.created_at, 'avatar', pr.avatar, 'bio', pr.bio, 'reputation', pr.reputation,
    'cash', pr.cash, 'bank', pr.bank, 'diamonds', pr.diamonds,
    'stamina', pr.stamina, 'stamina_max', pr.stamina_max,
    'health', pr.health, 'health_max', pr.health_max,
    'heat', pr.heat, 'heat_max', pr.heat_max,
    'heat_level', _heat_level(pr),
    'jailed', _jailed(pr), 'jail_until', case when isfinite(pr.jail_until) then pr.jail_until end,   -- null: until bail
    'hospital', _hospital(pr),
    'health_next', pr.health_tick + make_interval(mins => _cfg('health_regen_minutes')::int),
    'health_bought', pr.health_bought,
    'rep_earned', pr.rep_earned, 'path', pr.path,
    'path_required', _path_due(pr) is not null,
    'immune_until', pr.immune_until, 'immune', pr.immune_until > now(),
    'inventory_slots', pr.inventory_slots, 'storage_cap', floor(pr.storage_cap * (1 + _pk(pk, 'warehouse')))::int,
    'refills_used', pr.refills_used,
    'actions_done', pr.actions_done, 'fights_won', pr.fights_won, 'fights_lost', pr.fights_lost,
    'market_volume', pr.market_volume, 'imports', pr.imports,
    'next_tick', pr.stamina_tick + make_interval(mins => _cfg('stamina_regen_minutes')::int),   -- next stamina regen
    'power', jsonb_build_object('offense', to_jsonb(po), 'defense', to_jsonb(pd), 'jail', to_jsonb(pj)),
    'crew', (select jsonb_build_object('id', c.id, 'name', c.name, 'emblem', c.emblem, 'capo_id', c.capo_id,
                                       'is_capo', c.capo_id = u, 'co_capo_id', c.co_capo_id, 'is_co_capo', c.co_capo_id = u,
                                       'cartel_id', c.cartel_id,
                                       'members', (select count(*) from profiles where crew_id = c.id),
                                       'applications', case when _crew_boss(c, u) then (select count(*) from crew_applications where crew_id = c.id) else 0 end,
                                       'invites', case when c.capo_id = u and c.cartel_id is null then (select count(*) from cartel_invites where crew_id = c.id) else 0 end)
             from crews c where c.id = pr.crew_id),
    'cartel', (select jsonb_build_object('id', ca.id, 'name', ca.name, 'don_id', ca.don_id, 'is_don', ca.don_id = u)
               from crews c join cartels ca on ca.id = c.cartel_id where c.id = pr.crew_id),
    'storage', (select coalesce(jsonb_object_agg(commodity, qty), '{}'::jsonb) from storage where player_id = u),
    'storage_used', (select coalesce(sum(qty), 0) from storage where player_id = u),
    'prices', (select jsonb_object_agg(commodity, price) from street_prices),
    'grow_houses', (select coalesce(jsonb_agg(jsonb_build_object(
                      'id', g.id, 'commodity', g.commodity, 'level', g.level, 'running', g.running,
                      'started_at', g.started_at,
                      'rate', round(c.grow_rate * g.level * _grow_boost(pk, g.commodity), 1),
                      'cap', floor(c.grow_cap * g.level * _grow_boost(pk, g.commodity))::int,
                      'produced', least(floor(c.grow_cap * g.level * _grow_boost(pk, g.commodity))::int, g.banked + case when g.running
                          then floor(extract(epoch from now() - g.started_at) / 3600 * c.grow_rate * g.level * _grow_boost(pk, g.commodity))::int else 0 end),
                      'upgrade_cost', c.grow_price * g.level * 2) order by c.sort), '[]'::jsonb)
                    from grow_houses g join commodities c on c.code = g.commodity where g.player_id = u),
    'hustlers', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'commodity', commodity, 'count', count,
                      'units', units, 'cash_due', cash_due, 'returns_at', returns_at, 'back', returns_at <= now())
                      order by returns_at), '[]'::jsonb)
                 from hustlers where player_id = u and not collected),
    'inventory', (select coalesce(jsonb_agg(jsonb_build_object('item_id', i.item_id, 'qty', i.qty, 'name', d.name,
                      'category', d.category, 'att', d.att, 'def', d.def, 'capacity', d.capacity, 'price', d.price,
                      'combo_tag', d.combo_tag) order by d.sort), '[]'::jsonb)
                  from inventory i join item_defs d on d.id = i.item_id where i.player_id = u and i.qty > 0),
    'setups', (select coalesce(jsonb_object_agg(s, items), '{}'::jsonb) from (
                 select s.setup as s, coalesce(jsonb_agg(jsonb_build_object('item_id', s.item_id, 'qty', s.qty, 'name', d.name,
                        'category', d.category, 'att', d.att, 'def', d.def, 'combo_tag', d.combo_tag) order by d.sort), '[]'::jsonb) as items
                   from setup_items s join item_defs d on d.id = s.item_id where s.player_id = u and s.qty > 0 group by s.setup) x),
    'hoodlums', (select coalesce(jsonb_object_agg(code, qty), '{}'::jsonb) from player_hoodlums where player_id = u),
    'transport_capacity', _haul(u),
    'listings', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'commodity', commodity, 'qty', qty,
                      'unit_price', unit_price, 'expires_at', expires_at, 'held', status = 'returned') order by created_at desc), '[]'::jsonb)
                 from listings where seller_id = u and status in ('open', 'returned')),
    'ribbons', _ribbons(u),
    'server_time', now()
  ) || jsonb_build_object(   -- a second object: jsonb_build_object takes at most 100 arguments
    'hospital_out_at', ceil(_cfg('hospital_release_pct') / 100.0 * pr.health_max)::int,
    'heat_next', pr.last_tick + make_interval(mins => _cfg('regen_minutes')::int),
    'unread_activity', (select count(*) from activity where player_id = u and not seen),
    'unread_dms', (select count(*) from chat_reads r where r.player_id = u
                     and exists (select 1 from messages m where m.channel = r.channel and m.created_at > r.read_at and m.sender_id <> u)),
    'storage_base', pr.storage_cap,
    'listing_max', floor(_cfg('listing_max') * (1 + _pk(pk, 'trucking')))::int,
    'perks', pk,
    'drop', jsonb_build_object('subscribed', _drop_active(pr), 'since', pr.drop_since, 'until', pr.drop_until,
              'crates', pr.drop_crates, 'max', _cfg('drop_max_crates')::int,
              'opened', (select count(*) from drop_opens where player_id = u),
              'last', (select jsonb_build_object('label', z.label, 'kind', z.kind, 'amount', o.amount, 'jackpot', z.jackpot, 'at', o.created_at)
                         from drop_opens o join drop_prizes z on z.code = o.prize where o.player_id = u order by o.id desc limit 1)),
    'free_refills', pr.free_refills, 'free_hustlers', pr.free_hustlers,
    'combos', (select jsonb_object_agg(s, jsonb_build_object('active', _active_combo(u, s), 'complete', to_jsonb(_setup_combos(u, s)),
                 'chosen', (select combo from setup_combos where player_id = u and setup = s)))
                 from unnest(array['offense', 'defense', 'jail']::setup_kind[]) s),
    'slot_cost', (select jsonb_build_object('diamonds', c.diamonds, 'cash', c.cash) from _slot_cost(pr.inventory_slots) c),
    'boost', jsonb_build_object('side', pr.boost_side, 'until', pr.boost_until, 'active', _boost_active(pr),
               'amount', _cfg('boost_amount')::int)
  ) || jsonb_build_object(
    -- the market: street details (for previewing a hustle), my open buy orders, and what the next product refill restores
    'street', _street_json(),
    'orders', (select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'commodity', o.commodity, 'qty', o.qty, 'filled', o.filled,
                    'unit_price', o.unit_price, 'expires_at', o.expires_at) order by o.created_at desc), '[]'::jsonb)
               from buy_orders o where o.buyer_id = u and o.status = 'open'),
    'refill_share', _refill_share(pr.refills_used),
    'path_due', _path_due(pr),  -- why a path is required: 'rep' or 'grow'
    'heat_yellow', _heat_yellow(pr), 'heat_red', _heat_red(pr)   -- this player's lines (heat upgrades move them up)
  );
end $$;

-- the Law Office's perk is just bail now
update business_defs set perk = 'Cheaper bail' where code = 'law_office';

-- everyone inside right now stays until they post bail
update profiles set jail_until = 'infinity' where jail_until > now() and isfinite(jail_until);

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
do $$ declare f record; begin
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('go_to_jail', 'bail_out', 'do_action', 'get_me') loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('_cfg', '_bust_roll') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
end $$;
