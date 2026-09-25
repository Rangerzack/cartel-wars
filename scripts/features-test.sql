-- Tests for: hospital recovery, producer/trader paths, co-capo + bank ledger, 50-win block sieges.
-- Run after smoke-test.sql (reuses its helpers): scripts/local-db.sh test
\set ON_ERROR_STOP on
\set QUIET on

insert into auth.users (id, raw_user_meta_data) values
  ('a1111111-1111-1111-1111-111111111111', '{"name":"Hank"}'),
  ('a2222222-2222-2222-2222-222222222222', '{"name":"Gomie"}'),
  ('a3333333-3333-3333-3333-333333333333', '{"name":"Gus"}');

-- Hospital: +5 health per 5 minutes, and health bought on a sliding scale ---------------------------
select as_user('a1111111-1111-1111-1111-111111111111');
do $$ declare me jsonb; r jsonb; c1 bigint; c2 bigint; begin
  me := get_me();
  update profiles set health = 5, health_tick = now() - interval '10 minutes 30 seconds' where id = auth.uid();
  me := get_me();
  assert (me->>'health')::int = 15, 'two 5-minute ticks: ' || (me->>'health');
  assert (me->>'hospital')::boolean, 'still hospitalized at 15';
  assert (me->>'health_next')::timestamptz between now() and now() + interval '5 minutes', 'next health tick shown';
  update profiles set cash = 1000000 where id = auth.uid();
  r := buy_health(10); c1 := (r->>'cost')::bigint;
  assert c1 = 420 and (r->>'gain')::int = 10, 'first 10 points: ' || r::text;
  r := buy_health(10); c2 := (r->>'cost')::bigint;
  assert c2 = 460, 'next 10 cost more: ' || r::text;
  assert not (get_me()->>'hospital')::boolean;
  r := buy_health(1000);
  assert (r->>'gain')::int = 65 and (get_me()->>'health')::int = 100, 'capped at max: ' || r::text;
  perform expect_error('select buy_health(5)', 'full health');
  -- the 24h window resets the scale
  update profiles set health = 90, health_bought_at = now() - interval '25 hours' where id = auth.uid();
  r := buy_health(10); assert (r->>'cost')::bigint = 420, 'scale resets after 24h: ' || r::text;
end $$;

-- Paths ------------------------------------------------------------------------------------------
do $$ declare r jsonb; h uuid; begin
  update profiles set cash = 1000000, diamonds = 100, reputation = 60 where id = auth.uid();
  perform expect_error('select choose_path(''trader'')', 'unlock');
  perform grow_build('herb');                                  -- below 100 rep both sides are open
  update profiles set reputation = 20 where id = auth.uid();   -- spending rep doesn't lower rep_earned
  update profiles set reputation = 70 where id = auth.uid();   -- +50 → 110 earned
  assert (get_me()->>'rep_earned')::int = 110 and (get_me()->>'path_required')::boolean, 'path now required';
  perform expect_error('select grow_build(''dust'')', 'choose Producer or Trader');
  insert into storage (player_id, commodity, qty) values (auth.uid(), 'herb', 100)
    on conflict (player_id, commodity) do update set qty = 100;
  perform expect_error('select hire_hustlers(''herb'', 1)', 'choose Producer or Trader');

  r := choose_path('producer');
  assert (r->>'diamonds')::int = 0, 'first pick is free';
  perform grow_build('dust');
  perform expect_error('select hire_hustlers(''herb'', 1)', 'Only Traders');

  r := choose_path('trader');
  assert (r->>'diamonds')::int = 50 and (select diamonds from profiles where id = auth.uid()) = 50 - 20, 'switch costs 50💎';
  assert not exists (select 1 from grow_houses where player_id = auth.uid() and running), 'trader houses stopped';
  perform hire_hustlers('herb', 1);
  perform expect_error('select grow_build(''pills'')', 'Only Producers');
  h := (select id from grow_houses where player_id = auth.uid() and commodity = 'herb');
  perform expect_error(format('select grow_toggle(%L)', h), 'Only Producers');
  perform expect_error(format('select grow_upgrade(%L)', h), 'Only Producers');
  perform expect_error('select choose_path(''trader'')', 'already');
  update profiles set diamonds = 10 where id = auth.uid();
  perform expect_error('select choose_path(''producer'')', 'Switching costs 50');
end $$;

-- Co-Capo and the bank ledger --------------------------------------------------------------------
do $$ declare cid uuid; begin
  cid := (crew_create('DEA', '🦅')->>'id')::uuid;
  update profiles set cash = 100000 where id = auth.uid();
  perform crew_bank(5000);
end $$;
select as_user('a2222222-2222-2222-2222-222222222222');
do $$ begin perform crew_apply((select id from crews where name = 'DEA')); end $$;
select as_user('a1111111-1111-1111-1111-111111111111');
do $$ declare cid uuid := (select id from crews where name = 'DEA'); r jsonb; begin
  perform crew_decide('a2222222-2222-2222-2222-222222222222', true);
  perform crew_set_co_capo('a2222222-2222-2222-2222-222222222222');
  assert (get_crew(cid)->>'co_capo_id')::uuid = 'a2222222-2222-2222-2222-222222222222';
  assert (get_crew(cid)->'members'->1->>'is_co_capo')::boolean, 'co-capo listed second';
end $$;
select as_user('a2222222-2222-2222-2222-222222222222');
do $$ declare cid uuid := (select id from crews where name = 'DEA'); l jsonb; begin
  assert (get_me()->'crew'->>'is_co_capo')::boolean;
  perform expect_error('select crew_set_co_capo(null)', 'Only the Capo');
  perform expect_error('select crew_kick(''a1111111-1111-1111-1111-111111111111'')', 'cannot kick the Capo');
  update profiles set cash = 1000 where id = auth.uid();
  perform crew_bank(300);
  perform crew_bank(-2000);                                      -- co-capo can withdraw
  perform crew_update('🐍', 'Hermanos');
  assert (select emblem from crews where id = cid) = '🐍';
  l := get_bank_ledger('crew');
  assert jsonb_array_length(l) = 3, 'three entries: ' || l::text;
  assert l->0->>'kind' = 'withdraw' and (l->0->>'amount')::bigint = -2000 and (l->0->>'balance')::bigint = 3300 and l->0->>'player' = 'Gomie';
  assert l->2->>'kind' = 'deposit' and (l->2->>'amount')::bigint = 5000 and l->2->>'player' = 'Hank';
  perform expect_error('select get_bank_ledger(''cartel'')', 'not in a cartel');
end $$;
select as_user('a3333333-3333-3333-3333-333333333333');
do $$ begin perform expect_error('select get_bank_ledger(''crew'')', 'not in a crew'); end $$;

-- Sieges: 51 thugs minimum, 50 wins to take an owned block, each win resets the bonus clock ------
select as_user('a3333333-3333-3333-3333-333333333333');
do $$ declare b int; r jsonb; begin
  perform crew_create('Pollos Hermanos', '🐔');
  update profiles set cash = 50000000, stamina = 150, stamina_max = 150 where id = auth.uid();
  perform buy_hoodlums('thug', 1000);
  -- Gus's crew holds a corner block with no garrison
  b := (select b.id from blocks b join hoods h on h.id = b.hood_id where h.gx = 9 and h.gy = 9 and b.slot = 1);
  r := attack_block(b, 60, 0);
  assert (r->>'captured')::boolean, 'claimed: ' || r::text;
end $$;
select as_user('a1111111-1111-1111-1111-111111111111');
do $$ declare b int; r jsonb; blk jsonb; begin
  b := (select b.id from blocks b join hoods h on h.id = b.hood_id where h.gx = 9 and h.gy = 9 and b.slot = 1);
  update profiles set cash = 100000000, stamina = 150, stamina_max = 150, health = 100 where id = auth.uid();
  perform buy_hoodlums('thug', 1000);
  perform expect_error(format('select attack_block(%s, 20, 50)', b), 'at least 51 thugs');
  update blocks set bonus_at = now() + interval '10 minutes' where id = b;       -- under an hour to their bonus
  r := attack_block(b, 60, 0);
  assert (r->>'success')::boolean and not (r->>'captured')::boolean, 'first hit lands but does not take it: ' || r::text;
  assert (r->>'wins')::int = 1 and (r->>'wins_needed')::int = 50 and (r->>'bonus_reset')::boolean;
  assert (select bonus_at from blocks where id = b) > now() + interval '23 hours', 'their bonus clock restarted';
  assert (select owner_crew_id from blocks where id = b) = (select id from crews where name = 'Pollos Hermanos');
  -- the rest of the siege (fast-forward to 49, then the 50th hit takes it)
  update block_siege set wins = 49 where block_id = b and crew_id = (select id from crews where name = 'DEA');
  r := attack_block(b, 60, 0);
  assert (r->>'captured')::boolean and (r->>'wins')::int = 50, '50th win takes it: ' || r::text;
  assert (select owner_crew_id from blocks where id = b) = (select id from crews where name = 'DEA');
  assert not exists (select 1 from block_siege where block_id = b), 'siege counts cleared';
  blk := get_block(b);
  assert jsonb_array_length(blk->'log') = 3, 'block log has every attack: ' || (blk->'log')::text;
  assert (blk->'log'->0->>'captured')::boolean and blk->'log'->0->>'defender_crew' = 'Pollos Hermanos';
  assert (blk->'log'->0->>'thugs')::int = 60 and (blk->'log'->0->>'siege_wins')::int = 50;
  assert (blk->>'mine')::boolean;
  assert (select count(*) from messages where channel = 'crew:' || (select id from crews where name = 'Pollos Hermanos') and body like '%took%') = 1, 'defender told';
  -- territory map reports sieges
  perform attack_block((select b2.id from blocks b2 join hoods h on h.id = b2.hood_id where h.gx = 9 and h.gy = 9 and b2.slot = 2), 60, 0);
end $$;
select as_user('a3333333-3333-3333-3333-333333333333');
do $$ declare b int; t jsonb; r jsonb; begin
  b := (select b.id from blocks b join hoods h on h.id = b.hood_id where h.gx = 9 and h.gy = 9 and b.slot = 2);
  r := attack_block(b, 60, 0);
  assert (r->>'wins')::int = 1, 'Gus sieges DEA block: ' || r::text;
  t := get_territory();
  assert (t->'hoods'->80->'blocks'->1->>'my_wins')::int = 1 and (t->'hoods'->80->'blocks'->1->>'top_wins')::int = 1, 'map shows siege';
  assert (t->'rules'->>'siege_wins')::int = 50 and (t->'rules'->>'min_thugs')::int = 51;
  assert jsonb_array_length(get_block(b)->'siege') = 1;
end $$;

\echo 'FEATURES TEST PASSED'
