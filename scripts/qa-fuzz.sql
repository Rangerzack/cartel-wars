-- Phase 6 QA: every RPC that takes an amount, a count or a list, called with the values a tampered client could send
-- (negative, zero, huge, unknown codes, malformed JSON, yourself as the target). Each call runs alone; after each one
-- the caller's and the other player's balances, stock and gear must still be whole (no negatives, no money from
-- nowhere). A broken invariant fails, and so does a call that should have been refused but went through.
-- Run on a local database: psql -f scripts/qa-fuzz.sql   (makes its own two players)
\set ON_ERROR_STOP on
\set QUIET on

insert into auth.users (id, raw_user_meta_data) values
  ('f6f6f6f6-0006-4000-8000-000000000001', '{"name":"QaOne"}'),
  ('f6f6f6f6-0006-4000-8000-000000000002', '{"name":"QaTwo"}')
  on conflict do nothing;

create or replace function pg_temp.qa_as(u uuid) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', u)::text, false) $$;

do $$
declare
  one uuid := 'f6f6f6f6-0006-4000-8000-000000000001';
  two uuid := 'f6f6f6f6-0006-4000-8000-000000000002';
  -- [call, should it be refused?]
  calls text[][] := array[
    ['bank_deposit(-500)', 'refuse'], ['bank_deposit(0)', 'refuse'], ['bank_deposit(9223372036854775807)', 'refuse'],
    ['bank_withdraw(-500)', 'refuse'], ['bank_withdraw(0)', 'refuse'], ['bank_withdraw(5000)', 'refuse'],
    ['send_cash(''TWO'', -100)', 'refuse'], ['send_cash(''TWO'', 0)', 'refuse'], ['send_cash(''ONE'', 100)', 'refuse'],
    ['send_cash(''TWO'', 100000)', 'refuse'], ['send_cash(''00000000-0000-4000-8000-000000000000'', 10)', 'refuse'],
    ['send_diamonds(''TWO'', -5)', 'refuse'], ['send_diamonds(''TWO'', 0)', 'refuse'], ['send_diamonds(''ONE'', 1)', 'refuse'],
    ['buy_item(1, -1)', 'refuse'], ['buy_item(1, 0)', 'refuse'], ['buy_item(1, 2147483647)', 'refuse'], ['buy_item(99999, 1)', 'refuse'],
    ['sell_item(1, -1)', 'refuse'], ['sell_item(1, 0)', 'refuse'], ['sell_item(1, 5)', 'refuse'],
    ['buy_hoodlums(''thug'', -1)', 'refuse'], ['buy_hoodlums(''thug'', 0)', 'refuse'], ['buy_hoodlums(''nope'', 1)', 'refuse'],
    ['buy_hoodlums(''thug'', 2147483647)', 'refuse'],
    ['hire_hustlers(''herb'', -1)', 'refuse'], ['hire_hustlers(''herb'', 0)', 'refuse'], ['hire_hustlers(''nope'', 1)', 'refuse'],
    ['list_product(''herb'', -5, 10)', 'refuse'], ['list_product(''herb'', 10, -10)', 'refuse'], ['list_product(''herb'', 10, 0)', 'refuse'],
    ['post_order(''herb'', -5, 10)', 'refuse'], ['post_order(''herb'', 10, -1)', 'refuse'], ['post_order(''herb'', 10, 0)', 'refuse'],
    ['post_order(''herb'', 2147483647, 2147483647)', 'refuse'], ['post_order(''nope'', 10, 10)', 'refuse'],
    ['bribe_police(-10)', 'refuse'], ['bribe_police(0)', 'refuse'],
    ['buy_health(-10)', 'refuse'], ['buy_health(0)', 'refuse'], ['buy_health(2147483647)', 'refuse'],
    ['equip(''offense'', 1, -1)', 'refuse'], ['equip(''offense'', 1, 1000)', 'refuse'], ['equip(''offense'', 99999, 1)', 'refuse'],
    ['slots_spin(-100)', 'refuse'], ['slots_spin(0)', 'refuse'], ['slots_spin(9223372036854775807)', 'refuse'],
    ['blackjack_deal(-100)', 'refuse'], ['blackjack_deal(0)', 'refuse'], ['blackjack_deal(9223372036854775807)', 'refuse'],
    ['roulette_spin(''[{"type":"red","amount":-100}]'')', 'refuse'], ['roulette_spin(''[{"type":"red","amount":0}]'')', 'refuse'],
    ['roulette_spin(''[]'')', 'refuse'], ['roulette_spin(''{"x":1}'')', 'refuse'], ['roulette_spin(''null'')', 'refuse'],
    ['roulette_spin(''[{"type":"straight","value":99,"amount":100}]'')', 'refuse'],
    ['roulette_spin(''[{"type":"bogus","amount":100}]'')', 'refuse'],
    ['roulette_spin(''[{"type":"red","amount":"100"}]'')', 'either'],
    ['roulette_spin(''[{"type":"red","amount":100.5}]'')', 'refuse'],
    ['craps_bet(''pass'', -100)', 'refuse'], ['craps_bet(''pass'', 0)', 'refuse'], ['craps_bet(''bogus'', 100)', 'refuse'],
    ['crew_bank(-100)', 'refuse'], ['cartel_bank(-100)', 'refuse'],
    ['poker_join(1, 0, -100)', 'refuse'], ['poker_join(1, 99, 1000)', 'refuse'], ['poker_act(''raise'', -100)', 'refuse'],
    ['attack_block(1, -5, 0)', 'refuse'], ['attack_block(1, 51, -5)', 'refuse'],
    ['station_hoodlums(1, ''thug'', -5)', 'refuse'], ['withdraw_garrison(1, ''thug'', -5)', 'refuse'],
    ['upgrade_stat(''bogus'')', 'refuse'], ['refill(''stamina'', ''bogus'')', 'refuse'], ['refill(''bogus'', ''diamonds'')', 'refuse'],
    ['do_action(-1)', 'refuse'], ['do_action(99999)', 'refuse'],
    ['choose_path(''bogus'')', 'refuse'], ['set_combo(''offense'', ''bogus'')', 'refuse'],
    ['get_messages(''global'', -1)', 'either'], ['get_messages(''crew:00000000-0000-4000-8000-000000000000'', 10)', 'refuse'],
    ['get_messages(''dm:00000000-0000-4000-8000-000000000001:00000000-0000-4000-8000-000000000002'', 10)', 'refuse'],
    ['casino_history(-1)', 'either'], ['get_fights(-1)', 'either'], ['find_players('''', -1)', 'either'],
    ['forum_list(''general'', -5)', 'either'], ['forum_thread(1, -5)', 'either'],
    -- too long is cut to fit (500 for chat, 8 and 200 for the avatar and bio), not refused
    ['send_message(''global'', '''')', 'refuse'], ['send_message(''global'', repeat(''x'', 5000))', 'either'],
    ['update_profile(repeat(''🔥'', 50), repeat(''x'', 5000))', 'either']
  ];
  c text; want text; ok boolean; msg text; p1 profiles; p2 profiles; before1 bigint; before_world bigint; after_world bigint;
  accepted text[] := '{}'; broken text[] := '{}'; n int := 0;
begin
  update profiles set cash = 1000, bank = 1000, diamonds = 10, heat = 0, stamina = stamina_max, health = health_max,
                      in_hospital = false, jail_until = null, immune_until = now() - interval '1 day' where id in (one, two);
  perform pg_temp.qa_as(one);
  for i in 1 .. array_length(calls, 1) loop
    c := replace(replace(calls[i][1], 'ONE', one::text), 'TWO', two::text); want := calls[i][2];
    -- money in the two accounts before (cash + bank, both players): nothing a refused call does may change it
    select coalesce(sum(cash + bank), 0) into before_world from profiles where id in (one, two);
    begin
      execute 'select ' || c;
      ok := true; msg := '';
    exception when others then ok := false; msg := sqlerrm;
    end;
    n := n + 1;
    select * into p1 from profiles where id = one;
    select * into p2 from profiles where id = two;
    select coalesce(sum(cash + bank), 0) into after_world from profiles where id in (one, two);
    if p1.cash < 0 or p1.bank < 0 or p1.diamonds < 0 or p2.cash < 0 or p2.bank < 0 or p2.diamonds < 0 then
      broken := broken || format('%s: a balance went negative', c); end if;
    if exists (select 1 from inventory where player_id in (one, two) and qty < 0)
       or exists (select 1 from storage where player_id in (one, two) and qty < 0)
       or exists (select 1 from setup_items where player_id in (one, two) and qty < 0)
       or exists (select 1 from player_hoodlums where player_id in (one, two) and qty < 0) then
      broken := broken || format('%s: a count went negative', c); end if;
    if not ok and after_world <> before_world then broken := broken || format('%s: refused but money moved', c); end if;
    if ok and want = 'refuse' then accepted := accepted || format('%s', c); end if;
    raise notice '% %  %', case when ok then 'ok ' else 'no ' end, rpad(left(c, 70), 70), left(msg, 70);
    -- put the stakes back for the next call
    update profiles set cash = 1000, bank = 1000, diamonds = 10, stamina = stamina_max, health = health_max,
                        in_hospital = false, jail_until = null, heat = 0 where id in (one, two);
  end loop;
  raise notice 'QA FUZZ: % calls; went through that should have been refused: %', n, coalesce(nullif(array_to_string(accepted, ' | '), ''), 'none');
  if cardinality(broken) > 0 then raise exception 'QA FUZZ FAILED: %', array_to_string(broken, ' | '); end if;
  if cardinality(accepted) > 0 then raise exception 'QA FUZZ FAILED, went through: %', array_to_string(accepted, ' | '); end if;
end $$;

select ' QA FUZZ PASSED';
