-- Tests for profile moderation: the word filter, name rules and renames, reports, and the admin queue and actions.
-- Run after the other suites (reuses their helpers): scripts/local-db.sh test
\set ON_ERROR_STOP on
\set QUIET on

insert into auth.users (id, raw_user_meta_data) values
  ('ab111111-1111-1111-1111-111111111111', '{"name":"Warden"}'),
  ('ab222222-2222-2222-2222-222222222222', '{"name":"Snitch"}'),
  ('ab333333-3333-3333-3333-333333333333', '{"name":"Rowdy"}'),
  ('ab444444-4444-4444-4444-444444444444', '{"name":"SH1THEAD"}');      -- a blocked name at sign-up
update profiles set is_admin = true where id = 'ab111111-1111-1111-1111-111111111111';

-- The filter ------------------------------------------------------------------------------------------------
do $$ declare t text; begin
  foreach t in array array['FuckBoy', 'f.u.c.k', 'fuuuuck', 'Sh1tHead', 'BigDick', 'xNiGGeRx', 'ass', 'big ass', 'P0RNSTAR'] loop
    assert _is_blocked(t), t || ' should be blocked';
  end loop;
  -- whole-word and inside-a-word matches leave ordinary words alone
  foreach t in array array['Assassin', 'Hitman', 'BossHitman', 'Dickens', 'Cocktail', 'Grape', 'Analyst', 'Peacock', 'Therapist',
                           'Classic', 'Torpedo', 'Pedometer', 'Mesmerized', '][LLUM][NAT][', '🕶️', 'Eating beets and smacking cheeks'] loop
    assert not _is_blocked(t), t || ' should be allowed';
  end loop;
end $$;

-- Names ----------------------------------------------------------------------------------------------------
select as_user('ab333333-3333-3333-3333-333333333333');
do $$ declare r jsonb; begin
  assert (check_name('Kingpin')->>'ok')::boolean;
  assert check_name('ro')->>'why' = 'Names are 3 to 20 characters';
  assert check_name('snitch')->>'why' = 'That name is taken', 'any case';
  assert (check_name('rowdy')->>'ok')::boolean, 'your own name in another case is yours';
  assert check_name('player_12345678')->>'why' = 'That name is reserved';
  assert check_name('Thug 42')->>'why' = 'That name is reserved';
  assert check_name('BigDick')->>'why' = 'That name isn''t allowed';
  -- a normal name can't be changed
  perform get_me();
  assert not (get_me()->>'name_required')::boolean;
  perform expect_error('select choose_name(''Rowdier'')', 'only be changed after an admin resets');
  -- avatars and bios go through the filter too
  perform expect_error('select update_profile(''FUCK'', null)', 'That avatar isn''t allowed');
  perform expect_error('select update_profile(null, ''eat sh1t'')', 'bio has a word that isn''t allowed');
  perform update_profile('🤑', 'Cocktails on the roof');
  assert (select avatar from profiles where id = auth.uid()) = '🤑';
end $$;

-- a blocked name at sign-up becomes a placeholder, and the player is asked for a new one
select as_user('ab444444-4444-4444-4444-444444444444');
do $$ declare m jsonb; begin
  m := get_me();
  assert m->>'name' like 'player\_%' and (m->>'name_required')::boolean, 'placeholder: ' || (m->>'name');
  perform expect_error('select choose_name(''BigDick'')', 'isn''t allowed');
  perform expect_error('select choose_name(''Snitch'')', 'taken');
  perform choose_name('  Clean Slate ');
  m := get_me();
  assert m->>'name' = 'Clean Slate' and not (m->>'name_required')::boolean;
  perform expect_error('select choose_name(''Again'')', 'only be changed');
end $$;

-- Reports --------------------------------------------------------------------------------------------------
select as_user('ab222222-2222-2222-2222-222222222222');
do $$ declare r jsonb; target uuid := 'ab333333-3333-3333-3333-333333333333'; i int; begin
  perform get_me();
  perform expect_error(format('select report_profile(%L, ''name'')', auth.uid()), 'yourself');
  perform expect_error(format('select report_profile(%L, ''name'')', (select id from profiles where is_bot limit 1)), 'Thugs');
  perform expect_error(format('select report_profile(%L, ''vibes'')', target), 'Pick what');
  r := report_profile(target, 'avatar', 'that face is rude');
  assert (select snapshot->>'avatar' from profile_reports where id = (r->>'id')::bigint) = '🤑', 'snapshot kept';
  perform expect_error(format('select report_profile(%L, ''bio'')', target), 'already reported');
  -- ten a day
  update profile_reports set created_at = now() - interval '1 hour' where reporter_id = auth.uid();
  for i in 1..9 loop
    insert into profile_reports (reporter_id, target_id, reason, status) values (auth.uid(), (select id from profiles where not is_bot and id <> auth.uid() and id <> target offset i limit 1), 'other', 'dismissed');
  end loop;
  perform expect_error(format('select report_profile(%L, ''name'')', 'ab444444-4444-4444-4444-444444444444'), '10 reports a day');
  -- players can't see the queue or act
  perform expect_error('select mod_queue()', 'Admins only');
  perform expect_error(format('select mod_action(%L, ''reset_name'')', target), 'Admins only');
  perform expect_error('select mod_words()', 'Admins only');
end $$;

-- The admin: queue, actions, the log, the word list ------------------------------------------------------------
select as_user('ab111111-1111-1111-1111-111111111111');
do $$ declare q jsonb; r jsonb; target uuid := 'ab333333-3333-3333-3333-333333333333'; f jsonb; begin
  assert (get_me()->>'is_admin')::boolean and (get_me()->>'reports_open')::int >= 1;
  q := mod_queue();
  assert exists (select 1 from jsonb_array_elements(q) e where e->>'id' = target::text
                   and e->'reports'->0->>'reason' = 'avatar' and e->'reports'->0->>'reporter' = 'Snitch'
                   and e->'reports'->0->>'note' = 'that face is rude'), q::text;
  -- reset the avatar: the report closes, it's logged, and they hear about it
  r := mod_action(target, 'reset_avatar');
  assert r->>'old' = '🤑' and (r->>'reports')::int = 1 and (select avatar from profiles where id = target) = '🕶️', r::text;
  assert (select status from profile_reports where target_id = target order by id desc limit 1) = 'actioned';
  assert not exists (select 1 from jsonb_array_elements(mod_queue()) e where e->>'id' = target::text), 'off the queue';
  -- clear the bio, reset the name: they get a placeholder and pick a new one
  perform mod_action(target, 'clear_bio');
  assert (select bio from profiles where id = target) = '';
  r := mod_action(target, 'reset_name');
  assert r->>'old' = 'Rowdy' and r->>'new' like 'player\_%' and (select rename_pending from profiles where id = target), r::text;
  -- dismissing needs open reports; thugs are off limits
  perform expect_error(format('select mod_action(%L, ''dismiss'')', target), 'No open reports');
  perform expect_error(format('select mod_action(%L, ''reset_name'')', (select id from profiles where is_bot limit 1)), 'Thugs keep');
  perform expect_error(format('select mod_action(%L, ''ban'')', target), 'Unknown action');
  -- the log, newest first
  f := mod_log_list(10);
  assert f->0->>'action' = 'reset_name' and f->0->>'admin' = 'Warden' and f->1->>'action' = 'clear_bio' and f->2->>'action' = 'reset_avatar', f::text;
  -- the word list: add, it blocks, remove
  perform expect_error('select mod_words(''add'', ''no way'')', '2–30 letters');
  f := mod_words('add', 'Snitchy', 'part');
  assert exists (select 1 from jsonb_array_elements(f) e where e->>'word' = 'snitchy' and e->>'match' = 'part');
  assert _is_blocked('BigSnitchyMan');
  perform mod_words('remove', 'snitchy');
  assert not _is_blocked('BigSnitchyMan');
  perform expect_error('select mod_words(''remove'', ''snitchy'')', 'Not on the list');
  assert (select count(*) from mod_log where action in ('add_word', 'remove_word')) = 2;
end $$;

-- the reset player: an activity line for each action, the rename prompt, and a new name
select as_user('ab333333-3333-3333-3333-333333333333');
do $$ declare m jsonb; a jsonb; begin
  m := get_me();
  assert (m->>'name_required')::boolean and (m->>'rename_pending')::boolean;
  a := get_activity();
  assert (select count(*) from jsonb_array_elements(a) e where e->>'kind' = 'moderated') = 3, a::text;
  perform choose_name('Rowdy Reformed');
  m := get_me();
  assert m->>'name' = 'Rowdy Reformed' and not (m->>'name_required')::boolean and not (m->>'rename_pending')::boolean;
end $$;

-- a report someone dismisses
select as_user('ab444444-4444-4444-4444-444444444444');
do $$ begin perform report_profile('ab333333-3333-3333-3333-333333333333', 'name', 'still rowdy'); end $$;
select as_user('ab111111-1111-1111-1111-111111111111');
do $$ declare r jsonb; begin
  r := mod_action('ab333333-3333-3333-3333-333333333333', 'dismiss');
  assert (r->>'reports')::int = 1 and (select name from profiles where id = 'ab333333-3333-3333-3333-333333333333') = 'Rowdy Reformed';
  assert (select status from profile_reports where note = 'still rowdy') = 'dismissed';
end $$;

-- Grants: the sign-up check is open to everyone; the filter's insides aren't -------------------------------------
do $$ declare f text; begin
  assert has_function_privilege('anon', 'check_name(text)', 'execute');
  foreach f in array array['report_profile(uuid,text,text)', 'choose_name(text)', 'mod_queue()', 'mod_action(uuid,text)', 'mod_log_list(integer)',
                           'mod_words(text,text,text)'] loop
    assert has_function_privilege('authenticated', f, 'execute') and not has_function_privilege('anon', f, 'execute'), f;
  end loop;
  foreach f in array array['_is_blocked(text)', '_name_problem(text,uuid)', '_leet(text)'] loop
    assert not has_function_privilege('authenticated', f, 'execute'), f || ' should be private';
  end loop;
end $$;

select 'MODERATION TEST PASSED';
