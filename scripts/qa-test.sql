-- Tests for 20261005000021_qa (Phase 6), and the guards that keep those gaps shut (the grants are checked in
-- grants-test.sql, which runs first, before the suites add their own test helpers):
--  - list reads stop at 100 rows; a player search treats % and _ as letters
--  - roulette refuses a bet it can never pay before any money moves
--  - not enough money says what you have
-- Run after the other suites (reuses their helpers): scripts/local-db.sh test
\set ON_ERROR_STOP on
\set QUIET on

insert into auth.users (id, raw_user_meta_data) values
  ('f6f6f6f6-0021-4000-8000-000000000001', '{"name":"QaMe"}'),
  ('f6f6f6f6-0021-4000-8000-000000000002', '{"name":"Qa_Pal"}'),
  ('f6f6f6f6-0021-4000-8000-000000000003', '{"name":"QaxPal"}');

select as_user('f6f6f6f6-0021-4000-8000-000000000001');
do $$ declare me uuid := 'f6f6f6f6-0021-4000-8000-000000000001'; pal uuid := 'f6f6f6f6-0021-4000-8000-000000000002'; r jsonb; p profiles; begin
  -- lists: 150 fights and 150 casino rounds, a read asks for a million
  insert into fights (attacker_id, defender_id, winner_id, attacker_dmg, defender_dmg, cash_taken)
    select me, pal, me, 1, 1, 0 from generate_series(1, 150);
  insert into casino_bets (player_id, game, wager, payout) select me, 'slots', 100, 0 from generate_series(1, 150);
  assert jsonb_array_length(get_fights(1000000)) = 100, 'get_fights capped';
  assert jsonb_array_length(get_fights(-5)) = 1, 'get_fights at least one';
  assert jsonb_array_length(get_fights()) = 30, 'get_fights default';
  assert jsonb_array_length(casino_history(1000000)->'recent') = 100, 'casino_history capped';
  assert jsonb_array_length(casino_history(null)->'recent') = 30, 'casino_history default';
  assert jsonb_array_length(find_players('', 1000000)) <= 100, 'find_players capped';

  -- search: _ is an underscore, % is a percent sign
  r := find_players('Qa_P');
  assert jsonb_array_length(r) = 1 and r->0->>'name' = 'Qa_Pal', 'underscore matched itself: ' || r::text;
  assert jsonb_array_length(find_players('%')) = 0, 'a % is not everyone';
  assert jsonb_array_length(find_players('QaxP')) = 1, 'plain search still works';
  assert jsonb_array_length(find_players(null)) >= 0, 'null search answers';

  -- roulette: impossible bets are refused and cost nothing
  update profiles set cash = 5000, jail_until = null, in_hospital = false, health = health_max where id = me;
  perform expect_error($q$select roulette_spin('[{"type":"straight","value":99,"amount":100}]')$q$, 'A number bet is on 0 to 36');
  perform expect_error($q$select roulette_spin('[{"type":"straight","amount":100}]')$q$, 'A number bet is on 0 to 36');
  perform expect_error($q$select roulette_spin('[{"type":"dozen","value":4,"amount":100}]')$q$, 'Pick a dozen from 1 to 3');
  perform expect_error($q$select roulette_spin('[{"type":"column","value":0,"amount":100}]')$q$, 'Pick a column from 1 to 3');
  perform expect_error($q$select roulette_spin('[{"type":"red","amount":100},{"type":"bogus","amount":100}]')$q$, 'Unknown bet type bogus');
  assert (select cash from profiles where id = me) = 5000, 'a refused spin took nothing';
  -- every bet the table offers still spins
  r := roulette_spin('[{"type":"straight","value":0,"amount":100},{"type":"straight","value":36,"amount":100},{"type":"dozen","value":3,"amount":100},{"type":"column","value":1,"amount":100},{"type":"red","amount":100},{"type":"odd","amount":100},{"type":"high","amount":100}]');
  assert (r->>'wager')::int = 700 and jsonb_array_length(r->'bets') = 7, r::text;

  -- not enough money says what you have
  update profiles set cash = 250, bank = 40, diamonds = 3 where id = me;
  perform expect_error('select bank_deposit(300)', 'You have $250 on hand');
  perform expect_error('select bank_withdraw(41)', 'You have $40 in the bank');
  perform expect_error(format('select send_cash(%L, 251)', pal), 'You have $250 on hand');
  perform expect_error(format('select send_diamonds(%L, 4)', pal), 'You have 3 diamonds');
  perform expect_error('select bank_deposit(0)', 'Invalid amount');
  perform expect_error(format('select send_cash(%L, -1)', pal), 'Invalid amount');
  select * into p from profiles where id = me;
  assert p.cash = 250 and p.bank = 40 and p.diamonds = 3, 'nothing moved';
  -- and exactly enough still goes through
  perform bank_deposit(250); perform bank_withdraw(290);
  assert (select cash from profiles where id = me) = 290, 'deposit then withdraw all';
end $$;

delete from fights where attacker_id = 'f6f6f6f6-0021-4000-8000-000000000001';
delete from casino_bets where player_id = 'f6f6f6f6-0021-4000-8000-000000000001';

select ' QA TESTS PASSED';
