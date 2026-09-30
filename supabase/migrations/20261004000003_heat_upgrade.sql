-- Heat upgrades (Zack, 2026-09-30: "heat upgrades to be a flat 30 diamonds to be an extra 50 heat"; no cap).
-- 30 diamonds buys +50 max heat, and the yellow and red lines move up with it — 50 more heat before any bust risk,
-- not 50 more room to get busted in. Base: max 100, yellow 40, red 75. One upgrade: max 150, yellow 90, red 125.
-- Busts roll as before above your red line — (heat − red + 1) / 40 — and a bust drops heat to your yellow line.
-- Flat price, as many as you like.

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
    -- (1💎 for slots 7–31, 2💎 for 32–56 … 5💎 for 107–130; $20k for the 7th … $2.48M for the 130th — 💎370 + $155M in all)
    when 'slot_diamonds_base' then 1
    when 'slot_diamonds_every' then 25
    when 'slot_cash_step'     then 20000
    when 'boost_diamonds'     then 50     -- a boost: +boost_amount attack (Offense) or defense (Defense) for boost_hours
    when 'boost_amount'       then 50
    when 'boost_hours'        then 24
    else 0 end $$;

-- How much a player's heat upgrades have added, and where their lines sit.
create or replace function _heat_extra(pr profiles) returns integer
language sql immutable set search_path = public as $$ select greatest(0, pr.heat_max - _cfg('heat_base'))::int $$;
create or replace function _heat_yellow(pr profiles) returns integer
language sql immutable set search_path = public as $$ select (_cfg('heat_yellow') + _heat_extra(pr))::int $$;
create or replace function _heat_red(pr profiles) returns integer
language sql immutable set search_path = public as $$ select (_cfg('heat_red') + _heat_extra(pr))::int $$;
create or replace function _heat_level(pr profiles) returns text
language sql immutable set search_path = public as $$
  select case when pr.heat >= _heat_red(pr) then 'red' when pr.heat >= _heat_yellow(pr) then 'yellow' else 'green' end $$;

create or replace function _bust_roll(pr profiles) returns profiles
language plpgsql set search_path = public as $$
begin
  if _jailed(pr) then return pr; end if;
  if pr.heat >= _heat_red(pr) and random() < (pr.heat - _heat_red(pr) + 1) / 40.0 then
    pr.jail_until := now() + make_interval(secs => _cfg('jail_minutes') * 60 * (1 - _pk(_perks(pr.id), 'law_office')));
    pr.heat := _heat_yellow(pr);
  end if;
  return pr;
end $$;

-- kind: stamina (+5 / 10💎, max 150) | health (+25 / 10💎, max 500) | heat (+50 / 30💎, no cap) | slots (scaling)
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
    cost := case kind when 'stamina' then 10 when 'health' then 10 when 'heat' then _cfg('heat_upgrade_diamonds')::int else null end;
  end if;
  if cost is null then perform _fail('Bad upgrade'); end if;
  if pr.diamonds < cost then perform _fail(format('Costs %s diamond%s', cost, case when cost = 1 then '' else 's' end)); end if;
  if pr.cash < price then perform _fail(format('Costs $%s cash on hand', price)); end if;
  if kind = 'stamina' then
    if pr.stamina_max >= 150 then perform _fail('Stamina is maxed'); end if;
    update profiles set stamina_max = least(150, stamina_max + 5), stamina = stamina + 5 where id = u;
  elsif kind = 'health' then
    if pr.health_max >= 500 then perform _fail('Health is maxed'); end if;
    update profiles set health_max = least(500, health_max + 25), health = health + 25 where id = u;
  elsif kind = 'heat' then
    update profiles set heat_max = heat_max + _cfg('heat_upgrade_amount')::int where id = u;   -- no cap
  else
    update profiles set inventory_slots = inventory_slots + 1 where id = u;
  end if;
  update profiles set diamonds = diamonds - cost, cash = cash - price where id = u;
  return jsonb_build_object('cost', cost, 'cash', price);
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
    'jailed', _jailed(pr), 'jail_until', pr.jail_until,
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

create or replace function get_player(pid uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare pr profiles;
begin
  perform _uid();
  select * into pr from profiles where id = pid;
  if pr.id is null then perform _fail('No such player'); end if;
  return jsonb_build_object('id', pr.id, 'name', pr.name, 'created_at', pr.created_at, 'avatar', pr.avatar, 'bio', pr.bio, 'reputation', pr.reputation,
    'fights', pr.fights_won + pr.fights_lost, 'fights_won', pr.fights_won, 'actions', pr.actions_done,
    'health', pr.health, 'health_max', pr.health_max,
    'heat_level', _heat_level(pr),
    'jailed', _jailed(pr), 'hospital', _hospital(pr), 'immune', pr.immune_until > now(),
    'last_seen', pr.last_seen, 'ribbons', _ribbons(pr.id),
    'crew', (select jsonb_build_object('id', c.id, 'name', c.name, 'emblem', c.emblem) from crews c where c.id = pr.crew_id),
    'cartel', (select jsonb_build_object('id', ca.id, 'name', ca.name) from crews c join cartels ca on ca.id = c.cartel_id where c.id = pr.crew_id));
end $$;

create or replace function fight_preview(target uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); me profiles; them profiles; fs record; recent int; heat_after int; red int;
        counter numeric := _cfg('counter_pct') / 100.0; wins bigint; n bigint; dmin int; dmax int;
        known boolean; seen_combo text; seen_at timestamptz; their text; amax int; dmx int;
begin
  perform _nn(target, 'target');
  if target = u then perform _fail('You cannot attack yourself'); end if;
  if not exists (select 1 from profiles where id = target) then perform _fail('No such player'); end if;
  -- tick both (heat and cash feed the edges), locking in id order like attack()
  if u < target then me := _tick(u); them := _tick(target); else them := _tick(target); me := _tick(u); end if;
  perform _jail_check(me, them);
  select * into fs from _fight_setup(me, them);
  -- Whether they run a combo shows (you can see they're kitted out); which one doesn't, unless they're a thug
  -- or you've hit them before — then it's what they ran that time, which may have changed since.
  if them.is_bot or fs.d_code is null then
    known := true; their := fs.d_code;
  else
    select f.defender_combo, f.created_at into seen_combo, seen_at
      from fights f where f.attacker_id = u and f.defender_id = target and f.combos_logged and f.defender_combo is not null
     order by f.id desc limit 1;
    known := seen_combo is not null; their := seen_combo;
  end if;
  if known then
    amax := _combo_max(fs.a_code, their); dmx := _combo_max(their, fs.a_code);
  else
    amax := _combo_max(fs.a_code, null); dmx := _cfg('combo_neutral')::int;   -- neither counters, as far as you know
  end if;
  select count(*) filter (where x.sa > x.sd), count(*),
         min(least(80, round(case when x.sa > x.sd then counter * x.sd else x.sd end))::int),
         max(least(80, round(case when x.sa > x.sd then counter * x.sd else x.sd end))::int)
    into wins, n, dmin, dmax
    from (select fs.base_a + least(10, ra + fs.edge_a) + ca as sa, fs.base_d + least(10, rd + fs.edge_d) + cd as sd
            from generate_series(0, 6) ra, generate_series(0, 6) rd,
                 generate_series(0, amax) ca, generate_series(0, dmx) cd) x;
  select count(*) into recent from fights where attacker_id = u and defender_id = target and created_at > now() - interval '1 hour';
  heat_after := least(me.heat_max, me.heat + 4);
  red := _heat_red(me);                       -- this attacker's red line (heat upgrades move it up)
  return jsonb_build_object(
    'win_pct', round(100.0 * wins / n)::int,
    'win_exact', round(100.0 * wins / n, 1),
    'dmg_min', dmin, 'dmg_max', dmax,
    'my_health', me.health, 'hospital_risk', me.health - dmax <= 19,
    'dry', recent >= 3, 'hits_this_hour', recent,
    'stamina_cost', 2, 'heat_gain', 4,
    'bust_pct', case when _jailed(me) or heat_after < red then 0 else round(100.0 * (heat_after - red + 1) / 40)::int end,
    'setup', fs.sa, 'their_setup', fs.sd,
    'edges', fs.edges, 'edge_you', fs.edge_a, 'edge_them', fs.edge_d,
    'base_you', round(fs.base_a, 1), 'base_them', round(fs.base_d, 1),
    'combo_you', fs.a_code is not null, 'combo_them', dmx > 0,
    'my_combo', fs.a_code, 'their_combo', their, 'their_combo_known', known, 'their_combo_seen_at', seen_at,
    'their_has_combo', fs.d_code is not null,
    'my_combo_max', amax, 'their_combo_max', dmx,
    'my_att', round(fs.a_att)::int, 'my_def', round(fs.a_def)::int,
    'their_att', round(fs.d_att)::int, 'their_def', round(fs.d_def)::int);
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
      'heat_base', _cfg('heat_base'), 'heat_upgrade_diamonds', _cfg('heat_upgrade_diamonds'), 'heat_upgrade_amount', _cfg('heat_upgrade_amount'))
  ) $$;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
do $$ declare f record; begin
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('upgrade_stat', 'get_me', 'get_player', 'fight_preview', 'get_catalog') loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('_cfg', '_heat_extra', '_heat_yellow', '_heat_red', '_heat_level', '_bust_roll') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
end $$;
