-- Tests for week 2: activity feed, unread DMs, the rookie poker table, fight preview.
-- Run after the other suites (reuses their helpers and some of their state): scripts/local-db.sh test
\set ON_ERROR_STOP on
\set QUIET on

insert into auth.users (id, raw_user_meta_data) values
  ('b1111111-1111-1111-1111-111111111111', '{"name":"Walt"}'),
  ('b2222222-2222-2222-2222-222222222222', '{"name":"Jesse"}'),
  ('b3333333-3333-3333-3333-333333333333', '{"name":"Mike"}');

-- Activity from the features suite: sieges, block changes, applications, joins -------------------
select as_user('a3333333-3333-3333-3333-333333333333');   -- Gus, whose corner block DEA took
do $$ declare f jsonb; begin
  f := get_activity(50);
  assert exists (select 1 from jsonb_array_elements(f) e where e->>'kind' = 'siege' and e->>'crew' = 'DEA' and e->>'block' like '% — Block A'), 'Gus saw the siege start: ' || f::text;
  assert exists (select 1 from jsonb_array_elements(f) e where e->>'kind' = 'block_lost' and e->>'crew' = 'DEA' and e->>'actor' = 'Hank' and (e->>'hood_id') is not null), 'Gus lost the block to DEA';
end $$;
select as_user('a1111111-1111-1111-1111-111111111111');   -- Hank, DEA capo
do $$ declare f jsonb; begin
  f := get_activity(50);
  assert exists (select 1 from jsonb_array_elements(f) e where e->>'kind' = 'applied' and e->>'actor' = 'Gomie'), 'capo heard about the application';
  assert not exists (select 1 from jsonb_array_elements(f) e where e->>'kind' = 'block_taken'), 'the attacker is not told about his own capture';
  -- Gus is sieging DEA's second block: live progress on the siege line
  assert exists (select 1 from jsonb_array_elements(f) e where e->>'kind' = 'siege' and e->>'crew' = 'Pollos Hermanos'
                   and (e->>'siege_wins')::int >= 1 and (e->>'siege_need')::int = 50), 'DEA sees the siege with progress: ' || f::text;
end $$;
select as_user('a2222222-2222-2222-2222-222222222222');   -- Gomie, DEA member
do $$ declare f jsonb; begin
  f := get_activity(50);
  assert exists (select 1 from jsonb_array_elements(f) e where e->>'kind' = 'joined' and e->>'crew' = 'DEA' and e->>'actor' = 'Hank'), 'accepted into DEA';
  assert exists (select 1 from jsonb_array_elements(f) e where e->>'kind' = 'block_taken' and e->>'actor' = 'Hank'), 'crew-mates hear about a capture';
end $$;

-- Fights: one line per attacker per hour, unread count, mark seen ----------------------------------
select as_user('b2222222-2222-2222-2222-222222222222');
do $$ begin perform get_me(); end $$;
select as_user('b1111111-1111-1111-1111-111111111111');
do $$ declare r jsonb; p jsonb; f jsonb; begin
  perform get_me();
  update profiles set cash = 100000, stamina = 25, health = 100 where id in ('b1111111-1111-1111-1111-111111111111', 'b2222222-2222-2222-2222-222222222222');
  p := fight_preview('b2222222-2222-2222-2222-222222222222');
  assert (p->>'win_pct')::int between 0 and 100 and (p->>'dmg_min')::int <= (p->>'dmg_max')::int, 'preview: ' || p::text;
  assert not (p->>'dry')::boolean and (p->>'stamina_cost')::int = 2 and (p->>'setup') = 'offense';
  perform expect_error('select fight_preview(auth.uid())', 'yourself');
  perform attack('b2222222-2222-2222-2222-222222222222');
  update profiles set health = 100 where id in ('b1111111-1111-1111-1111-111111111111', 'b2222222-2222-2222-2222-222222222222');
  perform attack('b2222222-2222-2222-2222-222222222222');
  update profiles set health = 100 where id in ('b1111111-1111-1111-1111-111111111111', 'b2222222-2222-2222-2222-222222222222');
  perform attack('b2222222-2222-2222-2222-222222222222');
  p := fight_preview('b2222222-2222-2222-2222-222222222222');
  assert (p->>'dry')::boolean and (p->>'hits_this_hour')::int = 3, 'fourth hit this hour is dry: ' || p::text;
  -- the attacker's own feed stays quiet
  assert jsonb_array_length(get_activity()) = 0, 'attacker has no activity';
end $$;
select as_user('b2222222-2222-2222-2222-222222222222');
do $$ declare f jsonb; e jsonb; me jsonb; begin
  me := get_me();
  assert (me->>'unread_activity')::int = 1, 'three hits fold into one unread line: ' || (me->>'unread_activity');
  f := get_activity();
  e := f->0;
  assert e->>'kind' = 'attacked' and e->>'actor' = 'Walt' and (e->'data'->>'n')::int = 3, 'folded: ' || e::text;
  assert (e->'data'->>'held')::int = (select count(*) from fights where defender_id = auth.uid() and winner_id = auth.uid());
  assert (e->'data'->>'cash_lost')::bigint = (select coalesce(sum(cash_taken), 0) from fights where defender_id = auth.uid() and winner_id <> auth.uid());
  assert not (e->>'seen')::boolean;
  assert (activity_mark_seen()->>'cleared')::int = 1;
  assert (get_me()->>'unread_activity')::int = 0 and (get_activity()->0->>'seen')::boolean, 'cleared';
end $$;
-- a new hit after they've looked starts a fresh line
select as_user('b1111111-1111-1111-1111-111111111111');
do $$ begin
  update profiles set health = 100, stamina = 25 where id in ('b1111111-1111-1111-1111-111111111111', 'b2222222-2222-2222-2222-222222222222');
  perform attack('b2222222-2222-2222-2222-222222222222');
end $$;
select as_user('b2222222-2222-2222-2222-222222222222');
do $$ begin
  assert jsonb_array_length(get_activity()) = 2 and (get_me()->>'unread_activity')::int = 1, 'new line after mark seen';
  perform activity_mark_seen();
end $$;

-- Marketplace sales -------------------------------------------------------------------------------
select as_user('b1111111-1111-1111-1111-111111111111');
do $$ declare r jsonb; begin
  update profiles set cash = 1000000 where id = auth.uid();
  perform buy_item((select id from item_defs where name = 'Van'), 1);
  insert into storage (player_id, commodity, qty) values (auth.uid(), 'herb', 200)
    on conflict (player_id, commodity) do update set qty = 200;
  r := list_product('herb', 100, 40);
  perform set_config('test.listing', r->>'id', false);
end $$;
select as_user('b3333333-3333-3333-3333-333333333333');
do $$ declare l uuid := current_setting('test.listing')::uuid; begin
  perform get_me();
  update profiles set cash = 1000000 where id = auth.uid();
  perform buy_listing(l, 30);
  perform buy_listing(l, 70);                     -- sells out
end $$;
select as_user('b1111111-1111-1111-1111-111111111111');
do $$ declare f jsonb; l uuid := current_setting('test.listing')::uuid; begin
  f := get_activity();
  assert jsonb_array_length(f) = 1 and f->0->>'kind' = 'sold' and f->0->>'actor' = 'Mike', 'one sale line: ' || f::text;
  assert (f->0->'data'->>'units')::int = 100 and (f->0->'data'->>'cash')::bigint = 4000 and f->0->'data'->>'commodity' = 'herb', 'both buys fold: ' || f::text;
  -- cancelling your own listing isn't a sale
  perform list_product('herb', 50, 40);
  perform cancel_listing((select id from listings where seller_id = auth.uid() and status = 'open'));
  assert jsonb_array_length(get_activity()) = 1, 'no sale line for a cancel';
end $$;

-- Crew fights and kicks ---------------------------------------------------------------------------
select as_user('b1111111-1111-1111-1111-111111111111');
do $$ begin perform crew_create('Blue Sky', '💎'); end $$;
select as_user('b2222222-2222-2222-2222-222222222222');
do $$ begin perform crew_apply((select id from crews where name = 'Blue Sky')); end $$;
select as_user('b1111111-1111-1111-1111-111111111111');
do $$ begin perform crew_decide('b2222222-2222-2222-2222-222222222222', true); end $$;
select as_user('b3333333-3333-3333-3333-333333333333');
do $$ declare r jsonb; begin
  perform crew_create('Fixers', '🧰');
  r := crew_fight((select id from crews where name = 'Blue Sky'));
end $$;
select as_user('b2222222-2222-2222-2222-222222222222');
do $$ declare f jsonb; begin
  f := get_activity();
  assert f->0->>'kind' = 'crew_fight' and f->0->>'crew' = 'Fixers' and f->0->>'actor' = 'Mike', 'Jesse hears about the crew fight: ' || f::text;
  assert f->1->>'kind' = 'joined' and f->1->>'crew' = 'Blue Sky';
end $$;
select as_user('b1111111-1111-1111-1111-111111111111');
do $$ begin
  assert exists (select 1 from jsonb_array_elements(get_activity()) e where e->>'kind' = 'crew_fight'), 'capo too';
  perform crew_kick('b2222222-2222-2222-2222-222222222222');
end $$;
select as_user('b2222222-2222-2222-2222-222222222222');
do $$ begin
  assert get_activity()->0->>'kind' = 'kicked' and get_activity()->0->>'crew' = 'Blue Sky', 'kicked line';
  perform crew_create('Jesse Crew', '🧪');       -- founding your own crew isn't news to you
  assert get_activity()->0->>'kind' = 'kicked';
end $$;

-- Unread DMs ----------------------------------------------------------------------------------------
select as_user('b3333333-3333-3333-3333-333333333333');
do $$ declare ch text; begin
  ch := dm_channel('b1111111-1111-1111-1111-111111111111');
  perform send_message(ch, 'got a job for you');
  perform send_message(ch, 'call me');
  assert (get_me()->>'unread_dms')::int = 0, 'your own messages are read';
end $$;
select as_user('b1111111-1111-1111-1111-111111111111');
do $$ declare ch text; c jsonb; begin
  ch := dm_channel('b3333333-3333-3333-3333-333333333333');
  assert (get_me()->>'unread_dms')::int = 1, 'one conversation unread';
  c := get_conversations();
  assert (c->0->>'unread')::int = 2 and c->0->>'other' = 'Mike', 'two unread in it: ' || c::text;
  assert (mark_read(ch)->>'ok')::boolean;
  assert (get_me()->>'unread_dms')::int = 0 and (get_conversations()->0->>'unread')::int = 0, 'read';
  assert not (mark_read('global')->>'ok')::boolean and not (mark_read('dm:00000000-0000-0000-0000-000000000000:11111111-0000-0000-0000-000000000000')->>'ok')::boolean,
    'only your own DMs';
  perform send_message(ch, 'on my way');
end $$;
select as_user('b3333333-3333-3333-3333-333333333333');
do $$ begin
  assert (get_me()->>'unread_dms')::int = 1 and (get_conversations()->0->>'unread')::int = 1, 'reply shows unread for Mike';
end $$;

-- Rookie poker table --------------------------------------------------------------------------------
select as_user('b3333333-3333-3333-3333-333333333333');
do $$ declare t int := (select id from poker_tables where max_age_days is not null); r jsonb; begin
  r := poker_lobby();
  assert r->0->>'name' like 'Rookie Room%' and (r->0->>'eligible')::boolean;
  update profiles set cash = 100000 where id = auth.uid();
  perform expect_error(format('select poker_join(%s, 0, 50000)', t), 'Buy in for');
  r := poker_join(t, 0, 10000);
  assert (r->'me'->>'stack')::bigint = 10000;
  perform poker_leave();
  -- veterans can't sit
  update profiles set created_at = now() - interval '8 days' where id = auth.uid();
  assert not (poker_lobby()->0->>'eligible')::boolean;
  perform expect_error(format('select poker_join(%s, 0, 10000)', t), 'first 7 days');
end $$;

select 'WEEK 2 TEST PASSED';
