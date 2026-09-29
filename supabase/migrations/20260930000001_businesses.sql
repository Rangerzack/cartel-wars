-- Businesses: every block in the city is a business, and the crew that holds it gets a perk.
--
--  * 19 businesses in 6 categories. Each hood's blocks A–F are one of each category — A Production, B Transport,
--    C Nightlife, D Muscle, E Retail, F Services — and within a category the business rotates hood to hood
--    ((gx + gy) mod n), which spreads every business evenly across the rings.
--  * One block's perk = the business's base, doubled in the center hood (ring 0) and 1x on the outer ring (ring 4),
--    x1.5 when the crew holds all six blocks of that hood, x1.75 if that crew is also in a cartel.
--  * Several blocks of the same business stack: the best counts in full and each extra adds a quarter of its own
--    value, up to double the best one. Every perk also has a hard ceiling.
--  * Perks go to every member of the crew that holds the blocks. They're personal (cheaper, faster, more), never
--    crew-bank money. Security Firm is the one crew-level perk: the crew's garrisons defend harder.
--  * Money-loop guard: Chop Shop tops out at -40% and Repo Co resale at 60%, so nothing can be bought and sold back
--    at a profit.

-- ---------------------------------------------------------------------------
-- Businesses and the map
-- ---------------------------------------------------------------------------
create table if not exists business_defs (
  code      text primary key,
  name      text not null,
  category  text not null,     -- production | transport | nightlife | muscle | retail | services
  slot      integer not null,  -- the block (1–6 = A–F) this category sits on in every hood
  rot       integer not null,  -- position within the category; hood (gx + gy) mod n picks which one
  icon      text not null,
  perk      text not null,     -- what it does, in a few words
  base      numeric not null,  -- one outer-ring block's perk (a fraction)
  ceiling   numeric not null,  -- the most it can ever reach
  sort      integer not null
);
alter table business_defs enable row level security;
revoke all on business_defs from anon, authenticated;

insert into business_defs (code, name, category, slot, rot, icon, perk, base, ceiling, sort) values
  ('grow_house',     'Grow House',     'production', 1, 0, '🌿', 'Herb grows faster',                     0.10, 0.50, 1),
  ('dust_lab',       'Dust Lab',       'production', 1, 1, '🧪', 'Dust cooks faster',                     0.10, 0.50, 2),
  ('pill_factory',   'Pill Factory',   'production', 1, 2, '💊', 'Pills press faster',                    0.10, 0.50, 3),
  ('utility',        'Utility Co',     'production', 1, 3, '⚡', 'Every grow house produces more',        0.05, 0.25, 4),
  ('chop_shop',      'Chop Shop',      'transport',  2, 0, '🔧', 'Vehicles cost less',                    0.10, 0.40, 5),
  ('trucking',       'Trucking Co',    'transport',  2, 1, '🚚', 'Bigger loads on the market',            0.25, 1.00, 6),
  ('repo',           'Repo Co',        'transport',  2, 2, '🔑', 'Sell items back for more',              0.05, 0.10, 7),
  ('strip_club',     'Strip Club',     'nightlife',  3, 0, '💃', 'Hustlers carry more',                   0.10, 0.40, 8),
  ('night_club',     'Night Club',     'nightlife',  3, 1, '🎶', 'Hustlers come back sooner',             0.10, 0.40, 9),
  ('dispensary',     'Dispensary',     'nightlife',  3, 2, '🍃', 'Hustlers sell over street price',       0.05, 0.20, 10),
  ('gym',            'Gym',            'muscle',     4, 0, '🏋️', 'Thugs cost less',                       0.10, 0.40, 11),
  ('shooting_range', 'Shooting Range', 'muscle',     4, 1, '🎯', 'Mercenaries and enforcers cost less',   0.10, 0.40, 12),
  ('security_firm',  'Security Firm',  'muscle',     4, 2, '🛡️', 'Your crew''s garrisons defend harder',  0.10, 0.40, 13),
  ('pawn_shop',      'Pawn Shop',      'retail',     5, 0, '💍', 'Weapons and protection cost less',      0.05, 0.20, 14),
  ('pharmacy',       'Pharmacy',       'retail',     5, 1, '⚕️', 'Product refills use less product',      0.10, 0.40, 15),
  ('warehouse',      'Warehouse',      'retail',     5, 2, '📦', 'More storage',                          0.10, 0.40, 16),
  ('clinic',         'Clinic',         'services',   6, 0, '🏥', 'Hospital health costs less',            0.10, 0.40, 17),
  ('law_office',     'Law Office',     'services',   6, 1, '⚖️', 'Cheaper bail, shorter jail',            0.15, 0.40, 18),
  ('bent_cop',       'Bent Cop',       'services',   6, 2, '👮', 'Bribes cost less',                      0.10, 0.40, 19)
on conflict (code) do nothing;

alter table blocks add column if not exists business text references business_defs(code);
update blocks b set business = d.code
  from hoods h, business_defs d
 where h.id = b.hood_id and d.slot = b.slot
   and d.rot = (h.gx + h.gy) % (select count(*) from business_defs x where x.slot = b.slot);

-- ---------------------------------------------------------------------------
-- Perk engine
-- ---------------------------------------------------------------------------
-- One block's perk.
create or replace function _business_value(base numeric, ring integer, full_hood boolean, in_cartel boolean) returns numeric
language sql immutable set search_path = public as $$
  select base * (1 + (4 - greatest(0, least(4, ring))) / 4.0)
       * case when full_hood then case when in_cartel then 1.75 else 1.5 end else 1 end $$;

-- A crew's perks, one row per business it holds: the stacked value, how many blocks, and its best block.
create or replace function _crew_perk_rows(cid uuid)
returns table (code text, value numeric, blocks integer, best_block integer, best numeric, best_full boolean)
language sql stable set search_path = public as $$
  with c as (select cartel_id is not null as in_cartel from crews where id = cid),
  mine as (select b.id, b.hood_id, b.business from blocks b where b.owner_crew_id = cid and b.business is not null),
  fh as (select hood_id from blocks where owner_crew_id = cid group by hood_id having count(*) = 6),
  v as (select m.id, m.business, d.ceiling, m.hood_id in (select hood_id from fh) as is_full,
               _business_value(d.base, greatest(abs(h.gx - 5), abs(h.gy - 5)), m.hood_id in (select hood_id from fh),
                               coalesce((select in_cartel from c), false)) as val
          from mine m join hoods h on h.id = m.hood_id join business_defs d on d.code = m.business),
  r as (select v.*, row_number() over (partition by v.business order by v.val desc, v.id) as rn from v)
  select r.business,
         least(max(r.ceiling), 2 * max(r.val) filter (where r.rn = 1),
               max(r.val) filter (where r.rn = 1) + 0.25 * coalesce(sum(r.val) filter (where r.rn > 1), 0)),
         count(*)::int, max(r.id) filter (where r.rn = 1), max(r.val) filter (where r.rn = 1),
         bool_or(r.is_full) filter (where r.rn = 1)
    from r group by r.business $$;

-- {business: perk} for a crew, and for a player (their crew's).
create or replace function _crew_perks(cid uuid) returns jsonb language sql stable set search_path = public as $$
  select coalesce(jsonb_object_agg(code, round(value, 4)), '{}'::jsonb) from _crew_perk_rows(cid) $$;

create or replace function _perks(p uuid) returns jsonb language sql stable set search_path = public as $$
  select coalesce((select _crew_perks(crew_id) from profiles where id = p and crew_id is not null), '{}'::jsonb) $$;

create or replace function _pk(perks jsonb, code text) returns numeric language sql immutable set search_path = public as $$
  select coalesce((perks->>code)::numeric, 0) $$;

-- Production multiplier for one product: its lab plus the Utility Co.
create or replace function _grow_boost(perks jsonb, commodity text) returns numeric language sql immutable set search_path = public as $$
  select 1 + _pk(perks, case commodity when 'herb' then 'grow_house' when 'dust' then 'dust_lab' when 'pills' then 'pill_factory' end)
           + _pk(perks, 'utility') $$;

-- Storage with the Warehouse perk.
create or replace function _storage_cap(p uuid, base integer) returns integer language sql stable set search_path = public as $$
  select floor(base * (1 + _pk(_perks(p), 'warehouse')))::int $$;

-- ---------------------------------------------------------------------------
-- Production: labs and the Utility Co
-- ---------------------------------------------------------------------------
create or replace function _grow_settle(g grow_houses) returns grow_houses language plpgsql set search_path = public as $$
declare c commodities; rate numeric; units int; cap int; boost numeric := _grow_boost(_perks(g.player_id), g.commodity);
begin
  select * into c from commodities where code = g.commodity;
  if g.running then
    rate := c.grow_rate * g.level * boost;               -- units per hour
    cap := floor(c.grow_cap * g.level * boost)::int;     -- the house holds more too, so it fills in the same time
    units := floor(extract(epoch from now() - g.started_at) / 3600 * rate)::int;
    if g.banked + units >= cap then
      g.banked := cap; g.started_at := now();            -- capped: progress beyond the cap is lost anyway
    else
      g.banked := g.banked + units;
      g.started_at := g.started_at + make_interval(secs => units / rate * 3600);   -- keep the fractional unit
    end if;
  end if;
  return g;
end $$;

-- ---------------------------------------------------------------------------
-- Storage: Warehouse
-- ---------------------------------------------------------------------------
create or replace function _return_product(p uuid, com text, n integer, listing uuid, final listing_status) returns integer
language plpgsql set search_path = public as $$
declare cap int; used int; fit int;
begin
  select storage_cap into cap from profiles where id = p for update;
  cap := _storage_cap(p, cap);
  select coalesce(sum(qty), 0) into used from storage where player_id = p;
  fit := greatest(0, least(n, cap - used));
  if fit > 0 then
    insert into storage as st (player_id, commodity, qty) values (p, com, fit)
      on conflict (player_id, commodity) do update set qty = st.qty + excluded.qty;
  end if;
  if fit = n then update listings set status = final, qty = 0 where id = listing;
  else update listings set status = 'returned', qty = n - fit where id = listing; end if;
  return fit;
end $$;

create or replace function grow_collect(house uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; g grow_houses; used int; room int; take int;
begin
  pr := _tick(u);
  select * into g from grow_houses where id = house and player_id = u for update;
  if g.id is null then perform _fail('No such grow house'); end if;
  g := _grow_settle(g);
  select coalesce(sum(qty), 0) into used from storage where player_id = u;
  room := _storage_cap(u, pr.storage_cap) - used;
  take := least(g.banked, greatest(room, 0));
  if take <= 0 then perform _fail(case when g.banked = 0 then 'Nothing to collect yet' else 'Storage is full' end); end if;
  update storage set qty = qty + take where player_id = u and commodity = g.commodity;
  update grow_houses set banked = g.banked - take, started_at = g.started_at where id = g.id;
  return jsonb_build_object('collected', take, 'left', g.banked - take);
end $$;

create or replace function buy_listing(listing uuid, n integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; l listings; used int; cost bigint;
begin
  perform _nn(n, 'quantity');
  pr := _tick(u);
  select * into l from listings where id = listing and status = 'open' and expires_at > now() for update;
  if l.id is null then perform _fail('That listing is gone'); end if;
  if l.seller_id = u then perform _fail('That is your own listing'); end if;
  if n <= 0 or n > l.qty then perform _fail('Invalid quantity'); end if;
  cost := l.unit_price::bigint * n;
  if pr.cash < cost then perform _fail(format('Costs $%s', cost)); end if;
  select coalesce(sum(qty), 0) into used from storage where player_id = u;
  if used + n > _storage_cap(u, pr.storage_cap) then perform _fail('Not enough storage room'); end if;
  update profiles set cash = cash - cost, market_volume = market_volume + cost where id = u;
  update profiles set cash = cash + cost, market_volume = market_volume + cost where id = l.seller_id;
  perform _event(u, 'market', cost); perform _event(l.seller_id, 'market', cost);
  update storage set qty = qty + n where player_id = u and commodity = l.commodity;
  if n = l.qty then update listings set status = 'sold' where id = l.id;
  else update listings set qty = qty - n where id = l.id; end if;
  return jsonb_build_object('cost', cost, 'units', n);
end $$;

-- ---------------------------------------------------------------------------
-- Market: Trucking Co (bigger vehicles' loads and a bigger listing limit)
-- ---------------------------------------------------------------------------
create or replace function list_product(commodity text, n integer, unit_price integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; have int; street int; cap int; l listings;
        truck numeric := _pk(_perks(u), 'trucking'); maxn int := floor(_cfg('listing_max') * (1 + truck))::int;
begin
  perform _nn(n, 'quantity'); perform _nn(unit_price, 'price');
  pr := _tick(u);
  perform _refresh_prices();
  if n < _cfg('listing_min') or n > maxn then
    perform _fail(format('List between %s and %s units', _cfg('listing_min'), maxn)); end if;
  select price into street from street_prices where street_prices.commodity = list_product.commodity;
  if street is null then perform _fail('Bad commodity'); end if;
  if unit_price <= 0 or unit_price > street then perform _fail(format('Street price is $%s — you cannot list above it', street)); end if;
  select coalesce(max(d.capacity), 0) into cap from inventory i join item_defs d on d.id = i.item_id
   where i.player_id = u and i.qty > 0 and d.category = 'transport';
  cap := floor(cap * (1 + truck))::int;
  if cap < n then perform _fail(format('Your transport carries %s units — buy a bigger vehicle', cap)); end if;
  select qty into have from storage where player_id = u and storage.commodity = list_product.commodity;
  if coalesce(have, 0) < n then perform _fail('Not enough in storage'); end if;
  update storage set qty = qty - n where player_id = u and storage.commodity = list_product.commodity;
  insert into listings (seller_id, commodity, qty, unit_price) values (u, commodity, n, unit_price) returning * into l;
  return jsonb_build_object('id', l.id);
end $$;

-- ---------------------------------------------------------------------------
-- Hustlers: Strip Club (carry more), Night Club (back sooner), Dispensary (sell over street)
-- ---------------------------------------------------------------------------
create or replace function hire_hustlers(commodity text, n integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; c commodities; have int; units int; cost int; price int; due bigint; pk jsonb := _perks(u);
begin
  perform _nn(n, 'count');
  pr := _tick(u);
  perform _need_path(pr, 'trader');
  perform _refresh_prices();
  select * into c from commodities where code = hire_hustlers.commodity;
  if c.code is null or n <= 0 or n > 100 then perform _fail('Hire between 1 and 100 hustlers'); end if;
  units := floor(c.hustler_units * n * (1 + _pk(pk, 'strip_club')))::int;
  cost := _cfg('hustler_price')::int * n;
  select qty into have from storage where player_id = u and storage.commodity = c.code;
  if coalesce(have, 0) < units then perform _fail(format('Needs %s %s in storage', units, c.name)); end if;
  if pr.cash < cost then perform _fail(format('Hiring costs $%s', cost)); end if;
  select sp.price into price from street_prices sp where sp.commodity = c.code;
  due := floor(units::numeric * price * (1 + _pk(pk, 'dispensary')))::bigint;
  update storage set qty = qty - units where player_id = u and storage.commodity = c.code;
  update profiles set cash = cash - cost where id = u;
  insert into hustlers (player_id, commodity, count, units, cash_due, returns_at)
  values (u, c.code, n, units, due, now() + make_interval(secs => _cfg('hustler_hours') * 3600 * (1 - _pk(pk, 'night_club'))));
  return jsonb_build_object('units', units, 'cash_due', due, 'cost', cost);
end $$;

-- ---------------------------------------------------------------------------
-- Shop: Pawn Shop (weapons, jail weapons, protection), Chop Shop (vehicles), Repo Co (resale)
-- ---------------------------------------------------------------------------
create or replace function buy_item(item integer, n integer default 1) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; d item_defs; cost bigint; disc numeric := 0;
begin
  perform _nn(n, 'quantity');
  pr := _tick(u);
  select * into d from item_defs where id = item;
  if d.id is null or n <= 0 then perform _fail('Bad item'); end if;
  if d.drop_only then perform _fail(format('%s can only be found on actions', d.name)); end if;
  if d.rep_price > 0 then
    cost := d.rep_price::bigint * n;
    if pr.reputation < cost then perform _fail(format('Needs %s reputation', cost)); end if;
    update profiles set reputation = reputation - cost where id = u;
  else
    disc := _pk(_perks(u), case when d.category = 'transport' then 'chop_shop' else 'pawn_shop' end);
    cost := round(d.price * (1 - disc))::bigint * n;
    if pr.cash < cost then perform _fail(format('Costs $%s', cost)); end if;
    update profiles set cash = cash - cost where id = u;
  end if;
  insert into inventory (player_id, item_id, qty) values (u, item, n)
    on conflict (player_id, item_id) do update set qty = inventory.qty + excluded.qty;
  return jsonb_build_object('cost', cost, 'discount', disc);
end $$;

create or replace function sell_item(item integer, n integer default 1) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); have int; used int; d item_defs; refund bigint;
begin
  perform _nn(n, 'quantity');
  perform _tick(u);
  select * into d from item_defs where id = item;
  select qty into have from inventory where player_id = u and item_id = item;
  select coalesce(max(qty), 0) into used from setup_items where player_id = u and item_id = item;
  if d.id is null or n <= 0 or coalesce(have, 0) - used < n then perform _fail('Not enough unequipped units to sell'); end if;
  if d.rep_price > 0 then perform _fail('Rare items cannot be sold'); end if;
  if d.drop_only then perform _fail('Rare finds cannot be sold'); end if;
  refund := floor(d.price * (0.5 + _pk(_perks(u), 'repo')))::bigint * n;
  update inventory set qty = qty - n where player_id = u and item_id = item;
  update profiles set cash = cash + refund where id = u;
  return jsonb_build_object('refund', refund);
end $$;

-- ---------------------------------------------------------------------------
-- Hoodlums: Gym (thugs), Shooting Range (mercenaries and enforcers)
-- ---------------------------------------------------------------------------
create or replace function buy_hoodlums(kind text, n integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; owned int; cost bigint; disc numeric;
begin
  perform _nn(n, 'quantity');
  pr := _tick(u);
  if n < 1 or n > 1000 then perform _fail('Buy between 1 and 1000 per transaction'); end if;
  if not exists (select 1 from hoodlum_defs d where d.code = kind) then perform _fail('Bad hoodlum'); end if;
  select coalesce(ph.qty, 0) into owned from player_hoodlums ph where ph.player_id = u and ph.code = kind;
  disc := _pk(_perks(u), case kind when 'thug' then 'gym' when 'mercenary' then 'shooting_range' when 'enforcer' then 'shooting_range' else '' end);
  cost := ceil(_hoodlum_price(kind, coalesce(owned, 0), n) * (1 - disc))::bigint;
  if pr.cash < cost then perform _fail(format('Costs $%s', cost)); end if;
  update profiles set cash = cash - cost where id = u;
  insert into player_hoodlums as ph (player_id, code, qty) values (u, kind, n)
    on conflict (player_id, code) do update set qty = ph.qty + excluded.qty;
  return jsonb_build_object('cost', cost, 'discount', disc);
end $$;

-- ---------------------------------------------------------------------------
-- Services: Pharmacy (refills), Clinic (health), Law Office (bail, jail time), Bent Cop (bribes)
-- ---------------------------------------------------------------------------
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
  else
    select * into c from commodities where code = method;
    if c.code is null then perform _fail('Bad refill'); end if;
    units := case when kind = 'stamina' then c.refill_stamina else c.refill_health end;
    units := ceil(units * (1 - _pk(_perks(u), 'pharmacy')))::int;
    select qty into have from storage where player_id = u and commodity = method;
    if coalesce(have, 0) < units then perform _fail(format('Needs %s %s', units, c.name)); end if;
    update storage set qty = qty - units where player_id = u and commodity = method;
    gain := case when pr.refills_used >= 3 then ceil(missing / 2.0) else missing end;
    update profiles set refills_used = refills_used + 1,
           refills_reset_at = case when pr.refills_used = 0 then now() else refills_reset_at end where id = u;
  end if;
  if kind = 'stamina' then update profiles set stamina = stamina + gain where id = u;
  else update profiles set health = health + gain where id = u; end if;
  return jsonb_build_object('gain', gain, 'units', units);
end $$;

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
  cost := ceil(_health_price(pr.health_bought, points) * (1 - _pk(_perks(u), 'clinic')))::bigint;
  if pr.cash < cost then perform _fail(format('%s health costs $%s', points, cost)); end if;
  update profiles set cash = cash - cost, health = health + points,
         health_bought = health_bought + points,
         health_bought_at = coalesce(health_bought_at, now())
   where id = u;
  return jsonb_build_object('cost', cost, 'gain', points, 'health', pr.health + points);
end $$;

create or replace function bail_out() returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; mins int; cost int;
begin
  pr := _tick(u);
  if not _jailed(pr) then perform _fail('You are not in jail'); end if;
  mins := ceil(extract(epoch from pr.jail_until - now()) / 60)::int;
  cost := ceil((_cfg('bail_base') + mins * _cfg('bail_per_minute')) * (1 - _pk(_perks(u), 'law_office')))::int;
  if pr.cash < cost then perform _fail(format('Bail costs $%s', cost)); end if;
  update profiles set cash = cash - cost, jail_until = null where id = u;
  return jsonb_build_object('cost', cost);
end $$;

-- Busted: jail time is shorter with a Law Office. (Bribing your way into jail on purpose is still 2 hours.)
create or replace function _bust_roll(pr profiles) returns profiles language plpgsql set search_path = public as $$
begin
  if _jailed(pr) then return pr; end if;
  if pr.heat >= _cfg('heat_red') and random() < (pr.heat - _cfg('heat_red') + 1) / 40.0 then
    pr.jail_until := now() + make_interval(secs => _cfg('jail_minutes') * 60 * (1 - _pk(_perks(pr.id), 'law_office')));
    pr.heat := _cfg('heat_yellow')::int;
  end if;
  return pr;
end $$;

create or replace function bribe_police(points integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; n int; cost int;
begin
  perform _nn(points, 'amount');
  pr := _tick(u);
  n := least(points, pr.heat);
  if n <= 0 then perform _fail('No heat to bribe away'); end if;
  cost := ceil(n * _cfg('bribe_per_heat') * (1 - _pk(_perks(u), 'bent_cop')))::int;
  if pr.cash < cost then perform _fail(format('That bribe costs $%s', cost)); end if;
  update profiles set cash = cash - cost, heat = heat - n where id = u;
  return jsonb_build_object('cost', cost, 'heat', pr.heat - n);
end $$;

-- ---------------------------------------------------------------------------
-- Turf: Security Firm (the defending crew's garrisons count for more)
-- ---------------------------------------------------------------------------
create or replace function attack_block(block integer, thugs integer, mercs integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; b blocks; h hoods; have_t int; have_m int; atk numeric; res numeric;
        claim int := 0; success boolean; captured boolean := false; loss_frac numeric; lost_t int; lost_m int;
        g record; gloss numeric; glost int := 0; nwins int; defender crews; my_cartel uuid; guard numeric := 0;
        need int := _cfg('siege_wins')::int; min_thugs int := _cfg('siege_min_thugs')::int;
        cycle interval := make_interval(hours => _cfg('block_bonus_hours')::int);
begin
  perform _nn(thugs, 'thugs'); perform _nn(mercs, 'mercenaries');
  pr := _tick(u);
  if pr.crew_id is null then perform _fail('Join a crew to fight for territory'); end if;
  if _jailed(pr) then perform _fail('You cannot run a turf war from jail'); end if;
  if _hospital(pr) then perform _fail('You are in the hospital'); end if;
  if mercs < 0 then perform _fail('Bad number of mercenaries'); end if;
  if thugs < min_thugs then perform _fail(format('A turf attack needs at least %s thugs', min_thugs)); end if;
  select * into b from blocks where id = block for update;
  if b.id is null then perform _fail('No such block'); end if;
  if b.owner_crew_id = pr.crew_id then perform _fail('Your crew already holds that block'); end if;
  select * into h from hoods where id = b.hood_id;
  if b.owner_crew_id is not null then
    select * into defender from crews where id = b.owner_crew_id;
    select cartel_id into my_cartel from crews where id = pr.crew_id;
    if my_cartel is not null and defender.cartel_id = my_cartel then perform _fail('That block belongs to a crew in your cartel'); end if;
    guard := _pk(_crew_perks(b.owner_crew_id), 'security_firm');
  end if;
  select coalesce(qty,0) into have_t from player_hoodlums where player_id = u and code = 'thug';
  select coalesce(qty,0) into have_m from player_hoodlums where player_id = u and code = 'mercenary';
  if coalesce(have_t,0) < thugs or coalesce(have_m,0) < mercs then perform _fail('Not enough hoodlums'); end if;
  if b.owner_crew_id is null then
    claim := h.price / 6;
    if pr.cash < claim then perform _fail(format('Claiming a block here costs $%s', claim)); end if;
  end if;
  if pr.stamina < 3 then perform _fail('A turf war takes 3 stamina'); end if;

  atk := (thugs * 10 + mercs * 60) * (0.9 + random() * 0.2);
  res := h.base_resistance + (1 + guard) * coalesce((select sum(bg.qty * d.def) from block_garrison bg join hoodlum_defs d on d.code = bg.code where bg.block_id = block), 0);
  if atk < res * 0.25 then perform _fail(format('That force would be laughed off the block — bring at least a quarter of the resistance (~%s)', round(res * 0.25))); end if;
  success := atk > res;
  update profiles set stamina = stamina - 3 where id = u;

  -- attacker losses: proportional to how hard the resistance was, up to 50%
  loss_frac := least(1, res / greatest(atk, 1)) * 0.5;
  lost_t := floor(thugs * loss_frac); lost_m := floor(mercs * loss_frac);
  update player_hoodlums set qty = qty - lost_t where player_id = u and code = 'thug';
  update player_hoodlums set qty = qty - lost_m where player_id = u and code = 'mercenary';

  -- garrison losses (rounded down — a token raid doesn't chip away at a big garrison)
  gloss := least(1, atk / greatest(res, 1)) * 0.5;
  for g in select * from block_garrison where block_id = block and qty > 0 loop
    glost := glost + floor(g.qty * gloss)::int;
    update block_garrison set qty = qty - floor(g.qty * gloss)::int where block_id = block and code = g.code;
  end loop;

  if success then
    if b.owner_crew_id is null then
      captured := true;                                   -- empty block: one win claims it
    else
      insert into block_siege as s (block_id, crew_id, wins) values (block, pr.crew_id, 1)
        on conflict (block_id, crew_id) do update set wins = s.wins + 1, updated_at = now()
        returning s.wins into nwins;
      if nwins >= need then
        captured := true;
      else
        update blocks set bonus_at = now() + cycle where id = block;   -- every hit restarts their bonus clock
      end if;
    end if;
  end if;

  if captured then
    glost := glost + coalesce((select sum(qty) from block_garrison where block_id = block), 0)::int;
    delete from block_garrison where block_id = block;
    delete from block_siege where block_id = block;
    update blocks set owner_crew_id = pr.crew_id, taken_at = now(), bonus_at = now() + cycle where id = block;
    if claim > 0 then update profiles set cash = cash - claim where id = u; end if;
    perform _recompute_hood(h.id);
    perform _event(u, 'turf');
    if defender.id is not null then
      insert into messages (channel, sender_id, sender_name, body)
      values ('crew:' || defender.id, u, pr.name, format('🏚 %s took %s from your crew.', (select name from crews where id = pr.crew_id), b.name));
    end if;
  end if;

  insert into territory_log (block_id, attacker_id, crew_id, defender_crew_id, success, captured, attack, resistance,
                             thugs, mercs, lost_thugs, lost_mercs, garrison_lost, siege_wins)
  values (block, u, pr.crew_id, b.owner_crew_id, success, captured, round(atk), round(res),
          thugs, mercs, lost_t, lost_m, glost, case when b.owner_crew_id is not null then coalesce(nwins, (select s.wins from block_siege s where s.block_id = block and s.crew_id = pr.crew_id), 0) end);
  return jsonb_build_object('success', success, 'captured', captured, 'attack', round(atk), 'resistance', round(res),
    'lost_thugs', lost_t, 'lost_mercs', lost_m, 'garrison_lost', glost,
    'claim_paid', case when captured then claim else 0 end,
    'wins', case when b.owner_crew_id is not null then case when captured then need else coalesce(nwins, (select s.wins from block_siege s where s.block_id = block and s.crew_id = pr.crew_id), 0) end end,
    'wins_needed', need,
    'bonus_reset', success and not captured and b.owner_crew_id is not null);
end $$;

-- Spies report the resistance an attack would really face, Security Firm included.
create or replace function spy_block(block integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); have int; g jsonb; b blocks; h hoods; guard numeric := 0;
begin
  perform _tick(u);
  select * into b from blocks where id = block; select * into h from hoods where id = b.hood_id;
  if b.id is null then perform _fail('No such block'); end if;
  select qty into have from player_hoodlums where player_id = u and code = 'spy';
  if coalesce(have, 0) < 1 then perform _fail('You need a Spy'); end if;
  update player_hoodlums set qty = qty - 1 where player_id = u and code = 'spy';
  if b.owner_crew_id is not null then guard := _pk(_crew_perks(b.owner_crew_id), 'security_firm'); end if;
  select coalesce(jsonb_object_agg(code, qty), '{}'::jsonb) into g from block_garrison where block_id = block and qty > 0;
  return jsonb_build_object('garrison', g, 'resistance', round(
    h.base_resistance + (1 + guard) * coalesce((select sum(bg.qty * d.def) from block_garrison bg join hoodlum_defs d on d.code = bg.code where bg.block_id = block), 0)),
    'security', guard);
end $$;

-- ---------------------------------------------------------------------------
-- Reads: the map, a block, a crew, the catalog and the player
-- ---------------------------------------------------------------------------
create or replace function get_territory() returns jsonb
language sql security definer set search_path = public stable as $$
  with me as (select crew_id from profiles where id = auth.uid()),
  g as (select block_id, sum(qty) as n, jsonb_object_agg(code, qty) as garrison
          from block_garrison where qty > 0 group by block_id),
  s as (select block_id, max(wins) as top, max(wins) filter (where crew_id = (select crew_id from me)) as mine
          from block_siege group by block_id),
  bl as (select b.hood_id,
                count(*) filter (where b.owner_crew_id = (select crew_id from me)) as my_blocks,
                count(b.owner_crew_id) = 6 and count(distinct b.owner_crew_id) = 1 as full_hood,
                jsonb_agg(jsonb_build_object('id', b.id, 'slot', b.slot, 'name', b.name, 'business', b.business,
                  'owner', case when c.id is not null then jsonb_build_object('id', c.id, 'name', c.name, 'emblem', c.emblem) end,
                  'mine', b.owner_crew_id is not null and b.owner_crew_id = (select crew_id from me),
                  'garrisoned', g.n is not null,
                  'garrison_size', case when b.owner_crew_id = (select crew_id from me) then coalesce(g.n, 0) end,
                  'garrison', case when b.owner_crew_id = (select crew_id from me) then g.garrison end,
                  'bonus_at', b.bonus_at,
                  'my_wins', coalesce(s.mine, 0), 'top_wins', coalesce(s.top, 0)) order by b.slot) as blocks
           from blocks b left join crews c on c.id = b.owner_crew_id
           left join g on g.block_id = b.id left join s on s.block_id = b.id
          group by b.hood_id)
  select jsonb_build_object(
    'hoods', coalesce(jsonb_agg(jsonb_build_object('id', h.id, 'name', h.name, 'district', h.island, 'gx', h.gx, 'gy', h.gy,
               'ring', greatest(abs(h.gx - 5), abs(h.gy - 5)),
               'price', h.price, 'claim_price', h.price / 6, 'daily_income', h.daily_income, 'block_bonus', _block_bonus(h.daily_income),
               'base_resistance', h.base_resistance, 'my_blocks', bl.my_blocks, 'full_hood', bl.full_hood,
               'owner', (select jsonb_build_object('id', c.id, 'name', c.name, 'emblem', c.emblem) from crews c where c.id = h.owner_crew_id),
               'blocks', bl.blocks) order by h.gy, h.gx), '[]'::jsonb),
    'rules', jsonb_build_object('siege_wins', _cfg('siege_wins'), 'min_thugs', _cfg('siege_min_thugs'),
                                'bonus_hours', _cfg('block_bonus_hours'), 'stamina', 3),
    'my_perks', _perks(auth.uid()))
  from hoods h join bl on bl.hood_id = h.id $$;

create or replace function get_block(block integer) returns jsonb
language plpgsql security definer set search_path = public stable as $$
declare u uuid := _uid(); b blocks; h hoods; my_crew uuid; mine boolean; d business_defs; ring int; is_full boolean := false;
        owner_cartel boolean := false; my_perks jsonb;
begin
  select * into b from blocks where id = block;
  if b.id is null then perform _fail('No such block'); end if;
  select * into h from hoods where id = b.hood_id;
  select * into d from business_defs where code = b.business;
  select crew_id into my_crew from profiles where id = u;
  mine := b.owner_crew_id is not null and b.owner_crew_id = my_crew;
  ring := greatest(abs(h.gx - 5), abs(h.gy - 5));
  if b.owner_crew_id is not null then
    is_full := (select count(*) from blocks where hood_id = h.id and owner_crew_id = b.owner_crew_id) = 6;
    owner_cartel := exists (select 1 from crews where id = b.owner_crew_id and cartel_id is not null);
  end if;
  my_perks := _perks(u);
  return jsonb_build_object('id', b.id, 'name', b.name, 'slot', b.slot, 'hood_id', h.id, 'hood', h.name, 'district', h.island,
    'gx', h.gx, 'gy', h.gy, 'ring', ring, 'claim_price', h.price / 6, 'block_bonus', _block_bonus(h.daily_income),
    'base_resistance', h.base_resistance, 'bonus_at', b.bonus_at, 'taken_at', b.taken_at, 'mine', mine,
    'owner', (select jsonb_build_object('id', c.id, 'name', c.name, 'emblem', c.emblem) from crews c where c.id = b.owner_crew_id),
    'garrisoned', exists (select 1 from block_garrison where block_id = b.id and qty > 0),
    'garrison', case when mine then (select coalesce(jsonb_object_agg(code, qty), '{}'::jsonb) from block_garrison where block_id = b.id and qty > 0) end,
    'siege', (select coalesce(jsonb_agg(jsonb_build_object('crew_id', c.id, 'crew', c.name, 'emblem', c.emblem, 'wins', s.wins,
                'mine', c.id = my_crew, 'at', s.updated_at) order by s.wins desc, s.updated_at), '[]'::jsonb)
              from block_siege s join crews c on c.id = s.crew_id where s.block_id = b.id and s.wins > 0),
    'log', (select coalesce(jsonb_agg(_territory_log_json(l) order by l.created_at desc, l.id desc), '[]'::jsonb)
            from (select * from territory_log where block_id = b.id order by created_at desc, id desc limit 30) l),
    'business', case when d.code is not null then jsonb_build_object(
        'code', d.code, 'name', d.name, 'icon', d.icon, 'category', d.category, 'perk', d.perk, 'ceiling', d.ceiling,
        'value', round(_business_value(d.base, ring, false, false), 4),                -- this block on its own
        'value_full', round(_business_value(d.base, ring, true, false), 4),           -- with the whole hood
        'value_full_cartel', round(_business_value(d.base, ring, true, true), 4),     -- ... and in a cartel
        'owner_value', case when b.owner_crew_id is not null then round(_business_value(d.base, ring, is_full, owner_cartel), 4) end,
        'owner_full', is_full,
        'owner_total', case when b.owner_crew_id is not null then _pk(_crew_perks(b.owner_crew_id), d.code) end,
        'my_total', _pk(my_perks, d.code)) end);
end $$;

create or replace function get_crew(cid uuid) returns jsonb
language plpgsql security definer set search_path = public stable as $$
declare u uuid := _uid(); c crews; boss boolean;
begin
  select * into c from crews where id = cid;
  if c.id is null then perform _fail('No such crew'); end if;
  boss := _crew_boss(c, u);
  return jsonb_build_object('id', c.id, 'name', c.name, 'emblem', c.emblem, 'description', c.description,
    'capo_id', c.capo_id, 'is_capo', c.capo_id = u, 'co_capo_id', c.co_capo_id, 'is_co_capo', c.co_capo_id = u,
    'is_boss', boss, 'created_at', c.created_at,
    'bank', case when exists (select 1 from profiles where id = u and crew_id = c.id) then c.bank end,
    'cartel', (select jsonb_build_object('id', id, 'name', name, 'don_id', don_id) from cartels where id = c.cartel_id),
    'members', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'avatar', p.avatar, 'fights_won', p.fights_won,
                  'actions', p.actions_done, 'is_capo', p.id = c.capo_id, 'is_co_capo', p.id = c.co_capo_id, 'last_seen', p.last_seen)
                  order by p.id = c.capo_id desc, p.id = c.co_capo_id desc, p.name), '[]'::jsonb)
                from profiles p where p.crew_id = c.id),
    'blocks', (select coalesce(jsonb_agg(jsonb_build_object('id', b.id, 'name', b.name, 'hood', h.name, 'hood_id', h.id, 'island', h.island,
                  'bonus_at', b.bonus_at, 'business', b.business) order by b.bonus_at nulls last), '[]'::jsonb)
               from blocks b join hoods h on h.id = b.hood_id where b.owner_crew_id = c.id),
    'applications', case when boss then
       (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'at', a.created_at)), '[]'::jsonb)
        from crew_applications a join profiles p on p.id = a.player_id where a.crew_id = c.id) end,
    'applied', exists (select 1 from crew_applications where crew_id = c.id and player_id = u),
    'invites', case when c.capo_id = u then
       (select coalesce(jsonb_agg(jsonb_build_object('id', ca.id, 'name', ca.name)), '[]'::jsonb)
        from cartel_invites i join cartels ca on ca.id = i.cartel_id where i.crew_id = c.id) end,
    'power', jsonb_build_object('att', _crew_power(c.id, true), 'def', _crew_power(c.id, false)),
    'fights', (select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'attacker', a.name, 'attacker_id', a.id, 'defender', d.name, 'defender_id', d.id,
                  'won', f.won, 'attack', f.attack_power, 'defense', f.defense_power, 'cash', f.cash_taken, 'at', f.created_at,
                  'we_attacked', f.attacker_crew = c.id) order by f.created_at desc), '[]'::jsonb)
               from (select * from crew_fights where attacker_crew = c.id or defender_crew = c.id order by created_at desc limit 10) f
               join crews a on a.id = f.attacker_crew join crews d on d.id = f.defender_crew),
    'next_fight_at', (select max(created_at) + make_interval(mins => _cfg('crew_fight_cooldown_min')::int) from crew_fights
                      where defender_crew = c.id and attacker_crew = (select crew_id from profiles where id = u)),
    -- the crew's perks: stacked value, how many blocks, and the best one (with its hood)
    'perks', (select coalesce(jsonb_agg(jsonb_build_object('code', r.code, 'value', round(r.value, 4), 'blocks', r.blocks,
                  'best', round(r.best, 4), 'best_full', r.best_full, 'best_block', r.best_block, 'best_name', b.name, 'best_hood_id', b.hood_id)
                  order by d.sort), '[]'::jsonb)
              from _crew_perk_rows(c.id) r join business_defs d on d.code = r.code join blocks b on b.id = r.best_block));
end $$;

create or replace function get_catalog() returns jsonb
language sql security definer set search_path = public stable as $$
  select jsonb_build_object(
    'actions', (select jsonb_agg(to_jsonb(a) order by a.sort) from action_defs a),
    'items', (select jsonb_agg(to_jsonb(i) order by i.sort) from item_defs i),
    'commodities', (select jsonb_agg(to_jsonb(c) order by c.sort) from commodities c),
    'hoodlums', (select jsonb_agg(to_jsonb(h)) from hoodlum_defs h),
    'businesses', (select jsonb_agg(to_jsonb(b) order by b.sort) from business_defs b),
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
      'bot_min_strength', _cfg('bot_min_strength'), 'jail_minutes', _cfg('jail_minutes'))
  ) $$;

-- get_me: the player's perks, and storage / cargo / grow houses with their perks applied.
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
    'path_required', pr.path is null and pr.rep_earned >= _cfg('path_rep'),
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
    'transport_capacity', floor((select coalesce(max(d.capacity), 0) from inventory i join item_defs d on d.id = i.item_id
                           where i.player_id = u and i.qty > 0 and d.category = 'transport') * (1 + _pk(pk, 'trucking')))::int,
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
    'perks', pk
  );
end $$;

-- ---------------------------------------------------------------------------
-- Grants: the new helpers stay private.
-- ---------------------------------------------------------------------------
do $$ declare f record; begin
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('_business_value', '_crew_perk_rows', '_crew_perks', '_perks', '_pk',
                                                         '_grow_boost', '_storage_cap', '_grow_settle', '_return_product', '_bust_roll') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
end $$;
