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
  -- split-up words join back into one group (either side ≤ 2 letters, or both ≤ 3), in names and chat alike
  foreach t in array array['FuckBoy', 'f.u.c.k', 'fuuuuck', 'xNiGGeRx', 'f u c k', 'fu ck', 'fuc k', 'nig ger', 'nigg er', 'c.u.n.t', 'kkk',
                           'the kkk rally', 'you f u c k', 'f.u.c.k this', 'white power', 'WhitePower', 'Sieg Heil', 'porch monkey'] loop
    assert _is_blocked(t) and _is_blocked_hard(t), t || ' should be blocked everywhere';
  end loop;
  -- two ordinary words stay apart, so a listed word can't be read across them (musi[c unt]il)
  foreach t in array array['music until dawn', 'panic until the cops leave', 'traffic until 5', 'doc until noon', 'Music Until',
                           'Eating beets and smacking cheeks'] loop
    assert not _is_blocked(t) and not _is_blocked_hard(t), t || ' should be allowed everywhere';
  end loop;
  assert _squash_groups('f u c k off') = array['fuckoff'] and _squash_groups('nigg er') = array['nigger'];
  assert _squash_groups('music until dawn') = array['music', 'until', 'dawn'] and _squash_groups('xNiGGeRx') = array['xniggerx'];
  assert (check_name('Music Until')->>'ok')::boolean;
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
  -- a profile report: no message or post behind it, so no ref, text or live flag
  assert exists (select 1 from jsonb_array_elements(q) e where e->>'id' = target::text and e->'muted_until' = 'null'::jsonb
                   and e->'reports'->0->>'kind' = 'profile' and e->'reports'->0->'ref_id' = 'null'::jsonb
                   and e->'reports'->0->'text' = 'null'::jsonb and e->'reports'->0->'live' = 'null'::jsonb), q::text;
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

-- The filter on crews, cartels, the forum and chat (#11) ------------------------------------------------------------
insert into auth.users (id, raw_user_meta_data) values ('ab555555-5555-5555-5555-555555555555', '{"name":"Potty Mouth"}');
select as_user('ab555555-5555-5555-5555-555555555555');
do $$ declare r jsonb; tid bigint; pid bigint; begin
  perform get_me();
  -- names, emblems, descriptions and titles: every tier, whole words included
  perform expect_error('select crew_create(''Big Dick Crew'')', 'That name isn''t allowed');
  perform expect_error('select crew_create(''Sh1theads'')', 'That name isn''t allowed');
  perform expect_error('select crew_create(''Clean Crew'', ''ASS'')', 'That emblem isn''t allowed');
  perform expect_error('select crew_create(''Clean Crew'', ''🏴'', ''we kick ass'')', 'That description has a word that isn''t allowed');
  perform crew_create('Assassins', '🗡️', 'Quiet work.');
  perform expect_error('select crew_update(''🗡️'', ''f.u.c.k the cops'')', 'That description has a word that isn''t allowed');
  perform expect_error('select cartel_create(''Cock Cartel'')', 'That name isn''t allowed');
  perform cartel_create('Cocktail Hour');
  perform expect_error('select forum_create_thread(''general'', ''Pussy cats'', ''meow'')', 'That title has a word that isn''t allowed');
  -- posts and chat: only the words marked chat, each tier matched its own way, so swearing goes through and slurs don't
  perform expect_error('select forum_create_thread(''general'', ''Fair warning'', ''you r3tard'')', 'That message has a word that isn''t allowed');
  tid := (forum_create_thread('general', 'Fair warning', 'Kiss my ass, Lalo.')->>'id')::bigint;
  perform expect_error(format('select forum_edit(''thread'', %s, ''still fine'', ''Dick moves'')', tid), 'That title has a word that isn''t allowed');
  perform expect_error(format('select forum_edit(''thread'', %s, ''you f u c k'')', tid), 'That message has a word that isn''t allowed');
  perform forum_edit('thread', tid, 'Kiss my ass, Salamanca.', 'Final warning');
  assert (select title from forum_threads where id = tid) = 'Final warning';
  perform expect_error(format('select forum_reply(%s, ''nig ger'')', tid), 'That message has a word that isn''t allowed');
  pid := (forum_reply(tid, 'son of a b1tch')->>'id')::bigint;
  perform forum_edit('post', pid, 'What a dick.');
  perform expect_error(format('select forum_edit(''post'', %s, ''what a cunt'')', pid), 'That message has a word that isn''t allowed');
  perform send_message('global', 'kiss my ass');
  perform send_message('global', 'eat sh1t');
  perform send_message('global', 'bullshit');
  perform send_message('global', 'music until dawn');
  perform expect_error('select send_message(''global'', ''that''''s retarded'')', 'That message has a word that isn''t allowed');
  perform expect_error('select send_message(''global'', ''f.u.c.k this'')', 'That message has a word that isn''t allowed');
  perform expect_error('select send_message(''global'', ''white power'')', 'That message has a word that isn''t allowed');
  -- whole-word slurs marked chat: refused in chat and posts, as whole words only
  perform expect_error('select send_message(''global'', ''you fag'')', 'That message has a word that isn''t allowed');
  perform expect_error('select send_message(''global'', ''Nazi scum'')', 'That message has a word that isn''t allowed');
  perform expect_error(format('select forum_reply(%s, ''shut up homo'')', tid), 'That message has a word that isn''t allowed');
  perform send_message('global', 'grapes and fagioli');
  assert _is_blocked_hard('you f4g') and _is_blocked_hard('rapists') and not _is_blocked_hard('Therapist') and not _is_blocked_hard('a homogeneous crew');
  assert _is_blocked('big ass') and not _is_blocked_hard('big ass') and not _is_blocked_hard('what a dick');
  assert _is_blocked('BigShitHead') and not _is_blocked_hard('BigShitHead') and _is_blocked_hard('BigRetardHead');
  -- names stay strict
  assert check_name('Bullshit')->>'why' = 'That name isn''t allowed';
  perform expect_error('select forum_create_thread(''general'', ''Son of a b1tch'', ''hi'')', 'That title has a word that isn''t allowed');
  -- old messages are left alone
  insert into messages (channel, sender_id, sender_name, body) values ('global', auth.uid(), 'Potty Mouth', 'old r3tard talk');
  assert exists (select 1 from jsonb_array_elements(get_messages('global', 200)) e where e->>'body' = 'old r3tard talk');
end $$;

-- The chat switch: the admin flips "shit" on for chat and off again; each flip is logged ----------------------------
do $$ declare f jsonb; admin text := 'ab111111-1111-1111-1111-111111111111'; potty text := 'ab555555-5555-5555-5555-555555555555'; begin
  perform as_user(admin);
  f := mod_words();
  assert (select bool_and(jsonb_typeof(e->'chat') = 'boolean') from jsonb_array_elements(f) e), 'every word says whether it reaches chat';
  assert exists (select 1 from jsonb_array_elements(f) e where e->>'word' = 'shit' and not (e->>'chat')::boolean);
  assert exists (select 1 from jsonb_array_elements(f) e where e->>'word' = 'retard' and (e->>'chat')::boolean);
  assert exists (select 1 from jsonb_array_elements(f) e where e->>'word' = 'nigger' and (e->>'chat')::boolean);
  f := mod_words('chat', 'Shit');
  assert exists (select 1 from jsonb_array_elements(f) e where e->>'word' = 'shit' and (e->>'chat')::boolean), f::text;
  assert (select new_value from mod_log where action = 'set_word' order by id desc limit 1) = 'shit (part, chat on)';
  perform as_user(potty);
  perform expect_error('select send_message(''global'', ''bullshit'')', 'That message has a word that isn''t allowed');
  perform as_user(admin);
  perform mod_words('chat', 'shit');
  assert (select new_value from mod_log where action = 'set_word' order by id desc limit 1) = 'shit (part, chat off)';
  assert mod_log_list(1)->0->>'action' = 'set_word';
  perform as_user(potty);
  perform send_message('global', 'bullshit');
  perform expect_error('select mod_words(''chat'', ''shit'')', 'Admins only');
  -- whole-word entries carry the switch too: slurs on, crude words off, and the admin can flip either
  perform as_user(admin);
  f := mod_words();
  assert (select bool_and((e->>'chat')::boolean) from jsonb_array_elements(f) e
           where e->>'word' in ('coon', 'paki', 'spic', 'fag', 'dyke', 'homo', 'nazi', 'heil', 'rape', 'rapist', 'pedo')), 'whole-word slurs block chat';
  assert not (select bool_or((e->>'chat')::boolean) from jsonb_array_elements(f) e
               where e->>'word' in ('dick', 'cock', 'ass', 'arse', 'cum', 'anal', 'anus', 'tits', 'boob', 'pussy', 'twat', 'wank', 'prick')), 'crude whole words don''t';
  f := mod_words('chat', 'dick');
  assert exists (select 1 from jsonb_array_elements(f) e where e->>'word' = 'dick' and e->>'match' = 'word' and (e->>'chat')::boolean), f::text;
  assert (select new_value from mod_log where action = 'set_word' order by id desc limit 1) = 'dick (word, chat on)';
  perform as_user(potty);
  perform expect_error('select send_message(''global'', ''what a dick'')', 'That message has a word that isn''t allowed');
  perform send_message('global', 'Dickens on the shelf');
  perform as_user(admin);
  perform mod_words('chat', 'dick');
  assert (select new_value from mod_log where action = 'set_word' order by id desc limit 1) = 'dick (word, chat off)';
  perform as_user(potty);
  perform send_message('global', 'what a dick');
  perform as_user(admin);
  perform expect_error('select mod_words(''chat'', ''nosuchword'')', 'Not on the list');
  -- added words reach chat unless the admin says otherwise
  perform mod_words('add', 'grassy', 'part');
  perform mod_words('add', 'snitchy', 'part', false);
  assert _is_blocked_hard('a grassy rat') and not _is_blocked_hard('a snitchy rat') and _is_blocked('a snitchy rat');
  assert (select new_value from mod_log where action = 'add_word' order by id desc limit 1) = 'snitchy (part, chat off)';
  perform mod_words('add', 'grub', 'word');
  assert _is_blocked_hard('you grub') and not _is_blocked_hard('grubby');
  assert (select new_value from mod_log where action = 'add_word' order by id desc limit 1) = 'grub (word, chat on)';
  perform mod_words('remove', 'grassy'); perform mod_words('remove', 'snitchy'); perform mod_words('remove', 'grub');
end $$;

-- Grants: the sign-up check is open to everyone; the filter's insides aren't -------------------------------------
do $$ declare f text; begin
  assert has_function_privilege('anon', 'check_name(text)', 'execute');
  foreach f in array array['report_profile(uuid,text,text)', 'choose_name(text)', 'mod_queue()', 'mod_action(uuid,text,bigint)', 'mod_log_list(integer)',
                           'mod_words(text,text,text,boolean)'] loop
    assert has_function_privilege('authenticated', f, 'execute') and not has_function_privilege('anon', f, 'execute'), f;
  end loop;
  foreach f in array array['_is_blocked(text)', '_name_problem(text,uuid)', '_leet(text)', '_blocked_by(text,text[],boolean)', '_is_blocked_hard(text)',
                           '_squash_groups(text)'] loop
    assert not has_function_privilege('authenticated', f, 'execute') and not has_function_privilege('anon', f, 'execute'), f || ' should be private';
  end loop;
  -- the old signatures are gone, so a call can't land on them
  assert to_regprocedure('mod_words(text,text,text)') is null and to_regprocedure('_blocked_by(text,text[])') is null;
end $$;

select 'MODERATION TEST PASSED';
