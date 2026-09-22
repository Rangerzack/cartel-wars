-- Cartel Wars — Forum: categories, threads, replies, light moderation.
-- Categories: Game Updates (admins start threads, anyone replies), New Player, Market, General, War, Off Topic, Suggestions.

set check_function_bodies = on;

-- ---------------------------------------------------------------------------
-- Admins: emails that get the admin flag at registration (or right now, if already registered)
-- ---------------------------------------------------------------------------
create table admins (email text primary key);
insert into admins (email) values ('zack@rangelab.io');

alter table profiles add column is_admin boolean not null default false;
update profiles p set is_admin = true from auth.users u where u.id = p.id and lower(u.email) in (select lower(email) from admins);

create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform _create_profile(new.id, new.raw_user_meta_data ->> 'name');
  if new.email is not null and exists (select 1 from admins where lower(email) = lower(new.email)) then
    update profiles set is_admin = true where id = new.id;
  end if;
  return new;
end $$;

create or replace function _is_admin(u uuid) returns boolean language sql stable as $$
  select coalesce((select is_admin from profiles where id = u), false) $$;

-- ---------------------------------------------------------------------------
-- Schema
-- ---------------------------------------------------------------------------
create table forum_threads (
  id             bigserial primary key,
  category       text not null check (category in ('updates','new_player','market','general','war','off_topic','suggestions')),
  author_id      uuid not null references profiles(id) on delete cascade,
  title          text not null check (char_length(title) between 3 and 120),
  body           text not null check (char_length(body) between 1 and 4000),
  pinned         boolean not null default false,
  locked         boolean not null default false,
  deleted        boolean not null default false,
  reply_count    integer not null default 0,
  last_post_at   timestamptz not null default now(),
  last_poster_id uuid references profiles(id) on delete set null,
  created_at     timestamptz not null default now(),
  edited_at      timestamptz
);
create index forum_threads_cat_idx on forum_threads(category, pinned desc, last_post_at desc) where not deleted;
create index forum_threads_author_idx on forum_threads(author_id, created_at desc);

create table forum_posts (
  id         bigserial primary key,
  thread_id  bigint not null references forum_threads(id) on delete cascade,
  author_id  uuid not null references profiles(id) on delete cascade,
  body       text not null check (char_length(body) between 1 and 4000),
  deleted    boolean not null default false,
  created_at timestamptz not null default now(),
  edited_at  timestamptz
);
create index forum_posts_thread_idx on forum_posts(thread_id, id);
create index forum_posts_author_idx on forum_posts(author_id, created_at desc);

do $$
declare t text;
begin
  for t in select unnest(array['admins','forum_threads','forum_posts']) loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create or replace function _forum_cfg(key text) returns numeric language sql immutable as $$
  select case key
    when 'page_threads'   then 25
    when 'page_posts'     then 50
    when 'thread_cooldown_s' then 60    -- one new thread a minute
    when 'post_cooldown_s'   then 10    -- one reply every ten seconds
    else 0 end $$;

create or replace function _forum_author(p uuid) returns jsonb language sql stable as $$
  select jsonb_build_object('id', id, 'name', name, 'avatar', avatar, 'is_admin', is_admin,
                            'crew', (select jsonb_build_object('id', c.id, 'name', c.name, 'emblem', c.emblem) from crews c where c.id = profiles.crew_id))
  from profiles where id = p $$;

create or replace function _forum_snippet(t text) returns text language sql immutable as $$
  select left(regexp_replace(t, '\s+', ' ', 'g'), 140) $$;

create or replace function _forum_thread_json(t forum_threads) returns jsonb language sql stable as $$
  select jsonb_build_object('id', t.id, 'category', t.category, 'title', t.title, 'snippet', _forum_snippet(t.body),
    'author', _forum_author(t.author_id), 'pinned', t.pinned, 'locked', t.locked, 'reply_count', t.reply_count,
    'last_post_at', t.last_post_at, 'last_poster', (select name from profiles where id = t.last_poster_id),
    'created_at', t.created_at) $$;

-- ---------------------------------------------------------------------------
-- Reads
-- ---------------------------------------------------------------------------
create or replace function forum_categories() returns jsonb
language plpgsql security definer set search_path = public stable as $$
declare u uuid := _uid();
begin
  return jsonb_build_object(
    'is_admin', _is_admin(u),
    'categories', (select coalesce(jsonb_agg(jsonb_build_object('key', c.key, 'threads', c.threads, 'posts', c.posts, 'last_post_at', c.last_post_at,
                       'last', (select jsonb_build_object('id', t.id, 'title', t.title, 'last_poster', (select name from profiles where id = t.last_poster_id))
                                  from forum_threads t where t.category = c.key and not t.deleted order by t.last_post_at desc limit 1)) order by c.ord), '[]'::jsonb)
      from (select k.key, k.ord, count(t.id) as threads, coalesce(sum(t.reply_count), 0) as posts, max(t.last_post_at) as last_post_at
              from unnest(array['updates','new_player','market','general','war','off_topic','suggestions']) with ordinality as k(key, ord)
              left join forum_threads t on t.category = k.key and not t.deleted
             group by k.key, k.ord) c));
end $$;

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
    'threads', (select coalesce(jsonb_agg(_forum_thread_json(t) order by t.pinned desc, t.last_post_at desc), '[]'::jsonb)
                from (select * from forum_threads where category = cat and not deleted
                       order by pinned desc, last_post_at desc limit n offset greatest(0, page) * n) t));
end $$;

create or replace function forum_thread(tid bigint, page integer default 0) returns jsonb
language plpgsql security definer set search_path = public stable as $$
declare u uuid := _uid(); t forum_threads; n int := _forum_cfg('page_posts')::int; adm boolean := _is_admin(u);
begin
  select * into t from forum_threads where id = tid and not deleted;
  if t.id is null then perform _fail('That thread is gone'); end if;
  return jsonb_build_object(
    'thread', _forum_thread_json(t) || jsonb_build_object('body', t.body, 'edited_at', t.edited_at, 'mine', t.author_id = u),
    'is_admin', adm,
    'can_reply', not t.locked or adm,
    'page', page, 'pages', greatest(1, ceil(t.reply_count::numeric / n)::int),
    'posts', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'author', _forum_author(p.author_id),
                'body', case when p.deleted then null else p.body end, 'deleted', p.deleted,
                'created_at', p.created_at, 'edited_at', p.edited_at, 'mine', p.author_id = u) order by p.id), '[]'::jsonb)
              from (select * from forum_posts where thread_id = tid order by id limit n offset greatest(0, page) * n) p));
end $$;

-- ---------------------------------------------------------------------------
-- Writes
-- ---------------------------------------------------------------------------
create or replace function forum_create_thread(cat text, title text, body text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); t forum_threads; last timestamptz;
begin
  if cat not in ('updates','new_player','market','general','war','off_topic','suggestions') then perform _fail('No such board'); end if;
  if cat = 'updates' and not _is_admin(u) then perform _fail('Only the game team posts in Game Updates — reply to a thread instead'); end if;
  if title is null or char_length(trim(title)) < 3 then perform _fail('Give the thread a title (3+ characters)'); end if;
  if char_length(trim(title)) > 120 then perform _fail('Title is too long (120 max)'); end if;
  if body is null or char_length(trim(body)) < 1 then perform _fail('Write something first'); end if;
  if char_length(body) > 4000 then perform _fail('Post is too long (4,000 characters max)'); end if;
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

-- delete your own reply (or anything, as admin). Threads are soft-deleted so links just say "gone".
create or replace function forum_delete(kind text, id bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); adm boolean := _is_admin(u); p forum_posts;
begin
  perform _nn(id, 'id');
  if kind = 'thread' then
    update forum_threads t set deleted = true where t.id = forum_delete.id and not t.deleted and (t.author_id = u or adm);
    if not found then perform _fail('Nothing to delete'); end if;
  elsif kind = 'post' then
    update forum_posts x set deleted = true where x.id = forum_delete.id and not x.deleted and (x.author_id = u or adm) returning x.* into p;
    if p.id is null then perform _fail('Nothing to delete'); end if;
  else
    perform _fail('Bad delete');
  end if;
  return jsonb_build_object('ok', true);
end $$;

-- admin: pin / unpin / lock / unlock / move
create or replace function forum_moderate(tid bigint, action text, cat text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid();
begin
  if not _is_admin(u) then perform _fail('Admins only'); end if;
  perform _nn(tid, 'thread');
  case action
    when 'pin'    then update forum_threads set pinned = true  where id = tid;
    when 'unpin'  then update forum_threads set pinned = false where id = tid;
    when 'lock'   then update forum_threads set locked = true  where id = tid;
    when 'unlock' then update forum_threads set locked = false where id = tid;
    when 'move'   then
      if cat not in ('updates','new_player','market','general','war','off_topic','suggestions') then perform _fail('No such board'); end if;
      update forum_threads set category = cat where id = tid;
    else perform _fail('Unknown action');
  end case;
  if not found then perform _fail('No such thread'); end if;
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------------
-- Grants (default privileges revoke execute; grant the public RPCs)
-- ---------------------------------------------------------------------------
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname in ('forum_categories','forum_list','forum_thread','forum_create_thread','forum_reply','forum_edit','forum_delete','forum_moderate') loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and (p.proconfig is null or not p.proconfig::text like '%search_path%') loop
    execute format('alter function %s set search_path = public', f.sig);
  end loop;
end $$;
