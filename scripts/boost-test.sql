-- Tests for scaling slot prices (diamonds + cash) and the 24-hour attack/defense boost.
-- Run after the other suites (reuses their helpers): scripts/local-db.sh test
\set ON_ERROR_STOP on
\set QUIET on

insert into auth.users (id, raw_user_meta_data) values
  ('c8888888-8888-8888-8888-888888888888', '{"name":"Eladio"}'),
  ('c9999999-9999-9999-9999-999999999999', '{"name":"Bolsa"}');

-- Slot prices ---------------------------------------------------------------------------------------------------
do $$ declare c record; begin
  -- the k-th slot past six: 10 + 5k diamonds and $100,000 x k²
  select * into c from _slot_cost(6);  assert c.diamonds = 15 and c.cash = 100000, '7th: ' || c::text;
  select * into c from _slot_cost(7);  assert c.diamonds = 20 and c.cash = 400000, '8th: ' || c::text;
  select * into c from _slot_cost(11); assert c.diamonds = 40 and c.cash = 3600000, '12th: ' || c::text;
  select * into c from _slot_cost(17); assert c.diamonds = 70 and c.cash = 14400000, '18th: ' || c::text;
  select * into c from _slot_cost(23); assert c.diamonds = 100 and c.cash = 32400000, '24th: ' || c::text;
  select * into c from _slot_cost(29); assert c.diamonds = 130 and c.cash = 57600000, '30th: ' || c::text;
end $$;

select as_user('c8888888-8888-8888-8888-888888888888');
do $$ declare u uuid := auth.uid(); m jsonb; r jsonb; begin
  m := get_me();
  assert (m->>'inventory_slots')::int = 6 and (m->'slot_cost'->>'diamonds')::int = 15 and (m->'slot_cost'->>'cash')::int = 100000, m->'slot_cost'::text;
  -- needs both
  update profiles set diamonds = 100, cash = 99999 where id = u;
  perform expect_error('select upgrade_stat(''slots'')', 'Costs $100000 cash on hand');
  update profiles set diamonds = 14, cash = 1000000 where id = u;
  perform expect_error('select upgrade_stat(''slots'')', 'Costs 15 diamonds');
  update profiles set diamonds = 100, cash = 1000000, bank = 5000000 where id = u;
  r := upgrade_stat('slots');
  assert (r->>'cost')::int = 15 and (r->>'cash')::int = 100000, r::text;
  assert (select diamonds from profiles where id = u) = 85 and (select cash from profiles where id = u) = 900000, 'charged both';
  -- the next one costs more; banked cash doesn't count
  r := upgrade_stat('slots');
  assert (r->>'cost')::int = 20 and (r->>'cash')::int = 400000 and (select inventory_slots from profiles where id = u) = 8;
  m := get_me();
  assert (m->'slot_cost'->>'diamonds')::int = 25 and (m->'slot_cost'->>'cash')::int = 900000;
  perform expect_error('select upgrade_stat(''slots'')', 'cash on hand');
  -- slots top out at 130
  update profiles set inventory_slots = 129, diamonds = 1000, cash = 2000000000 where id = u;
  r := upgrade_stat('slots');
  assert (r->>'cost')::int = 630 and (r->>'cash')::bigint = 1537600000 and (select inventory_slots from profiles where id = u) = 130, r::text;
  perform expect_error('select upgrade_stat(''slots'')', 'maxed at 130');
  assert (get_catalog()->'config'->>'max_slots')::int = 130;
  update profiles set inventory_slots = 8 where id = u;
  -- stamina and health are unchanged: 10 diamonds, no cash
  update profiles set cash = 0 where id = u;
  r := upgrade_stat('health');
  assert (r->>'cost')::int = 10 and (r->>'cash')::int = 0;
end $$;

-- The boost ---------------------------------------------------------------------------------------------------
do $$ declare u uuid := 'c8888888-8888-8888-8888-888888888888'; m jsonb; r jsonb; t0 timestamptz; begin
  perform reset_fighter(u);
  update profiles set diamonds = 200 where id = u;
  m := get_me();
  assert m->'boost'->>'side' is null and not (m->'boost'->>'active')::boolean and (m->'boost'->>'amount')::int = 50;
  assert (m->'power'->'offense'->>'att')::int = 20;
  perform expect_error('select buy_boost(''speed'')', 'attack or defense');
  -- boost attack: +50 in the Offense setup only
  r := buy_boost('attack');
  assert r->>'side' = 'attack' and (r->>'cost')::int = 50, r::text;
  assert (select diamonds from profiles where id = u) = 150;
  m := get_me();
  assert (m->'boost'->>'active')::boolean and m->'boost'->>'side' = 'attack';
  assert (m->'power'->'offense'->>'att')::int = 70 and (m->'power'->'offense'->>'def')::int = 20, 'offense +50 att: ' || (m->'power')::text;
  assert (m->'power'->'defense'->>'att')::int = 20 and (m->'power'->'defense'->>'def')::int = 20, 'defense untouched';
  assert (m->'power'->'jail'->>'att')::int = 20, 'jail untouched';
  -- about 24 hours
  t0 := (m->'boost'->>'until')::timestamptz;
  assert t0 between now() + interval '23 hours 59 minutes' and now() + interval '24 hours 1 minute', t0::text;
  -- the other side is locked out while it runs
  perform expect_error('select buy_boost(''defense'')', 'still running');
  -- buying again while it runs adds 24 hours; still +50, not +100
  perform buy_boost('attack');
  assert (select boost_until from profiles where id = u) = t0 + interval '24 hours', 'extended';
  assert (get_me()->'power'->'offense'->>'att')::int = 70, 'no stacking';
  -- it runs out
  update profiles set boost_until = now() - interval '1 second' where id = u;
  m := get_me();
  assert not (m->'boost'->>'active')::boolean and (m->'power'->'offense'->>'att')::int = 20, 'expired';
  -- once it runs out, either side is open again: switch to defense for a fresh 24 hours
  r := buy_boost('defense');
  assert r->>'side' = 'defense' and (select boost_until from profiles where id = u) > now() + interval '23 hours 59 minutes', r::text;
  m := get_me();
  assert (m->'power'->'defense'->>'def')::int = 70 and (m->'power'->'offense'->>'att')::int = 20, 'switched: ' || (m->'power')::text;
  perform expect_error('select buy_boost(''attack'')', 'still running');
  -- and back to attack after that one runs out
  update profiles set boost_until = now() - interval '1 second' where id = u;
  perform buy_boost('attack');
  assert (select boost_side from profiles where id = u) = 'attack';
  update profiles set diamonds = 49 where id = u;
  perform expect_error('select buy_boost(''attack'')', 'Costs 50 diamonds');
end $$;

-- A defense boost counts in the Defense setup, and in fights ------------------------------------------------------
select as_user('c9999999-9999-9999-9999-999999999999');
do $$ declare u uuid := auth.uid(); a uuid := 'c8888888-8888-8888-8888-888888888888'; m jsonb; p jsonb; before numeric; begin
  perform get_me(); perform reset_fighter(u);
  update profiles set diamonds = 50 where id = u;
  -- Eladio (attack boost, 70/20 on offense) looks at Bolsa before and after her defense boost
  perform set_config('request.jwt.claims', json_build_object('sub', a)::text, false);
  update profiles set boost_until = now() + interval '1 hour' where id = a;
  p := fight_preview(u);
  assert (p->>'my_att')::int = 70 and (p->>'their_def')::int = 20, p::text;
  before := (p->>'base_you')::numeric;
  perform set_config('request.jwt.claims', json_build_object('sub', u)::text, false);
  perform buy_boost('defense');
  m := get_me();
  assert (m->'power'->'defense'->>'def')::int = 70 and (m->'power'->'offense'->>'def')::int = 20, (m->'power')::text;
  perform expect_error('select buy_boost(''attack'')', 'still running');
  perform set_config('request.jwt.claims', json_build_object('sub', a)::text, false);
  p := fight_preview(u);
  assert (p->>'their_def')::int = 70 and (p->>'base_you')::numeric < before, 'her boost blunts his: ' || p::text;
  -- grants
  assert has_function_privilege('authenticated', 'buy_boost(text)', 'execute');
  assert not has_function_privilege('anon', 'buy_boost(text)', 'execute');
  assert not has_function_privilege('authenticated', '_slot_cost(integer)', 'execute');
end $$;

select 'BOOST TEST PASSED';
