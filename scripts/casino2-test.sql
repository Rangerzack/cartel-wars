-- Tests for the casino upgrade: craps odds / place numbers / hardways / come-out rules, blackjack splits.
-- Run after the other suites: scripts/local-db.sh test
\set ON_ERROR_STOP on
\set QUIET on

insert into auth.users (id, raw_user_meta_data) values ('d1111111-1111-1111-1111-111111111111', '{"name":"Ace Rothstein"}');
select as_user('d1111111-1111-1111-1111-111111111111');

-- Craps ------------------------------------------------------------------------------------------------
do $$ declare me uuid := auth.uid(); r jsonb; c0 bigint; cash bigint;
begin
  perform get_me();
  update profiles set cash = 10000000 where id = me;
  cash := (select p.cash from profiles p where p.id = me);

  -- place bets and hardways are off on the come-out; the puck is set by the dice even with no line bet
  perform craps_bet('place6', 600); perform craps_bet('hard8', 100);
  r := _craps_roll(me, 3, 4);                        -- come-out 7: nothing on the felt is working
  assert (r->'bets'->>'place6')::bigint = 600 and (r->'bets'->>'hard8')::bigint = 100 and (r->>'payout')::bigint = 0, 'off on the come-out: ' || r::text;
  assert r->>'event' = 'natural' and (r->>'point') is null;
  r := _craps_roll(me, 2, 2);                        -- point 4 (no line bet needed)
  assert (r->>'point')::int = 4 and r->>'event' = 'point', 'puck on 4: ' || r::text;
  c0 := (select p.cash from profiles p where p.id = me);
  r := _craps_roll(me, 3, 3);                        -- 6: place 6 pays 7:6 and stays up
  assert (r->>'payout')::bigint = 700 and (r->'bets'->>'place6')::bigint = 600, 'place 6 paid and stays: ' || r::text;
  assert (select p.cash from profiles p where p.id = me) = c0 + 700;
  r := _craps_roll(me, 4, 4);                        -- hard 8: pays 9:1, stays up
  assert (r->>'payout')::bigint = 900 and (r->'bets'->>'hard8')::bigint = 100, 'hard 8: ' || r::text;
  r := _craps_roll(me, 5, 3);                        -- easy 8: hard 8 loses, place 6 stays
  assert (r->'bets'->>'hard8') is null and (r->'bets'->>'place6')::bigint = 600, 'easy 8 kills the hardway: ' || r::text;
  r := _craps_roll(me, 5, 2);                        -- seven out: place 6 loses, puck off
  assert (r->'bets') = '{}'::jsonb and (r->>'point') is null and r->>'event' = 'seven_out', 'seven out: ' || r::text;
  assert jsonb_array_length(r->'history') = 6 and (r->'history'->0->>'sum')::int = 7, 'history newest first: ' || (r->'history')::text;

  -- odds: 3-4-5x behind pass, paid at true odds
  perform expect_error('select craps_bet(''pass_odds'', 100)', 'once a point is set');
  perform craps_bet('pass', 1000);
  r := _craps_roll(me, 4, 2);                        -- point 6
  assert (r->'odds_max'->>'pass_odds')::bigint = 5000, '5x on 6: ' || r::text;
  perform expect_error('select craps_bet(''pass_odds'', 5100)', 'Odds max');
  perform expect_error('select craps_bet(''dont_odds'', 600)', 'Don''t Pass first');
  perform expect_error('select craps_bet(''pass'', 100)', 'only before the point');
  perform craps_bet('pass_odds', 5000);
  c0 := (select p.cash from profiles p where p.id = me);
  r := _craps_roll(me, 5, 1);                        -- point made: pass 1:1, odds 6:5
  assert (r->>'payout')::bigint = 2000 + 5000 + 6000, 'pass + odds on 6: ' || r::text;
  assert (select p.cash from profiles p where p.id = me) = c0 + 13000 and (r->'bets') = '{}'::jsonb;

  -- lay odds behind don't pass: 6x, pays 1:2 on 4/10
  perform craps_bet('dont', 1000);
  r := _craps_roll(me, 3, 1);                        -- point 4
  assert (r->'odds_max'->>'dont_odds')::bigint = 6000;
  perform craps_bet('dont_odds', 6000);
  -- odds can come down; the don't pass (contract once the point is on) stays
  r := craps_clear();
  assert (r->'bets'->>'dont')::bigint = 1000 and (r->'bets'->>'dont_odds') is null, 'odds come down: ' || r::text;
  perform craps_bet('dont_odds', 6000);
  r := _craps_roll(me, 6, 1);                        -- seven out: don't wins 1:1, lay pays 3000
  assert (r->>'payout')::bigint = 2000 + 6000 + 3000, 'don''t + lay: ' || r::text;

  -- place 4/5/9/10 pay 9:5 and 7:5; field and props unchanged
  perform craps_bet('place5', 500); perform craps_bet('place10', 500); perform craps_bet('field', 100);
  r := _craps_roll(me, 4, 5);                        -- come-out 9: field wins 1:1, place bets off; point 9
  assert (r->>'payout')::bigint = 200 and (r->>'point')::int = 9, 'field on the come-out: ' || r::text;
  r := _craps_roll(me, 4, 1);                        -- 5: place 5 pays 7:5
  assert (r->>'payout')::bigint = 700, 'place 5: ' || r::text;
  r := _craps_roll(me, 6, 4);                        -- 10: place 10 pays 9:5
  assert (r->>'payout')::bigint = 900, 'place 10: ' || r::text;
  r := craps_clear();
  assert (r->'bets') = '{}'::jsonb;
  -- table max still applies to everything but odds
  perform expect_error('select craps_bet(''hard6'', 600000)', 'Bets are');
  assert (select sum(payout) from casino_bets where player_id = me and game = 'craps') > 0;
end $$;

-- Blackjack splits (loaded shoe) ----------------------------------------------------------------------
-- cards: rank*4 + suit, rank 0=2 … 6=8 … 8=T … 11=K, 12=A
do $$ declare me uuid := auth.uid(); r jsonb; c0 bigint;
begin
  update profiles set cash = 1000000 where id = me;
  -- a pair of eights vs dealer K-7; shoe: T, 3, T
  insert into blackjack_games (player_id, shoe, player, dealer, wager, status, hands, active)
  values (me, array[32, 4, 33, 40, 41, 42], array[24, 25], array[44, 20], 1000, 'playing',
          jsonb_build_array(jsonb_build_object('cards', jsonb_build_array(24, 25), 'bet', 1000, 'doubled', false, 'split', false, 'aces', false, 'done', false)), 0)
  on conflict (player_id) do update set shoe = excluded.shoe, player = excluded.player, dealer = excluded.dealer, wager = 1000,
    status = 'playing', result = null, hands = excluded.hands, active = 0;
  r := blackjack_state();
  assert (r->>'can_split')::boolean and (r->>'can_double')::boolean, 'eights can split: ' || r::text;
  c0 := (select cash from profiles where id = me);
  r := blackjack_action('split');
  assert jsonb_array_length(r->'hands') = 2 and (r->>'active')::int = 0 and (r->>'wager')::bigint = 2000, 'two hands: ' || r::text;
  assert r->'hands'->0->'cards' = '["8s","Ts"]'::jsonb and r->'hands'->1->'cards' = '["8h","3s"]'::jsonb, 'split cards: ' || r::text;
  assert not (r->>'can_split')::boolean, '18 is not a pair';
  r := blackjack_action('stand');                    -- first hand stands on 18
  assert (r->>'active')::int = 1 and (r->>'can_double')::boolean, 'on to hand two (11), double after split allowed: ' || r::text;
  r := blackjack_action('double');                   -- 11 + T = 21
  assert r->>'status' = 'done', 'round over: ' || r::text;
  assert r->'result'->'hands'->0->>'outcome' = 'win' and r->'result'->'hands'->1->>'outcome' = 'win', 'both beat 17: ' || r::text;
  assert (r->'result'->>'payout')::bigint = 2000 + 4000 and (r->>'wager')::bigint = 3000 and r->'result'->>'outcome' = 'split';
  assert (select cash from profiles where id = me) = c0 - 1000 - 1000 + 6000, 'split + double books: ' || (select cash from profiles where id = me);
  assert (select wager from casino_bets where player_id = me and game = 'blackjack' order by id desc limit 1) = 3000;

  -- split aces: one card each, 21 pays even money (not blackjack)
  update blackjack_games set shoe = array[32, 36, 40, 41], player = array[48, 49], dealer = array[44, 20], wager = 1000, status = 'playing',
    result = null, active = 0,
    hands = jsonb_build_array(jsonb_build_object('cards', jsonb_build_array(48, 49), 'bet', 1000, 'doubled', false, 'split', false, 'aces', false, 'done', false))
   where player_id = me;
  c0 := (select cash from profiles where id = me);
  r := blackjack_action('split');
  assert r->>'status' = 'done' and jsonb_array_length(r->'hands') = 2, 'aces play themselves: ' || r::text;
  assert r->'result'->'hands'->0->>'outcome' = 'win' and (r->'result'->>'payout')::bigint = 4000, 'split-ace 21 pays 1:1: ' || r::text;
  assert (select cash from profiles where id = me) = c0 - 1000 + 4000;

  -- can't hit split aces, can't split non-pairs
  update blackjack_games set shoe = array[48, 20, 20, 20, 20], player = array[48, 49], dealer = array[44, 20], status = 'playing', result = null, active = 0,
    hands = jsonb_build_array(jsonb_build_object('cards', jsonb_build_array(48, 44), 'bet', 1000, 'doubled', false, 'split', false, 'aces', false, 'done', false))
   where player_id = me;
  perform expect_error('select blackjack_action(''split'')', 'only split a pair');
  -- unlike ten-value cards split (K and J)
  update blackjack_games set hands = jsonb_build_array(jsonb_build_object('cards', jsonb_build_array(44, 36), 'bet', 1000, 'doubled', false, 'split', false, 'aces', false, 'done', false)),
    shoe = array[20, 21, 22, 23]
   where player_id = me;
  assert (blackjack_state()->>'can_split')::boolean, 'K and J split';
  c0 := (select cash from profiles where id = me);
  r := blackjack_action('split');                    -- K+7, J+7
  assert r->'hands'->0->'cards' = '["Ks","7s"]'::jsonb and r->'hands'->1->'cards' = '["Js","7h"]'::jsonb, 'tens split: ' || r::text;
  r := blackjack_action('stand');
  r := blackjack_action('stand');
  assert r->>'status' = 'done' and r->'result'->'hands'->0->>'outcome' = 'push' and (r->'result'->>'payout')::bigint = 2000, 'two pushes vs 17: ' || r::text;
  assert (select cash from profiles where id = me) = c0 - 1000 + 2000;
  perform expect_error('select blackjack_action(''hit'')', 'No hand');
end $$;

select 'CASINO 2 TEST PASSED';
