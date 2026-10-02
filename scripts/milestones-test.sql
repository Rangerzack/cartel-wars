-- Tests for milestones round 2 (20261004000017_milestones): 30 diamonds every 250 actions, every 500 fight wins, every
-- 500 turf attacks and every $10M wagered at the casino, on top of the lifetime ladders (now with total fights and
-- casino wagered), each payout written to the feed; the turf and casino counts kept by triggers; bots never paid.
-- Run after the other suites (reuses their helpers): scripts/local-db.sh test
\set ON_ERROR_STOP on
\set QUIET on

insert into auth.users (id, raw_user_meta_data) values
  ('e1e1e1e1-0017-4000-8000-000000000001', '{"name":"Mila"}');

select as_user('e1e1e1e1-0017-4000-8000-000000000001');
do $$ declare u uuid := auth.uid(); d0 int; a jsonb; blk int; bot uuid; begin
  perform get_me();
  delete from milestones where player_id = u; delete from milestone_repeats where player_id = u; delete from activity where player_id = u;
  update profiles set actions_done = 0, fights_won = 0, fights_lost = 0, turf_attacks = 0, casino_wagered = 0, diamonds = 0 where id = u;

  -- 249 actions: the 50/100 ladder steps, no repeat yet; 250: the 250 ladder step and the first repeat
  update profiles set actions_done = 249 where id = u; perform _award_milestones(u);
  assert (select diamonds from profiles where id = u) = 5 + 10, 'ladder only below 250';
  update profiles set actions_done = 250 where id = u; perform _award_milestones(u);
  assert (select diamonds from profiles where id = u) = 15 + 15 + 30, 'ladder 250 and the first repeat: ' || (select diamonds from profiles where id = u);
  assert (select paid from milestone_repeats where player_id = u and key = 'every_actions') = 1;
  a := (select data from activity where player_id = u and kind = 'milestone' order by id desc limit 1);
  assert a->>'what' = 'actions' and (a->>'n')::int = 250 and (a->>'diamonds')::int = 45, 'one feed line per kind: ' || a::text;
  -- 1,010 actions: three more repeats (500, 750, 1000) and the 500 and 1k ladder steps, paid once
  update profiles set actions_done = 1010 where id = u; perform _award_milestones(u); perform _award_milestones(u);
  assert (select paid from milestone_repeats where player_id = u and key = 'every_actions') = 4;
  assert (select diamonds from profiles where id = u) = 60 + 3 * 30 + 25 + 50, 'three repeats and two ladder steps';

  -- fights: wins repeat every 500; every fight, won or lost, climbs the total-fights ladder
  d0 := (select diamonds from profiles where id = u);
  update profiles set fights_won = 499, fights_lost = 2 where id = u; perform _award_milestones(u);
  assert (select diamonds from profiles where id = u) = d0 + 5 + 20 + 25 + 5 + 15, 'win ladder to 250 and fights ladder to 500, no repeat';
  update profiles set fights_won = 500 where id = u; perform _award_milestones(u);
  assert (select diamonds from profiles where id = u) = d0 + 70 + 30 + 30, 'the 500-win step and the first win repeat';

  -- turf: every attack on a block counts (the trigger on territory_log), 500 of them pay 30
  d0 := (select diamonds from profiles where id = u);
  blk := (select id from blocks order by id limit 1);
  update profiles set turf_attacks = 499 where id = u;
  insert into territory_log (block_id, attacker_id, success, attack, resistance) values (blk, u, false, 10, 500);
  assert (select turf_attacks from profiles where id = u) = 500, 'the trigger counts the attack';
  assert (select diamonds from profiles where id = u) = d0 + 30, 'turf repeat at 500';

  -- casino: every bet's wager counts (the trigger on casino_bets): $10M pays the repeat and the ladder to $10M
  d0 := (select diamonds from profiles where id = u);
  insert into casino_bets (player_id, game, wager, payout) values (u, 'slots', 9999999, 0);
  assert (select casino_wagered from profiles where id = u) = 9999999;
  assert (select diamonds from profiles where id = u) = d0 + 5 + 10, 'ladder to $5M, no repeat yet';
  insert into casino_bets (player_id, game, wager, payout) values (u, 'poker', 1, 2);
  assert (select diamonds from profiles where id = u) = d0 + 15 + 20 + 30, '$10M: the ladder step and the first repeat';
  a := (select data from activity where player_id = u and kind = 'milestone' order by id desc limit 1);
  assert a->>'what' = 'wagered' and (a->>'n')::bigint = 10000000 and (a->>'diamonds')::int = 50, 'casino feed line: ' || a::text;

  -- get_me carries the new counts; the catalog has every step
  assert (get_me()->>'turf_attacks')::int = 500 and (get_me()->>'casino_wagered')::bigint = 10000000;
  assert (select count(*) from jsonb_array_elements(get_catalog()->'milestones') m where (m->>'repeat')::boolean) = 4;

  -- bots are never paid
  bot := (select id from profiles where is_bot limit 1);
  if bot is not null then
    d0 := (select diamonds from profiles where id = bot);
    update profiles set actions_done = 5000 where id = bot; perform _award_milestones(bot);
    assert (select diamonds from profiles where id = bot) = d0, 'bots get nothing';
  end if;

  assert not has_function_privilege('authenticated', '_milestone_total(profiles,text)', 'execute')
     and not has_function_privilege('authenticated', '_turf_counted()', 'execute')
     and not has_table_privilege('authenticated', 'milestone_repeats', 'select');
end $$;

select ' MILESTONES TEST PASSED';
