-- End-to-end smoke test against the local stack. Run: scripts/local-db.sh test
\set ON_ERROR_STOP on
\set QUIET on

-- two players sign up
insert into auth.users (id, raw_user_meta_data) values
  ('11111111-1111-1111-1111-111111111111', '{"name":"Escobar"}'),
  ('22222222-2222-2222-2222-222222222222', '{"name":"Lalo"}');

create or replace function as_user(u text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', u)::text, false) $$;
create or replace function expect_error(sql text, needle text) returns void language plpgsql as $$
begin
  execute sql; raise exception 'expected error containing "%" from: %', needle, sql;
exception when others then
  if sqlerrm not like '%' || needle || '%' then raise exception 'wrong error: % (wanted "%")', sqlerrm, needle; end if;
end $$;

select as_user('11111111-1111-1111-1111-111111111111');

do $$ declare me jsonb; r jsonb; begin
  me := get_me();
  assert me->>'name' = 'Escobar', 'trigger created profile';
  assert (me->>'cash')::int = 10000, 'starter cash';
  assert (me->>'stamina')::int = 25;
  assert me->'power'->'offense'->>'att' = '20', 'barehands';

  -- actions
  r := do_action((select id from action_defs where sort = 1));
  assert (r->>'pay')::int between 140 and 220, 'action pay';
  perform expect_error('select do_action((select id from action_defs where sort = 4))', 'Requires Brass Knuckles');
  perform expect_error('select do_action((select id from action_defs where sort = 30))', 'only be done in jail');
  perform expect_error('select do_action((select id from action_defs where sort = 12))', 'crew of at least 2');

  -- items & setups
  perform buy_item((select id from item_defs where name = 'Brass Knuckles'), 2);
  perform buy_item((select id from item_defs where name = 'Leather Jacket'), 1);
  perform buy_item((select id from item_defs where name = 'Shank'), 1);
  perform buy_item((select id from item_defs where name = 'Motorcycle'), 1);
  perform equip('offense', (select id from item_defs where name = 'Brass Knuckles'), 2);
  perform equip('offense', (select id from item_defs where name = 'Leather Jacket'), 1);
  perform equip('offense', (select id from item_defs where name = 'Motorcycle'), 1);
  perform equip('defense', (select id from item_defs where name = 'Leather Jacket'), 1);
  perform expect_error($x$select equip('jail', (select id from item_defs where name = 'Brass Knuckles'), 1)$x$, 'confiscated');
  perform expect_error($x$select equip('offense', (select id from item_defs where name = 'Shank'), 1)$x$, 'jail setup');
  perform equip('jail', (select id from item_defs where name = 'Shank'), 1);
  perform expect_error($x$select equip('offense', (select id from item_defs where name = 'Brass Knuckles'), 3)$x$, 'do not own');
  me := get_me();
  assert me->'power'->'offense'->>'att' = '30', 'att = 20 + 4*2 + 2 (moto): ' || (me->'power'->'offense');
  assert me->'power'->'offense'->>'def' = '27', 'def = 20 + 5 + 2';
  assert (me->'power'->'offense'->>'combo')::boolean, 'melee combo';
  r := do_action((select id from action_defs where sort = 4));  -- now has knuckles
  perform expect_error($x$select sell_item((select id from item_defs where name = 'Brass Knuckles'), 1)$x$, 'unequipped');

  -- economy
  perform expect_error('select grow_build(''pills'')', 'Costs');
  update profiles set cash = cash + 500000 where id = auth.uid();
  perform grow_build('herb');
  me := get_me();
  assert jsonb_array_length(me->'grow_houses') = 1 and (me->'grow_houses'->0->>'running')::boolean;
  update grow_houses set started_at = now() - interval '3 hours' where player_id = auth.uid();
  me := get_me();
  assert (me->'grow_houses'->0->>'produced')::int = 60, 'produced 3h*20 = ' || (me->'grow_houses'->0->>'produced');
  r := grow_collect((me->'grow_houses'->0->>'id')::uuid);
  assert (r->>'collected')::int = 60;
  me := get_me();
  assert (me->'storage'->>'herb')::int = 60;
end $$;

-- the dust house needs $15,000 and 20 diamonds; we have both now
do $$ declare me jsonb; r jsonb; h uuid; begin
  perform grow_build('dust');
  me := get_me();
  assert (me->>'diamonds')::int = 5, 'diamonds spent on second grow house';
  h := (select id from grow_houses where player_id = auth.uid() and commodity = 'herb');
  perform grow_toggle(h); perform grow_toggle(h);
  r := grow_upgrade(h);
  assert (r->>'level')::int = 2;

  -- hustlers
  update storage set qty = 200 where player_id = auth.uid() and commodity = 'herb';
  r := hire_hustlers('herb', 2);
  assert (r->>'units')::int = 32;
  perform expect_error('select collect_hustlers()', 'back yet');
  update hustlers set returns_at = now() - interval '1 minute' where player_id = auth.uid();
  r := collect_hustlers();
  assert (r->>'cash')::int = 32 * (select price from street_prices where commodity = 'herb'), 'hustler cash';

  -- marketplace
  perform expect_error('select list_product(''herb'', 100, 10)', 'transport carries 25');
  perform buy_item((select id from item_defs where name = 'Sedan'), 1);
  perform expect_error('select list_product(''herb'', 100, 99999)', 'cannot list above');
  r := list_product('herb', 100, 40);
  me := get_me();
  assert (me->'storage'->>'herb')::int = 68, 'storage after listing: ' || (me->'storage'->>'herb');
  assert jsonb_array_length(me->'listings') = 1;
  perform expect_error(format('select buy_listing(%L, 10)', r->>'id'), 'your own');

  -- bank
  perform bank_deposit(1000);
  perform expect_error('select bank_withdraw(5000)', 'Invalid');
  perform bank_withdraw(500);
  me := get_me(); assert (me->>'bank')::int = 500;

  -- hospital / police / jail
  update profiles set health = 10 where id = auth.uid();
  perform expect_error('select do_action((select id from action_defs where sort = 1))', 'hospital');
  r := hospital_checkout(); assert (r->>'cost')::int = 400;
  update profiles set heat = 60 where id = auth.uid();
  r := bribe_police(20); assert (r->>'cost')::int = 800 and (r->>'heat')::int = 40;
  r := do_action((select id from action_defs where sort = 25)); -- bribe police to get in jail
  assert (r->>'busted')::boolean;
  me := get_me(); assert (me->>'jailed')::boolean;
  perform expect_error('select do_action((select id from action_defs where sort = 1))', 'in jail');
  r := do_action((select id from action_defs where sort = 30));
  assert (r->>'pay')::int between 100 and 200, 'jail action pays';
  r := bail_out(); assert (r->>'cost')::int > 2000;
  me := get_me(); assert not (me->>'jailed')::boolean;

  -- heat bust roll: force red heat and hammer actions until busted
  update profiles set heat = 100, stamina = 150, stamina_max = 150 where id = auth.uid();
  for i in 1..60 loop
    r := do_action((select id from action_defs where sort = 1));
    exit when (r->>'busted')::boolean;
  end loop;
  assert (r->>'busted')::boolean, 'got busted at red heat';
  update profiles set jail_until = null, heat = 0 where id = auth.uid();

  -- refills
  update profiles set stamina = 0 where id = auth.uid();
  update storage set qty = 1000 where player_id = auth.uid() and commodity = 'herb';
  r := refill('stamina', 'herb'); assert (r->>'gain')::int = 150;
  update profiles set stamina = 0 where id = auth.uid();
  perform expect_error('select refill(''stamina'', ''diamonds'')', 'Not enough diamonds');
  update profiles set diamonds = 100 where id = auth.uid();
  r := refill('stamina', 'diamonds');
  perform expect_error('select refill(''stamina'', ''diamonds'')', 'Already full');
  perform upgrade_stat('health'); perform upgrade_stat('slots');
  me := get_me(); assert (me->>'health_max')::int = 125 and (me->>'inventory_slots')::int = 7;

  -- regen: back-date the tick
  update profiles set stamina = 0, health = 50, heat = 30, last_tick = now() - interval '55 minutes' where id = auth.uid();
  me := get_me();
  assert (me->>'stamina')::int = 10, 'stamina regen 5 ticks * 2: ' || (me->>'stamina');
  assert (me->>'health')::int = 60 and (me->>'heat')::int = 25, 'health/heat regen';
end $$;

-- second player, crews, fights
select as_user('22222222-2222-2222-2222-222222222222');
do $$ declare me jsonb; r jsonb; crew uuid; begin
  me := get_me(); assert me->>'name' = 'Lalo';
  perform expect_error('select attack(''11111111-1111-1111-1111-111111111111'')', 'immunity');
  update profiles set immune_until = now() where id <> auth.uid();
  update profiles set cash = 50000, health = 100 where id = auth.uid();
  r := attack('11111111-1111-1111-1111-111111111111');
  assert r ? 'won' and (r->>'damage_dealt')::int between 0 and 80, 'fight result ' || r::text;
  assert jsonb_array_length(get_fights()) = 1;
  perform expect_error('select attack(auth.uid())', 'yourself');

  r := crew_create('Los Pollos', '🐔', 'Chicken and more.');
  crew := (r->>'id')::uuid;
  perform expect_error('select crew_create(''Again'')', 'Leave your crew');
  me := get_me(); assert (me->'crew'->>'is_capo')::boolean;
  perform crew_bank(1000);
  perform expect_error('select crew_bank(-5000)', 'Not enough in the crew bank');
  perform crew_bank(-500);
  assert (get_crew(crew)->>'bank')::int = 500;
  r := cartel_create('Juárez');
  assert (get_cartel((r->>'id')::uuid)->>'is_don')::boolean;
  perform cartel_bank(100);
  perform send_message('global', 'hola'); perform send_message('crew:' || crew, 'crew only');
  perform expect_error('select send_message(''crew:00000000-0000-0000-0000-000000000000'', ''x'')', 'cannot post');
  assert jsonb_array_length(get_messages('global')) = 1;
  perform send_message(dm_channel('11111111-1111-1111-1111-111111111111'), 'psst');
  assert jsonb_array_length(get_conversations()) = 1;
end $$;

-- player 1 applies to crew, gets accepted, then territory
select as_user('11111111-1111-1111-1111-111111111111');
do $$ declare crew uuid; begin
  crew := (select id from crews where name = 'Los Pollos');
  perform crew_apply(crew);
  assert (get_crew(crew)->>'applied')::boolean;
  assert jsonb_array_length(get_conversations()) = 1, 'dm visible to both';
  assert jsonb_array_length(get_messages(dm_channel('22222222-2222-2222-2222-222222222222'))) = 1;
end $$;
select as_user('22222222-2222-2222-2222-222222222222');
do $$ declare r jsonb; t jsonb; b int; hid int; begin
  perform crew_decide('11111111-1111-1111-1111-111111111111', true);
  assert (select crew_id from profiles where name = 'Escobar') is not null;
  assert jsonb_array_length(get_crew((select id from crews where name = 'Los Pollos'))->'members') = 2;

  update profiles set cash = 5000000 where id = auth.uid();
  r := buy_hoodlums('thug', 100);
  assert (r->>'cost')::bigint between 100000 and 110000, 'thug price scales: ' || (r->>'cost');
  perform buy_hoodlums('spy', 2); perform buy_hoodlums('enforcer', 5); perform buy_hoodlums('mercenary', 10);
  t := get_territory();
  assert jsonb_array_length(t) = 4, 'four islands';
  b := (t->0->'hoods'->0->'blocks'->0->>'id')::int;   -- cheapest hood, resistance 200
  hid := (t->0->'hoods'->0->>'id')::int;
  r := attack_block(b, 10, 0);       -- 100 attack vs 200: fails
  assert not (r->>'success')::boolean, 'weak attack fails';
  r := attack_block(b, 30, 5);       -- 300+300 attack vs 200: wins
  assert (r->>'success')::boolean, 'attack wins: ' || r::text;
  assert (r->>'claim_paid')::int = 4000;
  perform station_hoodlums(b, 'enforcer', 5);
  r := spy_block(b); assert (r->>'resistance')::int = 500, 'garrison def counts: ' || r::text;
  perform expect_error(format('select attack_block(%s, 1, 0)', b), 'already holds');
  -- take the rest of the hood → hood owner
  for i in 1..3 loop
    r := attack_block((t->0->'hoods'->0->'blocks'->i->>'id')::int, 30, 5);
    assert (r->>'success')::boolean;
  end loop;
  assert (select owner_crew_id from hoods where id = hid) = (select id from crews where name = 'Los Pollos'), 'hood captured';
  -- daily payout
  update hoods set last_payout_at = now() - interval '25 hours' where id = hid;
  perform get_me();
  assert (select bank from crews where name = 'Los Pollos') = 500 + 256000, 'crew got 80%: ' || (select bank from crews where name = 'Los Pollos');
  assert (select bank from cartels where name = 'Juárez') = 100 + 64000, 'cartel got 20%';
  assert jsonb_array_length(get_territory_log()) >= 5;
  assert top_users() ? 'crews';
  assert jsonb_array_length(find_players('esc')) = 1;
  assert get_player('11111111-1111-1111-1111-111111111111')->'crew'->>'name' = 'Los Pollos';
end $$;

-- leaving: capo leaves, successor takes over crew and cartel
select as_user('22222222-2222-2222-2222-222222222222');
do $$ begin
  perform crew_leave();
  assert (select capo_id from crews where name = 'Los Pollos') = '11111111-1111-1111-1111-111111111111', 'successor capo';
  assert (select don_id from cartels where name = 'Juárez') = '11111111-1111-1111-1111-111111111111', 'successor don';
end $$;
select as_user('11111111-1111-1111-1111-111111111111');
do $$ begin
  perform crew_leave();
  assert not exists (select 1 from crews where name = 'Los Pollos'), 'crew disbanded';
  assert not exists (select 1 from cartels where name = 'Juárez'), 'cartel dissolved';
  assert (select count(*) from blocks where owner_crew_id is not null) = 0, 'blocks freed';
end $$;

-- listing expiry returns product
update listings set expires_at = now() - interval '1 minute';
select get_me();
do $$ begin
  assert (select status from listings limit 1) = 'expired';
  assert (select qty from storage where player_id = '11111111-1111-1111-1111-111111111111' and commodity = 'herb') = 1000 - 400 + 100, 'listing returned';
end $$;

-- anon cannot call anything
reset role; select set_config('request.jwt.claims', '', false);
select expect_error('select get_me()', 'Not signed in');

\echo 'SMOKE TEST PASSED'
