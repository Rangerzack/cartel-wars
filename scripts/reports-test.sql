-- Tests for reporting and moderating content (#10): reports of chat messages, forum threads and replies (who can report
-- what, reasons, the shared daily limit), the queue (kind, ref, text, live), deleting a message / reply / thread, the
-- mute ladder and unmute, the activity lines and log rows, grants.
-- Run after the other suites (reuses their helpers): scripts/local-db.sh test
\set ON_ERROR_STOP on
\set QUIET on

-- the error a statement raises, or null
create or replace function error_of(sql text) returns text language plpgsql as $$
begin
  execute sql;
  return null;
exception when others then return sqlerrm;
end $$;

insert into auth.users (id, raw_user_meta_data) values
  ('de111111-1111-1111-1111-111111111111', '{"name":"Marshal"}'),
  ('de222222-2222-2222-2222-222222222222', '{"name":"Tipster"}'),
  ('de333333-3333-3333-3333-333333333333', '{"name":"Mouthy"}'),
  ('de444444-4444-4444-4444-444444444444', '{"name":"Outsider"}');
update profiles set is_admin = true where id = 'de111111-1111-1111-1111-111111111111';

-- Mouthy talks: two global lines, two DMs to the tipster, crew chat, a thread and two replies. A thug's line too.
select as_user('de333333-3333-3333-3333-333333333333');
do $$ declare tid bigint; begin
  perform crew_create('Loud Crew', '📢', 'We shout.');
  perform update_profile(null, 'Loud and proud');
  perform send_message('global', 'you are trash');
  perform send_message('global', 'buy my stuff');
  perform send_message(dm_channel('de222222-2222-2222-2222-222222222222'), 'first');
  perform send_message(dm_channel('de222222-2222-2222-2222-222222222222'), 'watch your back');
  perform send_message('crew:' || (select crew_id from profiles where id = auth.uid()), 'loud crew only');
  tid := (forum_create_thread('general', 'Mouthy thread', 'Read my rant')->>'id')::bigint;
end $$;
select as_user('de222222-2222-2222-2222-222222222222');
do $$ begin
  perform send_message('global', 'tipster here');
  perform forum_create_thread('general', 'Tipster thread', 'Calm talk');
end $$;
-- (replies directly, past the ten-second cooldown)
insert into forum_posts (thread_id, author_id, body) select id, 'de333333-3333-3333-3333-333333333333', 'reply one' from forum_threads where title = 'Tipster thread';
insert into forum_posts (thread_id, author_id, body) select id, 'de333333-3333-3333-3333-333333333333', 'reply two' from forum_threads where title = 'Tipster thread';
insert into forum_posts (thread_id, author_id, body) select id, 'de222222-2222-2222-2222-222222222222', 'my own reply' from forum_threads where title = 'Tipster thread';
insert into messages (channel, sender_id, sender_name, body) select 'global', id, name, 'thug talk' from profiles where is_bot order by bot_level limit 1;

-- Reporting -----------------------------------------------------------------------------------------------------------
select as_user('de222222-2222-2222-2222-222222222222');
do $$ declare r jsonb; M uuid := 'de333333-3333-3333-3333-333333333333'; m1 bigint; m3 bigint; t1 bigint; p1 bigint; own bigint; i int; begin
  m1 := (select id from messages where body = 'you are trash');
  m3 := (select id from messages where body = 'watch your back');
  t1 := (select id from forum_threads where title = 'Mouthy thread');
  p1 := (select id from forum_posts where body = 'reply one');
  perform expect_error(format('select report_message(%s, ''spam'')', (select id from messages where body = 'tipster here')), 'You can''t report your own message');
  perform expect_error(format('select report_message(%s, ''spam'')', (select id from messages where body = 'thug talk')), 'Thugs can''t be reported');
  perform expect_error(format('select report_message(%s, ''name'')', m1), 'Pick what''s wrong: harassment, hate, spam, threat or other');
  perform expect_error('select report_message(0, ''spam'')', 'No such message');
  -- someone else's crew chat isn't yours to read, so it isn't yours to report
  perform expect_error(format('select report_message(%s, ''spam'')', (select id from messages where body = 'loud crew only')), 'No such message');
  r := report_message(m1, 'harassment', 'called me trash');
  assert (select row(kind, ref_id, target_id, reason, note) = row('message'::text, m1, M, 'harassment'::text, 'called me trash'::text)
            from profile_reports where id = (r->>'id')::bigint), 'the message report';
  assert (select snapshot from profile_reports where id = (r->>'id')::bigint)
         = jsonb_build_object('kind', 'message', 'text', 'you are trash', 'channel', 'global', 'author', 'Mouthy'), 'snapshot';
  perform expect_error(format('select report_message(%s, ''spam'')', m1), 'You''ve already reported this');
  -- a DM you're part of
  perform report_message(m3, 'threat');
  -- the forum: a thread and a reply; not your own, not something that's gone, not a made-up kind
  perform expect_error(format('select report_forum(''post'', %s, ''spam'')', (select id from forum_posts where body = 'my own reply')), 'You can''t report your own post');
  perform expect_error(format('select report_forum(''thread'', %s, ''spam'')', (select id from forum_threads where title = 'Tipster thread')), 'You can''t report your own post');
  perform expect_error(format('select report_forum(''thread'', %s, ''bio'')', t1), 'Pick what''s wrong');
  perform expect_error(format('select report_forum(''comment'', %s, ''spam'')', t1), 'Report a thread or a reply');
  perform expect_error('select report_forum(''post'', 0, ''spam'')', 'That reply is gone');
  r := report_forum('thread', t1, 'spam', 'ad');
  assert (select snapshot->>'kind' = 'forum_thread' and snapshot->>'text' = 'Read my rant' and snapshot->>'title' = 'Mouthy thread'
             and snapshot->>'category' = 'general' and snapshot->>'author' = 'Mouthy' and kind = 'forum_thread' and ref_id = t1
            from profile_reports where id = (r->>'id')::bigint), 'thread snapshot';
  perform expect_error(format('select report_forum(''thread'', %s, ''hate'')', t1), 'already reported this');
  r := report_forum('post', p1, 'hate');
  assert (select snapshot->>'kind' = 'forum_post' and snapshot->>'text' = 'reply one' and snapshot->>'title' = 'Tipster thread'
             and kind = 'forum_post' and ref_id = p1 and target_id = M from profile_reports where id = (r->>'id')::bigint), 'post snapshot';
  -- the profile is a different thing to report, and keeps its four reasons
  perform expect_error(format('select report_profile(%L, ''hate'')', M), 'Pick what''s wrong: name, avatar, bio or other');
  perform report_profile(M, 'bio', 'loud bio');
  perform expect_error(format('select report_profile(%L, ''name'')', M), 'You''ve already reported them');
  -- 10 a day across every kind: five sent, five more (other kinds, already closed) reach the limit
  for i in 1..5 loop
    insert into profile_reports (reporter_id, target_id, kind, ref_id, reason, status)
    values (auth.uid(), M, 'message', (select id from messages where body = 'first'), 'spam', 'dismissed');
  end loop;
  perform expect_error(format('select report_message(%s, ''spam'')', (select id from messages where body = 'buy my stuff')), '10 reports a day');
  perform expect_error(format('select report_forum(''post'', %s, ''spam'')', (select id from forum_posts where body = 'reply two')), '10 reports a day');
  perform expect_error(format('select report_profile(%L, ''name'')', 'de444444-4444-4444-4444-444444444444'), '10 reports a day');
  update profile_reports set created_at = now() - interval '25 hours' where reporter_id = auth.uid() and status = 'dismissed';
end $$;

-- the outsider reports the second reply and the other global line
select as_user('de444444-4444-4444-4444-444444444444');
do $$ begin
  perform report_forum('post', (select id from forum_posts where body = 'reply two'), 'harassment');
  perform report_message((select id from messages where body = 'buy my stuff'), 'spam', 'spam');
end $$;

-- Mouthy takes down his own first reply: the queue shows that report as no longer live
select as_user('de333333-3333-3333-3333-333333333333');
do $$ begin perform forum_delete('post', (select id from forum_posts where body = 'reply one')); end $$;

-- The queue -----------------------------------------------------------------------------------------------------------
select as_user('de111111-1111-1111-1111-111111111111');
do $$ declare q jsonb; e jsonb; M uuid := 'de333333-3333-3333-3333-333333333333'; begin
  q := mod_queue();
  select x into e from jsonb_array_elements(q) x where x->>'id' = M::text;
  assert jsonb_array_length(e->'reports') = 7, e::text;
  assert e->'muted_until' = 'null'::jsonb;
  assert exists (select 1 from jsonb_array_elements(e->'reports') r where r->>'kind' = 'message' and (r->>'ref_id')::bigint = (select id from messages where body = 'you are trash')
                   and r->>'text' = 'you are trash' and (r->>'live')::boolean and r->>'reason' = 'harassment' and r->>'reporter' = 'Tipster'), e::text;
  assert exists (select 1 from jsonb_array_elements(e->'reports') r where r->>'kind' = 'forum_post' and r->>'text' = 'reply one' and not (r->>'live')::boolean), 'deleted reply: not live';
  assert exists (select 1 from jsonb_array_elements(e->'reports') r where r->>'kind' = 'forum_post' and r->>'text' = 'reply two' and (r->>'live')::boolean);
  assert exists (select 1 from jsonb_array_elements(e->'reports') r where r->>'kind' = 'forum_thread' and r->>'text' = 'Read my rant' and (r->>'live')::boolean);
  assert exists (select 1 from jsonb_array_elements(e->'reports') r where r->>'kind' = 'profile' and r->'live' = 'null'::jsonb and r->'ref_id' = 'null'::jsonb);
  -- reports_open counts players, whatever they were reported for
  assert (get_me()->>'reports_open')::int = (select count(distinct target_id) from profile_reports where status = 'open');
end $$;

-- Deleting content -----------------------------------------------------------------------------------------------------
do $$ declare r jsonb; M uuid := 'de333333-3333-3333-3333-333333333333'; m1 bigint; p2 bigint; t1 bigint; open_before int; begin
  m1 := (select id from messages where body = 'you are trash');
  p2 := (select id from forum_posts where body = 'reply two');
  t1 := (select id from forum_threads where title = 'Mouthy thread');
  perform expect_error(format('select mod_action(%L, ''delete_message'')', M), 'Missing message');
  perform expect_error(format('select mod_action(%L, ''delete_message'', %s)', M, (select id from messages where body = 'tipster here')), 'No such message from them');
  open_before := (select count(*) from profile_reports where target_id = M and status = 'open');
  -- a message: blanked and flagged, only its own report closes
  r := mod_action(M, 'delete_message', m1);
  assert r->>'old' = 'you are trash' and (r->>'reports')::int = 1, r::text;
  assert (select body = '' and deleted from messages where id = m1);
  assert (select status from profile_reports where kind = 'message' and ref_id = m1 and reason = 'harassment') = 'actioned';
  assert (select count(*) from profile_reports where target_id = M and status = 'open') = open_before - 1;
  perform expect_error(format('select mod_action(%L, ''delete_message'', %s)', M, m1), 'That message is already gone');
  -- a reply: the forum's soft delete, its report closes
  r := mod_action(M, 'delete_post', p2);
  assert r->>'old' = 'reply two' and (r->>'reports')::int = 1 and (select deleted from forum_posts where id = p2), r::text;
  perform expect_error(format('select mod_action(%L, ''delete_post'', %s)', M, p2), 'That reply is already gone');
  perform expect_error(format('select mod_action(%L, ''delete_post'', %s)', M, (select id from forum_posts where body = 'my own reply')), 'No such reply from them');
  -- a thread
  r := mod_action(M, 'delete_thread', t1);
  assert r->>'old' = 'Mouthy thread' and (r->>'reports')::int = 1 and (select deleted from forum_threads where id = t1), r::text;
  perform expect_error(format('select mod_action(%L, ''delete_thread'', %s)', M, (select id from forum_threads where title = 'Tipster thread')), 'No such thread from them');
  -- a DM: the conversation's last line falls back to the one before
  perform mod_action(M, 'delete_message', (select id from messages where body = 'watch your back'));
end $$;

-- what players see of the deleted content
select as_user('de222222-2222-2222-2222-222222222222');
do $$ declare r jsonb; begin
  assert exists (select 1 from jsonb_array_elements(get_messages('global', 200)) e
                  where (e->>'id')::bigint = (select id from messages where sender_name = 'Mouthy' and deleted and channel = 'global')
                    and (e->>'deleted')::boolean and e->>'body' = ''), 'get_messages flags it';
  assert not exists (select 1 from jsonb_array_elements(get_messages('global', 200)) e where e->>'body' = 'you are trash');
  assert exists (select 1 from jsonb_array_elements(get_messages('global', 200)) e where e->>'body' = 'tipster here' and not (e->>'deleted')::boolean);
  assert (select e->>'last' from jsonb_array_elements(get_conversations()) e where e->>'other_id' = 'de333333-3333-3333-3333-333333333333') = 'first';
  r := forum_thread((select id from forum_threads where title = 'Tipster thread'));
  assert exists (select 1 from jsonb_array_elements(r->'posts') p where (p->>'deleted')::boolean and p->'body' = 'null'::jsonb
                   and (p->>'id')::bigint = (select id from forum_posts where body = 'reply two')), r::text;
  perform expect_error(format('select forum_thread(%s)', (select id from forum_threads where title = 'Mouthy thread')), 'That thread is gone');
  -- and deleted content can't be reported again
  perform expect_error(format('select report_message(%s, ''spam'')', (select id from messages where sender_name = 'Mouthy' and deleted and channel = 'global')), 'That message is gone');
  perform expect_error(format('select report_forum(''thread'', %s, ''spam'')', (select id from forum_threads where title = 'Mouthy thread')), 'That thread is gone');
end $$;

-- The mute ladder ------------------------------------------------------------------------------------------------------
select as_user('de111111-1111-1111-1111-111111111111');
do $$ declare r jsonb; M uuid := 'de333333-3333-3333-3333-333333333333'; open_before int; begin
  perform expect_error(format('select mod_action(%L, ''unmute'')', M), 'They aren''t muted');
  perform expect_error(format('select mod_action(%L, ''mute_1d'')', (select id from profiles where is_bot limit 1)), 'Thugs can''t be moderated');
  perform expect_error(format('select mod_action(%L, ''mute_2d'')', M), 'Unknown action');
  open_before := (select count(*) from profile_reports where target_id = M and status = 'open');
  assert open_before = 3, 'the dead reply, the profile and the spam line: ' || open_before;
  -- a mute closes everything open on them
  r := mod_action(M, 'mute_1d');
  assert (r->>'reports')::int = 3 and r->'old' = 'null'::jsonb and (r->>'new')::timestamptz = now() + interval '1 day', r::text;
  assert (select muted_until from profiles where id = M) = now() + interval '1 day';
  assert not exists (select 1 from profile_reports where target_id = M and status = 'open');
  -- the admin sees it on the profile; nobody else does
  assert (get_player(M)->>'muted_until')::timestamptz = now() + interval '1 day';
  perform as_user('de222222-2222-2222-2222-222222222222');
  assert get_player(M)->'muted_until' = 'null'::jsonb;
  perform as_user('de111111-1111-1111-1111-111111111111');
end $$;

-- muted: no chat, no forum posts or edits, no new bio or crew description; the exact text says until when
select as_user('de333333-3333-3333-3333-333333333333');
do $$ declare want text; tid bigint := (select id from forum_threads where title = 'Tipster thread'); begin
  want := 'You''re muted until ' || to_char((select muted_until from profiles where id = auth.uid()) at time zone 'UTC', 'Mon DD HH24:MI') || ' UTC';
  assert want ~ '^You''re muted until [A-Z][a-z]{2} \d\d \d\d:\d\d UTC$', want;
  assert error_of('select send_message(''global'', ''let me talk'')') = want, error_of('select send_message(''global'', ''let me talk'')');
  assert error_of(format('select send_message(%L, ''psst'')', dm_channel('de222222-2222-2222-2222-222222222222'))) = want;
  assert error_of('select forum_create_thread(''general'', ''Muted thread'', ''hello'')') = want;
  assert error_of(format('select forum_reply(%s, ''hello'')', tid)) = want;
  assert error_of(format('select forum_edit(''post'', %s, ''edited'')', (select id from forum_posts where body = 'reply one'))) = want;
  assert error_of('select update_profile(null, ''New bio'')') = want;
  assert error_of('select crew_update(''📢'', ''New description'')') = want;
  -- what isn't speech still works: the avatar, the emblem, an unchanged text, clearing the bio
  perform update_profile('🤐', 'Loud and proud');
  perform crew_update('🔇', 'We shout.');
  perform update_profile(null, '');
  assert (select avatar = '🤐' and bio = '' from profiles where id = auth.uid());
  assert (get_me()->>'muted_until')::timestamptz = (select muted_until from profiles where id = auth.uid());
end $$;

-- a longer mute replaces the shorter one; reported while muted, the queue says so; then the admin lifts it
select as_user('de444444-4444-4444-4444-444444444444');
do $$ begin perform report_profile('de333333-3333-3333-3333-333333333333', 'avatar', 'zipped mouth'); end $$;
select as_user('de111111-1111-1111-1111-111111111111');
do $$ declare r jsonb; M uuid := 'de333333-3333-3333-3333-333333333333'; was timestamptz := (select muted_until from profiles where id = M); begin
  assert (select (x->>'muted_until')::timestamptz from jsonb_array_elements(mod_queue()) x where x->>'id' = M::text) = was, 'queue shows the mute';
  r := mod_action(M, 'mute_7d');
  assert (r->>'old')::timestamptz = was and (r->>'new')::timestamptz = now() + interval '7 days' and (r->>'reports')::int = 1, r::text;
  r := mod_action(M, 'mute_30d');
  assert (r->>'new')::timestamptz = now() + interval '30 days' and (r->>'reports')::int = 0, r::text;
end $$;
select as_user('de444444-4444-4444-4444-444444444444');
do $$ begin perform report_profile('de333333-3333-3333-3333-333333333333', 'name', 'still loud'); end $$;
select as_user('de111111-1111-1111-1111-111111111111');
do $$ declare r jsonb; M uuid := 'de333333-3333-3333-3333-333333333333'; begin
  -- lifting a mute leaves open reports for the admin to look at
  r := mod_action(M, 'unmute');
  assert (r->>'reports')::int = 0 and r->'new' = 'null'::jsonb and (select muted_until from profiles where id = M) is null, r::text;
  assert exists (select 1 from profile_reports where target_id = M and status = 'open' and note = 'still loud');
  perform expect_error(format('select mod_action(%L, ''unmute'')', M), 'They aren''t muted');
  -- profile actions still close everything open on the player, content reports included
  perform mod_action(M, 'dismiss');
end $$;
select as_user('de222222-2222-2222-2222-222222222222');
do $$ begin
  perform report_message((select id from messages where body = 'first'), 'other', 'meh');
  perform report_profile('de333333-3333-3333-3333-333333333333', 'avatar');
end $$;
select as_user('de111111-1111-1111-1111-111111111111');
do $$ declare r jsonb; begin
  r := mod_action('de333333-3333-3333-3333-333333333333', 'reset_avatar');
  assert (r->>'reports')::int = 2, r::text;
end $$;

-- unmuted: talking again
select as_user('de333333-3333-3333-3333-333333333333');
do $$ declare a jsonb; begin
  assert get_me()->'muted_until' = 'null'::jsonb;
  perform send_message('global', 'I am back');
  perform update_profile(null, 'Quieter now');
  -- the activity lines: one per action, the mutes with their end
  a := get_activity(100);
  assert (select array_agg(e->'data'->>'action' order by (e->>'id')::bigint) from jsonb_array_elements(a) e where e->>'kind' = 'moderated')
         = array['delete_message', 'delete_post', 'delete_thread', 'delete_message', 'mute_1d', 'mute_7d', 'mute_30d', 'unmute', 'reset_avatar'], a::text;
  assert (select bool_and(e->'data'->>'until' is not null) from jsonb_array_elements(a) e where e->'data'->>'action' like 'mute\_%');
  assert (select bool_and(e->'data'->>'until' is null) from jsonb_array_elements(a) e where e->'data'->>'action' not like 'mute\_%' and e->>'kind' = 'moderated');
end $$;

-- the log
select as_user('de111111-1111-1111-1111-111111111111');
do $$ declare l jsonb; begin
  l := mod_log_list(20);
  assert (select array_agg(e->>'action' order by (e->>'id')::bigint) from jsonb_array_elements(l) e where e->>'target' = 'Mouthy')
         = array['delete_message', 'delete_post', 'delete_thread', 'delete_message', 'mute_1d', 'mute_7d', 'mute_30d', 'unmute', 'dismiss', 'reset_avatar'], l::text;
  assert exists (select 1 from jsonb_array_elements(l) e where e->>'action' = 'delete_message' and e->>'old' = 'you are trash' and (e->>'reports')::int = 1 and e->>'admin' = 'Marshal');
  assert exists (select 1 from jsonb_array_elements(l) e where e->>'action' = 'mute_1d' and (e->>'reports')::int = 3 and e->>'new' is not null);
end $$;

-- players can't act
select as_user('de222222-2222-2222-2222-222222222222');
do $$ begin
  perform expect_error('select mod_action(''de333333-3333-3333-3333-333333333333'', ''mute_1d'')', 'Admins only');
  perform expect_error(format('select mod_action(''de333333-3333-3333-3333-333333333333'', ''delete_message'', %s)', (select id from messages where body = 'buy my stuff')), 'Admins only');
end $$;

-- Grants: the new and changed RPCs are for signed-in players; the helpers are private; the old mod_action is gone ------
do $$ declare f text; begin
  foreach f in array array['report_message(bigint,text,text)', 'report_forum(text,bigint,text,text)', 'report_profile(uuid,text,text)',
                           'mod_action(uuid,text,bigint)', 'mod_queue()', 'mod_words(text,text,text,boolean)', 'get_me()', 'get_player(uuid)',
                           'get_messages(text,integer)', 'get_conversations()', 'send_message(text,text)', 'forum_create_thread(text,text,text)',
                           'forum_reply(bigint,text)', 'forum_edit(text,bigint,text,text)', 'crew_update(text,text)', 'update_profile(text,text)'] loop
    assert has_function_privilege('authenticated', f, 'execute') and not has_function_privilege('anon', f, 'execute'), f;
  end loop;
  foreach f in array array['_report_guard(uuid,uuid,text,bigint)', '_report_live(text,bigint)', '_check_muted(uuid)', '_is_blocked_hard(text)'] loop
    assert not has_function_privilege('authenticated', f, 'execute') and not has_function_privilege('anon', f, 'execute'), f || ' should be private';
  end loop;
  assert to_regprocedure('mod_action(uuid,text)') is null, 'the two-argument mod_action is gone';
end $$;

select 'REPORTS TEST PASSED';
