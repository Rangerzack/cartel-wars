-- Tests for blocking players (#9): who can be blocked, DMs both ways, group chat and forum hiding, crew applications and
-- cartel invites, the blocked list, unblocking, get_me / get_player, grants.
-- Run after the other suites (reuses their helpers): scripts/local-db.sh test
\set ON_ERROR_STOP on
\set QUIET on

insert into auth.users (id, raw_user_meta_data) values
  ('bb111111-1111-1111-1111-111111111111', '{"name":"Blocker"}'),
  ('bb222222-2222-2222-2222-222222222222', '{"name":"Pest"}'),
  ('bb333333-3333-3333-3333-333333333333', '{"name":"Bystander"}'),
  ('bb444444-4444-4444-4444-444444444444', '{"name":"Capo Dee"}');

-- Set up: Dee runs a crew; the bystander runs another with the blocker as Co-Capo and starts a forum thread
select as_user('bb444444-4444-4444-4444-444444444444');
do $$ begin perform crew_create('Dee Crew', '🦂'); end $$;
select as_user('bb333333-3333-3333-3333-333333333333');
do $$ begin perform forum_create_thread('war', 'Turf talk', 'Who holds the docks?'); perform crew_create('Bystanders', '👀'); end $$;
select as_user('bb111111-1111-1111-1111-111111111111');
do $$ begin perform crew_apply((select id from crews where name = 'Bystanders')); perform send_message('global', 'blocker here'); end $$;
select as_user('bb333333-3333-3333-3333-333333333333');
do $$ begin perform crew_decide('bb111111-1111-1111-1111-111111111111', true); perform crew_set_co_capo('bb111111-1111-1111-1111-111111111111'); end $$;

-- Before the block, the pest DMs the blocker, talks in global chat, posts in the forum and applies to Dee's crew
select as_user('bb222222-2222-2222-2222-222222222222');
do $$ begin
  perform send_message(dm_channel('bb111111-1111-1111-1111-111111111111'), 'you up?');
  perform send_message('global', 'pest was here');
  perform forum_create_thread('war', 'Pest thread', 'Listen to me');
  perform forum_reply((select id from forum_threads where title = 'Turf talk'), 'pest reply');
  perform crew_apply((select id from crews where name = 'Dee Crew'));
end $$;

-- The blocker blocks the pest -------------------------------------------------------------------------------------
select as_user('bb111111-1111-1111-1111-111111111111');
do $$ declare r jsonb; P uuid := 'bb222222-2222-2222-2222-222222222222'; begin
  assert (get_me()->>'unread_dms')::int = 1, 'unread before';
  perform expect_error(format('select block_player(%L)', auth.uid()), 'You can''t block yourself');
  perform expect_error(format('select block_player(%L)', (select id from profiles where is_bot limit 1)), 'Thugs can''t be blocked');
  perform expect_error(format('select block_player(%L)', gen_random_uuid()), 'No such player');
  r := block_player(P);
  assert (r->>'blocked')::boolean, r::text;
  perform expect_error(format('select block_player(%L)', P), 'already blocked');
  r := get_me();
  assert r->'blocked' = jsonb_build_array(P), (r->'blocked')::text;
  assert (r->>'unread_dms')::int = 0, 'a blocked conversation stops counting as unread';
  r := get_player(P);
  assert (r->>'blocked')::boolean and not (r->>'blocked_me')::boolean, r::text;
  -- DMs: no sending, the conversation drops out, the history is still readable
  perform expect_error(format('select send_message(%L, ''hey'')', dm_channel(P)), 'You can''t message them');
  assert not exists (select 1 from jsonb_array_elements(get_conversations()) e where e->>'other_id' = P::text);
  assert get_messages(dm_channel(P))->0->>'body' = 'you up?';
  -- group chat leaves their lines out
  assert not exists (select 1 from jsonb_array_elements(get_messages('global', 200)) e where e->>'sender_id' = P::text), 'global hides the pest';
  assert exists (select 1 from jsonb_array_elements(get_messages('global', 200)) e where e->>'body' = 'blocker here');
  -- the forum: their thread and reply are hidden, without text; everyone else's are untouched
  r := forum_list('war');
  assert exists (select 1 from jsonb_array_elements(r->'threads') e where e->>'title' = 'Pest thread' and (e->>'hidden')::boolean and e->>'snippet' = ''), r::text;
  assert exists (select 1 from jsonb_array_elements(r->'threads') e where e->>'title' = 'Turf talk' and not (e->>'hidden')::boolean and e->>'snippet' = 'Who holds the docks?'), r::text;
  r := forum_thread((select id from forum_threads where title = 'Pest thread'));
  assert (r->'thread'->>'hidden')::boolean and r->'thread'->>'body' = '' and r->'thread'->>'snippet' = '' and r->'thread'->'author'->>'name' = 'Pest', r::text;
  r := forum_thread((select id from forum_threads where title = 'Turf talk'));
  assert not (r->'thread'->>'hidden')::boolean and r->'thread'->>'body' = 'Who holds the docks?', r::text;
  assert (r->'posts'->0->>'hidden')::boolean and r->'posts'->0->>'body' = '' and r->'posts'->0->'author'->>'name' = 'Pest', r::text;
end $$;

-- The pest's side: no DMs either way, but blocking is one-way everywhere else
select as_user('bb222222-2222-2222-2222-222222222222');
do $$ declare r jsonb; A uuid := 'bb111111-1111-1111-1111-111111111111'; begin
  r := get_player(A);
  assert not (r->>'blocked')::boolean and (r->>'blocked_me')::boolean, r::text;
  assert get_me()->'blocked' = '[]'::jsonb;
  perform expect_error(format('select send_message(%L, ''why'')', dm_channel(A)), 'You can''t message them');
  assert not exists (select 1 from jsonb_array_elements(get_conversations()) e where e->>'other_id' = A::text);
  assert exists (select 1 from jsonb_array_elements(get_messages('global', 200)) e where e->>'body' = 'blocker here'), 'only the blocker stops seeing';
  -- the blocker is Co-Capo of Bystanders: no applying there
  perform expect_error(format('select crew_apply(%L)', (select id from crews where name = 'Bystanders')), 'You can''t apply to this crew');
  -- blocking is about talking: sending cash still works
  perform send_cash(A, 100);
end $$;

-- The bystander sees everything
select as_user('bb333333-3333-3333-3333-333333333333');
do $$ declare r jsonb; begin
  assert exists (select 1 from jsonb_array_elements(get_messages('global', 200)) e where e->>'body' = 'pest was here');
  r := forum_thread((select id from forum_threads where title = 'Turf talk'));
  assert not (r->'posts'->0->>'hidden')::boolean and r->'posts'->0->>'body' = 'pest reply', r::text;
end $$;

-- Dee (a Capo) blocks the pest: the pending application is declined, and a new one is refused
select as_user('bb444444-4444-4444-4444-444444444444');
do $$ begin
  assert exists (select 1 from crew_applications a join crews c on c.id = a.crew_id where c.name = 'Dee Crew' and a.player_id = 'bb222222-2222-2222-2222-222222222222');
  perform block_player('bb222222-2222-2222-2222-222222222222');
  assert not exists (select 1 from crew_applications where player_id = 'bb222222-2222-2222-2222-222222222222'), 'application declined';
end $$;
select as_user('bb222222-2222-2222-2222-222222222222');
do $$ begin
  perform expect_error(format('select crew_apply(%L)', (select id from crews where name = 'Dee Crew')), 'You can''t apply to this crew');
  -- as a Don: no inviting Dee's crew; the bystander's crew is fine (its Capo hasn't blocked them)
  perform crew_create('Pest Control', '🪳');
  perform cartel_create('Pest Cartel');
  perform expect_error(format('select cartel_invite(%L)', (select id from crews where name = 'Dee Crew')), 'You can''t invite this crew');
  perform cartel_invite((select id from crews where name = 'Bystanders'));
end $$;
-- ...until the bystander blocks them too: the pending invite is declined
select as_user('bb333333-3333-3333-3333-333333333333');
do $$ begin
  assert exists (select 1 from cartel_invites i join crews c on c.id = i.crew_id where c.name = 'Bystanders');
  perform block_player('bb222222-2222-2222-2222-222222222222');
  assert not exists (select 1 from cartel_invites i join crews c on c.id = i.crew_id where c.name = 'Bystanders'), 'invite declined';
  perform unblock_player('bb222222-2222-2222-2222-222222222222');
end $$;

-- The blocked list, then unblocking puts everything back --------------------------------------------------------------
select as_user('bb111111-1111-1111-1111-111111111111');
do $$ declare r jsonb; P uuid := 'bb222222-2222-2222-2222-222222222222'; D uuid := 'bb444444-4444-4444-4444-444444444444'; begin
  perform block_player(D);
  update blocked_players set created_at = created_at + interval '1 second' where blocker_id = auth.uid() and blocked_id = D;
  r := blocked_list();
  assert jsonb_array_length(r) = 2 and r->0->>'name' = 'Capo Dee' and r->1->>'name' = 'Pest' and r->1->>'id' = P::text
     and r->1->>'avatar' is not null and r->1->>'at' is not null, 'newest first: ' || r::text;
  perform unblock_player(D);
  r := unblock_player(P);
  assert not (r->>'blocked')::boolean;
  perform expect_error(format('select unblock_player(%L)', P), 'You haven''t blocked them');
  assert get_me()->'blocked' = '[]'::jsonb and blocked_list() = '[]'::jsonb;
  assert not (get_player(P)->>'blocked')::boolean;
  perform send_message(dm_channel(P), 'ok, talk');
  assert exists (select 1 from jsonb_array_elements(get_conversations()) e where e->>'other_id' = P::text);
  assert exists (select 1 from jsonb_array_elements(get_messages('global', 200)) e where e->>'body' = 'pest was here');
  assert exists (select 1 from jsonb_array_elements(forum_list('war')->'threads') e where e->>'title' = 'Pest thread' and not (e->>'hidden')::boolean and e->>'snippet' = 'Listen to me');
end $$;
select as_user('bb222222-2222-2222-2222-222222222222');
do $$ begin
  perform send_message(dm_channel('bb111111-1111-1111-1111-111111111111'), 'finally');
  assert not (get_player('bb111111-1111-1111-1111-111111111111')->>'blocked_me')::boolean;
end $$;

-- Grants: the new RPCs are for signed-in players; the helpers and the table are private --------------------------------
do $$ declare f text; begin
  foreach f in array array['block_player(uuid)', 'unblock_player(uuid)', 'blocked_list()', 'get_me()', 'get_player(uuid)',
                           'send_message(text,text)', 'get_messages(text,integer)', 'get_conversations()', 'crew_apply(uuid)',
                           'cartel_invite(uuid)', 'forum_list(text,integer)', 'forum_thread(bigint,integer)'] loop
    assert has_function_privilege('authenticated', f, 'execute') and not has_function_privilege('anon', f, 'execute'), f;
  end loop;
  foreach f in array array['_has_blocked(uuid,uuid)', '_blocked_pair(uuid,uuid)', '_dm_other(text,uuid)'] loop
    assert not has_function_privilege('authenticated', f, 'execute'), f || ' should be private';
  end loop;
  assert not has_table_privilege('authenticated', 'blocked_players', 'select') and not has_table_privilege('anon', 'blocked_players', 'select');
end $$;

select 'BLOCK TEST PASSED';
