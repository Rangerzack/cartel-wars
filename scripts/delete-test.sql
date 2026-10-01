-- Tests for in-app account deletion (#8): the typed confirmation, thugs, crew succession (Co-Capo, the longest-standing
-- member, a crew of one), the Don, a poker seat, listings and buy orders settled before the profile goes, what other
-- players keep (fights, trades, ledger, territory log, activity lines) and lose (chat lines, DMs, forum posts), the
-- deleted_accounts tally, the dead session, deletes straight from auth.users (the dashboard's "Delete user": a member, a
-- Capo, a crew of one), and grants.
-- Run after the other suites (reuses their helpers): scripts/local-db.sh test
\set ON_ERROR_STOP on
\set QUIET on

insert into auth.users (id, raw_user_meta_data) values
  ('dd111111-1111-1111-1111-111111111111', '{"name":"Kingpin"}'),
  ('dd222222-2222-2222-2222-222222222222', '{"name":"Second"}'),
  ('dd333333-3333-3333-3333-333333333333', '{"name":"Old Timer"}'),
  ('dd444444-4444-4444-4444-444444444444', '{"name":"Other Capo"}'),
  ('dd555555-5555-5555-5555-555555555555', '{"name":"Witness"}'),
  ('dd666666-6666-6666-6666-666666666666', '{"name":"Boss NoCo"}'),
  ('dd777777-7777-7777-7777-777777777777', '{"name":"Rookie"}'),
  ('dd888888-8888-8888-8888-888888888888', '{"name":"Veteran"}'),
  ('dd999999-9999-9999-9999-999999999999', '{"name":"Lone Wolf"}'),
  ('ddaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa', '{"name":"Don Solo"}'),
  ('ddbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb', '{"name":"Ally Capo"}');
update profiles set cash = 1000000 where id::text like 'dd%';

-- A test-only trigger records the profile as it was at the moment it was deleted (it fires before the cascade), so the
-- suite can check what delete_account settled first.
create table _test_delete_snap (id uuid, cash bigint, herb int, open_listings int, open_orders int, seated boolean, crew_id uuid);
create function _test_delete_snap() returns trigger language plpgsql as $$
begin
  insert into _test_delete_snap values (old.id, old.cash, (select qty from storage where player_id = old.id and commodity = 'herb'),
    (select count(*) from listings where seller_id = old.id and status in ('open', 'returned')),
    (select count(*) from buy_orders where buyer_id = old.id and status = 'open'),
    exists (select 1 from poker_seats where player_id = old.id), old.crew_id);
  return old;
end $$;
create trigger aa_test_delete_snap before delete on profiles for each row execute function _test_delete_snap();

-- Kingpin runs a crew (Second as Co-Capo, Old Timer a member) and founded a cartel that Other Capo's crew joined -------
select as_user('dd444444-4444-4444-4444-444444444444');
do $$ begin perform crew_create('Other Crew', '🦊'); end $$;
select as_user('dd111111-1111-1111-1111-111111111111');
do $$ begin perform crew_create('Kingpin Crew', '👑'); perform cartel_create('Kingpin Cartel'); perform crew_bank(5000);
  perform cartel_invite((select id from crews where name = 'Other Crew')); end $$;
select as_user('dd444444-4444-4444-4444-444444444444');
do $$ begin perform cartel_accept((select id from cartels where name = 'Kingpin Cartel')); end $$;
select as_user('dd222222-2222-2222-2222-222222222222');
do $$ begin perform crew_apply((select id from crews where name = 'Kingpin Crew')); end $$;
select as_user('dd333333-3333-3333-3333-333333333333');
do $$ begin perform crew_apply((select id from crews where name = 'Kingpin Crew')); end $$;
select as_user('dd111111-1111-1111-1111-111111111111');
do $$ begin perform crew_decide('dd222222-2222-2222-2222-222222222222', true); perform crew_decide('dd333333-3333-3333-3333-333333333333', true);
  perform crew_set_co_capo('dd222222-2222-2222-2222-222222222222'); end $$;

-- What Kingpin leaves behind for Witness: forum posts both ways, chat, a DM, trades, a fight, a territory log line ------
select as_user('dd555555-5555-5555-5555-555555555555');
do $$ begin
  perform forum_create_thread('general', 'Witness thread', 'Who runs this town?');
  perform send_message('global', 'witness was here');
  perform send_message(dm_channel('dd111111-1111-1111-1111-111111111111'), 'hey boss');
end $$;
select as_user('dd333333-3333-3333-3333-333333333333');
do $$ begin perform forum_reply((select id from forum_threads where title = 'Witness thread'), 'not you'); end $$;
update storage set qty = case commodity when 'herb' then 1000 when 'pills' then 100 else 0 end where player_id = 'dd111111-1111-1111-1111-111111111111';
update profiles set storage_cap = 5000 where id = 'dd111111-1111-1111-1111-111111111111';
insert into inventory (player_id, item_id, qty)
select 'dd111111-1111-1111-1111-111111111111', id, 1 from item_defs where category = 'transport' order by capacity desc limit 1;
select as_user('dd111111-1111-1111-1111-111111111111');
do $$ begin
  perform forum_create_thread('general', 'Kingpin thread', 'I run this town');
  perform forum_reply((select id from forum_threads where title = 'Witness thread'), 'I do');
  perform send_message('global', 'kingpin was here');
  perform send_message(dm_channel('dd555555-5555-5555-5555-555555555555'), 'what');
  perform list_product('herb', 200, (select price from street_prices where commodity = 'herb'));
  perform post_order('dust', 100, (select price from street_prices where commodity = 'dust'));
end $$;
select as_user('dd555555-5555-5555-5555-555555555555');
do $$ begin
  perform forum_reply((select id from forum_threads where title = 'Kingpin thread'), 'sure you do');
  perform buy_listing((select id from listings where seller_id = 'dd111111-1111-1111-1111-111111111111' and status = 'open'), 50);
  perform post_order('pills', 25, (select price from street_prices where commodity = 'pills'));
end $$;
select as_user('dd111111-1111-1111-1111-111111111111');
do $$ begin
  perform fill_order((select id from buy_orders where buyer_id = 'dd555555-5555-5555-5555-555555555555' and status = 'open'), 25);
  perform attack('dd555555-5555-5555-5555-555555555555');
end $$;
-- and Witness hits back, so Kingpin is on both sides of Witness's fight log
update profiles set health = 100, stamina = 100 where id in ('dd111111-1111-1111-1111-111111111111', 'dd555555-5555-5555-5555-555555555555');
select as_user('dd555555-5555-5555-5555-555555555555');
do $$ begin perform attack('dd111111-1111-1111-1111-111111111111'); end $$;
insert into territory_log (block_id, attacker_id, crew_id, success, attack, resistance)
select min(id), 'dd111111-1111-1111-1111-111111111111', (select id from crews where name = 'Kingpin Crew'), true, 900, 400 from blocks;

-- Kingpin, Second and Old Timer sit at a fresh table; Kingpin is first to act in the live hand
create temp table _test_table as
select t.id as tid, t.small_blind + t.big_blind as blinds from poker_tables t where t.max_age_days is null
   and not exists (select 1 from poker_seats s where s.table_id = t.id) and not exists (select 1 from poker_hands h where h.table_id = t.id)
 order by t.big_blind, t.id limit 1;
do $$ declare t_id int := (select tid from _test_table); begin
  assert t_id is not null, 'a table nobody has played at';
  insert into poker_seats (table_id, seat, player_id, stack)
  select t_id, x.seat, x.p, t.min_buyin from poker_tables t,
         (values (0, 'dd111111-1111-1111-1111-111111111111'::uuid), (1, 'dd222222-2222-2222-2222-222222222222'::uuid),
                 (2, 'dd333333-3333-3333-3333-333333333333'::uuid)) x(seat, p) where t.id = t_id;
  update profiles set cash = cash - (select min_buyin from poker_tables where id = t_id) where id::text similar to 'dd(1|2|3)%';
end $$;
select as_user('dd111111-1111-1111-1111-111111111111');
do $$ declare st jsonb; begin
  st := poker_state((select tid from _test_table));
  assert st->'hand'->>'stage' = 'preflop' and (st->'hand'->>'to_act')::int = 0 and (st->'hand'->'my'->>'total_bet')::bigint = 0, st::text;
end $$;

-- Boss NoCo runs a crew without a Co-Capo: Rookie joined first, Veteran has been around longer ------------------------
select as_user('dd666666-6666-6666-6666-666666666666');
do $$ begin perform crew_create('NoCo Crew', '🐺'); end $$;
select as_user('dd777777-7777-7777-7777-777777777777');
do $$ begin perform crew_apply((select id from crews where name = 'NoCo Crew')); end $$;
select as_user('dd888888-8888-8888-8888-888888888888');
do $$ begin perform crew_apply((select id from crews where name = 'NoCo Crew')); end $$;
select as_user('dd666666-6666-6666-6666-666666666666');
do $$ begin perform crew_decide('dd777777-7777-7777-7777-777777777777', true); perform crew_decide('dd888888-8888-8888-8888-888888888888', true); end $$;
update profiles set created_at = now() - interval '10 days' where id = 'dd777777-7777-7777-7777-777777777777';
update profiles set created_at = now() - interval '20 days' where id = 'dd888888-8888-8888-8888-888888888888';
update profiles set created_at = now() - interval '12 days 3 hours' where id = 'dd666666-6666-6666-6666-666666666666';

-- Lone Wolf is a crew of one, alone in a cartel, holding a block, on the paid Daily Drop ----------------------------
select as_user('dd999999-9999-9999-9999-999999999999');
do $$ begin perform crew_create('Lone Crew', '🌙'); perform cartel_create('Lone Cartel'); end $$;
update blocks set owner_crew_id = (select id from crews where name = 'Lone Crew'), taken_at = now(), bonus_at = now() + interval '1 day'
 where id = (select max(id) from blocks where owner_crew_id is null);
update profiles set drop_since = now(), drop_until = now() + interval '20 days' where id = 'dd999999-9999-9999-9999-999999999999';

-- Don Solo is a crew of one and Don of a cartel that Ally Capo's crew also belongs to -------------------------------
select as_user('ddbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
do $$ begin perform crew_create('Ally Crew', '🤝'); end $$;
select as_user('ddaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
do $$ begin perform crew_create('Solo Crew', '🎩'); perform cartel_create('Two Crew Cartel');
  perform cartel_invite((select id from crews where name = 'Ally Crew')); perform cartel_bank(1000); end $$;
select as_user('ddbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
do $$ begin perform cartel_accept((select id from cartels where name = 'Two Crew Cartel')); end $$;

-- Before: Witness sees Kingpin's fights and DM
select as_user('dd555555-5555-5555-5555-555555555555');
do $$ begin
  assert exists (select 1 from jsonb_array_elements(get_fights()) e where e->>'attacker' = 'Kingpin' and e->>'defender' = 'Witness');
  assert exists (select 1 from jsonb_array_elements(get_fights()) e where e->>'attacker' = 'Witness' and e->>'defender' = 'Kingpin');
  assert exists (select 1 from jsonb_array_elements(get_conversations()) e where e->>'other_id' = 'dd111111-1111-1111-1111-111111111111');
  assert (select reply_count from forum_threads where title = 'Witness thread') = 2;
end $$;
create temp table _test_counts as select (select count(*) from deleted_accounts) as deleted;
create temp table _test_fights as select get_fights() as log, p.fights_won as won, p.fights_lost as lost, (combo_meta()->>'fights')::int as meta
  from profiles p where p.id = 'dd555555-5555-5555-5555-555555555555';

-- The confirmation, and thugs ------------------------------------------------------------------------------------------
select as_user((select id::text from profiles where is_bot order by bot_level limit 1));
do $$ begin
  perform expect_error(format('select delete_account(%L)', (select name from profiles where id = auth.uid())), 'Thugs can''t be deleted');
end $$;
select as_user('dd111111-1111-1111-1111-111111111111');
do $$ begin
  perform expect_error('select delete_account(''Kingpn'')', 'Type your street name to confirm');
  perform expect_error('select delete_account(''Witness'')', 'Type your street name to confirm');
  perform expect_error('select delete_account('''')', 'Type your street name to confirm');
  perform expect_error('select delete_account(null)', 'Type your street name to confirm');
  assert exists (select 1 from profiles where id = auth.uid()), 'nothing happened';
end $$;

-- Kingpin deletes: a Capo with a Co-Capo, the Don, at a poker table, with a listing and a buy order open --------------
do $$ declare k uuid := auth.uid(); cash0 bigint; stack0 bigint; held0 bigint; herb0 int; listed0 int; snap _test_delete_snap; r jsonb; begin
  select cash into cash0 from profiles where id = k;
  select stack into stack0 from poker_seats where player_id = k;
  select sum(qty::bigint * unit_price) into held0 from buy_orders where buyer_id = k and status = 'open';
  select qty into herb0 from storage where player_id = k and commodity = 'herb';
  select qty into listed0 from listings where seller_id = k and status = 'open';
  assert stack0 > 0 and held0 > 0 and listed0 = 150, format('stack %s held %s listed %s', stack0, held0, listed0);
  r := delete_account('  kingPIN ');                                  -- any case, spaces trimmed
  assert r = '{"deleted": true}'::jsonb, r::text;
  -- at the moment the profile went: out of the crew, off the table, stack and held cash back on hand, product back in storage
  select * into snap from _test_delete_snap where id = k;
  assert snap.crew_id is null and not snap.seated and snap.open_listings = 0 and snap.open_orders = 0, row_to_json(snap)::text;
  assert snap.cash = cash0 + stack0 + held0, format('cash %s, wanted %s', snap.cash, cash0 + stack0 + held0);
  assert snap.herb = herb0 + listed0, format('herb %s, wanted %s', snap.herb, herb0 + listed0);
  -- then it's gone, sign-in included
  assert not exists (select 1 from profiles where id = k) and not exists (select 1 from auth.users where id = k);
  assert not exists (select 1 from listings where seller_id = k) and not exists (select 1 from buy_orders where buyer_id = k);
end $$;

-- The Co-Capo took the crew and the cartel; the bank stayed; the deposit is still in the ledger, nameless ---------------
select as_user('dd222222-2222-2222-2222-222222222222');
do $$ declare c crews; ca cartels; r jsonb; begin
  select * into c from crews where name = 'Kingpin Crew';
  select * into ca from cartels where name = 'Kingpin Cartel';
  assert c.capo_id = auth.uid() and c.co_capo_id is null, 'the Co-Capo steps up';
  assert ca.don_id = auth.uid(), 'and is Don now';
  assert c.bank = 5000, 'the crew bank stays';
  assert (select count(*) from profiles where crew_id = c.id) = 2;
  r := get_me();
  assert (r->'crew'->>'is_capo')::boolean and (r->'cartel'->>'is_don')::boolean, r::text;
  r := get_bank_ledger('crew');
  assert exists (select 1 from jsonb_array_elements(r) e where e->>'kind' = 'deposit' and (e->>'amount')::bigint = 5000
                   and e->>'player_id' is null and e->>'player' is null), r::text;
  -- the poker hand plays on: Second is next to act, Kingpin's seat is empty
  r := poker_state((select tid from _test_table));
  assert (r->'hand'->>'to_act')::int = 1 and not (r->'hand'->>'finished')::boolean, r::text;
  assert jsonb_array_length(r->'seats') = 2 and (r->'hand'->>'pot')::bigint = (select blinds from _test_table), r::text;
  r := poker_act('fold');
  assert (r->'hand'->>'finished')::boolean and (r->'hand'->'result'->'won'->>'2')::bigint = (select blinds from _test_table), r::text;
end $$;

-- Witness: fights, trades, the activity lines and the territory log stay without the name; the chat line, the DMs and
-- Kingpin's forum posts are gone, and the threads they were in add up -----------------------------------------------------
select as_user('dd555555-5555-5555-5555-555555555555');
do $$ declare r jsonb; k text := 'dd111111-1111-1111-1111-111111111111'; t forum_threads; begin
  r := get_me();
  assert r->>'name' = 'Witness', 'a bystander carries on';
  perform expect_error(format('select get_player(%L)', k), 'No such player');
  assert exists (select 1 from market_trades where buyer_id = auth.uid() and seller_id is null and via = 'listing' and units = 50);
  assert exists (select 1 from market_trades where buyer_id = auth.uid() and seller_id is null and via = 'order' and units = 25);
  r := get_activity();
  assert exists (select 1 from jsonb_array_elements(r) e where e->>'kind' = 'attacked' and e->>'actor_id' is null and e->>'actor' is null), r::text;
  assert exists (select 1 from jsonb_array_elements(r) e where e->>'kind' = 'filled' and e->>'actor_id' is null and e->>'actor' is null), r::text;
  r := get_territory_log(100);
  assert exists (select 1 from jsonb_array_elements(r) e where e->>'crew' = 'Kingpin Crew' and e->>'attacker_id' is null and e->>'attacker' is null), r::text;
  -- both fights stay in Witness's log with Kingpin's side reading "Deleted player", and nothing else about them changed
  r := get_fights();
  assert exists (select 1 from jsonb_array_elements(r) e where e->>'attacker' = 'Deleted player' and e->>'attacker_id' is null
                   and e->>'defender' = 'Witness' and not (e->>'i_attacked')::boolean), r::text;
  assert exists (select 1 from jsonb_array_elements(r) e where e->>'defender' = 'Deleted player' and e->>'defender_id' is null
                   and e->>'attacker' = 'Witness' and (e->>'i_attacked')::boolean), r::text;
  assert (select array_agg(e - '{attacker,attacker_id,defender,defender_id}'::text[] order by (e->>'id')::bigint) from jsonb_array_elements(r) e)
       = (select array_agg(e - '{attacker,attacker_id,defender,defender_id}'::text[] order by (e->>'id')::bigint) from jsonb_array_elements((select log from _test_fights)) e),
         'who won, damage and cash read as before: ' || r::text;
  assert not exists (select 1 from fights where k::uuid in (attacker_id, defender_id, winner_id)), 'no trace of the id';
  -- Witness's record is untouched and still adds up to the log; the city's combo stats still count both fights
  assert (select fights_won from profiles where id = auth.uid()) = (select won from _test_fights)
     and (select fights_lost from profiles where id = auth.uid()) = (select lost from _test_fights);
  assert (select fights_won + fights_lost from profiles where id = auth.uid()) = jsonb_array_length(r) and jsonb_array_length(r) = 2, r::text;
  assert (combo_meta()->>'fights')::int = (select meta from _test_fights), combo_meta()::text;
  assert not exists (select 1 from jsonb_array_elements(get_messages('global', 500)) e where e->>'body' = 'kingpin was here');
  assert exists (select 1 from jsonb_array_elements(get_messages('global', 500)) e where e->>'body' = 'witness was here');
  assert not exists (select 1 from jsonb_array_elements(get_conversations()) e where e->>'other_id' = k), 'the DM conversation is gone';
  assert not exists (select 1 from messages where channel like 'dm:%' and position(k in channel) > 0);
  assert not exists (select 1 from chat_reads where channel like 'dm:%' and position(k in channel) > 0);
  assert not exists (select 1 from forum_threads where title = 'Kingpin thread'), 'their thread goes, with its replies';
  select * into t from forum_threads where title = 'Witness thread';
  assert t.reply_count = 1 and t.last_poster_id = 'dd333333-3333-3333-3333-333333333333'
     and t.last_post_at = (select created_at from forum_posts where thread_id = t.id), 'recounted: ' || row_to_json(t)::text;
  r := forum_thread(t.id);
  assert jsonb_array_length(r->'posts') = 1 and r->'posts'->0->'author'->>'name' = 'Old Timer' and r->'thread'->>'last_poster' = 'Old Timer', r::text;
  assert exists (select 1 from jsonb_array_elements(forum_list('general')->'threads') e where e->>'title' = 'Witness thread' and (e->>'reply_count')::int = 1);
end $$;

-- A deleted session can't do anything, or bring the profile back
select as_user('dd111111-1111-1111-1111-111111111111');
do $$ begin
  perform expect_error('select get_me()', 'No such player');
  perform expect_error('select delete_account(''Kingpin'')', 'No such player');
  perform expect_error('select ensure_profile()', 'foreign key');
end $$;

-- Boss NoCo deletes: no Co-Capo, so the longest-standing member (Veteran) takes over, not the first to join ------------
select as_user('dd666666-6666-6666-6666-666666666666');
do $$ begin perform delete_account('Boss NoCo'); end $$;
do $$ declare c crews; begin
  select * into c from crews where name = 'NoCo Crew';
  assert c.capo_id = 'dd888888-8888-8888-8888-888888888888' and c.co_capo_id is null, row_to_json(c)::text;
  assert (select count(*) from profiles where crew_id = c.id) = 2;
end $$;

-- Lone Wolf deletes: the crew disbands, its block goes free, and the cartel it was alone in dissolves ----------------
select as_user('dd999999-9999-9999-9999-999999999999');
do $$ declare b int; begin
  select id into b from blocks where owner_crew_id = (select id from crews where name = 'Lone Crew');
  perform delete_account('Lone Wolf');
  assert not exists (select 1 from crews where name = 'Lone Crew') and not exists (select 1 from cartels where name = 'Lone Cartel');
  assert (select owner_crew_id from blocks where id = b) is null, 'the block is free';
end $$;

-- Don Solo deletes: the crew disbands, the cartel carries on with Ally Capo as Don and its bank -----------------------
select as_user('ddaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa');
do $$ begin perform delete_account('Don Solo'); end $$;
select as_user('ddbbbbbb-bbbb-bbbb-bbbb-bbbbbbbbbbbb');
do $$ declare ca cartels; r jsonb; begin
  select * into ca from cartels where name = 'Two Crew Cartel';
  assert ca.don_id = auth.uid() and ca.bank = 1000, row_to_json(ca)::text;
  assert not exists (select 1 from crews where name = 'Solo Crew');
  assert (select array_agg(name) from crews where cartel_id = ca.id) = array['Ally Crew'];
  r := get_cartel(ca.id);
  assert (r->>'is_don')::boolean and r->>'don' = 'Ally Capo', r::text;
end $$;

-- Deleting straight from auth.users, as the Supabase dashboard's "Delete user" does: the profile delete trigger runs the
-- same succession without touching the row on its way out --------------------------------------------------------------
insert into auth.users (id, raw_user_meta_data) values
  ('dc111111-1111-1111-1111-111111111111', '{"name":"Dash Capo"}'),
  ('dc222222-2222-2222-2222-222222222222', '{"name":"Dash Co"}'),
  ('dc333333-3333-3333-3333-333333333333', '{"name":"Dash Member"}'),
  ('dc444444-4444-4444-4444-444444444444', '{"name":"Dash Lone"}');
update profiles set cash = 1000000 where id::text like 'dc%';
select as_user('dc111111-1111-1111-1111-111111111111');
do $$ begin perform crew_create('Dash Crew', '💨'); perform cartel_create('Dash Cartel'); perform crew_bank(3000); end $$;
select as_user('dc222222-2222-2222-2222-222222222222');
do $$ begin perform crew_apply((select id from crews where name = 'Dash Crew')); end $$;
select as_user('dc333333-3333-3333-3333-333333333333');
do $$ begin perform crew_apply((select id from crews where name = 'Dash Crew')); end $$;
select as_user('dc111111-1111-1111-1111-111111111111');
do $$ begin perform crew_decide('dc222222-2222-2222-2222-222222222222', true); perform crew_decide('dc333333-3333-3333-3333-333333333333', true);
  perform crew_set_co_capo('dc222222-2222-2222-2222-222222222222'); end $$;
select as_user('dc444444-4444-4444-4444-444444444444');
do $$ begin perform crew_create('Dash Lone Crew', '🌘'); perform cartel_create('Dash Lone Cartel'); end $$;
update blocks set owner_crew_id = (select id from crews where name = 'Dash Lone Crew'), taken_at = now(), bonus_at = now() + interval '1 day'
 where id = (select max(id) from blocks where owner_crew_id is null);

-- a member: the crew carries on as it was
delete from auth.users where id = 'dc333333-3333-3333-3333-333333333333';
do $$ declare c crews; begin
  select * into c from crews where name = 'Dash Crew';
  assert not exists (select 1 from profiles where id = 'dc333333-3333-3333-3333-333333333333');
  assert c.capo_id = 'dc111111-1111-1111-1111-111111111111' and c.co_capo_id = 'dc222222-2222-2222-2222-222222222222' and c.bank = 3000, row_to_json(c)::text;
  assert (select count(*) from profiles where crew_id = c.id) = 2;
end $$;

-- the Capo, who is also the Don: the Co-Capo takes the crew and the cartel, and the bank stays
delete from auth.users where id = 'dc111111-1111-1111-1111-111111111111';
select as_user('dc222222-2222-2222-2222-222222222222');
do $$ declare c crews; r jsonb; begin
  select * into c from crews where name = 'Dash Crew';
  assert not exists (select 1 from profiles where id = 'dc111111-1111-1111-1111-111111111111');
  assert c.capo_id = auth.uid() and c.co_capo_id is null and c.bank = 3000, row_to_json(c)::text;
  assert (select don_id from cartels where name = 'Dash Cartel') = auth.uid(), 'and is Don now';
  assert (select array_agg(id) from profiles where crew_id = c.id) = array[auth.uid()];
  r := get_me();
  assert (r->'crew'->>'is_capo')::boolean and (r->'cartel'->>'is_don')::boolean, r::text;
  r := get_bank_ledger('crew');
  assert exists (select 1 from jsonb_array_elements(r) e where e->>'kind' = 'deposit' and (e->>'amount')::bigint = 3000 and e->>'player_id' is null), r::text;
end $$;

-- a crew of one: it disbands, its block goes free, and the cartel it was alone in dissolves
do $$ declare b int := (select id from blocks where owner_crew_id = (select id from crews where name = 'Dash Lone Crew')); begin
  assert b is not null;
  delete from auth.users where id = 'dc444444-4444-4444-4444-444444444444';
  assert not exists (select 1 from profiles where id = 'dc444444-4444-4444-4444-444444444444');
  assert not exists (select 1 from crews where name = 'Dash Lone Crew') and not exists (select 1 from cartels where name = 'Dash Lone Cartel');
  assert (select owner_crew_id is null and bonus_at is null from blocks where id = b), 'the block is free';
end $$;

-- The tally: one row each, nothing that identifies anyone --------------------------------------------------------------
do $$ declare n0 bigint := (select deleted from _test_counts); begin
  assert (select count(*) from deleted_accounts) = n0 + 4;
  assert (select array_agg(column_name::text order by ordinal_position) from information_schema.columns where table_name = 'deleted_accounts')
       = array['id', 'deleted_at', 'days_played', 'had_purchases'];
  assert (select array_agg(days_played order by id) from (select * from deleted_accounts order by id desc limit 4) x) = array[0, 12, 0, 0];
  assert (select array_agg(had_purchases order by id) from (select * from deleted_accounts order by id desc limit 4) x) = array[false, false, true, false];
  assert not exists (select 1 from auth.users where id in ('dd111111-1111-1111-1111-111111111111', 'dd666666-6666-6666-6666-666666666666',
                                                           'dd999999-9999-9999-9999-999999999999', 'ddaaaaaa-aaaa-aaaa-aaaa-aaaaaaaaaaaa'));
end $$;

-- Grants: signed-in players only; the tally is private ----------------------------------------------------------------
do $$ begin
  assert has_function_privilege('authenticated', 'delete_account(text)', 'execute');
  assert not has_function_privilege('anon', 'delete_account(text)', 'execute');
  assert not has_table_privilege('authenticated', 'deleted_accounts', 'select') and not has_table_privilege('anon', 'deleted_accounts', 'select');
end $$;

drop trigger aa_test_delete_snap on profiles;
drop function _test_delete_snap();
drop table _test_delete_snap;

select 'DELETE TEST PASSED';
