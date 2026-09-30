-- The market overhaul (Zack, 2026-09-30: "do all of that except the alt farm part").
-- Product was worth far more burned as stamina refills than sold, the Trader path was strictly worse than
-- Producer, the path split only bound players who earned reputation, and street price was dice. So:
--
--  1. Refills: after the three full product refills of a game day, each one restores half as much as the one
--     before (150 → 150 → 150 → 75 → 38 → 19 …). It used to stay at half forever.
--  2. Paths: anyone can pick Producer or Trader any time. Until they do, they can run grow houses up to level 5
--     and send hustlers at the $400 fee. Taking a grow house past level 5 (or reaching 100 reputation, as
--     before) means picking one. Existing players with bigger houses get asked; the first pick is still free.
--  3. Traders: no hire fee up front — their hustlers keep 10% of the take instead — and they sell 10% over
--     street. Daily Drop hustler credits waive the cut on that many hustlers (unpathed players: the fee).
--  4. Street price answers to supply. Every unit hustlers sell pushes that product's street price down; the
--     push fades by half every 4 hours. A batch sells at the price halfway through its own push, so dumping
--     a mountain at once pays less per unit. The random wiggle is now ±15% (was ±35%) and drifts back to base.
--  5. Marketplace: list up to 150% of street (was: no higher than street), a 5% seller fee on every sale, buy
--     orders (post "Wanted: 2,000 Dust at $170" with the cash held until it fills, is cancelled or expires in
--     48h), and a trade log for last price and 24h volume.
-- Every number lives in _cfg or commodities.market_depth.

-- ---------------------------------------------------------------------------
-- Config
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
    when 'slot_diamonds_base' then 10     -- the k-th slot past the base costs base + step x k diamonds ...
    when 'slot_diamonds_step' then 5
    when 'slot_cash_step'     then 100000 -- ... and this x k² cash
    when 'boost_diamonds'     then 50     -- a boost: +boost_amount attack (Offense) or defense (Defense) for boost_hours
    when 'boost_amount'       then 50
    when 'boost_hours'        then 24
    else 0 end $$;

-- ---------------------------------------------------------------------------
-- 1. Refills: full for the first three of the day, then each restores half the one before
-- ---------------------------------------------------------------------------
create or replace function _refill_share(used int) returns numeric
language sql immutable set search_path = public as $$
  select case when used < _cfg('refill_full') then 1.0
              else power(0.5, least(30, used - _cfg('refill_full') + 1)) end $$;

create or replace function refill(kind text, method text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; c commodities; units int; missing int; gain int; have int;
begin
  perform _nn(kind, 'refill kind'); perform _nn(method, 'refill method');
  pr := _tick(u);
  if kind not in ('stamina','health') then perform _fail('Bad refill'); end if;
  missing := case when kind = 'stamina' then pr.stamina_max - pr.stamina else pr.health_max - pr.health end;
  if missing <= 0 then perform _fail('Already full'); end if;
  if method = 'diamonds' then
    if pr.diamonds < _cfg('refill_diamonds') then perform _fail('Not enough diamonds'); end if;
    update profiles set diamonds = diamonds - _cfg('refill_diamonds')::int where id = u;
    gain := missing;
  elsif method = 'free' then
    -- a Daily Drop credit: a full stamina refill that doesn't count toward the three a day
    if kind <> 'stamina' then perform _fail('Free refills are for stamina'); end if;
    if pr.free_refills <= 0 then perform _fail('No free refills left'); end if;
    update profiles set free_refills = free_refills - 1 where id = u;
    gain := missing;
  else
    select * into c from commodities where code = method;
    if c.code is null then perform _fail('Bad refill'); end if;
    units := case when kind = 'stamina' then c.refill_stamina else c.refill_health end;
    units := ceil(units * (1 - _pk(_perks(u), 'pharmacy')))::int;
    select qty into have from storage where player_id = u and commodity = method;
    if coalesce(have, 0) < units then perform _fail(format('Needs %s %s', units, c.name)); end if;
    update storage set qty = qty - units where player_id = u and commodity = method;
    gain := ceil(missing * _refill_share(pr.refills_used))::int;
    update profiles set refills_used = refills_used + 1,
           refills_reset_at = case when pr.refills_used = 0 then now() else refills_reset_at end where id = u;
  end if;
  if kind = 'stamina' then update profiles set stamina = stamina + gain where id = u;
  else update profiles set health = health + gain where id = u; end if;
  return jsonb_build_object('gain', gain, 'units', units, 'next_share', _refill_share(pr.refills_used + case when units is null then 0 else 1 end));
end $$;

-- ---------------------------------------------------------------------------
-- 2. Paths: pick any time; required at 100 rep or to take a grow house past level 5
-- ---------------------------------------------------------------------------
-- Why this player has to pick now: 'rep', 'grow' (a house past the level), or null (not yet).
create or replace function _path_due(pr profiles) returns text
language sql stable set search_path = public as $$
  select case when pr.path is not null then null
              when pr.rep_earned >= _cfg('path_rep') then 'rep'
              when exists (select 1 from grow_houses g where g.player_id = pr.id and g.level > _cfg('path_grow_level')) then 'grow'
              end $$;

create or replace function _need_path(pr profiles, want text) returns void
language plpgsql set search_path = public as $$
begin
  if pr.path is null then
    case _path_due(pr)
      when 'rep' then perform _fail(format('You have %s reputation — choose Producer or Trader on the Economy page first', _cfg('path_rep')));
      when 'grow' then perform _fail(format('Your grow houses are past level %s — choose Producer or Trader on the Economy page first', _cfg('path_grow_level')));
      else null;
    end case;
  elsif pr.path <> want then
    perform _fail(case want when 'producer' then 'Only Producers run grow houses — switch paths on the Economy page'
                            else 'Only Traders send hustlers — switch paths on the Economy page' end);
  end if;
end $$;

create or replace function choose_path(p text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; cost int := 0; g grow_houses;
begin
  perform _nn(p, 'path');
  pr := _tick(u);
  if p not in ('producer', 'trader') then perform _fail('Pick producer or trader'); end if;
  if pr.path = p then perform _fail('You are already on that path'); end if;
  if pr.path is not null then
    cost := _cfg('path_switch_diamonds')::int;
    if pr.diamonds < cost then perform _fail(format('Switching costs %s diamonds', cost)); end if;
  end if;
  update profiles set path = p, path_chosen_at = now(), diamonds = diamonds - cost where id = u;
  if p = 'trader' then
    -- traders don't grow: freeze what's been produced and stop every house
    for g in select * from grow_houses where player_id = u and running for update loop
      g := _grow_settle(g);
      update grow_houses set banked = g.banked, running = false, started_at = null where id = g.id;
    end loop;
  end if;
  return jsonb_build_object('path', p, 'diamonds', cost);
end $$;

create or replace function grow_upgrade(house uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; g grow_houses; c commodities; cost int;
begin
  pr := _tick(u);
  perform _need_path(pr, 'producer');
  select * into g from grow_houses where id = house and player_id = u for update;
  if g.id is null then perform _fail('No such grow house'); end if;
  if pr.path is null and g.level >= _cfg('path_grow_level') then
    perform _fail(format('Pick Producer or Trader to take a grow house past level %s', _cfg('path_grow_level')));
  end if;
  select * into c from commodities where code = g.commodity;
  cost := c.grow_price * g.level * 2;
  if pr.cash < cost then perform _fail(format('Upgrade costs $%s', cost)); end if;
  g := _grow_settle(g);
  update profiles set cash = cash - cost where id = u;
  update grow_houses set level = level + 1, banked = g.banked, started_at = g.started_at where id = g.id;
  return jsonb_build_object('cost', cost, 'level', g.level + 1);
end $$;

-- ---------------------------------------------------------------------------
-- 4. Street price: base × wiggle × what hustler dumping has knocked off
-- ---------------------------------------------------------------------------
-- How many units sold at once would take the whole pressure cap off (about $3M of each at base price).
alter table commodities add column if not exists market_depth integer not null default 50000;
update commodities c set market_depth = v.d from (values ('herb', 50000), ('dust', 15000), ('pills', 5000)) v(code, d) where c.code = v.code;

alter table street_prices add column if not exists wiggle      numeric     not null default 0;   -- -0.15 .. 0.15
alter table street_prices add column if not exists wiggle_at   timestamptz not null default now();
alter table street_prices add column if not exists pressure    numeric     not null default 0;   -- share knocked off by dumping (capped when priced)
alter table street_prices add column if not exists pressure_at timestamptz not null default now();
-- carry today's prices over as the starting wiggle (inside the new, narrower band)
update street_prices sp set wiggle = round(greatest(-_cfg('price_noise_pct') / 100.0, least(_cfg('price_noise_pct') / 100.0, sp.price::numeric / c.base_price - 1)), 5),
                            wiggle_at = now(), pressure = 0, pressure_at = now()
  from commodities c where c.code = sp.commodity;

-- Pressure left after it fades for the time since `at`.
create or replace function _decay(pressure numeric, at timestamptz) returns numeric
language sql stable set search_path = public as $$
  select pressure * power(0.5, greatest(0, extract(epoch from now() - at)) / 3600.0 / _cfg('price_recover_hours')) $$;

-- The unrounded street price for a given wiggle and pressure.
create or replace function _street(base integer, wiggle numeric, pressure numeric) returns numeric
language sql immutable set search_path = public as $$
  select greatest(1, base * (1 + wiggle) * (1 - least(_cfg('price_pressure_max_pct') / 100.0, greatest(0, pressure)))) $$;

-- Called on every get_me and before anything that prices product. Pressure fades continuously (written at most once
-- a minute); the wiggle takes one random step every 10 minutes, pulled a little back toward base each time.
create or replace function _refresh_prices() returns void
language plpgsql set search_path = public as $$
declare lim numeric := _cfg('price_noise_pct') / 100.0; step numeric := _cfg('price_step_pct') / 100.0;
        keep numeric := 1 - _cfg('price_revert_pct') / 100.0;
begin
  update street_prices sp
     set pressure = round(_decay(sp.pressure, sp.pressure_at), 6), pressure_at = now(),
         wiggle = case when sp.wiggle_at <= now() - interval '10 minutes'
                       then round(greatest(-lim, least(lim, sp.wiggle * keep + (random() * 2 - 1)::numeric * step)), 5) else sp.wiggle end,
         wiggle_at = case when sp.wiggle_at <= now() - interval '10 minutes' then now() else sp.wiggle_at end,
         updated_at = now()
   where sp.updated_at <= now() - interval '1 minute';
  if found then
    update street_prices sp set price = round(_street(c.base_price, sp.wiggle, sp.pressure))::int
      from commodities c where c.code = sp.commodity and sp.updated_at = now();
  end if;
end $$;
update street_prices sp set price = round(_street(c.base_price, sp.wiggle, sp.pressure))::int, updated_at = now()
  from commodities c where c.code = sp.commodity;

-- Street for the UI: price now, base, the dumping discount and wiggle (so the page can preview a batch), depth.
create or replace function _street_json() returns jsonb
language sql stable set search_path = public as $$
  select jsonb_object_agg(sp.commodity, jsonb_build_object(
           'price', sp.price, 'base', c.base_price, 'wiggle', round(sp.wiggle, 4),
           'pressure', round(least(_cfg('price_pressure_max_pct') / 100.0, _decay(sp.pressure, sp.pressure_at)), 4),
           'depth', c.market_depth))
    from street_prices sp join commodities c on c.code = sp.commodity $$;

-- ---------------------------------------------------------------------------
-- 3 + 4. Hustlers: Traders pay a cut instead of a fee and sell over street; every batch pushes the price down
-- ---------------------------------------------------------------------------
create or replace function hire_hustlers(commodity text, n integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; c commodities; sp street_prices; have int; units int; cost int := 0; pk jsonb := _perks(u);
        comped int; trader boolean; cut numeric := 0; markup numeric := 0; p0 numeric; p1 numeric; each numeric; due bigint;
begin
  perform _nn(n, 'count');
  pr := _tick(u);
  perform _need_path(pr, 'trader');
  perform _refresh_prices();
  select * into c from commodities where code = hire_hustlers.commodity;
  if c.code is null or n <= 0 or n > 100 then perform _fail('Hire between 1 and 100 hustlers'); end if;
  trader := pr.path = 'trader';
  units := floor(c.hustler_units * n * (1 + _pk(pk, 'strip_club')))::int;
  comped := least(n, pr.free_hustlers);            -- Daily Drop credits: no fee (or, for a Trader, no cut) on that many
  if trader then
    cut := _cfg('trader_cut_pct') / 100.0 * (n - comped) / n;
    markup := _cfg('trader_markup_pct') / 100.0;
  else
    cost := _cfg('hustler_price')::int * (n - comped);
  end if;
  select qty into have from storage where player_id = u and storage.commodity = c.code;
  if coalesce(have, 0) < units then perform _fail(format('Needs %s %s in storage', units, c.name)); end if;
  if pr.cash < cost then perform _fail(format('Hiring costs $%s', cost)); end if;
  -- the batch sells into the street: it gets the price halfway through its own push
  select * into sp from street_prices where street_prices.commodity = c.code for update;
  p0 := _decay(sp.pressure, sp.pressure_at);
  p1 := p0 + units::numeric / greatest(1, c.market_depth);
  each := _street(c.base_price, sp.wiggle, (p0 + p1) / 2);
  due := floor(units * each * (1 + _pk(pk, 'dispensary') + markup) * (1 - cut))::bigint;
  p1 := round(least(p1, 2.5 * _cfg('price_pressure_max_pct') / 100.0), 6);   -- a flood takes longer to clear, but not forever
  update street_prices set pressure = p1, pressure_at = now(), price = round(_street(c.base_price, sp.wiggle, p1))::int
   where street_prices.commodity = c.code;
  update storage set qty = qty - units where player_id = u and storage.commodity = c.code;
  update profiles set cash = cash - cost, free_hustlers = free_hustlers - comped where id = u;
  insert into hustlers (player_id, commodity, count, units, cash_due, returns_at)
  values (u, c.code, n, units, due, now() + make_interval(secs => _cfg('hustler_hours') * 3600 * (1 - _pk(pk, 'night_club'))));
  return jsonb_build_object('units', units, 'cash_due', due, 'cost', cost, 'free', comped,
                            'unit_price', round(each, 2), 'street', round(_street(c.base_price, sp.wiggle, p1))::int,
                            'cut', round(units * each * (1 + _pk(pk, 'dispensary') + markup) * cut)::bigint);
end $$;

-- ---------------------------------------------------------------------------
-- 5. Marketplace: price cap at 150% of street, a 5% seller fee, buy orders, a trade log
-- ---------------------------------------------------------------------------
create table if not exists market_trades (
  id         bigserial primary key,
  commodity  text not null references commodities(code),
  units      integer not null check (units > 0),
  unit_price integer not null check (unit_price > 0),
  buyer_id   uuid references profiles(id) on delete set null,
  seller_id  uuid references profiles(id) on delete set null,
  via        text not null check (via in ('listing', 'order')),
  created_at timestamptz not null default now()
);
create index if not exists market_trades_recent_idx on market_trades (commodity, created_at desc);
alter table market_trades enable row level security;

do $$ begin create type order_status as enum ('open', 'filled', 'cancelled', 'expired');
exception when duplicate_object then null; end $$;

-- A standing offer to buy. The cash for what's still wanted (qty × unit_price) is held off the buyer's hand
-- while it's open; cancelling or expiry hands the rest back.
create table if not exists buy_orders (
  id         uuid primary key default gen_random_uuid(),
  buyer_id   uuid not null references profiles(id) on delete cascade,
  commodity  text not null references commodities(code),
  qty        integer not null check (qty >= 0),            -- still wanted
  filled     integer not null default 0 check (filled >= 0),
  unit_price integer not null check (unit_price > 0),
  status     order_status not null default 'open',
  created_at timestamptz not null default now(),
  expires_at timestamptz not null default now() + interval '48 hours'
);
create index if not exists buy_orders_open_idx on buy_orders (commodity, unit_price desc) where status = 'open';
create index if not exists buy_orders_buyer_idx on buy_orders (buyer_id) where status = 'open';
alter table buy_orders enable row level security;

-- What a seller keeps of a sale after the fee.
create or replace function _after_fee(gross bigint) returns bigint
language sql immutable set search_path = public as $$
  select gross - floor(gross * _cfg('market_fee_pct') / 100.0)::bigint $$;

-- The most a listing or buy order can ask per unit at this street price.
create or replace function _price_cap(street integer) returns integer
language sql immutable set search_path = public as $$ select floor(street * _cfg('listing_max_pct') / 100.0)::int $$;

-- The biggest vehicle's load, with Trucking Co.
create or replace function _haul(p uuid) returns integer
language sql stable set search_path = public as $$
  select floor((select coalesce(max(d.capacity), 0) from inventory i join item_defs d on d.id = i.item_id
                 where i.player_id = p and i.qty > 0 and d.category = 'transport') * (1 + _pk(_perks(p), 'trucking')))::int $$;

create or replace function list_product(commodity text, n integer, unit_price integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; have int; street int; cap int; l listings;
        maxn int := floor(_cfg('listing_max') * (1 + _pk(_perks(u), 'trucking')))::int;
begin
  perform _nn(n, 'quantity'); perform _nn(unit_price, 'price');
  pr := _tick(u);
  perform _refresh_prices();
  if n < _cfg('listing_min') or n > maxn then
    perform _fail(format('List between %s and %s units', _cfg('listing_min'), maxn)); end if;
  select price into street from street_prices where street_prices.commodity = list_product.commodity;
  if street is null then perform _fail('Bad commodity'); end if;
  if unit_price <= 0 or unit_price > _price_cap(street) then
    perform _fail(format('Street price is $%s — you can list up to $%s', street, _price_cap(street))); end if;
  cap := _haul(u);
  if cap < n then perform _fail(format('Your transport carries %s units — buy a bigger vehicle', cap)); end if;
  select qty into have from storage where player_id = u and storage.commodity = list_product.commodity;
  if coalesce(have, 0) < n then perform _fail('Not enough in storage'); end if;
  update storage set qty = qty - n where player_id = u and storage.commodity = list_product.commodity;
  insert into listings (seller_id, commodity, qty, unit_price) values (u, commodity, n, unit_price) returning * into l;
  return jsonb_build_object('id', l.id);
end $$;

create or replace function buy_listing(listing uuid, n integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; l listings; used int; cost bigint; net bigint;
begin
  perform _nn(n, 'quantity');
  select * into l from listings where id = listing and status = 'open' and expires_at > now() for update;
  if l.id is null then perform _fail('That listing is gone'); end if;
  if l.seller_id = u then perform _fail('That is your own listing'); end if;
  perform 1 from profiles where id in (u, l.seller_id) order by id for update;   -- both sides, in a fixed order
  pr := _tick(u);
  if n <= 0 or n > l.qty then perform _fail('Invalid quantity'); end if;
  cost := l.unit_price::bigint * n;
  net := _after_fee(cost);
  if pr.cash < cost then perform _fail(format('Costs $%s', cost)); end if;
  select coalesce(sum(qty), 0) into used from storage where player_id = u;
  if used + n > _storage_cap(u, pr.storage_cap) then perform _fail('Not enough storage room'); end if;
  update profiles set cash = cash - cost, market_volume = market_volume + cost where id = u;
  update profiles set cash = cash + net, market_volume = market_volume + cost where id = l.seller_id;
  perform _event(u, 'market', cost); perform _event(l.seller_id, 'market', cost);
  update storage set qty = qty + n where player_id = u and commodity = l.commodity;
  if n = l.qty then update listings set status = 'sold' where id = l.id;
  else update listings set qty = qty - n where id = l.id; end if;
  insert into market_trades (commodity, units, unit_price, buyer_id, seller_id, via) values (l.commodity, n, l.unit_price, u, l.seller_id, 'listing');
  return jsonb_build_object('cost', cost, 'units', n);
end $$;

-- The seller's "sold" line shows what they kept after the fee.
create or replace function _act_listing_sale() returns trigger
language plpgsql security definer set search_path = public as $$
declare buyer uuid := auth.uid(); units int; cash bigint; a activity;
begin
  if buyer is null or buyer = new.seller_id then return null; end if;
  units := case when new.status = 'sold' then old.qty else old.qty - new.qty end;
  if units <= 0 then return null; end if;
  cash := _after_fee(units::bigint * new.unit_price);
  select * into a from activity
   where player_id = new.seller_id and kind = 'sold' and actor_id = buyer and data->>'commodity' = new.commodity
     and not seen and updated_at > now() - interval '1 hour'
   order by updated_at desc limit 1 for update;
  if a.id is null then
    insert into activity (player_id, kind, actor_id, data)
    values (new.seller_id, 'sold', buyer, jsonb_build_object('commodity', new.commodity, 'units', units, 'cash', cash));
  else
    update activity set updated_at = now(), data = jsonb_build_object('commodity', new.commodity,
        'units', (a.data->>'units')::int + units, 'cash', (a.data->>'cash')::bigint + cash)
     where id = a.id;
  end if;
  return null;
end $$;

create or replace function post_order(commodity text, n integer, unit_price integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; street int; cost bigint; o buy_orders;
begin
  perform _nn(commodity, 'commodity'); perform _nn(n, 'quantity'); perform _nn(unit_price, 'price');
  pr := _tick(u);
  perform _refresh_prices();
  select price into street from street_prices where street_prices.commodity = post_order.commodity;
  if street is null then perform _fail('Bad commodity'); end if;
  if n < _cfg('listing_min') or n > _cfg('order_max') then
    perform _fail(format('Order between %s and %s units', _cfg('listing_min'), _cfg('order_max'))); end if;
  if unit_price <= 0 or unit_price > _price_cap(street) then
    perform _fail(format('Street price is $%s — you can offer up to $%s', street, _price_cap(street))); end if;
  if (select count(*) from buy_orders where buyer_id = u and status = 'open') >= _cfg('orders_open_max') then
    perform _fail(format('You can have %s open buy orders at a time', _cfg('orders_open_max'))); end if;
  cost := n::bigint * unit_price;
  if pr.cash < cost then perform _fail(format('This order holds $%s of your cash on hand', cost)); end if;
  update profiles set cash = cash - cost where id = u;
  insert into buy_orders (buyer_id, commodity, qty, unit_price) values (u, post_order.commodity, n, post_order.unit_price) returning * into o;
  return jsonb_build_object('id', o.id, 'held', cost);
end $$;

create or replace function cancel_order(buy_order uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); o buy_orders; back bigint;
begin
  perform _nn(buy_order, 'order');
  select * into o from buy_orders where id = buy_order and buyer_id = u and status = 'open' for update;
  if o.id is null then perform _fail('No such order'); end if;
  perform _tick(u);
  back := o.qty::bigint * o.unit_price;
  update profiles set cash = cash + back where id = u;
  update buy_orders set status = 'cancelled' where id = o.id;
  return jsonb_build_object('returned', back, 'filled', o.filled);
end $$;

-- Sell into someone's buy order. Like listing, moving product takes a vehicle big enough for the lot. The product
-- lands in the buyer's storage even past their cap (they asked for it; they just can't add more until there's room).
create or replace function fill_order(buy_order uuid, n integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; o buy_orders; have int; cap int; gross bigint; net bigint; a activity; cname text;
begin
  perform _nn(buy_order, 'order'); perform _nn(n, 'quantity');
  select * into o from buy_orders where id = buy_order and status = 'open' and expires_at > now() for update;
  if o.id is null then perform _fail('That order is gone'); end if;
  if o.buyer_id = u then perform _fail('That is your own order'); end if;
  perform 1 from profiles where id in (u, o.buyer_id) order by id for update;
  pr := _tick(u);
  if n <= 0 or n > o.qty then perform _fail('Invalid quantity'); end if;
  select name into cname from commodities where code = o.commodity;
  select qty into have from storage where player_id = u and commodity = o.commodity;
  if coalesce(have, 0) < n then perform _fail(format('You only have %s %s', coalesce(have, 0), cname)); end if;
  cap := _haul(u);
  if cap < n then perform _fail(format('Your transport carries %s units — buy a bigger vehicle', cap)); end if;
  gross := n::bigint * o.unit_price;
  net := _after_fee(gross);
  update storage set qty = qty - n where player_id = u and commodity = o.commodity;
  insert into storage as st (player_id, commodity, qty) values (o.buyer_id, o.commodity, n)
    on conflict (player_id, commodity) do update set qty = st.qty + excluded.qty;
  update profiles set cash = cash + net, market_volume = market_volume + gross where id = u;
  update profiles set market_volume = market_volume + gross where id = o.buyer_id;
  perform _event(u, 'market', gross); perform _event(o.buyer_id, 'market', gross);
  update buy_orders set qty = qty - n, filled = filled + n, status = case when qty - n = 0 then 'filled'::order_status else 'open' end
   where id = o.id;
  insert into market_trades (commodity, units, unit_price, buyer_id, seller_id, via) values (o.commodity, n, o.unit_price, o.buyer_id, u, 'order');
  -- the buyer's feed: one line per seller and product while it's unread (like "sold")
  select * into a from activity
   where player_id = o.buyer_id and kind = 'filled' and actor_id = u and data->>'commodity' = o.commodity
     and not seen and updated_at > now() - interval '1 hour'
   order by updated_at desc limit 1 for update;
  if a.id is null then
    insert into activity (player_id, kind, actor_id, data)
    values (o.buyer_id, 'filled', u, jsonb_build_object('commodity', o.commodity, 'units', n, 'cash', gross));
  else
    update activity set updated_at = now(), data = jsonb_build_object('commodity', o.commodity,
        'units', (a.data->>'units')::int + n, 'cash', (a.data->>'cash')::bigint + gross)
     where id = a.id;
  end if;
  return jsonb_build_object('units', n, 'cash', net, 'fee', gross - net, 'left', o.qty - n);
end $$;

-- Expired listings go back to storage, expired buy orders hand their cash back, then block bonuses.
create or replace function _tick_world() returns void
language plpgsql set search_path = public as $$
declare l record; o record; b record; periods int; income bigint; cartel uuid; cut bigint;
        cycle interval := make_interval(hours => _cfg('block_bonus_hours')::int);
begin
  -- expired listings go back to storage; whatever doesn't fit waits in a 'returned' holding listing
  for l in select * from listings where status = 'open' and expires_at <= now() for update skip locked loop
    perform _return_product(l.seller_id, l.commodity, l.qty, l.id, 'expired');
  end loop;

  for o in select * from buy_orders where status = 'open' and expires_at <= now() for update skip locked loop
    update profiles set cash = cash + o.qty::bigint * o.unit_price where id = o.buyer_id;
    update buy_orders set status = 'expired' where id = o.id;
  end loop;

  for b in select bl.id, bl.name, bl.owner_crew_id, bl.bonus_at, h.daily_income
             from blocks bl join hoods h on h.id = bl.hood_id
            where bl.owner_crew_id is not null and bl.bonus_at <= now()
            for update of bl skip locked loop
    periods := 1 + floor(extract(epoch from now() - b.bonus_at) / extract(epoch from cycle))::int;
    income := _block_bonus(b.daily_income) * periods;
    select cartel_id into cartel from crews where id = b.owner_crew_id;
    if cartel is null then
      update crews set bank = bank + income where id = b.owner_crew_id;
      perform _crew_ledger(b.owner_crew_id, null, 'bonus', income, b.name);
    else
      cut := (income * 0.2)::bigint;
      update crews set bank = bank + (income - cut) where id = b.owner_crew_id;
      update cartels set bank = bank + cut where id = cartel;
      perform _crew_ledger(b.owner_crew_id, null, 'bonus', income - cut, b.name);
      perform _cartel_ledger(cartel, null, 'bonus', cut, b.name);
    end if;
    update blocks set bonus_at = b.bonus_at + periods * cycle where id = b.id;
  end loop;
end $$;

-- Street, the last 24 hours of trading, what's for sale (cheapest first) and what's wanted (best offer first).
create or replace function get_market(commodity text default null) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'prices', (select jsonb_object_agg(sp.commodity, sp.price) from street_prices sp),
    'street', _street_json(),
    'stats', (select jsonb_object_agg(c.code, jsonb_build_object(
                'last', (select t.unit_price from market_trades t where t.commodity = c.code order by t.id desc limit 1),
                'last_at', (select t.created_at from market_trades t where t.commodity = c.code order by t.id desc limit 1),
                'units_24h', (select coalesce(sum(t.units), 0) from market_trades t where t.commodity = c.code and t.created_at > now() - interval '24 hours'),
                'avg_24h', (select round(sum(t.units::numeric * t.unit_price) / nullif(sum(t.units), 0)) from market_trades t
                             where t.commodity = c.code and t.created_at > now() - interval '24 hours')))
              from commodities c),
    'listings', (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'commodity', l.commodity, 'qty', l.qty,
                   'unit_price', l.unit_price, 'seller', p.name, 'seller_id', l.seller_id, 'mine', l.seller_id = auth.uid(),
                   'expires_at', l.expires_at) order by l.unit_price, l.created_at), '[]'::jsonb)
                 from listings l join profiles p on p.id = l.seller_id
                 where l.status = 'open' and l.expires_at > now() and (get_market.commodity is null or l.commodity = get_market.commodity)),
    'orders', (select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'commodity', o.commodity, 'qty', o.qty, 'filled', o.filled,
                   'unit_price', o.unit_price, 'buyer', p.name, 'buyer_id', o.buyer_id, 'mine', o.buyer_id = auth.uid(),
                   'expires_at', o.expires_at) order by o.unit_price desc, o.created_at), '[]'::jsonb)
               from buy_orders o join profiles p on p.id = o.buyer_id
               where o.status = 'open' and o.expires_at > now() and (get_market.commodity is null or o.commodity = get_market.commodity))) $$;

-- ---------------------------------------------------------------------------
-- get_me: path_due, street details, my buy orders, the next refill's strength · get_catalog: the new config
-- ---------------------------------------------------------------------------
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
    'heat_level', case when pr.heat >= _cfg('heat_red') then 'red' when pr.heat >= _cfg('heat_yellow') then 'yellow' else 'green' end,
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
    'path_due', _path_due(pr)   -- why a path is required: 'rep' or 'grow'
  );
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
      'price_pressure_max_pct', _cfg('price_pressure_max_pct'), 'price_recover_hours', _cfg('price_recover_hours'))
  ) $$;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
do $$ declare f record; begin
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('refill', 'choose_path', 'grow_upgrade', 'hire_hustlers', 'list_product',
             'buy_listing', 'post_order', 'cancel_order', 'fill_order', 'get_market', 'get_me', 'get_catalog') loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('_cfg', '_refill_share', '_path_due', '_need_path', '_decay', '_street',
             '_refresh_prices', '_street_json', '_after_fee', '_price_cap', '_haul', '_act_listing_sale', '_tick_world') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
end $$;
