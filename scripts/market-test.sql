-- Tests for the market overhaul: refills (per drug since 0016), paths you can pick any time (and must past grow level 5),
-- Trader terms, street price that answers to hustler dumping, the 150% listing cap, the 5% seller fee and buy orders.
-- Run after the other suites (reuses their helpers): scripts/local-db.sh test
\set ON_ERROR_STOP on
\set QUIET on

insert into auth.users (id, raw_user_meta_data) values
  ('aa111111-1111-1111-1111-111111111111', '{"name":"Lalo"}'),
  ('aa222222-2222-2222-2222-222222222222', '{"name":"Nacho"}'),
  ('aa333333-3333-3333-3333-333333333333', '{"name":"Kim"}');

-- give a player plenty of a product (storage cap aside) and a truck
create or replace function stock(u uuid, com text, n int) returns void language sql as $$
  insert into storage as st (player_id, commodity, qty) values (u, com, n)
    on conflict (player_id, commodity) do update set qty = n $$;

-- Refills (20261004000016_drug_refills): drugs refill stamina only; each drug is full 3 times a game day (5 on the
-- Daily Drop), then restores half the stamina bar. (Until that migration product refills halved again each time.)
select as_user('aa111111-1111-1111-1111-111111111111');
do $$ declare u uuid := auth.uid(); r jsonb; gains int[] := '{}'; i int; m jsonb; begin
  perform get_me();
  update profiles set stamina_max = 150, diamonds = 100, drop_since = null, drop_until = null where id = u;
  perform stock(u, 'herb', 100000); perform stock(u, 'dust', 100000); perform stock(u, 'pills', 100000);
  m := get_me()->'refills';
  assert (m->>'full')::int = 3 and m->'used' = '{}'::jsonb and (m->>'late_share')::numeric = 0.5, 'get_me refills: ' || m::text;
  for i in 1..5 loop
    update profiles set stamina = 0, stamina_tick = now() where id = u;
    r := refill('stamina', 'herb');
    gains := gains || (r->>'gain')::int;
  end loop;
  assert gains = '{150,150,150,75,75}', 'three full, then half the bar: ' || gains::text;
  assert (r->>'full_left')::int = 0 and (r->>'full')::int = 3, 'none left: ' || r::text;
  assert (get_me()->'refills'->'used'->>'herb')::int = 5, 'counted per drug';
  -- half the bar never overfills
  update profiles set stamina = 120, stamina_tick = now() where id = u;
  assert (refill('stamina', 'herb')->>'gain')::int = 30, 'half the bar, up to full';
  -- dust has its own three
  update profiles set stamina = 0, stamina_tick = now() where id = u;
  r := refill('stamina', 'dust');
  assert (r->>'gain')::int = 150 and (r->>'full_left')::int = 2, 'dust is still full: ' || r::text;
  -- drugs don't heal
  update profiles set health = 0, health_max = 100 where id = u;
  perform expect_error('select refill(''health'', ''herb'')', 'Drugs refill stamina');
  assert (refill('health', 'diamonds')->>'gain')::int = 100, 'diamonds still heal';
  -- diamonds are always full and don't count against a drug
  update profiles set stamina = 0, stamina_tick = now() where id = u;
  r := refill('stamina', 'diamonds');
  assert (r->>'gain')::int = 150 and (get_me()->'refills'->'used'->>'herb')::int = 6, 'diamonds: ' || r::text;
  -- Daily Drop subscribers: 5 full of each
  update profiles set drop_since = now() - interval '1 day', drop_until = null where id = u;
  assert (get_me()->'refills'->>'full')::int = 5;
  gains := '{}';
  for i in 1..6 loop
    update profiles set stamina = 0, stamina_tick = now() where id = u;
    gains := gains || (refill('stamina', 'pills')->>'gain')::int;
  end loop;
  assert gains = '{150,150,150,150,150,75}', 'five full on the Daily Drop: ' || gains::text;
  -- a lapsed subscription is back to three: pills has used 6, so half
  update profiles set drop_until = now() - interval '1 minute', stamina = 0, stamina_tick = now() where id = u;
  assert (refill('stamina', 'pills')->>'gain')::int = 75, 'lapsed: back to three';
  -- the 00:00 UTC rollover: yesterday's counts don't count
  update profiles set drug_refills = jsonb_set(drug_refills, '{day}', to_jsonb((_game_day() - 1)::text)), stamina = 0, stamina_tick = now() where id = u;
  assert get_me()->'refills'->'used' = '{}'::jsonb, 'a new day starts at zero';
  r := refill('stamina', 'herb');
  assert (r->>'gain')::int = 150 and (r->>'full_left')::int = 2, 'full again after the rollover: ' || r::text;
  update profiles set drop_since = null, drop_until = null where id = u;
end $$;

-- Paths: pick any time -----------------------------------------------------------------------------------------
do $$ declare u uuid := auth.uid(); r jsonb; begin
  assert (select rep_earned from profiles where id = u) = 0;
  r := choose_path('trader');
  assert r->>'path' = 'trader' and (r->>'diamonds')::int = 0, 'no reputation needed: ' || r::text;
end $$;

-- Hustlers: Traders pay a cut, not a fee, and sell over street; unpathed players pay the fee ---------------------
do $$ declare u uuid := auth.uid(); r jsonb; street int; begin
  update profiles set cash = 0, free_hustlers = 0 where id = u;
  update street_prices set pressure = 0, pressure_at = now();
  perform stock(u, 'pills', 1000);
  r := hire_hustlers('pills', 10);                       -- 40 pills, no cash needed
  assert (r->>'cost')::int = 0 and (r->>'units')::int = 40, 'no fee: ' || r::text;
  assert abs((r->>'cash_due')::bigint - 40 * (r->>'unit_price')::numeric * 1.10 * 0.90) <= 2, 'street +10%, less 10%: ' || r::text;
  assert abs((r->>'cut')::numeric - 40 * (r->>'unit_price')::numeric * 1.10 * 0.10) <= 1, 'the cut: ' || r::text;
end $$;
select as_user('aa222222-2222-2222-2222-222222222222');
do $$ declare u uuid := auth.uid(); r jsonb; begin
  perform get_me();
  update profiles set cash = 10000 where id = u;
  perform stock(u, 'pills', 1000);
  r := hire_hustlers('pills', 10);
  assert (r->>'cost')::int = 4000 and abs((r->>'cash_due')::bigint - 40 * (r->>'unit_price')::numeric) <= 2, 'no path: fee, plain street: ' || r::text;
end $$;

-- Street price: dumping pushes it down, a batch sells at its own midpoint, and it recovers ------------------------
do $$ declare u uuid := auth.uid(); r jsonb; w numeric; before int; after int; p numeric; base int := 60; i int; begin
  update street_prices set pressure = 0, pressure_at = now(), wiggle = 0, wiggle_at = now(), updated_at = now(), price = base where commodity = 'herb';
  perform stock(u, 'herb', 200000);
  update profiles set cash = 10000000 where id = u;
  -- 100 hustlers carry 1,600 herb: 1600/50000 = 3.2% push, sold at the 1.6% midpoint
  r := hire_hustlers('herb', 100);
  assert (r->>'unit_price')::numeric = round(base * (1 - 0.016), 2), 'midpoint: ' || r::text;
  assert (select pressure from street_prices where commodity = 'herb') = 0.032;
  assert (r->>'street')::int = round(base * (1 - 0.032)) and (select price from street_prices where commodity = 'herb') = round(base * (1 - 0.032));
  -- the push fades by half every 4 hours
  update street_prices set pressure_at = now() - interval '4 hours', updated_at = now() - interval '2 minutes' where commodity = 'herb';
  perform _refresh_prices();
  select pressure into p from street_prices where commodity = 'herb';
  assert abs(p - 0.016) < 0.0001, 'half after 4h: ' || p;
  -- a flood: the price bottoms out at 60% off, and the stored push is capped so it clears in hours, not days
  update street_prices set pressure = 0, pressure_at = now(), wiggle = 0 where commodity = 'herb';
  for i in 1..40 loop perform hire_hustlers('herb', 100); end loop;      -- 64,000 herb
  assert (select price from street_prices where commodity = 'herb') = round(base * 0.4), 'floor at 40%';
  assert (select pressure from street_prices where commodity = 'herb') = 1.28;
  for i in 1..40 loop perform hire_hustlers('herb', 100); end loop;
  assert (select pressure from street_prices where commodity = 'herb') = 1.5, 'stored push capped at 1.5';
  -- the UI gets the same numbers (pressure as the discount actually applied)
  r := get_me()->'street'->'herb';
  assert (r->>'price')::int = 24 and (r->>'pressure')::numeric = 0.6 and (r->>'depth')::int = 50000 and (r->>'base')::int = 60, r::text;
  update street_prices set pressure = 0, pressure_at = now();
  -- the wiggle walks but stays within ±15%
  for i in 1..400 loop
    update street_prices set wiggle_at = now() - interval '11 minutes', updated_at = now() - interval '2 minutes';
    perform _refresh_prices();
    assert (select bool_and(abs(wiggle) <= 0.15) from street_prices), 'wiggle in band';
  end loop;
  assert (select bool_and(price between round(c.base_price * 0.85) and round(c.base_price * 1.15)) from street_prices sp join commodities c on c.code = sp.commodity);
  update street_prices sp set pressure = 0, wiggle = 0, price = c.base_price from commodities c where c.code = sp.commodity;
end $$;

-- Listings: up to 150% of street, and the seller pays 5% --------------------------------------------------------
select as_user('aa333333-3333-3333-3333-333333333333');
do $$ declare u uuid := auth.uid(); begin
  perform get_me();
  update profiles set cash = 5000000, storage_cap = 100000 where id = u;
  perform buy_item((select id from item_defs where name = 'Cargo Truck'), 1);
  perform stock(u, 'dust', 5000);
  perform expect_error('select list_product(''dust'', 100, 301)', 'you can list up to $300');
  perform set_config('test.listing', list_product('dust', 100, 300)->>'id', false);
end $$;
select as_user('aa222222-2222-2222-2222-222222222222');
do $$ declare u uuid := auth.uid(); s uuid := 'aa333333-3333-3333-3333-333333333333'; c0 bigint; r jsonb; begin
  update profiles set cash = 1000000, storage_cap = 100000 where id = u;
  select cash into c0 from profiles where id = s;
  r := buy_listing(current_setting('test.listing')::uuid, 100);
  assert (r->>'cost')::int = 30000 and (select cash from profiles where id = u) = 1000000 - 30000;
  assert (select cash from profiles where id = s) = c0 + 28500, 'seller keeps 95%';
  assert exists (select 1 from market_trades where buyer_id = u and seller_id = s and units = 100 and unit_price = 300 and via = 'listing');
end $$;

-- Buy orders ---------------------------------------------------------------------------------------------------
-- Nacho (d2) wants dust; Kim (d3) sells into it.
do $$ declare u uuid := auth.uid(); r jsonb; o uuid; i int; begin
  update profiles set cash = 1000000 where id = u;
  perform expect_error('select post_order(''dust'', 10, 100)', 'Order between 25 and 10000');
  perform expect_error('select post_order(''dust'', 100, 301)', 'you can offer up to $300');
  perform expect_error('select post_order(''dust'', 10000, 200)', 'holds $2000000 of your cash');
  r := post_order('dust', 2000, 170);
  assert (r->>'held')::int = 340000 and (select cash from profiles where id = u) = 1000000 - 340000, 'cash held: ' || r::text;
  perform set_config('test.order', r->>'id', false);
  assert jsonb_array_length(get_me()->'orders') = 1;
  perform expect_error(format('select fill_order(%L, 10)', r->>'id'), 'your own order');
  -- five open at most
  for i in 1..4 loop perform post_order('herb', 25, 10); end loop;
  perform expect_error('select post_order(''herb'', 25, 10)', '5 open buy orders');
  for o in select id from buy_orders where buyer_id = u and commodity = 'herb' loop perform cancel_order(o); end loop;
  assert (select cash from profiles where id = u) = 1000000 - 340000, 'cancels hand the cash back';
  -- the book: best offer first
  r := get_market('dust');
  assert jsonb_array_length(r->'orders') = 1 and (r->'orders'->0->>'unit_price')::int = 170 and r->'orders'->0->>'buyer' = 'Nacho', r->'orders'::text;
end $$;

select as_user('aa333333-3333-3333-3333-333333333333');
do $$ declare u uuid := auth.uid(); b uuid := 'aa222222-2222-2222-2222-222222222222'; o uuid := current_setting('test.order')::uuid;
            r jsonb; c0 bigint; bs0 int; f jsonb; begin
  select cash into c0 from profiles where id = u;
  select qty into bs0 from storage where player_id = b and commodity = 'dust';
  -- the buyer's storage is full: it lands anyway
  update profiles set storage_cap = 10 where id = b;
  r := fill_order(o, 600);
  assert (r->>'units')::int = 600 and (r->>'cash')::int = 96900 and (r->>'fee')::int = 5100 and (r->>'left')::int = 1400, 'fill: ' || r::text;
  assert (select cash from profiles where id = u) = c0 + 96900, 'seller paid, less 5%';
  assert (select qty from storage where player_id = b and commodity = 'dust') = bs0 + 600, 'past the cap';
  assert (select qty from buy_orders where id = o) = 1400 and (select filled from buy_orders where id = o) = 600;
  perform fill_order(o, 400);
  -- one line on the buyer's feed per seller and product
  perform as_user(b::text);
  f := get_activity();
  assert f->0->>'kind' = 'filled' and f->0->>'actor' = 'Kim' and (f->0->'data'->>'units')::int = 1000 and (f->0->'data'->>'cash')::int = 170000, f::text;
  perform as_user(u::text);
  -- vehicle and stock rules
  perform expect_error(format('select fill_order(%L, 1001)', o), 'Invalid quantity');
  update storage set qty = 50 where player_id = u and commodity = 'dust';
  perform expect_error(format('select fill_order(%L, 60)', o), 'You only have 50 Dust');
  update inventory set qty = 0 where player_id = u and item_id = (select id from item_defs where name = 'Cargo Truck');
  perform expect_error(format('select fill_order(%L, 10)', o), 'Your transport carries 0 units');
  update inventory set qty = 1 where player_id = u and item_id = (select id from item_defs where name = 'Cargo Truck');
  -- the trade log feeds the stats
  r := get_market()->'stats'->'dust';
  assert (r->>'last')::int = 170 and (r->>'units_24h')::int = 1100 and (r->>'avg_24h')::int = round((100 * 300 + 1000 * 170) / 1100.0), r::text;
end $$;

select as_user('aa222222-2222-2222-2222-222222222222');
do $$ declare u uuid := auth.uid(); o uuid := current_setting('test.order')::uuid; c0 bigint; r jsonb; begin
  select cash into c0 from profiles where id = u;
  r := cancel_order(o);
  assert (r->>'returned')::int = 1000 * 170 and (r->>'filled')::int = 1000, 'what was left comes back: ' || r::text;
  assert (select cash from profiles where id = u) = c0 + 170000;
  perform expect_error(format('select cancel_order(%L)', o), 'No such order');
  -- an order that runs out its 48 hours hands the cash back on the next world tick
  r := post_order('pills', 100, 500);
  select cash into c0 from profiles where id = u;
  update buy_orders set expires_at = now() - interval '1 second' where id = (r->>'id')::uuid;
  perform get_me();
  assert (select status from buy_orders where id = (r->>'id')::uuid) = 'expired' and (select cash from profiles where id = u) = c0 + 50000, 'expired';
end $$;
select as_user('aa333333-3333-3333-3333-333333333333');
do $$ begin
  perform expect_error(format('select fill_order(%L, 10)', current_setting('test.order')), 'That order is gone');
end $$;

-- Helpers stay private; the new calls are open to players ----------------------------------------------------------
do $$ declare f text; begin
  foreach f in array array['_refill_share(integer)', '_path_due(profiles)', '_decay(numeric,timestamp with time zone)', '_street(integer,numeric,numeric)',
                           '_street_json()', '_after_fee(bigint)', '_price_cap(integer)', '_haul(uuid)', '_refresh_prices()', '_tick_world()'] loop
    assert not has_function_privilege('authenticated', f, 'execute'), f || ' should be private';
  end loop;
  foreach f in array array['post_order(text,integer,integer)', 'cancel_order(uuid)', 'fill_order(uuid,integer)', 'get_market(text)'] loop
    assert has_function_privilege('authenticated', f, 'execute') and not has_function_privilege('anon', f, 'execute'), f;
  end loop;
end $$;

drop function stock(uuid, text, int);
select 'MARKET TEST PASSED';
