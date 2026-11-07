-- Tests for 20261030000022_season1: the season draw, the Personal Hood (lazy creation, the fight, income, upgrades,
-- perks, the boss), the campaign (card, claim, objectives, the gate) and how it all degrades with no season running.
-- Fights are made sure things by setting a block's defenders to 1 (always lost by them) or 100000 (never).
-- Run after the other suites (reuses as_user / expect_error): scripts/local-db.sh test
\set ON_ERROR_STOP on
\set QUIET on

insert into auth.users (id, raw_user_meta_data) values
  ('f9f9f9f9-0022-4000-8000-000000000001', '{"name":"SeasonBoss"}'),
  ('f9f9f9f9-0022-4000-8000-000000000002', '{"name":"SeasonPal"}');
update profiles set is_admin = true where id = 'f9f9f9f9-0022-4000-8000-000000000001';

-- no season yet: the game plays as before -------------------------------------------------------------------------------
select as_user('f9f9f9f9-0022-4000-8000-000000000002');
do $$ declare me jsonb; begin
  me := get_me();
  assert me->'season' = 'null'::jsonb and me->'home' = 'null'::jsonb and me->'mission' = 'null'::jsonb, 'nothing seasonal: ' || (me->'season')::text;
  assert jsonb_array_length(me->'unlocked') = 17, 'every tab open without a season: ' || (me->'unlocked')::text;
  perform expect_error('select home_state()', 'No season is running');
  perform expect_error('select home_attack(1, 10, 0)', 'No season is running');
  perform expect_error('select mission_claim(''six_blocks'')', 'No season is running');
  perform expect_error('select season_start(''Nope'')', 'Admins only');
  assert (select count(*) from home_blocks) = 0, 'no hood without a season';
end $$;

-- the draw ----------------------------------------------------------------------------------------------------------------
select as_user('f9f9f9f9-0022-4000-8000-000000000001');
do $$ declare s jsonb; begin
  perform expect_error('select season_start(''  '')', 'Name the season');
  perform expect_error('select season_start(''X'', now(), 3, array[1,2,3])', 'Seven defender numbers');
  s := season_start('Season T');
  assert s->>'name' = 'Season T' and jsonb_array_length(s->'home_businesses') = 6 and jsonb_array_length(s->'home_defenders') = 7, s::text;
  assert (select count(distinct x) from jsonb_array_elements_text(s->'home_businesses') x) = 6, 'six different businesses';
  assert (select bool_and(exists (select 1 from business_defs where code = x)) from jsonb_array_elements_text(s->'home_businesses') x), 'real businesses';
  assert (s->>'ends_at')::timestamptz - (s->>'starts_at')::timestamptz between interval '89 days' and interval '93 days', 'three months';
  perform expect_error('select season_start(''Overlap'')', 'overlaps a season');
  perform expect_error('select season_start(''Overlap'', now() + interval ''30 days'')', 'overlaps a season');
end $$;

-- the hood appears on first sight, once, garrisoned from the season's troop values ---------------------------------------
select as_user('f9f9f9f9-0022-4000-8000-000000000002');
do $$ declare me jsonb; s seasons := _season(); pal uuid := 'f9f9f9f9-0022-4000-8000-000000000002'; g record; begin
  me := get_me();
  assert me->'season'->>'name' = 'Season T', 'the season is on: ' || (me->'season')::text;
  assert (select count(*) from home_blocks where player_id = pal and season_id = s.id) = 6, 'six blocks';
  assert (select array_agg(business order by slot) from home_blocks where player_id = pal and season_id = s.id) = s.home_businesses, 'the draw, in slot order';
  perform get_me(); perform home_state();
  assert (select count(*) from home_blocks where player_id = pal) = 6 and (select count(*) from home_hoods where player_id = pal) = 1, 'made once';
  -- $50k of muscle holds block 1: 38 thugs and 7 enforcers, resistance 800; the boss sits on $10M
  assert s.home_defenders = array[50000, 150000, 500000, 1000000, 2500000, 5000000, 10000000], 'troop values: ' || s.home_defenders::text;
  select * into g from _home_garrison(50000);
  assert g.thugs = 38 and g.enforcers = 7 and g.resistance = 800, format('%s %s %s', g.thugs, g.enforcers, g.resistance);
  assert (select thugs = 38 and enforcers = 7 from home_blocks where player_id = pal and slot = 1), 'block 1 garrisoned';
  assert (select boss_thugs = 7500 and boss_enforcers = 1250 from home_hoods where player_id = pal), 'the boss garrisoned';
  assert (me->'home'->>'cleared')::int = 0 and (me->'home'->'next'->>'resistance')::int = 800 and (me->'home'->'next'->>'min_force')::int = 200
         and (me->'home'->'next'->>'my_attack')::int = 0, 'block 1 is next, nothing to send yet: ' || (me->'home')::text;
  assert me->'unlocked' = '["home","hood","territory","profile","store","chat","forum","activity","accolades","missions"]'::jsonb, 'the gate is shut, Territory open: ' || (me->'unlocked')::text;
end $$;

-- mission 1 and the claim --------------------------------------------------------------------------------------------------
do $$ declare me jsonb; r jsonb; pal uuid := 'f9f9f9f9-0022-4000-8000-000000000002'; cash0 bigint; begin
  update home_hoods set opened_at = null where player_id = pal; delete from missions where player_id = pal;
  me := get_me();
  assert me->'mission'->>'key' = 'six_blocks' and (me->'mission'->>'n')::int = 1 and (me->'mission'->>'total')::int = 16, (me->'mission')::text;
  assert not (me->'mission'->>'complete')::boolean, 'not done until the hood is opened';
  perform expect_error('select mission_claim(''six_blocks'')', 'Not done yet');
  perform expect_error('select mission_claim(''work'')', 'isn''t the mission you''re on');
  perform expect_error('select mission_claim(''bogus'')', 'No such mission');
  perform home_state();
  me := get_me();
  assert (me->'mission'->>'complete')::boolean and me->'mission'->>'done' like 'Every block''s got a crew sitting on it%', 'opened: ' || (me->'mission')::text;
  select cash into cash0 from profiles where id = pal;
  r := mission_claim('six_blocks');
  assert (r->>'reward_cash')::int = 500 and (select cash from profiles where id = pal) = cash0 + 500, 'paid: ' || r::text;
  assert r->'next'->>'key' = 'work' and r->'unlocked' ? 'actions', 'the city first: ' || (r->'next')::text;
  perform expect_error('select mission_claim(''six_blocks'')', 'isn''t the mission you''re on');
end $$;

-- the fight: muscle against the garrison ---------------------------------------------------------------------------------------
do $$ declare r jsonb; pal uuid := 'f9f9f9f9-0022-4000-8000-000000000002'; t0 int; begin
  update profiles set stamina = 10, health = 100, in_hospital = false, jail_until = null, cash = 1000000 where id = pal;
  perform expect_error('select home_attack(1)', 'send thugs and mercs');           -- the old shape says what changed
  perform expect_error('select home_boss()', 'send thugs and mercs');
  perform expect_error('select home_attack(0, 10, 0)', 'No such block');
  perform expect_error('select home_attack(7, 10, 0)', 'No such block');
  perform expect_error('select home_attack(1, 0, 0)', 'Send some muscle');
  perform expect_error('select home_attack(1, 10, 0)', 'Not enough hoodlums');
  insert into player_hoodlums (player_id, code, qty) values (pal, 'thug', 100), (pal, 'mercenary', 20)
    on conflict (player_id, code) do update set qty = excluded.qty;
  perform expect_error('select home_attack(2, 10, 0)', 'Take block 1 first');
  perform expect_error('select home_boss(10, 0)', 'Take all six blocks first');
  perform expect_error('select home_attack(1, 10, 0)', 'laughed off the block');   -- 100 att against 800: under a quarter
  update profiles set stamina = 2 where id = pal;
  perform expect_error('select home_attack(1, 100, 0)', 'takes 3 stamina');
  update profiles set stamina = 10, health = 10 where id = pal;
  perform expect_error('select home_attack(1, 100, 0)', 'in the hospital');
  update profiles set health = 100, jail_until = now() + interval '1 hour' where id = pal;
  perform expect_error('select home_attack(1, 100, 0)', 'Not from a cell');
  update profiles set jail_until = null, heat = 0 where id = pal;

  -- a loss: 30 thugs (300 att at most) against 800 — a fight, lost; both sides bleed; the block stays theirs
  r := home_attack(1, 30, 0);
  assert not (r->>'won')::boolean and (r->>'stamina')::int = 7 and (r->>'resistance')::int = 800 and (r->>'thugs')::int = 30, r::text;
  assert (r->>'lost_thugs')::int = 15, 'half the force on a lost fight: ' || r::text;                 -- loss_frac = min(1, 800/atk) * .5 = .5
  assert (r->>'garrison_lost')::int between 1 and 20 and (r->>'garrison_left')::int < 800, 'the garrison bled a little: ' || r::text;
  assert (select qty from player_hoodlums where player_id = pal and code = 'thug') = 85, 'thugs gone';
  assert (select cleared_at is null from home_blocks where player_id = pal and slot = 1), 'still theirs';
  assert (select health from profiles where id = pal) = 100 and (select heat from profiles where id = pal) = 0
         and (select count(*) from fights where attacker_id = pal) = 0, 'no health, no heat, no fight row';
  -- a win: 85 thugs and 20 mercs (2,050 att at least 1,845) against what's left; the garrison is wiped, the clock starts
  t0 := (select qty from player_hoodlums where player_id = pal and code = 'thug');
  r := home_attack(1, 85, 20);
  assert (r->>'won')::boolean and (r->'hood'->>'cleared')::int = 1 and (r->'hood'->>'next_slot')::int = 2, r::text;
  assert (r->>'lost_thugs')::int between 8 and 25 and (r->>'lost_mercs')::int between 2 and 6, 'losses scale with the resistance: ' || r::text;   -- loss_frac ≈ res / atk / 2 ≈ 0.14–0.21
  assert (select thugs = 0 and enforcers = 0 from home_blocks where player_id = pal and slot = 1), 'garrison wiped';
  assert (select cleared_at is not null and collected_at is not null from home_blocks where player_id = pal and slot = 1), 'cleared, clock started';
  assert (select qty from player_hoodlums where player_id = pal and code = 'thug') = t0 - (r->>'lost_thugs')::int, 'the survivors came home';
  perform expect_error('select home_attack(1, 10, 0)', 'already yours');
  assert (r->'hood'->'next'->>'resistance')::int = 2270 and (r->'hood'->'blocks'->1->>'value')::int = 150000, 'block 2 next: ' || (r->'hood'->'next')::text;
end $$;

-- income, collecting, upgrading -------------------------------------------------------------------------------------------
do $$ declare r jsonb; h jsonb; pal uuid := 'f9f9f9f9-0022-4000-8000-000000000002'; cash0 bigint; begin
  update home_blocks set collected_at = now() - interval '12 hours' where player_id = pal and slot = 1;
  h := home_state();
  assert (h->>'income_day')::int = 1500 and (h->>'ready_cash')::int = 750, 'half a day at level 1: ' || (h->'blocks'->0)::text;
  update home_blocks set collected_at = now() - interval '72 hours' where player_id = pal and slot = 1;
  assert (home_state()->>'ready_cash')::int = 3000, 'capped at 48 hours';
  select cash into cash0 from profiles where id = pal;
  r := home_collect(1);
  assert (r->>'collected')::int = 3000 and (select cash from profiles where id = pal) = cash0 + 3000, r::text;
  assert (select collects from home_hoods where player_id = pal) = 1, 'counted';
  perform expect_error('select home_collect(1)', 'Nothing to collect yet');
  perform expect_error('select home_collect(2)', 'isn''t yours yet');
  perform expect_error('select home_collect()', 'Nothing to collect yet');
  -- upgrades
  perform expect_error('select home_upgrade(2)', 'Take the block first');
  perform expect_error('select home_upgrade(9)', 'No such block');
  update profiles set cash = 4999 where id = pal;
  perform expect_error('select home_upgrade(1)', 'Costs $5000');
  update profiles set cash = 5000 where id = pal;
  update home_blocks set collected_at = now() - interval '24 hours' where player_id = pal and slot = 1;   -- $1,500 waiting
  r := home_upgrade(1);
  assert (r->>'level')::int = 2 and (r->>'cost')::int = 5000 and (select cash from profiles where id = pal) = 1500, 'paid, and the waiting cash was paid out first: ' || r::text;
  assert (home_state()->>'income_day')::int = 3000 and (home_state()->>'ready_cash')::int = 0, 'level 2 pays double from now';
  update home_blocks set level = 5 where player_id = pal and slot = 1;
  perform expect_error('select home_upgrade(1)', 'top level');
  assert (home_state()->'blocks'->0->'upgrade_cost') = 'null'::jsonb, 'no price past 5';
  update home_blocks set level = 1 where player_id = pal and slot = 1;
end $$;

-- perks: the ladder, and the larger of crew and hood ------------------------------------------------------------------------
do $$ declare pal uuid := 'f9f9f9f9-0022-4000-8000-000000000002'; s seasons := _season(); d business_defs; cid uuid; crewv numeric; begin
  select * into d from business_defs where code = s.home_businesses[1];
  assert _pk(_perks(pal), d.code) = d.base, format('level 1 is the base: %s vs %s', _pk(_perks(pal), d.code), d.base);
  update home_blocks set level = 5 where player_id = pal and slot = 1;
  assert _pk(_perks(pal), d.code) = d.ceiling, 'level 5 is the ceiling';
  update home_blocks set level = 3 where player_id = pal and slot = 1;
  assert _pk(_perks(pal), d.code) = round(d.base + (d.ceiling - d.base) / 2, 4), 'level 3 is halfway';
  -- a crew holding one block with the same business: whichever is larger wins, they never add up
  insert into crews (name, emblem, capo_id) values ('Perk Test Crew', '🧪', pal) returning id into cid;
  update profiles set crew_id = cid where id = pal;
  update blocks set owner_crew_id = cid, business = d.code where id = (select id from blocks order by id limit 1);
  crewv := _pk(_crew_perks(cid), d.code);
  assert crewv > 0, 'the crew has the perk';
  assert _pk(_perks(pal), d.code) = greatest(crewv, round(d.base + (d.ceiling - d.base) / 2, 4)), format('max, not sum: %s crew %s', _pk(_perks(pal), d.code), crewv);
  update blocks set owner_crew_id = null, business = null where owner_crew_id = cid;
  update profiles set crew_id = null where id = pal; delete from crews where id = cid;
  update home_blocks set level = 1 where player_id = pal and slot = 1;
end $$;

-- the campaign in its order: the city first, then the muscle, then the hood ---------------------------------------------------
do $$ declare pal uuid := 'f9f9f9f9-0022-4000-8000-000000000002'; me jsonb; r jsonb; s seasons := _season(); i int; begin
  -- 2 work: three actions; Actions is open while it's the mission
  assert get_me()->'mission'->>'key' = 'work' and get_me()->'unlocked' ? 'actions' and not (get_me()->'unlocked' ? 'items'), (get_me()->'unlocked')::text;
  update profiles set actions_done = 2 where id = pal;
  assert (get_me()->'mission'->>'progress')::int = 2 and not (get_me()->'mission'->>'complete')::boolean, '2 of 3';
  update profiles set actions_done = 3 where id = pal;
  perform mission_claim('work');
  -- 3 get armed: attack power 28 (a Baseball Bat on bare 20); the shop is open as soon as it's the mission
  assert get_me()->'mission'->>'key' = 'get_armed' and get_me()->'unlocked' ? 'items', (get_me()->'unlocked')::text;
  update profiles set cash = 100000, stamina = 50, health = 100 where id = pal;
  perform buy_item((select id from item_defs where name = 'Baseball Bat'), 1);
  perform equip('offense', (select id from item_defs where name = 'Baseball Bat'), 1);
  me := get_me();
  assert (me->'mission'->>'progress')::int = 28 and (me->'mission'->>'complete')::boolean, (me->'mission')::text;
  perform mission_claim('get_armed');
  -- 4 bank it: diamonds reward; Services and the Casino
  update profiles set bank = 0 where id = pal;
  assert get_me()->'mission'->>'key' = 'bank_it' and not (get_me()->'mission'->>'complete')::boolean, 'nothing banked';
  perform bank_deposit(100);
  i := (select diamonds from profiles where id = pal);
  r := mission_claim('bank_it');
  assert (select diamonds from profiles where id = pal) = i + 10 and r->'unlocked' ? 'services' and r->'unlocked' ? 'casino', r::text;
  -- 5 grow
  perform grow_build('herb');
  perform mission_claim('grow');
  assert get_me()->'unlocked' ? 'economy', 'economy open';
  -- 6 first blood
  update profiles set fights_won = 1 where id = pal;
  r := mission_claim('first_blood');
  assert r->'unlocked' ? 'fight', 'fight open';
  -- 7 move product
  update profiles set imports = 10 where id = pal;
  perform mission_claim('move_product');
  -- 8 hire muscle: thirty thugs, thugs alone (the mercs don't count); Marcus names block one's business and its price
  me := get_me();
  assert me->'mission'->>'key' = 'hire_muscle' and (me->'mission'->>'progress')::int >= 30 and (me->'mission'->>'complete')::boolean, (me->'mission')::text;
  update player_hoodlums set qty = 10 where player_id = pal and code = 'thug';
  delete from missions where player_id = pal and key = 'hire_muscle';
  assert (get_me()->'mission'->>'progress')::int = 10 and not (get_me()->'mission'->>'complete')::boolean, 'ten thugs is not thirty';
  update player_hoodlums set qty = 100 where player_id = pal and code = 'thug';
  r := mission_claim('hire_muscle');
  assert position((select name from business_defs where code = s.home_businesses[1]) in (r->'next'->>'intro')) = 0, 'block one''s intro: ' || (r->'next'->>'intro');
  -- 9 block one: already taken above, so it's met on sight
  me := get_me();
  assert me->'mission'->>'key' = 'block_one' and (me->'mission'->>'complete')::boolean, (me->'mission')::text;
  perform mission_claim('block_one');
  -- 10 open for business: the collect from earlier counts, and Marcus names the business
  me := get_me();
  assert me->'mission'->>'key' = 'open_for_business' and (me->'mission'->>'complete')::boolean, (me->'mission')::text;
  assert position((select name from business_defs where code = s.home_businesses[1]) in (me->'mission'->>'intro')) > 0, 'named: ' || (me->'mission'->>'intro');
  perform mission_claim('open_for_business');
  -- 11 build it up: any block to level 2
  update profiles set cash = 1000000 where id = pal;
  perform home_upgrade(1);
  perform mission_claim('build_it_up');
  -- 12 to 14: the blocks, each with enough muscle to be sure of it (attack at least 0.9 × force > resistance)
  update player_hoodlums set qty = 10000 where player_id = pal and code = 'thug';
  insert into player_hoodlums (player_id, code, qty) values (pal, 'mercenary', 10000) on conflict (player_id, code) do update set qty = 10000;
  update profiles set stamina = 50 where id = pal;
  r := home_attack(2, 300, 0);              -- 3,000 × 0.9 = 2,700 > 2,270
  assert (r->>'won')::boolean, 'block 2: ' || r::text;
  perform mission_claim('block_two');
  r := home_attack(3, 0, 140);              -- 8,400 × 0.9 = 7,560 > 7,530
  assert (r->>'won')::boolean, 'block 3: ' || r::text;
  r := home_attack(4, 0, 280);              -- 16,800 × 0.9 > 15,000
  assert (r->>'won')::boolean, 'block 4: ' || r::text;
  perform mission_claim('blocks_three_four');
  r := home_attack(5, 0, 700);              -- 42,000 × 0.9 > 37,530
  assert (r->>'won')::boolean, 'block 5: ' || r::text;
  r := home_attack(6, 0, 1400);             -- 84,000 × 0.9 > 75,000
  assert (r->>'won')::boolean, 'block 6: ' || r::text;
  assert (get_me()->'home'->>'cleared')::int = 6 and (get_me()->'home'->>'boss_ready')::boolean, 'the boss shows up';
  perform mission_claim('blocks_five_six');
  -- 15 the boss: $10M of muscle; income rises by half
  assert (home_state()->>'income_day')::int = 1500 * 5 + 3000, 'six blocks, one at level 2: ' || (home_state()->>'income_day');
  perform expect_error('select home_boss(100, 0)', 'laughed off');
  update player_hoodlums set qty = 10000 where player_id = pal and code = 'mercenary';
  r := home_boss(0, 2800);                  -- 168,000 × 0.9 > 150,000
  assert (r->>'won')::boolean and (r->>'boss')::boolean and (select boss_cleared_at is not null from home_hoods where player_id = pal), r::text;
  perform expect_error('select home_boss(10, 0)', 'already yours');
  assert (home_state()->>'income_day')::int = floor(1500 * 1.5) * 5 + floor(3000 * 1.5), 'the boss bonus: ' || (home_state()->>'income_day');
  r := mission_claim('the_boss');
  assert (r->>'reward_cash')::int = 100000 and (r->>'reward_diamonds')::int = 50 and r->'unlocked' ? 'crew', r::text;
  -- 16 into the city: three parts, three ticks
  me := get_me();
  assert me->'mission'->>'key' = 'into_the_city' and (me->'mission'->>'progress')::int = 1 and jsonb_array_length(me->'mission'->'parts') = 3, (me->'mission')::text;
  perform crew_create('Season Crew');
  me := get_me();
  assert (me->'mission'->>'progress')::int = 2 and (me->'mission'->'parts'->2->>'done')::boolean = false, 'two of three: ' || (me->'mission'->'parts')::text;
  update profiles set turf_attacks = 1 where id = pal;
  r := mission_claim('into_the_city');
  assert (r->>'reward_cash')::int = 25000 and (r->'next'->>'finished')::boolean, 'campaign done: ' || (r->'next')::text;
  me := get_me();
  assert (me->'mission'->>'finished')::boolean and jsonb_array_length(me->'unlocked') = 17, 'everything open at the end: ' || (me->'unlocked')::text;
  -- the log
  r := missions_state();
  assert jsonb_array_length(r->'missions') = 16 and (r->'missions'->15->>'claimed')::boolean and (r->'missions'->0->>'n')::int = 1, (r->'missions'->15)::text;
end $$;

-- a met objective stays met: cash withdrawn after Bank It doesn't reopen it ---------------------------------------------------
select as_user('f9f9f9f9-0022-4000-8000-000000000001');
do $$ declare me uuid := 'f9f9f9f9-0022-4000-8000-000000000001'; r jsonb; begin
  perform home_state(); perform mission_claim('six_blocks');
  update profiles set stamina = 50, health = 100, cash = 50000 where id = me;
  update profiles set actions_done = 3 where id = me; perform mission_claim('work');
  perform buy_item((select id from item_defs where name = 'Baseball Bat'), 1);
  perform equip('offense', (select id from item_defs where name = 'Baseball Bat'), 1);
  perform mission_claim('get_armed');
  perform bank_deposit(1000);
  assert (get_me()->'mission'->>'complete')::boolean, 'banked';
  perform bank_withdraw(1000);
  assert (get_me()->'mission'->>'complete')::boolean, 'seen done once, stays done';
  perform mission_claim('bank_it');
  -- a block taken by the admin too (for the rollover below): muscle in, block one out
  insert into player_hoodlums (player_id, code, qty) values (me, 'mercenary', 100) on conflict (player_id, code) do update set qty = 100;
  r := home_attack(1, 0, 20);               -- 1,200 × 0.9 > 800
  assert (r->>'won')::boolean, r::text;
end $$;

-- the rollover (20261106000025): Season T ends, Season U begins ------------------------------------------------------------
-- Pal finished Season T's campaign with six blocks and the boss; the admin is on mission 7. Rolling over gives both a
-- fresh hood and mission 1 again, keeps every Season T row, touches nothing on their profiles, and leaves the city open
-- for both (a hood in an earlier season makes a veteran). A player born in Season U is gated like anyone's first time.
select as_user('f9f9f9f9-0022-4000-8000-000000000002');
do $$ declare pal uuid := 'f9f9f9f9-0022-4000-8000-000000000002'; me jsonb; begin
  perform expect_error('select season_list()', 'Admins only');
  perform expect_error('select season_end(1)', 'Admins only');
  update profiles set cash = 123456, bank = 7890, diamonds = 42 where id = pal;
  me := get_me();
  assert (me->'home'->>'cleared')::int = 6 and (me->'home'->>'boss')::boolean, 'Season T: the hood is pal''s: ' || (me->'home')::text;
  assert (_home_perks(pal)->>(select business from home_blocks where player_id = pal and slot = 1))::numeric > 0, 'Season T perks apply';
end $$;
select as_user('f9f9f9f9-0022-4000-8000-000000000001');
do $$ declare boss uuid := 'f9f9f9f9-0022-4000-8000-000000000001'; pal uuid := 'f9f9f9f9-0022-4000-8000-000000000002';
           t seasons := _season(); l jsonb; r jsonb; me jsonb; u seasons; before jsonb; after jsonb; rows_t int; begin
  l := season_list();
  assert jsonb_array_length(l) = 1 and l->0->>'status' = 'running' and (l->0->>'players')::int = 2 and (l->0->>'bosses')::int = 1
         and jsonb_array_length(l->0->'businesses') = 6 and l->0->'businesses'->0 ? 'name', 'the list: ' || l::text;
  perform expect_error('select season_end(999)', 'No such season');
  perform expect_error(format('select season_cancel(%s)', t.id), 'has started');
  rows_t := (select count(*) from home_blocks where season_id = t.id) + (select count(*) from missions where season_id = t.id);
  before := (select to_jsonb(p) - 'last_seen' - 'stamina' - 'health' - 'stamina_tick' - 'health_tick' - 'heat' - 'heat_tick' from profiles p where id = pal);
  -- the end: no season, every tab open, nothing seasonal on get_me
  r := season_end(t.id);
  assert (r->>'ends_at')::timestamptz <= now(), r::text;
  perform expect_error(format('select season_end(%s)', t.id), 'already over');
  assert (select id from _season()) is null, 'no season running';
  me := get_me();
  assert me->'season' = 'null'::jsonb and me->'home' = 'null'::jsonb and jsonb_array_length(me->'unlocked') = 17, 'between seasons: ' || (me->'season')::text;
  perform expect_error('select home_state()', 'No season is running');
  -- a scheduled season can be cancelled; one starting now is the real Season U
  r := season_start('Season V', now() + interval '10 days', 1);
  assert (season_list()->0->>'status') = 'scheduled', season_list()::text;
  perform expect_error('select season_start(''Clash'', now() + interval ''20 days'', 1)', 'overlaps a season');
  perform season_cancel((r->>'id')::int);
  assert (select cancelled_at is not null from seasons where name = 'Season V'), 'cancelled, kept';
  perform expect_error(format('select season_cancel(%s)', (r->>'id')::int), 'already cancelled');
  -- a cancelled season is out of the way: it overlaps nothing and never runs
  r := season_start('Season W', now() + interval '20 days', 1);
  perform season_cancel((r->>'id')::int);
  r := season_start('Season U');
  u := _season();
  assert u.name = 'Season U' and u.id <> t.id, 'Season U is on';
  l := season_list();
  assert jsonb_array_length(l) = 4 and l->0->>'status' = 'cancelled' and l->1->>'status' = 'cancelled'
         and l->2->>'name' = 'Season U' and l->2->>'status' = 'running' and l->3->>'status' = 'over', l::text;
end $$;
-- pal, the veteran
select as_user('f9f9f9f9-0022-4000-8000-000000000002');
do $$ declare pal uuid := 'f9f9f9f9-0022-4000-8000-000000000002'; u seasons := _season(); me jsonb; h jsonb; begin
  me := get_me();
  assert me->'season'->>'name' = 'Season U', (me->'season')::text;
  assert (me->'home'->>'cleared')::int = 0 and not (me->'home'->>'boss')::boolean and (me->'home'->>'opened')::boolean is not true, 'a fresh hood: ' || (me->'home')::text;
  assert (select array_agg(business order by slot) from home_blocks where player_id = pal and season_id = u.id) = u.home_businesses, 'the new draw';
  assert me->'mission'->>'key' = 'six_blocks' and (me->'mission'->>'n')::int = 1, 'mission 1 again: ' || (me->'mission')::text;
  assert jsonb_array_length(me->'unlocked') = 17, 'a veteran keeps the city: ' || (me->'unlocked')::text;
  assert _home_perks(pal) = '{}'::jsonb, 'the old hood''s perks are gone: ' || _home_perks(pal)::text;
  h := home_state();
  assert (h->>'cleared')::int = 0 and (h->>'next_slot')::int = 1, h::text;
  -- Season T is history, untouched
  assert (select count(*) from home_blocks where player_id = pal and season_id <> u.id and cleared_at is not null) = 6, 'Season T blocks kept';
  assert (select count(*) from missions where player_id = pal and season_id <> u.id and claimed_at is not null) = 16, 'Season T missions kept';
  assert (select cash from profiles where id = pal) = 123456 and (select bank from profiles where id = pal) = 7890 and (select diamonds from profiles where id = pal) = 42, 'the profile is untouched';
  -- the campaign still pays a veteran
  perform mission_claim('six_blocks');
  assert (get_me()->'mission'->>'key') = 'work', 'on to Work';
  assert (select cash from profiles where id = pal) = 123956, 'paid $500';
end $$;
-- the admin is a veteran too (a hood in Season T, block one taken); a newcomer is not
select as_user('f9f9f9f9-0022-4000-8000-000000000001');
do $$ declare me jsonb; begin
  me := get_me();
  assert jsonb_array_length(me->'unlocked') = 17 and me->'mission'->>'key' = 'six_blocks', 'the admin keeps the city, starts the campaign over: ' || (me->'unlocked')::text;
end $$;
insert into auth.users (id, raw_user_meta_data) values ('f9f9f9f9-0022-4000-8000-000000000003', '{"name":"SeasonRook"}');
select as_user('f9f9f9f9-0022-4000-8000-000000000003');
do $$ declare me jsonb; begin
  me := get_me();
  assert me->'season'->>'name' = 'Season U' and not (me->'unlocked' ? 'actions') and jsonb_array_length(me->'unlocked') = 10, 'born in Season U, gated: ' || (me->'unlocked')::text;
end $$;

-- the season board (20261106000027): the boss first, then blocks, then claims, then who got there first ----------------
select as_user('f9f9f9f9-0022-4000-8000-000000000002');
do $$ declare pal uuid := 'f9f9f9f9-0022-4000-8000-000000000002'; boss uuid := 'f9f9f9f9-0022-4000-8000-000000000001';
           rook uuid := 'f9f9f9f9-0022-4000-8000-000000000003'; b jsonb; u seasons := _season(); begin
  update profiles set stamina = 50, health = 100 where id in (pal, boss);
  update player_hoodlums set qty = 10000 where player_id = pal and code = 'mercenary';
  perform home_attack(1, 0, 20); perform home_attack(2, 0, 50);   -- pal: two blocks, one claim
  update home_blocks set cleared_at = now() - interval '1 hour' where player_id = boss and season_id = u.id and slot = 1;   -- the admin: one block, earlier
  b := season_board(10);
  assert b->'season'->>'name' = 'Season U' and (b->>'players')::int = 3, b::text;
  assert b->'rows'->0->>'id' = pal::text and (b->'rows'->0->>'rank')::int = 1 and (b->'rows'->0->>'cleared')::int = 2 and (b->'rows'->0->>'me')::boolean, 'pal leads on blocks: ' || (b->'rows'->0)::text;
  assert b->'rows'->1->>'id' = boss::text and b->'rows'->2->>'id' = rook::text, 'then the admin, then the newcomer: ' || (b->'rows')::text;
  assert (b->'me'->>'rank')::int = 1 and (b->'me'->>'cleared')::int = 2, (b->'me')::text;
  -- the boss down beats any number of blocks; a limit of 1 keeps the leader only, and me still says where I am
  update home_hoods set boss_cleared_at = now() where player_id = boss and season_id = u.id;
  b := season_board(1);
  assert jsonb_array_length(b->'rows') = 1 and b->'rows'->0->>'id' = boss::text and (b->'rows'->0->>'boss')::boolean, (b->'rows')::text;
  assert (b->'me'->>'rank')::int = 2, (b->'me')::text;
  update home_hoods set boss_cleared_at = null where player_id = boss and season_id = u.id;
  -- a bot never shows
  update profiles set is_bot = true where id = rook;
  assert (season_board()->>'players')::int = 2, 'bots are off the board';
  update profiles set is_bot = false where id = rook;
end $$;
-- with no season the board is empty, not an error
update seasons set ends_at = now() where cancelled_at is null and ends_at > now();
do $$ begin
  assert season_board()->'season' = 'null'::jsonb and jsonb_array_length(season_board()->'rows') = 0, 'no season, no board';
end $$;
update seasons set ends_at = starts_at + interval '90 days' where name = 'Season U';

-- clean up what the later suites would trip on: a season stays (the fuzz runs with one), the crew goes
update profiles set crew_id = null where id = 'f9f9f9f9-0022-4000-8000-000000000002';
delete from crews where name = 'Season Crew';

select ' SEASON TEST PASSED';
