-- Tests for scaling slot prices (diamonds + cash), the milestone ladder that pays for them, and the 24-hour boost.
-- Run after the other suites (reuses their helpers): scripts/local-db.sh test
\set ON_ERROR_STOP on
\set QUIET on

insert into auth.users (id, raw_user_meta_data) values
  ('c8888888-8888-8888-8888-888888888888', '{"name":"Eladio"}'),
  ('c9999999-9999-9999-9999-999999999999', '{"name":"Bolsa"}');

-- Slot prices ---------------------------------------------------------------------------------------------------
do $$ declare c record; begin
  -- the k-th slot past six: 1 diamond (+1 every 4 slots) and $20,000 x k
  select * into c from _slot_cost(6);   assert c.diamonds = 1 and c.cash = 20000, '7th: ' || c::text;
  select * into c from _slot_cost(7);   assert c.diamonds = 1 and c.cash = 40000, '8th: ' || c::text;
  select * into c from _slot_cost(9);   assert c.diamonds = 1 and c.cash = 80000, '10th: ' || c::text;
  select * into c from _slot_cost(10);  assert c.diamonds = 2 and c.cash = 100000, '11th: ' || c::text;
  select * into c from _slot_cost(30);  assert c.diamonds = 7 and c.cash = 500000, '31st: ' || c::text;
  select * into c from _slot_cost(99);  assert c.diamonds = 24 and c.cash = 1880000, '100th: ' || c::text;
  select * into c from _slot_cost(129); assert c.diamonds = 31 and c.cash = 2480000, '130th: ' || c::text;
  -- all 124 of them: about 💎2,000 (1,984) and $155M
  assert (select sum((_slot_cost(s)).diamonds) from generate_series(6, 129) s) = 1984;
  assert (select sum((_slot_cost(s)).cash) from generate_series(6, 129) s) = 155000000;
end $$;

select as_user('c8888888-8888-8888-8888-888888888888');
do $$ declare u uuid := auth.uid(); m jsonb; r jsonb; begin
  m := get_me();
  assert (m->>'inventory_slots')::int = 6 and (m->'slot_cost'->>'diamonds')::int = 1 and (m->'slot_cost'->>'cash')::int = 20000, m->'slot_cost'::text;
  -- needs both
  update profiles set diamonds = 100, cash = 19999 where id = u;
  perform expect_error('select upgrade_stat(''slots'')', 'Costs $20000 cash on hand');
  update profiles set diamonds = 0, cash = 1000000 where id = u;
  perform expect_error('select upgrade_stat(''slots'')', 'Costs 1 diamond');
  update profiles set diamonds = 100, cash = 1000000, bank = 5000000 where id = u;
  r := upgrade_stat('slots');
  assert (r->>'cost')::int = 1 and (r->>'cash')::int = 20000, r::text;
  assert (select diamonds from profiles where id = u) = 99 and (select cash from profiles where id = u) = 980000, 'charged both';
  -- the next one costs more; banked cash doesn't count
  r := upgrade_stat('slots');
  assert (r->>'cost')::int = 1 and (r->>'cash')::int = 40000 and (select inventory_slots from profiles where id = u) = 8;
  m := get_me();
  assert (m->'slot_cost'->>'diamonds')::int = 1 and (m->'slot_cost'->>'cash')::int = 60000;
  update profiles set cash = 59999 where id = u;
  perform expect_error('select upgrade_stat(''slots'')', 'cash on hand');
  -- slots top out at 130
  update profiles set inventory_slots = 129, diamonds = 1000, cash = 2000000000 where id = u;
  r := upgrade_stat('slots');
  assert (r->>'cost')::int = 31 and (r->>'cash')::bigint = 2480000 and (select inventory_slots from profiles where id = u) = 130, r::text;
  perform expect_error('select upgrade_stat(''slots'')', 'maxed at 130');
  assert (get_catalog()->'config'->>'max_slots')::int = 130;
  update profiles set inventory_slots = 8 where id = u;
  -- stamina and health are unchanged: 10 diamonds, no cash
  update profiles set cash = 0 where id = u;
  r := upgrade_stat('health');
  assert (r->>'cost')::int = 10 and (r->>'cash')::int = 0;
end $$;

-- Milestones: a longer ladder, paid once each, and caught up for players already past a step ------------------------
do $$ declare u uuid := 'c9999999-9999-9999-9999-999999999999'; d0 int; begin
  perform as_user(u::text);
  perform get_me();
  delete from milestones where player_id = u;
  update profiles set actions_done = 20000, fights_won = 5000, diamonds = 0 where id = u;
  perform _award_milestones(u);
  -- every action step up to 20,000 (💎580) and every win step up to 5,000 (💎280)
  assert (select diamonds from profiles where id = u) = 580 + 280, 'ladder: ' || (select diamonds from profiles where id = u);
  assert (select count(*) from milestones where player_id = u) = 10 + 7;
  perform _award_milestones(u);
  assert (select diamonds from profiles where id = u) = 860, 'paid once';
  update profiles set actions_done = 100000 where id = u;
  perform _award_milestones(u);
  assert (select diamonds from profiles where id = u) = 860 + 150 + 200 + 250, 'the rest of the action ladder';
  -- the page gets the ladder
  assert jsonb_array_length(get_catalog()->'milestones') = 22;
  assert (select count(*) from milestone_defs) = 22 and not has_function_privilege('authenticated', '_award_milestones(uuid)', 'execute');
  perform as_user('c8888888-8888-8888-8888-888888888888');
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

-- Heat upgrades: 💎30 for +50 max heat, the yellow and red lines move up with it, flat price, no cap ----------------
do $$ declare u uuid := 'c8888888-8888-8888-8888-888888888888'; m jsonb; r jsonb; t uuid; i int; h profiles; begin
  perform set_config('request.jwt.claims', json_build_object('sub', u)::text, false);
  perform reset_fighter(u);
  update profiles set diamonds = 29, heat = 0, heat_max = 100 where id = u;
  m := get_me();
  assert (m->>'heat_yellow')::int = 40 and (m->>'heat_red')::int = 75, 'base lines: ' || (m->>'heat_red');
  perform expect_error('select upgrade_stat(''heat'')', 'Costs 30 diamonds');
  update profiles set diamonds = 100 where id = u;
  r := upgrade_stat('heat');
  assert (r->>'cost')::int = 30 and (r->>'cash')::int = 0, r::text;
  assert (select heat_max from profiles where id = u) = 150 and (select diamonds from profiles where id = u) = 70;
  m := get_me();
  assert (m->>'heat_max')::int = 150 and (m->>'heat_yellow')::int = 90 and (m->>'heat_red')::int = 125, 'lines moved: ' || m::text;
  -- 100 heat used to be red; now it's yellow, for you and for anyone looking at you
  update profiles set heat = 100 where id = u;
  assert get_me()->>'heat_level' = 'yellow' and get_player(u)->>'heat_level' = 'yellow';
  -- no bust below the new red line ...
  select * into h from profiles where id = u;
  h.heat := 124;
  for i in 1..300 loop h := _bust_roll(h); end loop;
  assert h.jail_until is null, 'no bust under 125';
  -- ... and above it a bust drops you to your yellow line
  h.heat := 150;
  for i in 1..300 loop exit when h.jail_until is not null; h := _bust_roll(h); end loop;
  assert h.jail_until is not null and h.heat = 90, 'bust at 150 → 90: ' || h.heat;
  -- the fight preview's bust warning uses the moved line (an attack adds 4 heat)
  t := (select id from profiles where is_bot order by bot_level limit 1);
  update profiles set health = health_max, in_hospital = false, jail_until = null where id = t;
  update profiles set heat = 120, last_tick = now() where id = u;
  assert (fight_preview(t)->>'bust_pct')::int = 0, 'under the line';
  update profiles set heat = 121, last_tick = now() where id = u;
  assert (fight_preview(t)->>'bust_pct')::int = 3, 'one over: 1/40';
  -- the same 30 every time, and no cap
  r := upgrade_stat('heat');
  assert (r->>'cost')::int = 30 and (select heat_max from profiles where id = u) = 200;
  update profiles set heat_max = 10000, diamonds = 30 where id = u;
  r := upgrade_stat('heat');
  assert (select heat_max from profiles where id = u) = 10050 and (get_me()->>'heat_red')::int = 75 + 9950;
  assert (get_catalog()->'config'->>'heat_upgrade_diamonds')::int = 30 and (get_catalog()->'config'->>'heat_upgrade_amount')::int = 50;
  assert not has_function_privilege('authenticated', '_heat_red(profiles)', 'execute');
  update profiles set heat = 0, heat_max = 100 where id = u;
end $$;

-- Going to jail for diamonds: 💎50, no stamina or cash, not an action — and you're in until you post bail -----------
do $$ declare u uuid := 'c9999999-9999-9999-9999-999999999999'; r jsonb; n int; begin
  perform set_config('request.jwt.claims', json_build_object('sub', u)::text, false);
  perform reset_fighter(u);
  update profiles set diamonds = 49 where id = u;
  perform expect_error('select go_to_jail()', 'Costs 50 diamonds');
  update profiles set diamonds = 60, stamina = 0, cash = 0 where id = u;
  select actions_done into n from profiles where id = u;
  r := go_to_jail();
  assert (r->>'cost')::int = 50 and (r->>'bail')::int = 8000 and (select diamonds from profiles where id = u) = 10, r::text;
  assert (get_me()->>'jailed')::boolean and get_me()->>'jail_until' is null, 'inside, no end time';
  assert (select jail_until from profiles where id = u) = 'infinity';
  assert (select actions_done from profiles where id = u) = n, 'not an action';
  perform expect_error('select go_to_jail()', 'already in jail');
  -- time doesn't let you out; bail does: $8,000 flat, cash on hand
  update profiles set last_tick = now() - interval '3 days', stamina_tick = now() - interval '3 days', health_tick = now() - interval '3 days' where id = u;
  assert (get_me()->>'jailed')::boolean, 'still inside days later';
  update profiles set cash = 7999 where id = u;
  perform expect_error('select bail_out()', 'Bail costs $8000');
  update profiles set cash = 10000 where id = u;
  r := bail_out();
  assert (r->>'cost')::int = 8000 and (select cash from profiles where id = u) = 2000 and not (get_me()->>'jailed')::boolean, r::text;
  -- the Bribe Police job and a bust from red heat are open-ended too
  update profiles set stamina = 25, cash = 5000 where id = u;
  perform do_action((select id from action_defs where effect = 'go_to_jail'));
  assert (select jail_until from profiles where id = u) = 'infinity', 'bribe job: until bail';
  update profiles set jail_until = null where id = u;
  -- not from a hospital bed
  update profiles set jail_until = null, health = 5, in_hospital = true, health_tick = now(), diamonds = 60 where id = u;
  perform expect_error('select go_to_jail()', 'in the hospital');
  assert (get_catalog()->'config'->>'jail_diamonds')::int = 50;
  assert has_function_privilege('authenticated', 'go_to_jail()', 'execute') and not has_function_privilege('anon', 'go_to_jail()', 'execute');
  perform reset_fighter(u);
end $$;

select 'BOOST TEST PASSED';
