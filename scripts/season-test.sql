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
  perform expect_error('select home_attack(1)', 'No season is running');
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

-- the hood appears on first sight, once --------------------------------------------------------------------------------------
select as_user('f9f9f9f9-0022-4000-8000-000000000002');
do $$ declare me jsonb; s seasons := _season(); pal uuid := 'f9f9f9f9-0022-4000-8000-000000000002'; begin
  me := get_me();
  assert me->'season'->>'name' = 'Season T', 'the season is on: ' || (me->'season')::text;
  assert (select count(*) from home_blocks where player_id = pal and season_id = s.id) = 6, 'six blocks';
  assert (select array_agg(business order by slot) from home_blocks where player_id = pal and season_id = s.id) = s.home_businesses, 'the draw, in slot order';
  perform get_me(); perform home_state();
  assert (select count(*) from home_blocks where player_id = pal) = 6 and (select count(*) from home_hoods where player_id = pal) = 1, 'made once';
  assert (me->'home'->>'cleared')::int = 0 and (me->'home'->'next'->>'defender')::int = 12 and (me->'home'->'next'->>'win_pct')::int = 100,
         'block 1 is a sure thing bare-handed: ' || (me->'home')::text;
  assert me->'unlocked' = '["home","hood","profile","store","chat","forum","activity","accolades","missions"]'::jsonb, 'the gate is shut: ' || (me->'unlocked')::text;
  assert not (me->'unlocked' ? 'items'), 'Six Blocks opens nothing';
end $$;

-- mission 1 and the claim --------------------------------------------------------------------------------------------------
do $$ declare me jsonb; r jsonb; pal uuid := 'f9f9f9f9-0022-4000-8000-000000000002'; cash0 bigint; begin
  -- a fresh player who hasn't looked at the hood yet (the block above called home_state; undo that)
  update home_hoods set opened_at = null where player_id = pal; delete from missions where player_id = pal;
  me := get_me();
  assert me->'mission'->>'key' = 'six_blocks' and (me->'mission'->>'n')::int = 1 and (me->'mission'->>'total')::int = 15, (me->'mission')::text;
  assert not (me->'mission'->>'complete')::boolean, 'not done until the hood is opened';
  perform expect_error('select mission_claim(''six_blocks'')', 'Not done yet');
  perform expect_error('select mission_claim(''block_one'')', 'isn''t the mission you''re on');
  perform expect_error('select mission_claim(''bogus'')', 'No such mission');
  perform home_state();
  me := get_me();
  assert (me->'mission'->>'complete')::boolean and me->'mission'->>'done' = 'First block''s held by a couple of kids with bats. Go introduce yourself.', 'opened: ' || (me->'mission')::text;
  select cash into cash0 from profiles where id = pal;
  r := mission_claim('six_blocks');
  assert (r->>'reward_cash')::int = 500 and (select cash from profiles where id = pal) = cash0 + 500, 'paid: ' || r::text;
  assert r->'next'->>'key' = 'block_one', 'the next card comes back with the claim: ' || (r->'next')::text;
  perform expect_error('select mission_claim(''six_blocks'')', 'isn''t the mission you''re on');
  assert (select claimed_at is not null from missions where player_id = pal and key = 'six_blocks'), 'claimed row';
end $$;

-- the fight ----------------------------------------------------------------------------------------------------------------
do $$ declare r jsonb; pal uuid := 'f9f9f9f9-0022-4000-8000-000000000002'; begin
  update profiles set stamina = 10, health = 100, in_hospital = false, jail_until = null where id = pal;
  perform expect_error('select home_attack(0)', 'No such block');
  perform expect_error('select home_attack(7)', 'No such block');
  perform expect_error('select home_attack(2)', 'Take block 1 first');
  perform expect_error('select home_boss()', 'Take all six blocks first');
  update profiles set stamina = 1 where id = pal;
  perform expect_error('select home_attack(1)', 'You need 2 stamina');
  update profiles set stamina = 10, health = 10 where id = pal;
  perform expect_error('select home_attack(1)', 'in the hospital');
  update profiles set health = 100, jail_until = now() + interval '1 hour' where id = pal;
  perform expect_error('select home_attack(1)', 'Not from a cell');
  update profiles set jail_until = null, heat = 0 where id = pal;

  -- a loss: the defenders can't be beaten; it costs stamina and some health, never into the hospital
  update seasons set home_defenders = array[100000, 1, 1, 1, 1, 1, 1];
  update profiles set health = 30 where id = pal;
  r := home_attack(1);
  assert not (r->>'won')::boolean and (r->>'stamina')::int = 8 and (r->>'defender')::int = 100000, r::text;
  assert (select health from profiles where id = pal) = 20 and (r->>'damage_taken')::int = 10, 'floored at 20: ' || r::text;
  update profiles set health = 21 where id = pal;
  r := home_attack(1);
  assert (select health from profiles where id = pal) = 20 and (r->>'damage_taken')::int = 1, 'a point above the floor loses a point';
  assert (select cleared_at is null from home_blocks where player_id = pal and slot = 1), 'still theirs';
  assert (select heat from profiles where id = pal) = 0 and (select count(*) from fights where attacker_id = pal) = 0, 'no heat, no fight row';
  -- a win
  update seasons set home_defenders = array[1, 1, 1, 1, 1, 1, 1];
  update profiles set health = 100, stamina = 10 where id = pal;
  r := home_attack(1);
  assert (r->>'won')::boolean and (r->'hood'->>'cleared')::int = 1 and (r->'hood'->>'next_slot')::int = 2, r::text;
  assert (select cleared_at is not null and collected_at is not null from home_blocks where player_id = pal and slot = 1), 'cleared, clock started';
  perform expect_error('select home_attack(1)', 'already yours');
  assert get_me()->'mission'->>'key' = 'block_one' and (get_me()->'mission'->>'complete')::boolean, 'mission 2 done';
  perform mission_claim('block_one');
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
  -- mission 3 (get armed) is next and not done; mission 4's objective is already met once it's current
  assert get_me()->'mission'->>'key' = 'get_armed' and not (get_me()->'mission'->>'complete')::boolean, (get_me()->'mission')::text;
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

-- the rest of the campaign: every objective, the gate, the boss ---------------------------------------------------------------
do $$ declare pal uuid := 'f9f9f9f9-0022-4000-8000-000000000002'; me jsonb; r jsonb; s seasons := _season(); i int; begin
  -- 3 get armed: the shop is open as soon as Get Armed is the mission (20261103000023), since the mission needs it
  assert get_me()->'unlocked' ? 'items' and not (get_me()->'unlocked' ? 'actions'), 'the current mission''s unlocks count: ' || (get_me()->'unlocked')::text;
  -- attack power 28 (a Baseball Bat on bare 20)
  update profiles set cash = 100000, stamina = 50, health = 100 where id = pal;
  perform buy_item((select id from item_defs where name = 'Baseball Bat'), 1);
  perform equip('offense', (select id from item_defs where name = 'Baseball Bat'), 1);
  me := get_me();
  assert (me->'mission'->>'progress')::int = 28 and (me->'mission'->>'complete')::boolean, (me->'mission')::text;
  r := mission_claim('get_armed');
  assert r->'unlocked' ? 'items', 'the shop opens: ' || (r->'unlocked')::text;
  -- 4 open for business: the collect from earlier already counts, and Marcus names the business
  me := get_me();
  assert me->'mission'->>'key' = 'open_for_business' and (me->'mission'->>'complete')::boolean, (me->'mission')::text;
  assert position((select name from business_defs where code = s.home_businesses[1]) in (me->'mission'->>'intro')) > 0, 'named: ' || (me->'mission'->>'intro');
  perform mission_claim('open_for_business');
  -- 5 work: three actions
  update profiles set actions_done = 2 where id = pal;
  assert (get_me()->'mission'->>'progress')::int = 2 and not (get_me()->'mission'->>'complete')::boolean, '2 of 3';
  update profiles set actions_done = 3 where id = pal;
  perform mission_claim('work');
  assert get_me()->'unlocked' ? 'actions', 'actions open';
  -- 6 bank it: diamonds reward
  update profiles set bank = 0 where id = pal;
  assert not (get_me()->'mission'->>'complete')::boolean, 'nothing banked';
  perform bank_deposit(100);
  i := (select diamonds from profiles where id = pal);
  r := mission_claim('bank_it');
  assert (select diamonds from profiles where id = pal) = i + 10 and r->'unlocked' ? 'services' and r->'unlocked' ? 'casino', r::text;
  -- 7 block two
  perform home_attack(2);
  perform mission_claim('block_two');
  -- 8 build it up: any block to level 2
  update profiles set cash = 100000 where id = pal;
  perform home_upgrade(2);
  perform mission_claim('build_it_up');
  -- 9 grow
  perform grow_build('herb');
  perform mission_claim('grow');
  assert get_me()->'unlocked' ? 'economy', 'economy open';
  -- 10 blocks three and four
  perform home_attack(3); perform home_attack(4);
  perform mission_claim('blocks_three_four');
  -- 11 first blood
  update profiles set fights_won = 1 where id = pal;
  r := mission_claim('first_blood');
  assert r->'unlocked' ? 'fight', 'fight open';
  -- 12 move product
  update profiles set imports = 10 where id = pal;
  perform mission_claim('move_product');
  -- 13 blocks five and six
  perform home_attack(5); perform home_attack(6);
  assert (get_me()->'home'->>'cleared')::int = 6 and (get_me()->'home'->>'boss_ready')::boolean, 'the boss shows up';
  perform mission_claim('blocks_five_six');
  -- 14 the boss: income rises by half
  assert (home_state()->>'income_day')::int = 1500 * 5 + 3000, 'six blocks, one at level 2: ' || (home_state()->>'income_day');
  r := home_boss();
  assert (r->>'won')::boolean and (r->>'boss')::boolean and (select boss_cleared_at is not null from home_hoods where player_id = pal), r::text;
  perform expect_error('select home_boss()', 'already yours');
  assert (home_state()->>'income_day')::int = floor(1500 * 1.5) * 5 + floor(3000 * 1.5), 'the boss bonus: ' || (home_state()->>'income_day');
  r := mission_claim('the_boss');
  assert (r->>'reward_diamonds')::int = 25 and r->'unlocked' ? 'crew' and r->'unlocked' ? 'territory', r::text;
  -- 15 into the city: three parts, three ticks
  me := get_me();
  assert me->'mission'->>'key' = 'into_the_city' and (me->'mission'->>'progress')::int = 0 and jsonb_array_length(me->'mission'->'parts') = 3, (me->'mission')::text;
  perform crew_create('Season Crew');
  insert into player_hoodlums (player_id, code, qty) values (pal, 'thug', 5) on conflict (player_id, code) do update set qty = 5;
  me := get_me();
  assert (me->'mission'->>'progress')::int = 2 and (me->'mission'->'parts'->2->>'done')::boolean = false, 'two of three: ' || (me->'mission'->'parts')::text;
  update profiles set turf_attacks = 1 where id = pal;
  r := mission_claim('into_the_city');
  assert (r->>'reward_cash')::int = 15000 and (r->'next'->>'finished')::boolean, 'campaign done: ' || (r->'next')::text;
  me := get_me();
  assert (me->'mission'->>'finished')::boolean and jsonb_array_length(me->'unlocked') = 17, 'everything open at the end: ' || (me->'unlocked')::text;
  -- the log
  r := missions_state();
  assert jsonb_array_length(r->'missions') = 15 and (r->'missions'->14->>'claimed')::boolean and (r->'missions'->0->>'n')::int = 1, (r->'missions'->14)::text;
end $$;

-- a met objective stays met: cash withdrawn after Bank It doesn't reopen it ---------------------------------------------------
select as_user('f9f9f9f9-0022-4000-8000-000000000001');
do $$ declare me uuid := 'f9f9f9f9-0022-4000-8000-000000000001'; r jsonb; begin
  perform home_state(); perform mission_claim('six_blocks');
  update seasons set home_defenders = array[1, 1, 1, 1, 1, 1, 1];
  update profiles set stamina = 50, health = 100, cash = 50000 where id = me;
  perform home_attack(1); perform mission_claim('block_one');
  perform buy_item((select id from item_defs where name = 'Baseball Bat'), 1);
  perform equip('offense', (select id from item_defs where name = 'Baseball Bat'), 1);
  perform mission_claim('get_armed');
  update home_blocks set collected_at = now() - interval '1 hour' where player_id = me and slot = 1;
  perform home_collect(); perform mission_claim('open_for_business');
  update profiles set actions_done = 3 where id = me; perform mission_claim('work');
  perform bank_deposit(1000);
  assert (get_me()->'mission'->>'complete')::boolean, 'banked';
  perform bank_withdraw(1000);
  assert (get_me()->'mission'->>'complete')::boolean, 'seen done once, stays done';
  perform mission_claim('bank_it');
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
  assert (select count(*) from missions where player_id = pal and season_id <> u.id and claimed_at is not null) = 15, 'Season T missions kept';
  assert (select cash from profiles where id = pal) = 123456 and (select bank from profiles where id = pal) = 7890 and (select diamonds from profiles where id = pal) = 42, 'the profile is untouched';
  -- the campaign still pays a veteran
  perform mission_claim('six_blocks');
  assert (get_me()->'mission'->>'key') = 'block_one', 'on to Block One';
  assert (select cash from profiles where id = pal) = 123956, 'paid $500';
end $$;
-- the admin is a veteran too (a hood in Season T on mission 7); a newcomer is not
select as_user('f9f9f9f9-0022-4000-8000-000000000001');
do $$ declare me jsonb; begin
  me := get_me();
  assert jsonb_array_length(me->'unlocked') = 17 and me->'mission'->>'key' = 'six_blocks', 'the admin keeps the city, starts the campaign over: ' || (me->'unlocked')::text;
end $$;
insert into auth.users (id, raw_user_meta_data) values ('f9f9f9f9-0022-4000-8000-000000000003', '{"name":"SeasonRook"}');
select as_user('f9f9f9f9-0022-4000-8000-000000000003');
do $$ declare me jsonb; begin
  me := get_me();
  assert me->'season'->>'name' = 'Season U' and not (me->'unlocked' ? 'actions') and jsonb_array_length(me->'unlocked') = 9, 'born in Season U, gated: ' || (me->'unlocked')::text;
end $$;

-- clean up what the later suites would trip on: a season stays (the fuzz runs with one), the crew goes
update profiles set crew_id = null where id = 'f9f9f9f9-0022-4000-8000-000000000002';
delete from crews where name = 'Season Crew';
update seasons set home_defenders = array[12, 22, 32, 45, 60, 75, 95];

select ' SEASON TEST PASSED';
