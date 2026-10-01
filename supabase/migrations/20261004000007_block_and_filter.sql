-- The word filter on chat, the forum, crews and cartels (#11), and blocking players (#9). Apple guideline 1.2 asks for "a
-- method for filtering objectionable material from being posted" and "the ability to block abusive users from the service".
--
--  * Filter: crew and cartel names, crew emblems and descriptions, and forum thread titles get the full check (all three
--    tiers), like player names, avatars and bios. Chat messages and forum posts get only the squash and part tiers, so
--    ordinary swearing in a crime game ("kiss my ass") still goes through and slurs don't. Existing names and old messages
--    are left as they are.
--  * Blocking is about talking. Block someone and:
--      DMs stop both ways: send_message refuses, the conversation drops out of your lists (and its unread count with it);
--      their lines in global, crew, cartel and table chat are left out of get_messages (the client drops realtime rows);
--      their forum threads and replies come back with hidden: true and no body or snippet;
--      they can't apply to a crew you run (Capo or Co-Capo), and a pending application is declined;
--      their cartel can't invite a crew you're Capo of while they're its Don, and a pending invite is declined.
--    Attacks, trades, listings and the rest are unaffected. Thugs can't be blocked.

-- ---------------------------------------------------------------------------
-- The word filter, by tier
-- ---------------------------------------------------------------------------
-- The matching code from 20261004000006, with the tiers to check passed in.
create or replace function _blocked_by(t text, tiers text[]) returns boolean
language sql stable set search_path = public as $$
  with toks as (select tok from regexp_split_to_table(_leet(regexp_replace(coalesce(t, ''), '([a-z])([A-Z])', '\1 \2', 'g')), '[^a-z]+') tok
                 where tok <> ''),
       sq as (select regexp_replace(_leet(t), '[^a-z]', '', 'g') s)
  select ('squash' = any(tiers) and exists (select 1 from banned_words b, sq where b.match = 'squash' and sq.s ~ _word_pattern(b.word)))
      or ('part' = any(tiers) and exists (select 1 from banned_words b, toks where b.match = 'part' and toks.tok ~ _word_pattern(b.word)))
      or ('word' = any(tiers) and exists (select 1 from banned_words b, toks where b.match = 'word' and toks.tok ~ ('^' || _word_pattern(b.word) || 's?$'))) $$;

-- Names, avatars, bios, crew emblems and descriptions, forum titles: every tier.
create or replace function _is_blocked(t text) returns boolean
language sql stable set search_path = public as $$ select _blocked_by(t, array['squash', 'part', 'word']) $$;

-- Chat messages and forum posts: whole-word matches are left out, so swearing goes through and slurs don't.
create or replace function _is_blocked_hard(t text) returns boolean
language sql stable set search_path = public as $$ select _blocked_by(t, array['squash', 'part']) $$;

-- ---------------------------------------------------------------------------
-- Crew and cartel names, forum titles and posts
-- ---------------------------------------------------------------------------
create or replace function crew_create(nm text, emblem text default '🏴', description text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; c crews;
begin
  pr := _tick(u);
  if pr.crew_id is not null then perform _fail('Leave your crew first'); end if;
  if char_length(trim(nm)) not between 3 and 24 then perform _fail('Crew name must be 3–24 characters'); end if;
  if _is_blocked(nm) then perform _fail('That name isn''t allowed'); end if;
  if _is_blocked(emblem) then perform _fail('That emblem isn''t allowed'); end if;
  if _is_blocked(description) then perform _fail('That description has a word that isn''t allowed'); end if;
  if exists (select 1 from crews where lower(name) = lower(trim(nm))) then perform _fail('That crew name is taken'); end if;
  insert into crews (name, emblem, description, capo_id)
  values (trim(nm), left(coalesce(nullif(emblem, ''), '🏴'), 8), left(coalesce(description, ''), 500), u) returning * into c;
  update profiles set crew_id = c.id where id = u;
  return jsonb_build_object('id', c.id);
end $$;

-- Crews can't be renamed; the emblem and description are the crew's avatar and bio, so they get the same check.
create or replace function crew_update(emblem text, description text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); c crews;
begin
  c := _my_bossed_crew(u);
  if _is_blocked(crew_update.emblem) then perform _fail('That emblem isn''t allowed'); end if;
  if _is_blocked(crew_update.description) then perform _fail('That description has a word that isn''t allowed'); end if;
  update crews x set emblem = left(coalesce(nullif(crew_update.emblem, ''), x.emblem), 8),
                     description = left(coalesce(crew_update.description, ''), 500)
   where x.id = c.id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function cartel_create(nm text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); c crews; ca cartels;
begin
  select * into c from crews where capo_id = u for update;
  if c.id is null then perform _fail('Only a Capo can found a cartel'); end if;
  if c.cartel_id is not null then perform _fail('Your crew is already in a cartel'); end if;
  if char_length(trim(nm)) not between 3 and 24 then perform _fail('Cartel name must be 3–24 characters'); end if;
  if _is_blocked(nm) then perform _fail('That name isn''t allowed'); end if;
  if exists (select 1 from cartels where lower(name) = lower(trim(nm))) then perform _fail('That cartel name is taken'); end if;
  insert into cartels (name, don_id) values (trim(nm), u) returning * into ca;
  update crews set cartel_id = ca.id where id = c.id;
  return jsonb_build_object('id', ca.id);
end $$;

create or replace function forum_create_thread(cat text, title text, body text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); t forum_threads; last timestamptz;
begin
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

-- ---------------------------------------------------------------------------
-- Blocking
-- ---------------------------------------------------------------------------
create table if not exists blocked_players (
  blocker_id uuid references profiles(id) on delete cascade,
  blocked_id uuid references profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (blocker_id, blocked_id)
);
create index if not exists blocked_players_blocked_idx on blocked_players (blocked_id);   -- "who blocked me"
alter table blocked_players enable row level security;
revoke all on blocked_players from anon, authenticated;

-- a has blocked b
create or replace function _has_blocked(a uuid, b uuid) returns boolean
language sql stable set search_path = public as $$
  select exists (select 1 from blocked_players where blocker_id = a and blocked_id = b) $$;

-- either one has blocked the other
create or replace function _blocked_pair(a uuid, b uuid) returns boolean
language sql stable set search_path = public as $$ select _has_blocked(a, b) or _has_blocked(b, a) $$;

-- the other player in dm:<a>:<b>
create or replace function _dm_other(ch text, u uuid) returns uuid
language sql immutable set search_path = public as $$
  select (case when split_part(ch, ':', 2) = u::text then split_part(ch, ':', 3) else split_part(ch, ':', 2) end)::uuid $$;

create or replace function block_player(target uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); t profiles;
begin
  perform _nn(target, 'player');
  if target = u then perform _fail('You can''t block yourself'); end if;
  select * into t from profiles where id = target;
  if t.id is null then perform _fail('No such player'); end if;
  if t.is_bot then perform _fail('Thugs can''t be blocked'); end if;
  if _has_blocked(u, target) then perform _fail('You''ve already blocked them'); end if;
  insert into blocked_players (blocker_id, blocked_id) values (u, target);
  -- anything of theirs waiting on you is declined: an application to a crew you run, an invite from their cartel
  delete from crew_applications a using crews c
   where a.crew_id = c.id and a.player_id = target and u in (c.capo_id, c.co_capo_id);
  delete from cartel_invites i using crews c, cartels ca
   where i.crew_id = c.id and c.capo_id = u and ca.id = i.cartel_id and ca.don_id = target;
  return jsonb_build_object('blocked', true);
end $$;

create or replace function unblock_player(target uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid();
begin
  perform _nn(target, 'player');
  delete from blocked_players where blocker_id = u and blocked_id = target;
  if not found then perform _fail('You haven''t blocked them'); end if;
  return jsonb_build_object('blocked', false);
end $$;

-- Who I've blocked, newest first.
create or replace function blocked_list() returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare u uuid := _uid();
begin
  return (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'avatar', p.avatar, 'at', b.created_at)
                   order by b.created_at desc), '[]'::jsonb)
            from blocked_players b join profiles p on p.id = b.blocked_id where b.blocker_id = u);
end $$;

-- Crews: no applying to a crew whose Capo or Co-Capo blocked you, no inviting a crew whose Capo blocked you (the Don).
create or replace function crew_apply(cid uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles;
begin
  pr := _tick(u);
  if pr.crew_id is not null then perform _fail('You are already in a crew'); end if;
  if not exists (select 1 from crews where id = cid) then perform _fail('No such crew'); end if;
  if exists (select 1 from crews c join blocked_players b on b.blocked_id = u and b.blocker_id in (c.capo_id, c.co_capo_id) where c.id = cid) then
    perform _fail('You can''t apply to this crew'); end if;
  insert into crew_applications (crew_id, player_id) values (cid, u) on conflict do nothing;
  return jsonb_build_object('ok', true);
end $$;

create or replace function cartel_invite(crew uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); ca cartels;
begin
  select * into ca from cartels where don_id = u;
  if ca.id is null then perform _fail('Only the Don can invite crews'); end if;
  if not exists (select 1 from crews where id = cartel_invite.crew and cartel_id is null) then perform _fail('That crew is unavailable'); end if;
  if exists (select 1 from crews c where c.id = cartel_invite.crew and _has_blocked(c.capo_id, u)) then perform _fail('You can''t invite this crew'); end if;
  insert into cartel_invites (cartel_id, crew_id) values (ca.id, cartel_invite.crew) on conflict do nothing;
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------------
-- Chat
-- ---------------------------------------------------------------------------
create or replace function send_message(channel text, body text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); nm text; m messages;
begin
  if channel is null or not _can_use_channel(u, channel) then perform _fail('You cannot post there'); end if;
  if char_length(trim(coalesce(body, ''))) = 0 then perform _fail('Say something first'); end if;
  if channel like 'dm:%' and _blocked_pair(u, _dm_other(channel, u)) then perform _fail('You can''t message them'); end if;
  if _is_blocked_hard(body) then perform _fail('That message has a word that isn''t allowed'); end if;
  select name into nm from profiles where id = u;
  insert into messages (channel, sender_id, sender_name, body) values (channel, u, nm, left(trim(body), 500)) returning * into m;
  return jsonb_build_object('id', m.id);
end $$;

-- Group chats leave out the people you've blocked (before the limit, so they leave no gap). A DM's history stays readable.
create or replace function get_messages(channel text, limit_n integer default 50) returns jsonb
language plpgsql security definer set search_path = public stable as $$
declare u uuid := _uid();
begin
  if not _can_use_channel(u, channel) then perform _fail('You cannot read that channel'); end if;
  return (select coalesce(jsonb_agg(to_jsonb(m) order by m.created_at), '[]'::jsonb)
          from (select x.id, x.sender_id, x.sender_name, x.body, x.created_at from messages x
                 where x.channel = get_messages.channel
                   and (get_messages.channel like 'dm:%' or not _has_blocked(u, x.sender_id))
                 order by x.created_at desc limit limit_n) m);
end $$;

-- Conversations with someone either of you blocked drop out.
create or replace function get_conversations() returns jsonb
language sql security definer set search_path = public stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('channel', x.channel, 'other_id', x.other_id,
           'other', (select name from profiles where id = x.other_id), 'last', x.body, 'at', x.created_at,
           'unread', (select count(*) from messages m
                       where m.channel = x.channel and m.sender_id <> auth.uid()
                         and m.created_at > coalesce((select r.read_at from chat_reads r where r.player_id = auth.uid() and r.channel = x.channel), '-infinity'::timestamptz)))
           order by x.created_at desc), '[]'::jsonb)
  from (select distinct on (channel) channel, body, created_at,
               (case when split_part(channel, ':', 2)::uuid = auth.uid() then split_part(channel, ':', 3) else split_part(channel, ':', 2) end)::uuid as other_id
          from messages where channel like 'dm:%' and position(auth.uid()::text in channel) > 0
         order by channel, created_at desc) x
  where not _blocked_pair(auth.uid(), x.other_id) $$;

-- ---------------------------------------------------------------------------
-- Forum reads: a blocked player's threads and replies come back hidden, without their text
-- ---------------------------------------------------------------------------
create or replace function forum_list(cat text, page integer default 0) returns jsonb
language plpgsql security definer set search_path = public stable as $$
declare u uuid := _uid(); n int := _forum_cfg('page_threads')::int; total int;
begin
  if cat not in ('updates','new_player','market','general','war','off_topic','suggestions') then perform _fail('No such board'); end if;
  select count(*) into total from forum_threads where category = cat and not deleted;
  return jsonb_build_object(
    'category', cat, 'page', page, 'pages', greatest(1, ceil(total::numeric / n)::int), 'total', total,
    'is_admin', _is_admin(u),
    'can_post', cat <> 'updates' or _is_admin(u),
    'threads', (select coalesce(jsonb_agg(_forum_thread_json(t) || case when _has_blocked(u, t.author_id)
                         then jsonb_build_object('hidden', true, 'snippet', '') else jsonb_build_object('hidden', false) end
                       order by t.pinned desc, t.last_post_at desc), '[]'::jsonb)
                from (select * from forum_threads where category = cat and not deleted
                       order by pinned desc, last_post_at desc limit n offset greatest(0, page) * n) t));
end $$;

create or replace function forum_thread(tid bigint, page integer default 0) returns jsonb
language plpgsql security definer set search_path = public stable as $$
declare u uuid := _uid(); t forum_threads; n int := _forum_cfg('page_posts')::int; adm boolean := _is_admin(u); hid boolean;
begin
  select * into t from forum_threads where id = tid and not deleted;
  if t.id is null then perform _fail('That thread is gone'); end if;
  hid := _has_blocked(u, t.author_id);
  return jsonb_build_object(
    'thread', _forum_thread_json(t) || jsonb_build_object('body', case when hid then '' else t.body end, 'edited_at', t.edited_at,
                'mine', t.author_id = u, 'hidden', hid) || case when hid then jsonb_build_object('snippet', '') else '{}'::jsonb end,
    'is_admin', adm,
    'can_reply', not t.locked or adm,
    'page', page, 'pages', greatest(1, ceil(t.reply_count::numeric / n)::int),
    'posts', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'author', _forum_author(p.author_id),
                'body', case when p.deleted then null when p.hidden then '' else p.body end, 'deleted', p.deleted, 'hidden', p.hidden,
                'created_at', p.created_at, 'edited_at', p.edited_at, 'mine', p.author_id = u) order by p.id), '[]'::jsonb)
              from (select f.*, _has_blocked(u, f.author_id) as hidden from forum_posts f
                     where f.thread_id = tid order by f.id limit n offset greatest(0, page) * n) p));
end $$;

-- ---------------------------------------------------------------------------
-- get_me: blocked (ids), and DMs with blocked players stop counting as unread · get_player: blocked, blocked_me
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
                     and exists (select 1 from messages m where m.channel = r.channel and m.created_at > r.read_at and m.sender_id <> u)
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
    'blocked', (select coalesce(jsonb_agg(blocked_id), '[]'::jsonb) from blocked_players where blocker_id = u)
  );
end $$;

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
    'blocked', _has_blocked(u, pr.id), 'blocked_me', _has_blocked(pr.id, u));
end $$;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
do $$ declare f record; begin
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('block_player', 'unblock_player', 'blocked_list', 'get_me', 'get_player',
             'send_message', 'get_messages', 'get_conversations', 'crew_create', 'crew_update', 'crew_apply', 'cartel_create',
             'cartel_invite', 'forum_list', 'forum_thread', 'forum_create_thread', 'forum_reply', 'forum_edit') loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('_blocked_by', '_is_blocked', '_is_blocked_hard', '_has_blocked', '_blocked_pair', '_dm_other') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
end $$;
