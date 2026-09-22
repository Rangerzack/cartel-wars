-- Forum smoke test. Run: scripts/local-db.sh test
\set ON_ERROR_STOP on
\set QUIET on

insert into auth.users (id, email, raw_user_meta_data) values
  ('66666666-6666-6666-6666-666666666666', 'zack@rangelab.io', '{"name":"TheDon"}'),
  ('77777777-7777-7777-7777-777777777777', 'newbie@test.local', '{"name":"Newbie"}')
on conflict do nothing;

create or replace function as_user(u text) returns void language sql as $$
  select set_config('request.jwt.claims', json_build_object('sub', u)::text, false) $$;
create or replace function expect_error(sql text, needle text) returns void language plpgsql as $$
begin
  execute sql; raise exception 'expected error containing "%" from: %', needle, sql;
exception when others then
  if sqlerrm not like '%' || needle || '%' then raise exception 'wrong error: % (wanted "%")', sqlerrm, needle; end if;
end $$;

do $$ declare A text := '66666666-6666-6666-6666-666666666666'; N text := '77777777-7777-7777-7777-777777777777'; r jsonb; tid bigint; pid bigint; c jsonb; begin
  -- admin flag from the admins list at registration
  assert (select is_admin from profiles where id = A::uuid), 'zack is admin';
  assert not (select is_admin from profiles where id = N::uuid), 'newbie is not';

  perform as_user(N);
  r := forum_categories();
  assert jsonb_array_length(r->'categories') = 7 and not (r->>'is_admin')::boolean, r::text;
  assert r->'categories'->0->>'key' = 'updates' and r->'categories'->6->>'key' = 'suggestions';
  perform expect_error('select forum_create_thread(''updates'', ''Patch notes'', ''x'')', 'Only the game team');
  perform expect_error('select forum_create_thread(''nope'', ''hi'', ''x'')', 'No such board');
  perform expect_error('select forum_create_thread(''general'', ''hi'', ''x'')', 'title');
  perform expect_error('select forum_create_thread(''general'', ''hello there'', ''   '')', 'Write something');
  r := forum_create_thread('new_player', 'How do I get out of jail?', 'Been stuck for an hour, what do I do?');
  tid := (r->>'id')::bigint;
  perform expect_error('select forum_create_thread(''general'', ''second one'', ''too fast'')', 'Slow down');
  r := forum_list('new_player');
  assert (r->>'total')::int = 1 and (r->>'can_post')::boolean and r->'threads'->0->>'title' = 'How do I get out of jail?', r::text;
  assert r->'threads'->0->'author'->>'name' = 'Newbie';
  r := forum_list('updates');
  assert not (r->>'can_post')::boolean, 'newbie cannot start threads in updates';

  -- admin posts an update, pins it; newbie replies
  perform as_user(A);
  r := forum_create_thread('updates', 'Casino opens Friday', 'Slots first, tables after.');
  perform forum_moderate((r->>'id')::bigint, 'pin');
  r := forum_create_thread('updates', 'Second update', 'admins skip the cooldown');
  r := forum_list('updates');
  assert (r->>'total')::int = 2 and (r->'threads'->0->>'pinned')::boolean and r->'threads'->0->>'title' = 'Casino opens Friday', 'pinned first: ' || r::text;
  perform as_user(N);
  perform expect_error('select forum_moderate(1, ''pin'')', 'Admins only');
  r := forum_reply(tid, 'Bribe the guard on the Actions page.');
  pid := (r->>'id')::bigint;
  perform expect_error(format('select forum_reply(%s, ''again'')', tid), 'Slow down');
  r := forum_thread(tid);
  assert (r->'thread'->>'reply_count')::int = 1 and jsonb_array_length(r->'posts') = 1 and (r->'thread'->>'mine')::boolean, r::text;
  assert r->'posts'->0->>'body' = 'Bribe the guard on the Actions page.' and (r->'posts'->0->>'mine')::boolean;
  assert r->'thread'->>'last_poster' = 'Newbie';
  -- edit own post, delete own post
  perform forum_edit('post', pid, 'Bribe the guard (Services page).');
  r := forum_thread(tid);
  assert r->'posts'->0->>'body' = 'Bribe the guard (Services page).' and r->'posts'->0->>'edited_at' is not null;
  perform forum_delete('post', pid);
  r := forum_thread(tid);
  assert (r->'posts'->0->>'deleted')::boolean and r->'posts'->0->'body' = 'null'::jsonb, 'deleted post hides body';
  -- can't touch others' posts
  perform as_user(A);
  update forum_posts set created_at = created_at - interval '1 minute' where author_id = A::uuid;
  r := forum_reply(tid, 'Admin here: also try the lawyer.');
  perform as_user(N);
  perform expect_error(format('select forum_delete(''post'', %s)', (r->>'id')::bigint), 'Nothing to delete');
  perform expect_error(format('select forum_edit(''post'', %s, ''hijack'')', (r->>'id')::bigint), 'Nothing to edit');
  -- lock stops replies (except admins), delete hides the thread
  perform as_user(A);
  perform forum_moderate(tid, 'lock');
  perform as_user(N);
  update forum_posts set created_at = created_at - interval '1 minute' where author_id = N::uuid;
  perform expect_error(format('select forum_reply(%s, ''one more'')', tid), 'locked');
  r := forum_thread(tid);
  assert (r->'thread'->>'locked')::boolean and not (r->>'can_reply')::boolean;
  perform as_user(A);
  perform forum_moderate(tid, 'move', 'general');
  assert (forum_list('general')->>'total')::int = 1 and (forum_list('new_player')->>'total')::int = 0, 'moved';
  perform forum_delete('thread', tid);
  perform expect_error(format('select forum_thread(%s)', tid), 'gone');
  c := forum_categories();
  assert (c->'categories'->0->>'threads')::int = 2 and (c->'categories'->3->>'threads')::int = 0, c::text;
  assert c->'categories'->0->'last'->>'title' is not null;
end $$;

\echo 'FORUM TEST PASSED'
