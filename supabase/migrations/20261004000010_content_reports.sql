-- Reporting and moderating chat messages and forum posts (#10). Apple guideline 1.2 asks for "a mechanism to report
-- offensive content and timely responses to concerns": reports covered profiles only, and chat had no way to act on it.
--
--  * Reports: profile_reports (the name stays; the notify trigger from 0009 is on it) now also holds reports of a chat
--    message, a forum thread or a forum reply: kind and ref_id (the message, thread or post id). report_message(mid,
--    reason, note) and report_forum('thread' | 'post', id, reason, note) take harassment / hate / spam / threat / other,
--    target the sender or author, and keep a snapshot of the text. You can only report what you can read, not your own
--    and not a thug's. One open report per thing you report, and the 10 a day count covers every kind.
--  * Mute: profiles.muted_until. A muted player can't chat, start threads, reply or edit posts, or rewrite their bio or
--    their crew's description (clearing them is fine): "You're muted until Oct 02 14:05 UTC". get_me says until when,
--    and get_player tells admins.
--  * Admin actions (mod_action gets a third argument, ref): delete_message blanks the message and flags it deleted
--    (get_messages returns {deleted: true, body: ''} and clients drop it), delete_post and delete_thread are the forum's
--    own soft delete, and mute_1d / mute_7d / mute_30d / unmute. A delete closes the reports on that message or post; a
--    mute or a profile action closes every open report on the player; lifting a mute closes none. All logged, and the
--    player gets an activity line.
--  * mod_queue(): each report says its kind, ref_id, the text it was about, and whether that text is still up (live).
--  * The word filter's chat switch now covers whole-word entries too, so "you fag" is refused in chat while "kiss my
--    ass" still goes through.

-- ---------------------------------------------------------------------------
-- Reports of content
-- ---------------------------------------------------------------------------
alter table profile_reports add column if not exists kind text not null default 'profile'
  check (kind in ('profile', 'message', 'forum_thread', 'forum_post'));
alter table profile_reports add column if not exists ref_id bigint;
alter table profile_reports add constraint profile_reports_ref_check check ((kind = 'profile') = (ref_id is null));
-- profiles keep their four reasons; content gets its own
alter table profile_reports drop constraint if exists profile_reports_reason_check;
alter table profile_reports add constraint profile_reports_reason_check check (case when kind = 'profile'
  then reason in ('name', 'avatar', 'bio', 'other') else reason in ('harassment', 'hate', 'spam', 'threat', 'other') end);
-- one open report per thing reported: the profile, or one message / thread / reply
drop index if exists profile_reports_one_open;
create unique index profile_reports_one_open on profile_reports (reporter_id, target_id, kind, coalesce(ref_id, 0)) where status = 'open';

alter table mod_log drop constraint if exists mod_log_action_check;
alter table mod_log add constraint mod_log_action_check
  check (action in ('reset_name', 'reset_avatar', 'clear_bio', 'dismiss', 'add_word', 'remove_word', 'set_word',
                    'delete_message', 'delete_post', 'delete_thread', 'mute_1d', 'mute_7d', 'mute_30d', 'unmute'));

-- A deleted message keeps its row (and its place in the history) with the text gone.
alter table messages add column if not exists deleted boolean not null default false;
alter table messages drop constraint if exists messages_body_check;
alter table messages add constraint messages_body_check check (char_length(body) <= 500 and (deleted or char_length(body) >= 1));

alter table profiles add column if not exists muted_until timestamptz;

-- One open report per thing you report, and 10 reports a day of every kind together.
create or replace function _report_guard(u uuid, target uuid, k text, ref bigint) returns void
language plpgsql set search_path = public as $$
begin
  if exists (select 1 from profile_reports r where r.reporter_id = u and r.target_id = target and r.kind = k
               and r.ref_id is not distinct from ref and r.status = 'open') then
    perform _fail(case when k = 'profile' then 'You''ve already reported them — an admin will take a look'
                       else 'You''ve already reported this — an admin will take a look' end);
  end if;
  if (select count(*) from profile_reports r where r.reporter_id = u and r.created_at > now() - interval '24 hours') >= 10 then
    perform _fail('You can send 10 reports a day'); end if;
end $$;

create or replace function report_profile(target uuid, reason text, note text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); t profiles; r profile_reports;
begin
  perform _nn(target, 'player'); perform _nn(reason, 'reason');
  if target = u then perform _fail('You can''t report yourself'); end if;
  select * into t from profiles where id = target;
  if t.id is null then perform _fail('No such player'); end if;
  if t.is_bot then perform _fail('Thugs can''t be reported'); end if;
  if reason not in ('name', 'avatar', 'bio', 'other') then perform _fail('Pick what''s wrong: name, avatar, bio or other'); end if;
  perform _report_guard(u, target, 'profile', null);
  insert into profile_reports (reporter_id, target_id, reason, note, snapshot)
  values (u, target, reason, left(trim(coalesce(note, '')), 200), jsonb_build_object('name', t.name, 'avatar', t.avatar, 'bio', t.bio))
  returning * into r;
  return jsonb_build_object('id', r.id);
end $$;

-- A chat line you can read (a channel you're in, a DM you're part of), not your own.
create or replace function report_message(mid bigint, reason text, note text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); m messages; t profiles; r profile_reports;
begin
  perform _nn(mid, 'message'); perform _nn(reason, 'reason');
  select * into m from messages x where x.id = mid;
  if m.id is null or not _can_use_channel(u, m.channel) then perform _fail('No such message'); end if;
  if m.deleted then perform _fail('That message is gone'); end if;
  if m.sender_id = u then perform _fail('You can''t report your own message'); end if;
  select * into t from profiles p where p.id = m.sender_id;
  if t.is_bot then perform _fail('Thugs can''t be reported'); end if;
  if reason not in ('harassment', 'hate', 'spam', 'threat', 'other') then perform _fail('Pick what''s wrong: harassment, hate, spam, threat or other'); end if;
  perform _report_guard(u, t.id, 'message', mid);
  insert into profile_reports (reporter_id, target_id, kind, ref_id, reason, note, snapshot)
  values (u, t.id, 'message', mid, reason, left(trim(coalesce(note, '')), 200),
          jsonb_build_object('kind', 'message', 'text', m.body, 'channel', m.channel, 'author', m.sender_name))
  returning * into r;
  return jsonb_build_object('id', r.id);
end $$;

-- A forum thread or reply that's still up, not your own. (Params are referenced as report_forum.<name> because kind and
-- id shadow columns.)
create or replace function report_forum(kind text, id bigint, reason text, note text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); th forum_threads; po forum_posts; t profiles; k text; snap jsonb; r profile_reports;
begin
  perform _nn(report_forum.id, 'post'); perform _nn(reason, 'reason');
  if report_forum.kind = 'thread' then
    select * into th from forum_threads x where x.id = report_forum.id and not x.deleted;
    if th.id is null then perform _fail('That thread is gone'); end if;
    k := 'forum_thread';
    snap := jsonb_build_object('text', th.body, 'title', th.title, 'category', th.category);
    select * into t from profiles p where p.id = th.author_id;
  elsif report_forum.kind = 'post' then
    select * into po from forum_posts x where x.id = report_forum.id and not x.deleted;
    select * into th from forum_threads x where x.id = po.thread_id and not x.deleted;
    if po.id is null or th.id is null then perform _fail('That reply is gone'); end if;
    k := 'forum_post';
    snap := jsonb_build_object('text', po.body, 'title', th.title, 'thread_id', th.id, 'category', th.category);
    select * into t from profiles p where p.id = po.author_id;
  else
    perform _fail('Report a thread or a reply');
  end if;
  if t.id = u then perform _fail('You can''t report your own post'); end if;
  if t.is_bot then perform _fail('Thugs can''t be reported'); end if;
  if reason not in ('harassment', 'hate', 'spam', 'threat', 'other') then perform _fail('Pick what''s wrong: harassment, hate, spam, threat or other'); end if;
  perform _report_guard(u, t.id, k, report_forum.id);
  insert into profile_reports (reporter_id, target_id, kind, ref_id, reason, note, snapshot)
  values (u, t.id, k, report_forum.id, reason, left(trim(coalesce(note, '')), 200), snap || jsonb_build_object('kind', k, 'author', t.name))
  returning * into r;
  return jsonb_build_object('id', r.id);
end $$;

-- Is the reported message, thread or reply still up? (null for a profile report)
create or replace function _report_live(k text, ref bigint) returns boolean
language sql stable set search_path = public as $$
  select case k
    when 'message' then exists (select 1 from messages m where m.id = ref and not m.deleted)
    when 'forum_thread' then exists (select 1 from forum_threads t where t.id = ref and not t.deleted)
    when 'forum_post' then exists (select 1 from forum_posts p join forum_threads t on t.id = p.thread_id
                                    where p.id = ref and not p.deleted and not t.deleted)
  end $$;

-- Players with open reports, most recently reported first; each report with what it was about.
create or replace function mod_queue() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not _is_admin(_uid()) then perform _fail('Admins only'); end if;
  return (select coalesce(jsonb_agg(x.j order by x.latest desc), '[]'::jsonb) from (
    select max(r.created_at) as latest, jsonb_build_object(
             'id', t.id, 'name', t.name, 'avatar', t.avatar, 'bio', t.bio, 'rename_pending', t.rename_pending,
             'muted_until', case when t.muted_until > now() then t.muted_until end,
             'reports', jsonb_agg(jsonb_build_object('id', r.id, 'kind', r.kind, 'ref_id', r.ref_id, 'reason', r.reason, 'note', r.note,
                          'snapshot', r.snapshot, 'text', r.snapshot->>'text', 'live', _report_live(r.kind, r.ref_id),
                          'reporter', rp.name, 'reporter_id', r.reporter_id, 'at', r.created_at) order by r.created_at desc)) as j
      from profile_reports r join profiles t on t.id = r.target_id left join profiles rp on rp.id = r.reporter_id
     where r.status = 'open'
     group by t.id) x);
end $$;

-- ---------------------------------------------------------------------------
-- Admin actions
-- ---------------------------------------------------------------------------
drop function if exists mod_action(uuid, text);
create or replace function mod_action(target uuid, action text, ref bigint default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); t profiles; old text; new text; closed int := 0; k text; till timestamptz;
        m messages; th forum_threads; po forum_posts;
begin
  if not _is_admin(u) then perform _fail('Admins only'); end if;
  perform _nn(target, 'player'); perform _nn(action, 'action');
  select * into t from profiles where id = target for update;
  if t.id is null then perform _fail('No such player'); end if;
  if t.is_bot then perform _fail(case when action in ('reset_name', 'reset_avatar', 'clear_bio', 'dismiss') then 'Thugs keep their names'
                                      else 'Thugs can''t be moderated' end); end if;
  case action
    when 'reset_name' then
      old := t.name; new := 'player_' || substr(replace(t.id::text, '-', ''), 1, 8);
      update profiles set name = new, rename_pending = true where id = target;
    when 'reset_avatar' then
      old := t.avatar; new := '🕶️';
      update profiles set avatar = new where id = target;
    when 'clear_bio' then
      old := t.bio; new := '';
      update profiles set bio = '' where id = target;
    when 'dismiss' then null;
    when 'delete_message' then
      perform _nn(ref, 'message');
      select * into m from messages x where x.id = ref for update;
      if m.id is null or m.sender_id <> target then perform _fail('No such message from them'); end if;
      if m.deleted then perform _fail('That message is already gone'); end if;
      old := m.body; k := 'message';
      update messages x set body = '', deleted = true where x.id = ref;
    -- the forum's own soft delete (forum_delete): a reply shows [deleted], a thread's links say it's gone
    when 'delete_post' then
      perform _nn(ref, 'reply');
      select * into po from forum_posts x where x.id = ref for update;
      if po.id is null or po.author_id <> target then perform _fail('No such reply from them'); end if;
      if po.deleted then perform _fail('That reply is already gone'); end if;
      old := po.body; k := 'forum_post';
      update forum_posts x set deleted = true where x.id = ref;
    when 'delete_thread' then
      perform _nn(ref, 'thread');
      select * into th from forum_threads x where x.id = ref for update;
      if th.id is null or th.author_id <> target then perform _fail('No such thread from them'); end if;
      if th.deleted then perform _fail('That thread is already gone'); end if;
      old := th.title; k := 'forum_thread';
      update forum_threads x set deleted = true where x.id = ref;
    -- a new mute replaces the old one, longer or shorter
    when 'mute_1d', 'mute_7d', 'mute_30d' then
      till := now() + make_interval(days => substring(action from '^mute_(\d+)d$')::int);
      old := case when t.muted_until > now() then to_jsonb(t.muted_until) #>> '{}' end; new := to_jsonb(till) #>> '{}';
      update profiles set muted_until = till where id = target;
    when 'unmute' then
      if not coalesce(t.muted_until > now(), false) then perform _fail('They aren''t muted'); end if;
      old := to_jsonb(t.muted_until) #>> '{}';
      update profiles set muted_until = null where id = target;
    else perform _fail('Unknown action');
  end case;
  -- a delete closes the reports on that message or post; the rest close everything open on the player, except an unmute
  if action <> 'unmute' then
    update profile_reports r set status = case when action = 'dismiss' then 'dismissed' else 'actioned' end,
           resolved_by = u, resolved_at = now()
     where r.target_id = target and r.status = 'open' and (k is null or (r.kind = k and r.ref_id = ref));
    get diagnostics closed = row_count;
  end if;
  if action = 'dismiss' and closed = 0 then perform _fail('No open reports on them'); end if;
  insert into mod_log (admin_id, target_id, action, old_value, new_value, reports) values (u, target, action, old, new, closed);
  if action <> 'dismiss' then
    insert into activity (player_id, kind, actor_id, data) values (target, 'moderated', null,
      jsonb_build_object('action', action) || case when till is null then '{}'::jsonb else jsonb_build_object('until', till) end);
  end if;
  return jsonb_build_object('action', action, 'old', old, 'new', new, 'reports', closed);
end $$;

-- ---------------------------------------------------------------------------
-- Mute
-- ---------------------------------------------------------------------------
create or replace function _check_muted(u uuid) returns void
language plpgsql set search_path = public as $$
declare till timestamptz;
begin
  select muted_until into till from profiles where id = u;
  if till > now() then perform _fail('You''re muted until ' || to_char(till at time zone 'UTC', 'Mon DD HH24:MI') || ' UTC'); end if;
end $$;

-- The latest send_message (20261004000007) with the mute.
create or replace function send_message(channel text, body text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); nm text; m messages;
begin
  if channel is null or not _can_use_channel(u, channel) then perform _fail('You cannot post there'); end if;
  perform _check_muted(u);
  if char_length(trim(coalesce(body, ''))) = 0 then perform _fail('Say something first'); end if;
  if channel like 'dm:%' and _blocked_pair(u, _dm_other(channel, u)) then perform _fail('You can''t message them'); end if;
  if _is_blocked_hard(body) then perform _fail('That message has a word that isn''t allowed'); end if;
  select name into nm from profiles where id = u;
  insert into messages (channel, sender_id, sender_name, body) values (channel, u, nm, left(trim(body), 500)) returning * into m;
  return jsonb_build_object('id', m.id);
end $$;

-- 20261004000007's get_messages, with deleted (a deleted line comes back with an empty body; clients don't show it).
create or replace function get_messages(channel text, limit_n integer default 50) returns jsonb
language plpgsql security definer set search_path = public stable as $$
declare u uuid := _uid();
begin
  if not _can_use_channel(u, channel) then perform _fail('You cannot read that channel'); end if;
  return (select coalesce(jsonb_agg(to_jsonb(m) order by m.created_at), '[]'::jsonb)
          from (select x.id, x.sender_id, x.sender_name, x.body, x.created_at, x.deleted from messages x
                 where x.channel = get_messages.channel
                   and (get_messages.channel like 'dm:%' or not _has_blocked(u, x.sender_id))
                 order by x.created_at desc limit limit_n) m);
end $$;

-- 20261004000007's get_conversations: a deleted message is neither the last line nor unread.
create or replace function get_conversations() returns jsonb
language sql security definer set search_path = public stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('channel', x.channel, 'other_id', x.other_id,
           'other', (select name from profiles where id = x.other_id), 'last', x.body, 'at', x.created_at,
           'unread', (select count(*) from messages m
                       where m.channel = x.channel and m.sender_id <> auth.uid() and not m.deleted
                         and m.created_at > coalesce((select r.read_at from chat_reads r where r.player_id = auth.uid() and r.channel = x.channel), '-infinity'::timestamptz)))
           order by x.created_at desc), '[]'::jsonb)
  from (select distinct on (channel) channel, body, created_at,
               (case when split_part(channel, ':', 2)::uuid = auth.uid() then split_part(channel, ':', 3) else split_part(channel, ':', 2) end)::uuid as other_id
          from messages where channel like 'dm:%' and position(auth.uid()::text in channel) > 0 and not deleted
         order by channel, created_at desc) x
  where not _blocked_pair(auth.uid(), x.other_id) $$;

create or replace function forum_create_thread(cat text, title text, body text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); t forum_threads; last timestamptz;
begin
  perform _check_muted(u);
  if cat not in ('updates','new_player','market','general','war','off_topic','suggestions') then perform _fail('No such board'); end if;
  if cat = 'updates' and not _is_admin(u) then perform _fail('Only the game team posts in Game Updates — reply to a thread instead'); end if;
  if title is null or char_length(trim(title)) < 3 then perform _fail('Give the thread a title (3+ characters)'); end if;
  if char_length(trim(title)) > 120 then perform _fail('Title is too long (120 max)'); end if;
  if _is_blocked(title) then perform _fail('That title has a word that isn''t allowed'); end if;
  if body is null or char_length(trim(body)) < 1 then perform _fail('Write something first'); end if;
  if char_length(body) > 4000 then perform _fail('Post is too long (4,000 characters max)'); end if;
  if _is_blocked_hard(body) then perform _fail('That message has a word that isn''t allowed'); end if;
  select max(created_at) into last from forum_threads where author_id = u;
  if not _is_admin(u) and last > now() - make_interval(secs => _forum_cfg('thread_cooldown_s')) then perform _fail('Slow down — one new thread a minute'); end if;
  insert into forum_threads (category, author_id, title, body, last_poster_id)
  values (cat, u, trim(title), trim(body), u) returning * into t;
  return jsonb_build_object('id', t.id);
end $$;

create or replace function forum_reply(tid bigint, body text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); t forum_threads; p forum_posts; last timestamptz;
begin
  perform _nn(tid, 'thread');
  perform _check_muted(u);
  select * into t from forum_threads where id = tid and not deleted for update;
  if t.id is null then perform _fail('That thread is gone'); end if;
  if t.locked and not _is_admin(u) then perform _fail('This thread is locked'); end if;
  if body is null or char_length(trim(body)) < 1 then perform _fail('Write something first'); end if;
  if char_length(body) > 4000 then perform _fail('Post is too long (4,000 characters max)'); end if;
  if _is_blocked_hard(body) then perform _fail('That message has a word that isn''t allowed'); end if;
  select max(created_at) into last from forum_posts where author_id = u;
  if not _is_admin(u) and last > now() - make_interval(secs => _forum_cfg('post_cooldown_s')) then perform _fail('Slow down — one reply every ten seconds'); end if;
  insert into forum_posts (thread_id, author_id, body) values (tid, u, trim(body)) returning * into p;
  update forum_threads set reply_count = reply_count + 1, last_post_at = p.created_at, last_poster_id = u where id = tid;
  return jsonb_build_object('id', p.id, 'page', (t.reply_count) / _forum_cfg('page_posts')::int);
end $$;

-- edit your own thread body / title or your own reply
create or replace function forum_edit(kind text, id bigint, body text, title text default null) returns jsonb
-- (params are referenced as forum_edit.<name> inside because they shadow the columns)
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); adm boolean := _is_admin(u);
begin
  perform _nn(id, 'id');
  perform _check_muted(u);
  if forum_edit.body is null or char_length(trim(forum_edit.body)) < 1 then perform _fail('Write something first'); end if;
  if char_length(forum_edit.body) > 4000 then perform _fail('Post is too long (4,000 characters max)'); end if;
  if kind = 'thread' and nullif(trim(forum_edit.title), '') is not null and _is_blocked(forum_edit.title) then
    perform _fail('That title has a word that isn''t allowed'); end if;
  if _is_blocked_hard(forum_edit.body) then perform _fail('That message has a word that isn''t allowed'); end if;
  if kind = 'thread' then
    update forum_threads t set body = trim(forum_edit.body), title = coalesce(nullif(trim(forum_edit.title), ''), t.title), edited_at = now()
     where t.id = forum_edit.id and not t.deleted and (t.author_id = u or adm);
  elsif kind = 'post' then
    update forum_posts p set body = trim(forum_edit.body), edited_at = now()
     where p.id = forum_edit.id and not p.deleted and (p.author_id = u or adm);
  else
    perform _fail('Bad edit');
  end if;
  if not found then perform _fail('Nothing to edit'); end if;
  return jsonb_build_object('ok', true);
end $$;

-- Muted: the description can be cleared but not rewritten (the emblem is free).
create or replace function crew_update(emblem text, description text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); c crews;
begin
  c := _my_bossed_crew(u);
  if left(coalesce(crew_update.description, ''), 500) not in ('', coalesce(c.description, '')) then perform _check_muted(u); end if;
  if _is_blocked(crew_update.emblem) then perform _fail('That emblem isn''t allowed'); end if;
  if _is_blocked(crew_update.description) then perform _fail('That description has a word that isn''t allowed'); end if;
  update crews x set emblem = left(coalesce(nullif(crew_update.emblem, ''), x.emblem), 8),
                     description = left(coalesce(crew_update.description, ''), 500)
   where x.id = c.id;
  return jsonb_build_object('ok', true);
end $$;

-- Muted: the bio can be cleared but not rewritten (the avatar is free).
create or replace function update_profile(avatar text default null, bio text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); was text;
begin
  select p.bio into was from profiles p where p.id = u;
  if left(update_profile.bio, 200) not in ('', coalesce(was, '')) then perform _check_muted(u); end if;
  if nullif(trim(update_profile.avatar), '') is not null and _is_blocked(update_profile.avatar) then perform _fail('That avatar isn''t allowed'); end if;
  if update_profile.bio is not null and _is_blocked(update_profile.bio) then perform _fail('Your bio has a word that isn''t allowed'); end if;
  update profiles p set avatar = left(coalesce(nullif(trim(update_profile.avatar), ''), p.avatar), 8),
                        bio = left(coalesce(update_profile.bio, p.bio), 200)
   where p.id = u;
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------------
-- The word filter: the chat switch on every tier
-- ---------------------------------------------------------------------------
-- Whole-word slurs and hate block chat; crude words stay off, so "kiss my ass" still goes through in a crime game.
update banned_words set chat = true
 where word in ('coon', 'paki', 'spic', 'fag', 'dyke', 'homo', 'nazi', 'heil', 'rape', 'rapist', 'pedo');
update banned_words set chat = false
 where word in ('dick', 'cock', 'ass', 'arse', 'cum', 'anal', 'anus', 'tits', 'boob', 'pussy', 'twat', 'wank', 'prick');

-- Chat messages and forum posts: the words marked chat, each matched its own way (whole words per word of the text).
create or replace function _is_blocked_hard(t text) returns boolean
language sql stable set search_path = public as $$ select _blocked_by(t, array['squash', 'part', 'word'], true) $$;

-- 20261004000008's mod_words, with the chat switch on whole-word entries too.
create or replace function mod_words(action text default 'list', word text default null, how text default 'word', chat boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); w text := lower(trim(coalesce(mod_words.word, ''))); c boolean := coalesce(mod_words.chat, true); b banned_words;
begin
  if not _is_admin(u) then perform _fail('Admins only'); end if;
  if action = 'add' then
    if w !~ '^[a-z]{2,30}$' then perform _fail('Words are 2–30 letters, a to z'); end if;
    if how not in ('squash', 'part', 'word') then perform _fail('Match anywhere, inside a word, or whole word'); end if;
    insert into banned_words (word, match, chat, added_by) values (w, how, c, u)
      on conflict on constraint banned_words_pkey do update set match = excluded.match, chat = excluded.chat;
    insert into mod_log (admin_id, action, new_value)
    values (u, 'add_word', w || ' (' || how || case when c then ', chat on' else ', chat off' end || ')');
  elsif action = 'remove' then
    delete from banned_words x where x.word = w;
    if not found then perform _fail('Not on the list'); end if;
    insert into mod_log (admin_id, action, old_value) values (u, 'remove_word', w);
  elsif action = 'chat' then
    select * into b from banned_words x where x.word = w for update;
    if b.word is null then perform _fail('Not on the list'); end if;
    update banned_words x set chat = not b.chat where x.word = w;
    insert into mod_log (admin_id, action, new_value)
    values (u, 'set_word', w || ' (' || b.match || case when b.chat then ', chat off' else ', chat on' end || ')');
  elsif action <> 'list' then
    perform _fail('Unknown action');
  end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('word', x.word, 'match', x.match, 'chat', x.chat) order by x.match, x.word), '[]'::jsonb)
            from banned_words x);
end $$;

-- ---------------------------------------------------------------------------
-- get_me: muted_until (null when not muted); a deleted DM line isn't unread
-- ---------------------------------------------------------------------------
create or replace function get_me() returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; po record; pd record; pj record; pk jsonb;
begin
  perform _refresh_prices();
  perform _tick_world();
  pr := _tick(u);
  update profiles set last_seen = now() where id = u;
  select * into po from _power(u, 'offense');
  select * into pd from _power(u, 'defense');
  select * into pj from _power(u, 'jail');
  pk := _perks(u);
  return jsonb_build_object(
    'id', pr.id, 'name', pr.name, 'created_at', pr.created_at, 'avatar', pr.avatar, 'bio', pr.bio, 'reputation', pr.reputation,
    'cash', pr.cash, 'bank', pr.bank, 'diamonds', pr.diamonds,
    'stamina', pr.stamina, 'stamina_max', pr.stamina_max,
    'health', pr.health, 'health_max', pr.health_max,
    'heat', pr.heat, 'heat_max', pr.heat_max,
    'heat_level', _heat_level(pr),
    'jailed', _jailed(pr), 'jail_until', case when isfinite(pr.jail_until) then pr.jail_until end,   -- null: until bail
    'hospital', _hospital(pr),
    'health_next', pr.health_tick + make_interval(mins => _cfg('health_regen_minutes')::int),
    'health_bought', pr.health_bought,
    'rep_earned', pr.rep_earned, 'path', pr.path,
    'path_required', _path_due(pr) is not null,
    'immune_until', pr.immune_until, 'immune', pr.immune_until > now(),
    'inventory_slots', pr.inventory_slots, 'storage_cap', floor(pr.storage_cap * (1 + _pk(pk, 'warehouse')))::int,
    'refills_used', pr.refills_used,
    'actions_done', pr.actions_done, 'fights_won', pr.fights_won, 'fights_lost', pr.fights_lost,
    'market_volume', pr.market_volume, 'imports', pr.imports,
    'next_tick', pr.stamina_tick + make_interval(mins => _cfg('stamina_regen_minutes')::int),   -- next stamina regen
    'power', jsonb_build_object('offense', to_jsonb(po), 'defense', to_jsonb(pd), 'jail', to_jsonb(pj)),
    'crew', (select jsonb_build_object('id', c.id, 'name', c.name, 'emblem', c.emblem, 'capo_id', c.capo_id,
                                       'is_capo', c.capo_id = u, 'co_capo_id', c.co_capo_id, 'is_co_capo', c.co_capo_id = u,
                                       'cartel_id', c.cartel_id,
                                       'members', (select count(*) from profiles where crew_id = c.id),
                                       'applications', case when _crew_boss(c, u) then (select count(*) from crew_applications where crew_id = c.id) else 0 end,
                                       'invites', case when c.capo_id = u and c.cartel_id is null then (select count(*) from cartel_invites where crew_id = c.id) else 0 end)
             from crews c where c.id = pr.crew_id),
    'cartel', (select jsonb_build_object('id', ca.id, 'name', ca.name, 'don_id', ca.don_id, 'is_don', ca.don_id = u)
               from crews c join cartels ca on ca.id = c.cartel_id where c.id = pr.crew_id),
    'storage', (select coalesce(jsonb_object_agg(commodity, qty), '{}'::jsonb) from storage where player_id = u),
    'storage_used', (select coalesce(sum(qty), 0) from storage where player_id = u),
    'prices', (select jsonb_object_agg(commodity, price) from street_prices),
    'grow_houses', (select coalesce(jsonb_agg(jsonb_build_object(
                      'id', g.id, 'commodity', g.commodity, 'level', g.level, 'running', g.running,
                      'started_at', g.started_at,
                      'rate', round(c.grow_rate * g.level * _grow_boost(pk, g.commodity), 1),
                      'cap', floor(c.grow_cap * g.level * _grow_boost(pk, g.commodity))::int,
                      'produced', least(floor(c.grow_cap * g.level * _grow_boost(pk, g.commodity))::int, g.banked + case when g.running
                          then floor(extract(epoch from now() - g.started_at) / 3600 * c.grow_rate * g.level * _grow_boost(pk, g.commodity))::int else 0 end),
                      'upgrade_cost', c.grow_price * g.level * 2) order by c.sort), '[]'::jsonb)
                    from grow_houses g join commodities c on c.code = g.commodity where g.player_id = u),
    'hustlers', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'commodity', commodity, 'count', count,
                      'units', units, 'cash_due', cash_due, 'returns_at', returns_at, 'back', returns_at <= now())
                      order by returns_at), '[]'::jsonb)
                 from hustlers where player_id = u and not collected),
    'inventory', (select coalesce(jsonb_agg(jsonb_build_object('item_id', i.item_id, 'qty', i.qty, 'name', d.name,
                      'category', d.category, 'att', d.att, 'def', d.def, 'capacity', d.capacity, 'price', d.price,
                      'combo_tag', d.combo_tag) order by d.sort), '[]'::jsonb)
                  from inventory i join item_defs d on d.id = i.item_id where i.player_id = u and i.qty > 0),
    'setups', (select coalesce(jsonb_object_agg(s, items), '{}'::jsonb) from (
                 select s.setup as s, coalesce(jsonb_agg(jsonb_build_object('item_id', s.item_id, 'qty', s.qty, 'name', d.name,
                        'category', d.category, 'att', d.att, 'def', d.def, 'combo_tag', d.combo_tag) order by d.sort), '[]'::jsonb) as items
                   from setup_items s join item_defs d on d.id = s.item_id where s.player_id = u and s.qty > 0 group by s.setup) x),
    'hoodlums', (select coalesce(jsonb_object_agg(code, qty), '{}'::jsonb) from player_hoodlums where player_id = u),
    'transport_capacity', _haul(u),
    'listings', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'commodity', commodity, 'qty', qty,
                      'unit_price', unit_price, 'expires_at', expires_at, 'held', status = 'returned') order by created_at desc), '[]'::jsonb)
                 from listings where seller_id = u and status in ('open', 'returned')),
    'ribbons', _ribbons(u),
    'server_time', now()
  ) || jsonb_build_object(   -- a second object: jsonb_build_object takes at most 100 arguments
    'hospital_out_at', ceil(_cfg('hospital_release_pct') / 100.0 * pr.health_max)::int,
    'heat_next', pr.last_tick + make_interval(mins => _cfg('regen_minutes')::int),
    'unread_activity', (select count(*) from activity where player_id = u and not seen),
    'unread_dms', (select count(*) from chat_reads r where r.player_id = u
                     and exists (select 1 from messages m where m.channel = r.channel and m.created_at > r.read_at and m.sender_id <> u and not m.deleted)
                     and not _blocked_pair(u, _dm_other(r.channel, u))),   -- that conversation is out of the list
    'storage_base', pr.storage_cap,
    'listing_max', floor(_cfg('listing_max') * (1 + _pk(pk, 'trucking')))::int,
    'perks', pk,
    'drop', jsonb_build_object('subscribed', _drop_active(pr), 'since', pr.drop_since, 'until', pr.drop_until,
              'crates', pr.drop_crates, 'max', _cfg('drop_max_crates')::int,
              'opened', (select count(*) from drop_opens where player_id = u),
              'last', (select jsonb_build_object('label', z.label, 'kind', z.kind, 'amount', o.amount, 'jackpot', z.jackpot, 'at', o.created_at)
                         from drop_opens o join drop_prizes z on z.code = o.prize where o.player_id = u order by o.id desc limit 1)),
    'free_refills', pr.free_refills, 'free_hustlers', pr.free_hustlers,
    'combos', (select jsonb_object_agg(s, jsonb_build_object('active', _active_combo(u, s), 'complete', to_jsonb(_setup_combos(u, s)),
                 'chosen', (select combo from setup_combos where player_id = u and setup = s)))
                 from unnest(array['offense', 'defense', 'jail']::setup_kind[]) s),
    'slot_cost', (select jsonb_build_object('diamonds', c.diamonds, 'cash', c.cash) from _slot_cost(pr.inventory_slots) c),
    'boost', jsonb_build_object('side', pr.boost_side, 'until', pr.boost_until, 'active', _boost_active(pr),
               'amount', _cfg('boost_amount')::int)
  ) || jsonb_build_object(
    -- the market: street details (for previewing a hustle), my open buy orders, and what the next product refill restores
    'street', _street_json(),
    'orders', (select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'commodity', o.commodity, 'qty', o.qty, 'filled', o.filled,
                    'unit_price', o.unit_price, 'expires_at', o.expires_at) order by o.created_at desc), '[]'::jsonb)
               from buy_orders o where o.buyer_id = u and o.status = 'open'),
    'refill_share', _refill_share(pr.refills_used),
    'path_due', _path_due(pr),  -- why a path is required: 'rep' or 'grow'
    'heat_yellow', _heat_yellow(pr), 'heat_red', _heat_red(pr),  -- this player's lines (heat upgrades move them up)
    -- moderation: admins see the queue size; a reset (or placeholder) name asks for a new one
    'is_admin', pr.is_admin, 'rename_pending', pr.rename_pending,
    'name_required', pr.rename_pending or pr.name like 'player\_%',
    'reports_open', case when pr.is_admin then (select count(distinct target_id) from profile_reports where status = 'open') else 0 end,
    -- players I've blocked: the client drops their realtime chat lines
    'blocked', (select coalesce(jsonb_agg(blocked_id), '[]'::jsonb) from blocked_players where blocker_id = u),
    -- muted: the client shows the end of the mute in place of the chat and forum composers
    'muted_until', case when pr.muted_until > now() then pr.muted_until end
  );
end $$;

-- get_player: admins see when a player's mute ends, so the profile can offer Unmute
create or replace function get_player(pid uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles;
begin
  select * into pr from profiles where id = pid;
  if pr.id is null then perform _fail('No such player'); end if;
  return jsonb_build_object('id', pr.id, 'name', pr.name, 'created_at', pr.created_at, 'avatar', pr.avatar, 'bio', pr.bio, 'reputation', pr.reputation,
    'fights', pr.fights_won + pr.fights_lost, 'fights_won', pr.fights_won, 'actions', pr.actions_done,
    'health', pr.health, 'health_max', pr.health_max,
    'heat_level', _heat_level(pr), 'is_bot', pr.is_bot,
    'jailed', _jailed(pr), 'hospital', _hospital(pr), 'immune', pr.immune_until > now(),
    'last_seen', pr.last_seen, 'ribbons', _ribbons(pr.id),
    'crew', (select jsonb_build_object('id', c.id, 'name', c.name, 'emblem', c.emblem) from crews c where c.id = pr.crew_id),
    'cartel', (select jsonb_build_object('id', ca.id, 'name', ca.name) from crews c join cartels ca on ca.id = c.cartel_id where c.id = pr.crew_id),
    'blocked', _has_blocked(u, pr.id), 'blocked_me', _has_blocked(pr.id, u),
    'muted_until', case when _is_admin(u) and pr.muted_until > now() then pr.muted_until end);
end $$;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
do $$ declare f record; begin
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('report_profile', 'report_message', 'report_forum', 'mod_queue', 'mod_action',
             'mod_words', 'get_me', 'get_player', 'get_messages', 'get_conversations', 'send_message', 'forum_create_thread', 'forum_reply',
             'forum_edit', 'crew_update', 'update_profile') loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('_report_guard', '_report_live', '_check_muted', '_is_blocked_hard') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
end $$;
