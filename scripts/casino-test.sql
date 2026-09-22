-- Casino smoke test (house games + a scripted 3-player poker hand). Run: scripts/local-db.sh test
\set ON_ERROR_STOP on
\set QUIET on

insert into auth.users (id, raw_user_meta_data) values
  ('33333333-3333-3333-3333-333333333333', '{"name":"Ace"}'),
  ('44444444-4444-4444-4444-444444444444', '{"name":"Bettor"}'),
  ('55555555-5555-5555-5555-555555555555', '{"name":"Chips"}')
on conflict do nothing;

create or replace function as_user(u text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', u)::text, false) $$;
create or replace function expect_error(sql text, needle text) returns void language plpgsql as $$
begin
  execute sql; raise exception 'expected error containing "%" from: %', needle, sql;
exception when others then
  if sqlerrm not like '%' || needle || '%' then raise exception 'wrong error: % (wanted "%")', sqlerrm, needle; end if;
end $$;
-- 'As' -> card int (rank*4 + suit)
create or replace function card(t text) returns integer language sql immutable as $$
  select (position(substr(t, 1, 1) in '23456789TJQKA') - 1) * 4 + position(substr(t, 2, 1) in 'shdc') - 1 $$;
create or replace function cards(variadic t text[]) returns integer[] language sql immutable as $$
  select array_agg(card(x) order by ord) from unnest(t) with ordinality as u(x, ord) $$;

-- ---------------------------------------------------------------------------
-- Hand evaluator
-- ---------------------------------------------------------------------------
do $$ begin
  assert _hand_name(_eval7(cards('As','Ks','Qs','Js','Ts','2d','3c'))) = 'Straight flush';
  assert _hand_name(_eval7(cards('9s','9h','9d','9c','Ts','2d','3c'))) = 'Four of a kind';
  assert _hand_name(_eval7(cards('9s','9h','9d','Tc','Ts','2d','3c'))) = 'Full house';
  assert _hand_name(_eval7(cards('2s','7s','9s','Js','Ks','2d','3c'))) = 'Flush';
  assert _hand_name(_eval7(cards('As','2h','3d','4c','5s','9d','Kc'))) = 'Straight';
  assert _hand_name(_eval7(cards('9s','9h','9d','Tc','Qs','2d','3c'))) = 'Three of a kind';
  assert _hand_name(_eval7(cards('9s','9h','Td','Tc','Qs','2d','3c'))) = 'Two pair';
  assert _hand_name(_eval7(cards('9s','9h','Jd','Tc','Qs','2d','3c'))) = 'Pair';
  assert _hand_name(_eval7(cards('9s','8h','Jd','Tc','Qs','2d','3c'))) = 'Straight', 'broadway-ish 8-Q';
  assert _hand_name(_eval7(cards('9s','7h','Jd','Tc','Qs','2d','3c'))) = 'High card';
  -- ordering
  assert _eval7(cards('As','Ks','Qs','Js','Ts','2d','3c')) > _eval7(cards('9s','9h','9d','9c','Ts','2d','3c')), 'SF > quads';
  assert _eval7(cards('9s','9h','9d','9c','Ts','2d','3c')) > _eval7(cards('9s','9h','9d','Tc','Ts','2d','3c')), 'quads > boat';
  assert _eval7(cards('9s','9h','9d','Tc','Ts','2d','3c')) > _eval7(cards('2s','7s','9s','Js','Ks','2d','3c')), 'boat > flush';
  assert _eval7(cards('2s','7s','9s','Js','Ks','2d','3c')) > _eval7(cards('As','2h','3d','4c','5s','9d','Kc')), 'flush > straight';
  assert _eval7(cards('6s','2h','3d','4c','5s','9d','Kc')) > _eval7(cards('As','2h','3d','4c','5s','9d','Kc')), '6-high straight > wheel';
  assert _eval7(cards('As','Ah','Kd','Kc','2s','3d','4c')) > _eval7(cards('As','Ah','Qd','Qc','Ks','3d','4c')), 'AAKK > AAQQ';
  assert _eval7(cards('As','Ah','Kd','Kc','Qs','3d','4c')) > _eval7(cards('As','Ah','Kd','Kc','Js','3d','4c')), 'two pair kicker';
  assert _eval7(cards('As','Ah','Jd','7c','5s','3d','2c')) > _eval7(cards('As','Ah','Td','9c','8s','3d','2c')), 'pair kicker';
  assert _eval7(cards('9s','9h','9d','Tc','Ts','Jd','Jc')) > _eval7(cards('9s','9h','9d','Tc','Ts','Qd','2c')), 'boat picks best pair';
  assert _eval7(cards('9s','9h','9d','Tc','Th','Td','2c')) = _eval7(cards('Ts','Th','Td','9c','9h','2d','3c')), 'trips over trips = TTT99';
  assert _eval7(cards('As','Ks','9s','7s','3s','2h','2d')) > _eval7(cards('As','Ks','9s','7s','2s','3h','3d')), 'flush 5th card';
  assert _eval7(cards('As','Kh','9d','7c','3s','2h','5d')) = _eval7(cards('Ad','Kc','9h','7s','5c','2s','4h')), 'high card ties on 5';
end $$;

-- ---------------------------------------------------------------------------
-- House games
-- ---------------------------------------------------------------------------
select as_user('33333333-3333-3333-3333-333333333333');
do $$ declare me jsonb; r jsonb; cash0 bigint; n int; expect bigint; i int; st jsonb; bets bigint; begin
  perform get_me();
  update profiles set cash = 1000000 where id = auth.uid();

  -- limits & lockouts
  perform expect_error('select slots_spin(50)', 'Bets are');
  perform expect_error('select slots_spin(600000)', 'Bets are');
  perform expect_error('select slots_spin(null)', 'Missing');
  update profiles set jail_until = now() + interval '1 hour' where id = auth.uid();
  perform expect_error('select slots_spin(100)', 'No gambling');
  update profiles set jail_until = null where id = auth.uid();

  -- slots: every spin balances
  for i in 1..200 loop
    cash0 := (select cash from profiles where id = auth.uid());
    r := slots_spin(1000);
    assert jsonb_array_length(r->'reels') = 3;
    assert (select cash from profiles where id = auth.uid()) = cash0 + (r->>'net')::bigint, 'slots cash: ' || r::text;
    assert (r->>'payout')::bigint = (1000 * (r->>'mult')::numeric)::bigint;
  end loop;
  assert (select count(*) from casino_bets where player_id = auth.uid() and game = 'slots') = 200;

  -- roulette: payouts follow the number
  perform expect_error('select roulette_spin(''[]''::jsonb)', 'Place a bet');
  perform expect_error('select roulette_spin(''[{"type":"red","amount":10}]''::jsonb)', 'at least');
  perform expect_error('select roulette_spin(''[{"type":"purple","amount":100}]''::jsonb)', 'Unknown bet type');
  perform expect_error('select roulette_spin(''[{"type":"red","amount":300000},{"type":"black","amount":300000}]''::jsonb)', 'Table max');
  for i in 1..60 loop
    cash0 := (select cash from profiles where id = auth.uid());
    r := roulette_spin('[{"type":"red","amount":500},{"type":"straight","value":17,"amount":100},{"type":"dozen","value":2,"amount":200},{"type":"column","value":3,"amount":100},{"type":"even","amount":100}]'::jsonb);
    n := (r->>'number')::int;
    expect := (case when n in (1,3,5,7,9,12,14,16,18,19,21,23,25,27,30,32,34,36) then 1000 else 0 end)
            + (case when n = 17 then 3600 else 0 end)
            + (case when n between 13 and 24 then 600 else 0 end)
            + (case when n <> 0 and n % 3 = 0 then 300 else 0 end)
            + (case when n <> 0 and n % 2 = 0 then 200 else 0 end);
    assert (r->>'payout')::bigint = expect, format('roulette n=%s payout=%s expected=%s', n, r->>'payout', expect);
    assert (r->>'wager')::bigint = 1000;
    assert (select cash from profiles where id = auth.uid()) = cash0 - 1000 + expect;
  end loop;

  -- craps
  perform expect_error('select craps_roll()', 'Place a bet');
  perform expect_error('select craps_bet(''hardway'', 100)', 'Unknown bet');
  cash0 := (select cash from profiles where id = auth.uid());
  st := craps_bet('pass', 1000);
  assert (st->'bets'->>'pass')::bigint = 1000;
  st := craps_bet('pass', 500);
  assert (st->'bets'->>'pass')::bigint = 1500, 'pass bets add up';
  st := craps_bet('field', 300);
  assert (select cash from profiles where id = auth.uid()) = cash0 - 1800;
  st := craps_clear();
  assert (st->'bets') = '{}'::jsonb and (select cash from profiles where id = auth.uid()) = cash0, 'clear refunds';
  -- play until a point is established, then check line bets are frozen
  for i in 1..200 loop
    if (craps_state()->>'point') is not null then exit; end if;
    if coalesce((craps_state()->'bets'->>'pass')::bigint, 0) = 0 then perform craps_bet('pass', 1000); end if;
    cash0 := (select cash from profiles where id = auth.uid());
    bets := (select coalesce(sum(value::bigint), 0) from jsonb_each_text(craps_state()->'bets'));
    r := craps_roll();
    assert (r->>'sum')::int between 2 and 12;
    assert (select cash from profiles where id = auth.uid()) = cash0 + (r->>'payout')::bigint, 'craps cash: ' || r::text;
    -- a come-out 7/11 pays 2:1, craps loses, anything else sets the point and keeps the bet
    if (r->>'sum')::int in (7, 11) then assert (r->>'payout')::bigint = 2000, 'pass wins: ' || r::text;
    elsif (r->>'sum')::int in (2, 3, 12) then assert (r->>'payout')::bigint = 0;
    else assert (r->>'point')::int = (r->>'sum')::int and (r->'bets'->>'pass')::bigint = 1000; end if;
  end loop;
  assert (craps_state()->>'point') is not null, 'point established within 200 rolls';
  perform expect_error('select craps_bet(''pass'', 100)', 'only before the point');
  st := craps_bet('place6', 600);
  st := craps_clear();
  assert (st->'bets'->>'pass')::bigint = 1000 and (st->'bets'->>'place6') is null, 'clear keeps the line bet once the point is on';
  for i in 1..200 loop exit when (craps_state()->>'point') is null; r := craps_roll(); end loop;
  assert (craps_state()->>'point') is null, 'point resolved';

  -- blackjack
  perform expect_error('select blackjack_action(''hit'')', 'No hand');
  assert blackjack_state()->>'status' = 'none';
  for i in 1..40 loop
    cash0 := (select cash from profiles where id = auth.uid());
    r := blackjack_deal(1000);
    assert jsonb_array_length(r->'player') = 2;
    if r->>'status' = 'playing' then
      assert (r->>'dealer_hidden')::boolean and jsonb_array_length(r->'dealer') = 1, 'hole card hidden';
      perform expect_error('select blackjack_deal(1000)', 'Finish the hand');
      if i % 3 = 0 and (r->>'can_double')::boolean then
        r := blackjack_action('double');
        assert (r->>'wager')::bigint = 2000;
      else
        while r->>'status' = 'playing' and (r->>'player_total')::int < 17 loop r := blackjack_action('hit'); end loop;
        if r->>'status' = 'playing' then r := blackjack_action('stand'); end if;
      end if;
    end if;
    assert r->>'status' = 'done' and not (r->>'dealer_hidden')::boolean and (r->>'dealer_total')::int >= 17 or (r->>'player_total')::int > 21, 'dealer finished: ' || r::text;
    assert (select cash from profiles where id = auth.uid()) = cash0 - (r->>'wager')::bigint + (r->'result'->>'payout')::bigint, 'bj cash: ' || r::text;
    if r->'result'->>'outcome' = 'blackjack' then assert (r->'result'->>'payout')::bigint = 2500; end if;
    if r->'result'->>'outcome' = 'push' then assert (r->>'player_total')::int = (r->>'dealer_total')::int; end if;
    if r->'result'->>'outcome' = 'win' then assert (r->>'player_total')::int > (r->>'dealer_total')::int and (r->>'dealer_total')::int <= 21; end if;
  end loop;
  assert blackjack_state()->>'status' = 'done';

  -- big wins add heat; history
  update profiles set heat = 0 where id = auth.uid();
  perform _casino_settle(auth.uid(), 'slots', 1000, 50000, '{}'::jsonb);
  assert (select heat from profiles where id = auth.uid()) = 2, 'big win heat';
  r := casino_history(5);
  assert jsonb_array_length(r->'recent') = 5 and (r->>'net') is not null;
  assert (select sum(amount) from accolade_events where player_id = auth.uid() and kind = 'gambler') = (r->>'net')::bigint, 'gambler accolade = net';
end $$;

-- ---------------------------------------------------------------------------
-- Poker: lobby, seating, a scripted 3-way all-in with side pots, timeouts, chat
-- ---------------------------------------------------------------------------
do $$ declare A text := '33333333-3333-3333-3333-333333333333'; B text := '44444444-4444-4444-4444-444444444444'; C text := '55555555-5555-5555-5555-555555555555';
  r jsonb; st jsonb; hid bigint; tid int := 1; s jsonb; begin
  perform as_user(B); perform get_me(); perform as_user(C); perform get_me();
  update profiles set cash = 1000000 where id in (A::uuid, B::uuid, C::uuid);

  perform as_user(A);
  r := poker_lobby();
  assert jsonb_array_length(r) = 7, 'seven tables';
  assert r->0->>'big_blind' = '2000' and r->6->>'big_blind' = '500000';
  perform expect_error('select poker_join(1, 0, 1000)', 'Buy in for');
  perform expect_error('select poker_join(1, 9, 100000)', 'Bad seat');
  perform expect_error('select poker_join(99, 0, 100000)', 'No such table');
  perform expect_error('select poker_act(''check'')', 'not at a table');
  st := poker_join(tid, 0, 100000);
  assert (select cash from profiles where id = A::uuid) = 900000;
  assert st->'hand' is null or st->'hand' = 'null'::jsonb, 'no hand alone: ' || st::text;
  assert (st->'me'->>'stack')::bigint = 100000;
  perform expect_error('select poker_join(2, 0, 100000)', 'already seated');
  assert (poker_lobby()->0->>'mine')::boolean;

  perform as_user(B);
  perform expect_error('select poker_join(1, 0, 100000)', 'seat is taken');
  st := poker_join(tid, 1, 100000);
  assert st->'hand'->>'stage' = 'preflop', 'hand starts when 2 are seated: ' || st::text;
  assert (st->'hand'->>'dealer')::int = 0 and (st->'hand'->>'to_act')::int = 0, 'heads-up: dealer posts sb and acts first';
  assert (st->'hand'->>'pot')::bigint = 3000;
  perform expect_error('select poker_act(''check'')', 'not your turn');
  perform as_user(C);
  st := poker_join(tid, 2, 200000);
  assert st->'hand'->'my' is null or st->'hand'->'my' = 'null'::jsonb, 'late joiner waits for the next hand';
  -- A folds the first hand: B wins the blinds with no rake (no flop)
  perform as_user(A);
  st := poker_act('fold');
  assert (st->'hand'->>'finished')::boolean and (st->'hand'->'result'->>'fold_out')::boolean;
  assert (st->'hand'->'result'->'won'->>'1')::bigint = 3000 and (st->'hand'->'result'->>'rake')::bigint = 0, st::text;
  assert (select stack from poker_seats where table_id = tid and seat = 1) = 101000;
  assert (select stack from poker_seats where table_id = tid and seat = 0) = 99000;

  -- next hand: skip the pause, set up stacks 100k / 50k / 200k
  update poker_seats set stack = case seat when 0 then 100000 when 1 then 50000 else 200000 end where table_id = tid;
  update poker_hands set finished_at = now() - interval '1 minute' where table_id = tid;
  st := poker_state(tid);
  assert st->'hand'->>'stage' = 'preflop' and (st->'hand'->>'no')::int = 2, st::text;
  assert (st->'hand'->>'dealer')::int = 1 and (st->'hand'->>'to_act')::int = 1, '3-handed: dealer 1, sb 2, bb 0, dealer acts first';
  hid := (st->'hand'->>'id')::bigint;
  assert (select count(*) from poker_hand_players where hand_id = hid) = 3;
  -- rig the cards: A KK, B AA, C 22; board 3h 7d 9c Js 4s → B wins the main pot, A the side pot
  update poker_hand_players set hole = cards('Kh','Kd') where hand_id = hid and seat = 0;
  update poker_hand_players set hole = cards('Ah','Ad') where hand_id = hid and seat = 1;
  update poker_hand_players set hole = cards('2h','2d') where hand_id = hid and seat = 2;
  update poker_hands set deck = cards('3h','7d','9c','Js','4s','8h','8d','Tc','Qd') where id = hid;
  -- B shoves 50k
  perform as_user(B);
  perform expect_error('select poker_act(''raise'', 3000)', 'Minimum raise');
  perform expect_error('select poker_act(''raise'', 60000)', 'only have');
  st := poker_act('raise', 50000);
  assert (st->'hand'->>'to_act')::int = 2 and (st->'hand'->>'current_bet')::bigint = 50000;
  assert (st->'hand'->>'min_raise')::bigint = 48000;
  -- C calls, A shoves 100k, C calls again → everyone in, board runs out
  perform as_user(C);
  st := poker_act('call');
  assert (st->'hand'->>'to_act')::int = 0 and (st->'hand'->'my'->>'street_bet')::bigint = 50000;
  perform as_user(A);
  perform expect_error('select poker_act(''check'')', 'need to call');
  st := poker_act('raise', 100000);
  assert (st->'hand'->>'to_act')::int = 2 and (st->'hand'->'my'->>'all_in')::boolean;
  perform as_user(C);
  assert (poker_state(tid)->'hand'->'my'->>'to_call')::bigint = 50000;
  st := poker_act('call');
  assert (st->'hand'->>'finished')::boolean and st->'hand'->>'stage' = 'done', st::text;
  assert not (st->'hand'->'result'->>'fold_out')::boolean;
  assert st->'hand'->'board' = '["3h","7d","9c","Js","4s"]'::jsonb, 'board ran out from the rigged deck: ' || (st->'hand'->'board')::text;
  assert (st->'hand'->'result'->>'rake')::bigint = 6000, 'rake capped at 3bb';
  assert (st->'hand'->'result'->'won'->>'1')::bigint = 144000, 'main pot 150k - 6k rake to B: ' || (st->'hand'->'result')::text;
  assert (st->'hand'->'result'->'won'->>'0')::bigint = 100000, 'side pot 100k to A';
  assert st->'hand'->'result'->'won'->>'2' is null, 'C wins nothing';
  assert (select stack from poker_seats where table_id = tid and seat = 0) = 100000;
  assert (select stack from poker_seats where table_id = tid and seat = 1) = 144000;
  assert (select stack from poker_seats where table_id = tid and seat = 2) = 100000;
  assert st->'hand'->'result'->'hands'->>'1' = 'Pair';
  -- showdown reveals everyone's cards, and hole cards are private otherwise
  s := (select x from jsonb_array_elements(st->'seats') x where (x->>'seat')::int = 1);
  assert s->'hole' = '["Ah","Ad"]'::jsonb and s->>'hand_name' = 'Pair', 'showdown shows B''s cards: ' || s::text;
  assert (select count(*) from casino_bets where game = 'poker' and detail->>'hand' = hid::text) = 3;
  assert (select payout - wager from casino_bets where game = 'poker' and detail->>'hand' = hid::text and player_id = C::uuid) = -100000;

  -- next hand: rig a timeout. Skip pause; nobody busted so all three play
  update poker_hands set finished_at = now() - interval '1 minute' where table_id = tid;
  st := poker_state(tid);
  assert (st->'hand'->>'no')::int = 3 and (st->'hand'->>'dealer')::int = 2 and (st->'hand'->>'to_act')::int = 2, st::text;
  hid := (st->'hand'->>'id')::bigint;
  -- private: C can't see A's hole cards mid-hand
  s := (select x from jsonb_array_elements(st->'seats') x where (x->>'seat')::int = 0);
  assert s->'hole' is null or s->'hole' = 'null'::jsonb, 'hole cards hidden mid-hand';
  update poker_hands set deadline = now() - interval '1 second' where id = hid;
  perform as_user(A);
  st := poker_state(tid);   -- the poll times C out → auto-fold (C owes 2000 facing the bb)
  assert (st->'hand'->>'to_act')::int = 0 and (select folded from poker_hand_players where hand_id = hid and seat = 2), 'C auto-folded: ' || st::text;
  assert (select missed from poker_seats where table_id = tid and seat = 2) = 1;
  st := poker_act('call');   -- A (sb) completes
  assert (st->'hand'->>'to_act')::int = 1;
  update poker_hands set deadline = now() - interval '1 second' where id = hid;
  st := poker_state(tid);   -- B (bb) times out with nothing to call → auto-check → flop
  assert st->'hand'->>'stage' = 'flop' and jsonb_array_length(st->'hand'->'board') = 3, st::text;
  assert (st->'hand'->>'to_act')::int = 0, 'sb acts first postflop';
  st := poker_act('bet', 4000);
  update poker_hands set deadline = now() - interval '1 second' where id = hid;
  st := poker_state(tid);   -- B times out facing a bet → folds → A wins; the flop was seen so it's raked
  assert (st->'hand'->>'finished')::boolean and (st->'hand'->'result'->'won'->>'0')::bigint = 8000 - 400, 'pot 8000 minus 5% rake: ' || (st->'hand'->'result')::text;
  assert (select missed from poker_seats where table_id = tid and seat = 1) = 2, 'B missed twice';
  assert (select stack from poker_seats where table_id = tid and seat = 0) = 101600;

  -- hand 4: A folds, B times out a third time → sits out; C takes the blinds
  update poker_hands set finished_at = now() - interval '1 minute' where table_id = tid;
  st := poker_state(tid);
  assert (st->'hand'->>'no')::int = 4 and (st->'hand'->>'dealer')::int = 0 and (st->'hand'->>'to_act')::int = 0, st::text;
  hid := (st->'hand'->>'id')::bigint;
  st := poker_act('fold');
  assert (st->'hand'->>'to_act')::int = 1;
  update poker_hands set deadline = now() - interval '1 second' where id = hid;
  st := poker_state(tid);
  assert (st->'hand'->>'finished')::boolean and (st->'hand'->'result'->'won'->>'2')::bigint = 3000, st::text;
  assert (select sitting_out from poker_seats where table_id = tid and seat = 1), 'B sat out after 3 misses';
  assert (select stack from poker_seats where table_id = tid and seat = 2) = 101000;

  -- C cashes out between hands
  perform as_user(C);
  r := poker_leave();
  assert (r->>'cashed_out')::bigint = 101000, r::text;
  assert (select cash from profiles where id = C::uuid) = 901000;
  assert not exists (select 1 from poker_seats where player_id = C::uuid);
  perform expect_error('select poker_leave()', 'not at a table');

  -- table chat: seated players only
  perform as_user(A);
  perform send_message('table:1', 'nice hand');
  perform expect_error('select send_message(''table:2'', ''x'')', 'cannot post');
  assert jsonb_array_length(get_messages('table:1')) >= 1;
  perform as_user(C);
  perform expect_error('select send_message(''table:1'', ''x'')', 'cannot post');

  -- rebuy tops up, capped at the max
  perform as_user(A);
  perform expect_error('select poker_join(1, 0, 400000)', 'exceed');
  st := poker_join(tid, 0, 50000);
  assert (st->'me'->>'stack')::bigint = 151600 and (select cash from profiles where id = A::uuid) = 850000;

  -- hand 5: B sits back in; A leaves mid-hand → folded out, B takes it
  perform as_user(B);
  st := poker_sit_in();
  assert not (select sitting_out from poker_seats where table_id = tid and seat = 1);
  update poker_hands set finished_at = now() - interval '1 minute' where table_id = tid;
  st := poker_state(tid);
  assert (st->'hand'->>'no')::int = 5 and (st->'hand'->>'to_act')::int = 1, st::text;
  perform as_user(A);
  r := poker_leave();
  assert (r->>'cashed_out')::bigint = 151600 - 2000, r::text;
  perform as_user(B);
  st := poker_state(tid);
  assert (st->'hand'->>'finished')::boolean and (st->'hand'->'result'->'won'->>'1')::bigint = 3000, 'A leaving ended the hand: ' || st::text;
  r := poker_leave();
  assert (r->>'cashed_out')::bigint = 141000 - 1000 + 3000, r::text;
  assert (select count(*) from poker_seats) = 0;
  assert (select sum(cash) from profiles where id in (A::uuid, B::uuid, C::uuid))
       = 3000000 - (select coalesce(sum((result->>'rake')::bigint), 0) from poker_hands where table_id = tid)
                 - 50000, 'chips conserved (50k = the rigged stacks before hand 2 removed 400k-350k)';
end $$;

\echo 'CASINO TEST PASSED'
