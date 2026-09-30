-- Tests for businesses: the map, the perk math (rings, full hoods, cartels, stacking, ceilings) and every perk's effect.
-- Run after the other suites (reuses their helpers): scripts/local-db.sh test
\set ON_ERROR_STOP on
\set QUIET on

insert into auth.users (id, raw_user_meta_data) values
  ('f1111111-1111-1111-1111-111111111111', '{"name":"Skyler"}'),
  ('f2222222-2222-2222-2222-222222222222', '{"name":"Huell"}'),
  ('f3333333-3333-3333-3333-333333333333', '{"name":"Kuby"}');

-- Hand a crew a set of blocks (and take everything else away from it).
create or replace function give_blocks(cid uuid, ids integer[]) returns void language sql as $$
  update blocks set owner_crew_id = null where owner_crew_id = cid and not (id = any(ids));
  update blocks set owner_crew_id = cid, bonus_at = now() + interval '1 day' where id = any(ids);
$$;
-- Blocks of a business in a ring, in a stable order.
create or replace function blocks_of(biz text, rng integer, n integer) returns integer[] language sql as $$
  select array(select b.id from blocks b join hoods h on h.id = b.hood_id
                where b.business = biz and greatest(abs(h.gx - 5), abs(h.gy - 5)) = rng order by b.id limit n) $$;
create or replace function near(a numeric, b numeric) returns boolean language sql immutable as $$ select abs(a - b) < 0.0001 $$;
-- A business's base (one outer block) and ceiling. The checks below are written against these, so they hold
-- whatever the table is tuned to (perks were cut to 75% of launch on 2026-10-01).
create or replace function base_of(biz text) returns numeric language sql stable as $$ select base from business_defs where code = biz $$;
create or replace function top_of(biz text) returns numeric language sql stable as $$ select ceiling from business_defs where code = biz $$;

-- The map ---------------------------------------------------------------------------------------------------
do $$ declare r record; begin
  assert (select count(*) from business_defs) = 19, '19 businesses';
  assert not exists (select 1 from blocks where business is null), 'every block is a business';
  -- every hood has one business from each of the six categories, on the same slot every time
  assert not exists (select 1 from blocks b join business_defs d on d.code = b.business where d.slot <> b.slot), 'slot = category';
  assert (select count(distinct (b.hood_id, d.category)) from blocks b join business_defs d on d.code = b.business) = 81 * 6;
  -- every business shows up in every ring from 1 outward, spread evenly
  for r in select d.code, count(*) filter (where greatest(abs(h.gx - 5), abs(h.gy - 5)) = 4) as outer_n,
                  count(distinct greatest(abs(h.gx - 5), abs(h.gy - 5))) filter (where greatest(abs(h.gx - 5), abs(h.gy - 5)) > 0) as rings
             from business_defs d join blocks b on b.business = d.code join hoods h on h.id = b.hood_id group by d.code loop
    assert r.rings = 4 and r.outer_n between 8 and 11, 'spread: ' || r.code || ' outer ' || r.outer_n || ' rings ' || r.rings;
  end loop;
  assert jsonb_array_length(get_catalog()->'businesses') = 19;
  -- tuning: every perk at 75% of launch
  assert near(base_of('gym'), 0.075) and near(top_of('gym'), 0.30) and near(top_of('trucking'), 0.75)
     and near(top_of('repo'), 0.075) and near(base_of('law_office'), 0.1125), 'perks at 75% of launch';
end $$;

-- One block's value ---------------------------------------------------------------------------------------------
do $$ begin
  assert near(_business_value(0.10, 4, false, false), 0.10), 'outer ring = base';
  assert near(_business_value(0.10, 0, false, false), 0.20), 'center = double';
  assert near(_business_value(0.10, 2, false, false), 0.15), 'halfway';
  assert near(_business_value(0.10, 4, true, false), 0.15), 'full hood x1.5';
  assert near(_business_value(0.10, 4, true, true), 0.175), 'full hood in a cartel x1.75';
  assert near(_business_value(0.10, 0, true, true), 0.35);
end $$;

-- Stacking, full hoods, cartels, ceilings ---------------------------------------------------------------------
select as_user('f1111111-1111-1111-1111-111111111111');
do $$ declare cid uuid; p jsonb; hid int; begin
  perform get_me();
  cid := (crew_create('Gray Matter', '⚗️', 'Chemistry.')->>'id')::uuid;
  assert near(top_of('gym'), 4 * base_of('gym')), 'gym tops out at 4x one outer block';
  -- one outer Gym: its base (b)
  perform give_blocks(cid, blocks_of('gym', 4, 1));
  assert near(_pk(_crew_perks(cid), 'gym'), base_of('gym')), 'one outer gym: ' || _crew_perks(cid)::text;
  assert near(_pk(get_me()->'perks', 'gym'), base_of('gym')), 'members see it in get_me';
  -- five outer Gyms: b + 4 x b/4 = 2b
  perform give_blocks(cid, blocks_of('gym', 4, 5));
  assert near(_pk(_crew_perks(cid), 'gym'), 2 * base_of('gym')), 'five: ' || _crew_perks(cid)::text;
  -- eight: would be 2.75b, but tops out at double the best block
  perform give_blocks(cid, blocks_of('gym', 4, 8));
  assert near(_pk(_crew_perks(cid), 'gym'), 2 * base_of('gym')), 'capped at 2x best';
  -- a ring-2 gym is the new best (1.5b); the eight outer ones add a quarter each, capped at 3b
  perform give_blocks(cid, blocks_of('gym', 4, 8) || blocks_of('gym', 2, 1));
  assert near(_pk(_crew_perks(cid), 'gym'), 3 * base_of('gym')), 'better best raises the cap: ' || _crew_perks(cid)::text;

  -- the whole center hood: every business there counts x2 (center) x1.5 (full hood)
  hid := (select id from hoods where gx = 5 and gy = 5);
  perform give_blocks(cid, array(select id from blocks where hood_id = hid));
  p := _crew_perks(cid);
  assert near(_pk(p, (select business from blocks where hood_id = hid and slot = 4)),
              _business_value((select base from business_defs d join blocks b on b.business = d.code where b.hood_id = hid and b.slot = 4), 0, true, false)),
         'center full hood: ' || p::text;
  assert (select count(*) from jsonb_object_keys(p)) = 6, 'six perks from one hood';
  -- one block short of the full hood: back to x1 (center still x2)
  perform give_blocks(cid, array(select id from blocks where hood_id = hid and slot < 6));
  assert near(_pk(_crew_perks(cid), (select business from blocks where hood_id = hid and slot = 1)),
              _business_value((select base from business_defs d join blocks b on b.business = d.code where b.hood_id = hid and b.slot = 1), 0, false, false));

  -- in a cartel, a full hood counts x1.75
  perform give_blocks(cid, array(select id from blocks where hood_id = hid));
  perform cartel_create('Los Cousins');
  assert near(_pk(_crew_perks(cid), (select business from blocks where hood_id = hid and slot = 1)),
              _business_value((select base from business_defs d join blocks b on b.business = d.code where b.hood_id = hid and b.slot = 1), 0, true, true)),
         'cartel bonus';

  -- hold the whole city in a cartel: every perk sits at its ceiling
  perform give_blocks(cid, array(select id from blocks));
  p := _crew_perks(cid);
  assert (select count(*) from jsonb_object_keys(p)) = 19;
  assert not exists (select 1 from business_defs d where not near(_pk(p, d.code), d.ceiling)), 'all at ceiling: ' || p::text;
  -- crew page lists them with the best block
  assert jsonb_array_length(get_crew(cid)->'perks') = 19;
  assert (select (e->>'best_full')::boolean and (e->>'blocks')::int > 20 from jsonb_array_elements(get_crew(cid)->'perks') e where e->>'code' = 'gym');
end $$;

-- The map and block payloads ------------------------------------------------------------------------------------
do $$ declare t jsonb; b jsonb; bid int; begin
  t := get_territory();
  assert (select bool_and((e->>'full_hood')::boolean) from jsonb_array_elements(t->'hoods') e), 'every hood full';
  assert (select count(*) from jsonb_array_elements(t->'hoods') h, jsonb_array_elements(h->'blocks') bl where bl->>'business' is not null) = 486;
  assert near(_pk(t->'my_perks', 'gym'), top_of('gym'));
  bid := (blocks_of('pawn_shop', 4, 1))[1];
  b := get_block(bid)->'business';
  assert b->>'code' = 'pawn_shop' and b->>'name' = 'Pawn Shop', b::text;
  assert near((b->>'value')::numeric, base_of('pawn_shop')) and near((b->>'value_full')::numeric, 1.5 * base_of('pawn_shop'))
     and near((b->>'value_full_cartel')::numeric, 1.75 * base_of('pawn_shop')), b::text;
  assert (b->>'owner_full')::boolean and near((b->>'owner_value')::numeric, 1.75 * base_of('pawn_shop'))
     and near((b->>'owner_total')::numeric, top_of('pawn_shop')) and near((b->>'my_total')::numeric, top_of('pawn_shop'));
end $$;

-- Effects: Skyler's crew holds the whole city in a cartel, so every perk is at its ceiling -------------------------
select as_user('f1111111-1111-1111-1111-111111111111');
do $$ declare u uuid := auth.uid(); r jsonb; mg item_defs; ct item_defs; c bigint; t timestamptz; h profiles; begin
  select * into mg from item_defs where name = 'Minigun';
  select * into ct from item_defs where name = 'Cargo Truck';
  update profiles set cash = 100000000, heat = 50, health = 50, health_bought = 0, jail_until = null, stamina = 25 where id = u;

  -- Pawn Shop off weapons, Chop Shop off vehicles
  r := buy_item(mg.id, 1);
  assert (r->>'cost')::bigint = round(mg.price * (1 - top_of('pawn_shop'))) and near((r->>'discount')::numeric, top_of('pawn_shop')), 'pawn: ' || r::text;
  r := buy_item(ct.id, 2);
  assert (r->>'cost')::bigint = round(ct.price * (1 - top_of('chop_shop'))) * 2, 'chop: ' || r::text;
  -- Repo Co: half back plus the perk, never more than it cost
  r := sell_item(ct.id, 1);
  assert (r->>'refund')::bigint = floor(ct.price * (0.5 + top_of('repo'))), 'repo: ' || r::text;
  assert (r->>'refund')::bigint <= round(ct.price * (1 - top_of('chop_shop'))), 'no buy-low sell-high loop';
  assert not exists (select 1 from item_defs d where not d.drop_only and d.rep_price = 0
                       and floor(d.price * (0.5 + top_of('repo')))
                           > round(d.price * (1 - case when d.category = 'transport' then top_of('chop_shop') else top_of('pawn_shop') end))), 'no loop anywhere';

  -- Gym off thugs, Shooting Range off mercs and enforcers
  delete from player_hoodlums where player_id = u;
  r := buy_hoodlums('thug', 100);
  assert (r->>'cost')::bigint = ceil(_hoodlum_price('thug', 0, 100) * (1 - top_of('gym'))), 'gym: ' || r::text;
  r := buy_hoodlums('enforcer', 10);
  assert (r->>'cost')::bigint = ceil(_hoodlum_price('enforcer', 0, 10) * (1 - top_of('shooting_range'))), 'range: ' || r::text;
  r := buy_hoodlums('spy', 10);
  assert (r->>'cost')::bigint = ceil(_hoodlum_price('spy', 0, 10)), 'spies full price';

  -- Bent Cop off bribes, Clinic off health
  r := bribe_police(10);
  assert (r->>'cost')::int = ceil(10 * _cfg('bribe_per_heat') * (1 - top_of('bent_cop'))), 'bent cop: ' || r::text;
  r := buy_health(10);
  assert (r->>'cost')::bigint = ceil(_health_price(0, 10) * (1 - top_of('clinic'))), 'clinic: ' || r::text;

  -- Law Office: cheaper bail (jail has no timer to shorten any more)
  update profiles set jail_until = 'infinity' where id = u;
  r := bail_out();
  assert (r->>'cost')::int = ceil(8000 * (1 - top_of('law_office'))), 'law bail: ' || r::text;
  select * into h from profiles where id = u;
  h.heat := 100;
  for i in 1..60 loop exit when h.jail_until is not null; h := _bust_roll(h); end loop;
  assert h.jail_until = 'infinity', 'busted until bail: ' || h.jail_until;

  -- Pharmacy: product refills use less
  insert into storage (player_id, commodity, qty) values (u, 'herb', 5000) on conflict (player_id, commodity) do update set qty = 5000;
  update profiles set stamina = 0 where id = u;
  r := refill('stamina', 'herb');
  assert (r->>'units')::int = ceil((select refill_stamina from commodities where code = 'herb') * (1 - top_of('pharmacy'))), 'pharmacy: ' || r::text;
  assert (select qty from storage where player_id = u and commodity = 'herb') = 5000 - (r->>'units')::int;

  -- Warehouse: more storage. Trucking Co: bigger cargo and listings
  r := get_me();
  assert (r->>'storage_cap')::int = floor((r->>'storage_base')::int * (1 + top_of('warehouse'))), 'warehouse: ' || (r->>'storage_cap');
  assert _storage_cap(u, 1000) = floor(1000 * (1 + top_of('warehouse')));
  assert (r->>'transport_capacity')::int = floor(1000 * (1 + top_of('trucking')))
     and (r->>'listing_max')::int = floor(_cfg('listing_max') * (1 + top_of('trucking'))), 'trucking: ' || (r->>'transport_capacity');
  update storage set qty = 3000 where player_id = u and commodity = 'herb';
  update profiles set storage_cap = 3000 where id = u;
  perform list_product('herb', 1500, 1);        -- over the 1000-unit truck and the 1000-unit limit, fine with Trucking Co

  -- Strip Club: hustlers carry more. Night Club: back sooner. Dispensary: over street
  r := hire_hustlers('herb', 10);
  assert (r->>'units')::int = floor(16 * 10 * (1 + top_of('strip_club'))), 'strip club: ' || r::text;
  -- (unit_price is the batch's street price, rounded to the cent in the reply)
  assert abs((r->>'cash_due')::bigint - (r->>'units')::int * (r->>'unit_price')::numeric * (1 + top_of('dispensary'))) <= (r->>'units')::int * 0.01 + 1, 'dispensary: ' || r::text;
  t := (select returns_at from hustlers where player_id = u order by returns_at desc limit 1);
  assert t between now() + make_interval(secs => _cfg('hustler_hours') * 3600 * (1 - top_of('night_club'))) - interval '5 seconds'
               and now() + make_interval(secs => _cfg('hustler_hours') * 3600 * (1 - top_of('night_club'))) + interval '5 seconds', 'night club: ' || t;

  -- Grow House: herb grows faster (and the house holds more), Utility Co on top
  insert into grow_houses (player_id, commodity, running, started_at, level) values (u, 'herb', true, now() - interval '1 hour', 1);
  r := (select e from jsonb_array_elements(get_me()->'grow_houses') e where e->>'commodity' = 'herb');
  assert near((r->>'rate')::numeric, round(20 * (1 + top_of('grow_house') + top_of('utility')), 1)), 'lab + utility: ' || r::text;
  assert (r->>'cap')::int = floor(200 * (1 + top_of('grow_house') + top_of('utility')))
     and (r->>'produced')::int = floor(20 * (1 + top_of('grow_house') + top_of('utility'))), r::text;
  r := grow_collect((select id from grow_houses where player_id = u and commodity = 'herb'));
  assert (r->>'collected')::int = floor(20 * (1 + top_of('grow_house') + top_of('utility'))), 'collect: ' || r::text;
end $$;

-- Security Firm: the defending crew's garrisons count for more -----------------------------------------------------
select as_user('f2222222-2222-2222-2222-222222222222');
do $$ declare u uuid := auth.uid(); bid int := (blocks_of('pawn_shop', 4, 1))[1]; r jsonb; base int; begin
  perform get_me();
  perform crew_create('Huell Moving', '🧳', 'Heavy lifting.');
  update profiles set cash = 1000000, stamina = 25 where id = u;
  insert into player_hoodlums (player_id, code, qty) values (u, 'thug', 500) on conflict (player_id, code) do update set qty = 500;
  delete from block_garrison where block_id = bid;
  insert into block_garrison (block_id, code, qty) values (bid, 'enforcer', 10);    -- 600 defense
  base := (select h.base_resistance from blocks b join hoods h on h.id = b.hood_id where b.id = bid);
  insert into player_hoodlums (player_id, code, qty) values (u, 'spy', 1) on conflict (player_id, code) do update set qty = 1;
  r := spy_block(bid);
  assert (r->>'resistance')::numeric = round(base + 600 * (1 + top_of('security_firm')))
     and near((r->>'security')::numeric, top_of('security_firm')), 'spy sees it: ' || r::text;
  r := attack_block(bid, 400, 0);
  assert (r->>'resistance')::numeric = round(base + 600 * (1 + top_of('security_firm'))), 'security firm: ' || r::text;
end $$;

-- Nobody in a crew: no perks, full prices ------------------------------------------------------------------------
select as_user('f3333333-3333-3333-3333-333333333333');
do $$ declare u uuid := auth.uid(); r jsonb; mg item_defs; begin
  perform get_me();
  select * into mg from item_defs where name = 'Minigun';
  update profiles set cash = 10000000 where id = u;
  assert get_me()->'perks' = '{}'::jsonb;
  r := buy_item(mg.id, 1);
  assert (r->>'cost')::bigint = mg.price, 'no crew, full price';
  assert _storage_cap(u, 500) = 500;
end $$;

-- put the map back for anything that runs after
update blocks set owner_crew_id = null where owner_crew_id in (select id from crews where name in ('Gray Matter', 'Huell Moving'));
delete from block_garrison where block_id in (select id from blocks where owner_crew_id is null);

select 'BUSINESS TEST PASSED';
