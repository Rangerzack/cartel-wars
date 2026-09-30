-- Profile moderation (Zack, 2026-09-30: "review the player profiles like if a player has an inappropriate name or
-- portfolio picture"). He picked: admin actions on profiles, a Report button with a review queue, and an automatic word
-- filter (players with a reset name pick a new one; DickBickGus and Str8Gey are left as they are).
--
--  * Word filter: banned_words, each matched one of three ways after lower-casing and undoing number/symbol swaps
--    (0→o 1→i 3→e 4→a 5→s 7→t @→a $→s !→i |→i) and stretched letters (fuuuck):
--      squash — anywhere, even split up by spaces or dots (f.u.c.k): the worst slurs and swears
--      part   — inside any one word of the text (camelCase counts as separate words): SH1THEAD
--      word   — only as a whole word (or plus s), so Assassin, Cocktail, Therapist, Dickens and Grape are fine
--    It guards new names (signup, renames), avatars and bios. Existing names aren't touched.
--  * Names: 3–20 characters, no control characters, not taken (any case), not "player_…" (the placeholder) or "Thug N"
--    (the NPCs), and not blocked. check_name() lets the sign-up form ask before creating the account.
--  * Reports: report_profile(target, reason, note) — name / avatar / bio / other, one open report per player you report,
--    10 a day. Each keeps a snapshot of what the profile said at the time.
--  * Admins (profiles.is_admin): mod_queue() lists players with open reports; mod_action(target, action) resets the name
--    (to player_xxxxxxxx, and the player gets a free rename prompt), resets the avatar (🕶️), clears the bio, or dismisses
--    the reports. Every action is logged (mod_log) and the player gets an activity line. mod_words() lists, adds and
--    removes filter words.

alter table profiles add column if not exists rename_pending boolean not null default false;

-- ---------------------------------------------------------------------------
-- The word filter
-- ---------------------------------------------------------------------------
create table if not exists banned_words (
  word       text primary key check (word ~ '^[a-z]{2,30}$'),
  match      text not null default 'word' check (match in ('squash', 'part', 'word')),
  added_by   uuid references profiles(id) on delete set null,
  created_at timestamptz not null default now()
);
alter table banned_words enable row level security;
insert into banned_words (word, match) values
  ('fuck', 'squash'),
  ('cunt', 'squash'),
  ('nigger', 'squash'),
  ('nigga', 'squash'),
  ('faggot', 'squash'),
  ('kike', 'squash'),
  ('kkk', 'squash'),
  ('whitepower', 'squash'),
  ('siegheil', 'squash'),
  ('jigaboo', 'squash'),
  ('porchmonkey', 'squash'),
  ('zipperhead', 'squash'),
  ('shit', 'part'),
  ('bitch', 'part'),
  ('whore', 'part'),
  ('slut', 'part'),
  ('porn', 'part'),
  ('penis', 'part'),
  ('vagina', 'part'),
  ('asshole', 'part'),
  ('hitler', 'part'),
  ('retard', 'part'),
  ('molest', 'part'),
  ('pedophile', 'part'),
  ('paedophile', 'part'),
  ('jizz', 'part'),
  ('dildo', 'part'),
  ('blowjob', 'part'),
  ('handjob', 'part'),
  ('cumshot', 'part'),
  ('tranny', 'part'),
  ('chink', 'part'),
  ('wetback', 'part'),
  ('towelhead', 'part'),
  ('raghead', 'part'),
  ('dick', 'word'),
  ('cock', 'word'),
  ('ass', 'word'),
  ('arse', 'word'),
  ('cum', 'word'),
  ('rape', 'word'),
  ('rapist', 'word'),
  ('anal', 'word'),
  ('anus', 'word'),
  ('pedo', 'word'),
  ('coon', 'word'),
  ('paki', 'word'),
  ('spic', 'word'),
  ('fag', 'word'),
  ('dyke', 'word'),
  ('homo', 'word'),
  ('nazi', 'word'),
  ('heil', 'word'),
  ('tits', 'word'),
  ('boob', 'word'),
  ('pussy', 'word'),
  ('twat', 'word'),
  ('wank', 'word'),
  ('prick', 'word')
on conflict (word) do nothing;

-- Lower-case and undo the usual number/symbol swaps.
create or replace function _leet(t text) returns text
language sql immutable set search_path = public as $$ select lower(translate(coalesce(t, ''), '013457@$!|', 'oieastasii')) $$;

-- 'fuck' → 'f+u+c+k+', so stretched letters still match.
create or replace function _word_pattern(w text) returns text
language sql immutable set search_path = public as $$ select regexp_replace(w, '(.)', '\1+', 'g') $$;

create or replace function _is_blocked(t text) returns boolean
language sql stable set search_path = public as $$
  with toks as (select tok from regexp_split_to_table(_leet(regexp_replace(coalesce(t, ''), '([a-z])([A-Z])', '\1 \2', 'g')), '[^a-z]+') tok
                 where tok <> ''),
       sq as (select regexp_replace(_leet(t), '[^a-z]', '', 'g') s)
  select exists (select 1 from banned_words b, sq where b.match = 'squash' and sq.s ~ _word_pattern(b.word))
      or exists (select 1 from banned_words b, toks where b.match = 'part' and toks.tok ~ _word_pattern(b.word))
      or exists (select 1 from banned_words b, toks where b.match = 'word' and toks.tok ~ ('^' || _word_pattern(b.word) || 's?$')) $$;

-- What's wrong with a name, or null if it's fine. `me` may keep their own name in a different case.
create or replace function _name_problem(nm text, me uuid) returns text
language sql stable set search_path = public as $$
  select case
    when nm is null or char_length(trim(nm)) < 3 or char_length(trim(nm)) > 20 then 'Names are 3 to 20 characters'
    when trim(nm) ~ '[[:cntrl:]]' then 'Letters, numbers and symbols only'
    when trim(nm) ~* '^player_' or trim(nm) ~* '^thug\s*\d+$' then 'That name is reserved'
    when _is_blocked(nm) then 'That name isn''t allowed'
    when exists (select 1 from profiles p where lower(p.name) = lower(trim(nm)) and p.id is distinct from me) then 'That name is taken'
  end $$;

-- For the sign-up form (before there's an account) and the rename prompt.
create or replace function check_name(nm text) returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object('ok', _name_problem(nm, auth.uid()) is null, 'why', _name_problem(nm, auth.uid())) $$;

create or replace function _create_profile(uid uuid, wanted text) returns profiles
language plpgsql security definer set search_path = public as $$
declare nm text; pr profiles;
begin
  nm := nullif(trim(coalesce(wanted, '')), '');
  if _name_problem(nm, uid) is not null then
    nm := 'player_' || substr(replace(uid::text, '-', ''), 1, 8);    -- they pick a real one from the rename prompt
  end if;
  insert into profiles (id, name, cash, diamonds, immune_until)
  values (uid, nm, _cfg('starter_cash')::bigint, _cfg('starter_diamonds')::int,
          now() + make_interval(hours => _cfg('immunity_hours')::int))
  returning * into pr;
  insert into storage (player_id, commodity, qty) select uid, code, 0 from commodities;
  return pr;
end $$;

create or replace function ensure_profile(wanted text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles;
begin
  select * into pr from profiles where id = u;
  if pr.id is null then
    pr := _create_profile(u, wanted);
  elsif wanted is not null and (pr.name like 'player\_%' or pr.rename_pending) and _name_problem(wanted, u) is null then
    update profiles set name = trim(wanted), rename_pending = false where id = u;
  end if;
  return get_me();
end $$;

-- A new name: for placeholder names and names an admin reset. Everyone else keeps theirs.
create or replace function choose_name(nm text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; why text;
begin
  perform _nn(nm, 'name');
  select * into pr from profiles where id = u for update;
  if not (pr.rename_pending or pr.name like 'player\_%') then perform _fail('Names can only be changed after an admin resets them'); end if;
  why := _name_problem(nm, u);
  if why is not null then perform _fail(why); end if;
  update profiles set name = trim(nm), rename_pending = false where id = u;
  return jsonb_build_object('name', trim(nm));
end $$;

create or replace function update_profile(avatar text default null, bio text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid();
begin
  if nullif(trim(update_profile.avatar), '') is not null and _is_blocked(update_profile.avatar) then perform _fail('That avatar isn''t allowed'); end if;
  if update_profile.bio is not null and _is_blocked(update_profile.bio) then perform _fail('Your bio has a word that isn''t allowed'); end if;
  update profiles p set avatar = left(coalesce(nullif(trim(update_profile.avatar), ''), p.avatar), 8),
                        bio = left(coalesce(update_profile.bio, p.bio), 200)
   where p.id = u;
  return jsonb_build_object('ok', true);
end $$;

-- ---------------------------------------------------------------------------
-- Reports and the admin queue
-- ---------------------------------------------------------------------------
create table if not exists profile_reports (
  id          bigserial primary key,
  reporter_id uuid references profiles(id) on delete cascade,
  target_id   uuid not null references profiles(id) on delete cascade,
  reason      text not null check (reason in ('name', 'avatar', 'bio', 'other')),
  note        text not null default '' check (char_length(note) <= 200),
  snapshot    jsonb not null default '{}'::jsonb,     -- name, avatar and bio when reported
  status      text not null default 'open' check (status in ('open', 'actioned', 'dismissed')),
  resolved_by uuid references profiles(id) on delete set null,
  resolved_at timestamptz,
  created_at  timestamptz not null default now()
);
create unique index if not exists profile_reports_one_open on profile_reports (reporter_id, target_id) where status = 'open';
create index if not exists profile_reports_open_idx on profile_reports (target_id) where status = 'open';
alter table profile_reports enable row level security;

create table if not exists mod_log (
  id         bigserial primary key,
  admin_id   uuid references profiles(id) on delete set null,
  target_id  uuid references profiles(id) on delete set null,
  action     text not null check (action in ('reset_name', 'reset_avatar', 'clear_bio', 'dismiss', 'add_word', 'remove_word')),
  old_value  text,
  new_value  text,
  reports    integer not null default 0,           -- open reports it closed
  created_at timestamptz not null default now()
);
alter table mod_log enable row level security;

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
  if exists (select 1 from profile_reports where reporter_id = u and target_id = target and status = 'open') then
    perform _fail('You''ve already reported them — an admin will take a look'); end if;
  if (select count(*) from profile_reports where reporter_id = u and created_at > now() - interval '24 hours') >= 10 then
    perform _fail('You can send 10 reports a day'); end if;
  insert into profile_reports (reporter_id, target_id, reason, note, snapshot)
  values (u, target, reason, left(trim(coalesce(note, '')), 200), jsonb_build_object('name', t.name, 'avatar', t.avatar, 'bio', t.bio))
  returning * into r;
  return jsonb_build_object('id', r.id);
end $$;

-- Players with open reports, most recently reported first.
create or replace function mod_queue() returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not _is_admin(_uid()) then perform _fail('Admins only'); end if;
  return (select coalesce(jsonb_agg(x.j order by x.latest desc), '[]'::jsonb) from (
    select max(r.created_at) as latest, jsonb_build_object(
             'id', t.id, 'name', t.name, 'avatar', t.avatar, 'bio', t.bio, 'rename_pending', t.rename_pending,
             'reports', jsonb_agg(jsonb_build_object('id', r.id, 'reason', r.reason, 'note', r.note, 'snapshot', r.snapshot,
                          'reporter', rp.name, 'reporter_id', r.reporter_id, 'at', r.created_at) order by r.created_at desc)) as j
      from profile_reports r join profiles t on t.id = r.target_id left join profiles rp on rp.id = r.reporter_id
     where r.status = 'open'
     group by t.id) x);
end $$;

create or replace function mod_action(target uuid, action text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); t profiles; old text; new text; closed int;
begin
  if not _is_admin(u) then perform _fail('Admins only'); end if;
  perform _nn(target, 'player'); perform _nn(action, 'action');
  select * into t from profiles where id = target for update;
  if t.id is null then perform _fail('No such player'); end if;
  if t.is_bot then perform _fail('Thugs keep their names'); end if;
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
    else perform _fail('Unknown action');
  end case;
  update profile_reports set status = case when action = 'dismiss' then 'dismissed' else 'actioned' end,
         resolved_by = u, resolved_at = now()
   where target_id = target and status = 'open';
  get diagnostics closed = row_count;
  if action = 'dismiss' and closed = 0 then perform _fail('No open reports on them'); end if;
  insert into mod_log (admin_id, target_id, action, old_value, new_value, reports) values (u, target, action, old, new, closed);
  if action <> 'dismiss' then
    insert into activity (player_id, kind, actor_id, data) values (target, 'moderated', null, jsonb_build_object('action', action));
  end if;
  return jsonb_build_object('action', action, 'old', old, 'new', new, 'reports', closed);
end $$;

create or replace function mod_log_list(limit_n integer default 50) returns jsonb
language plpgsql stable security definer set search_path = public as $$
begin
  if not _is_admin(_uid()) then perform _fail('Admins only'); end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'action', l.action, 'old', l.old_value, 'new', l.new_value,
                 'reports', l.reports, 'at', l.created_at, 'admin', a.name, 'target', t.name, 'target_id', l.target_id) order by l.id desc), '[]'::jsonb)
            from (select * from mod_log order by id desc limit greatest(1, least(coalesce(limit_n, 50), 200))) l
            left join profiles a on a.id = l.admin_id left join profiles t on t.id = l.target_id);
end $$;

-- list | add (with how it matches) | remove
create or replace function mod_words(action text default 'list', word text default null, how text default 'word') returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); w text := lower(trim(coalesce(mod_words.word, '')));
begin
  if not _is_admin(u) then perform _fail('Admins only'); end if;
  if action = 'add' then
    if w !~ '^[a-z]{2,30}$' then perform _fail('Words are 2–30 letters, a to z'); end if;
    if how not in ('squash', 'part', 'word') then perform _fail('Match anywhere, inside a word, or whole word'); end if;
    insert into banned_words (word, match, added_by) values (w, how, u) on conflict on constraint banned_words_pkey do update set match = excluded.match;
    insert into mod_log (admin_id, action, new_value) values (u, 'add_word', w || ' (' || how || ')');
  elsif action = 'remove' then
    delete from banned_words where banned_words.word = w;
    if not found then perform _fail('Not on the list'); end if;
    insert into mod_log (admin_id, action, old_value) values (u, 'remove_word', w);
  elsif action <> 'list' then
    perform _fail('Unknown action');
  end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('word', b.word, 'match', b.match) order by b.match, b.word), '[]'::jsonb) from banned_words b);
end $$;

-- ---------------------------------------------------------------------------
-- get_me: is_admin, name_required, reports_open · get_player: is_bot (no Report button on thugs)
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
                     and exists (select 1 from messages m where m.channel = r.channel and m.created_at > r.read_at and m.sender_id <> u)),
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
    'reports_open', case when pr.is_admin then (select count(distinct target_id) from profile_reports where status = 'open') else 0 end
  );
end $$;

create or replace function get_player(pid uuid) returns jsonb
language plpgsql stable security definer set search_path = public as $$
declare pr profiles;
begin
  perform _uid();
  select * into pr from profiles where id = pid;
  if pr.id is null then perform _fail('No such player'); end if;
  return jsonb_build_object('id', pr.id, 'name', pr.name, 'created_at', pr.created_at, 'avatar', pr.avatar, 'bio', pr.bio, 'reputation', pr.reputation,
    'fights', pr.fights_won + pr.fights_lost, 'fights_won', pr.fights_won, 'actions', pr.actions_done,
    'health', pr.health, 'health_max', pr.health_max,
    'heat_level', _heat_level(pr), 'is_bot', pr.is_bot,
    'jailed', _jailed(pr), 'hospital', _hospital(pr), 'immune', pr.immune_until > now(),
    'last_seen', pr.last_seen, 'ribbons', _ribbons(pr.id),
    'crew', (select jsonb_build_object('id', c.id, 'name', c.name, 'emblem', c.emblem) from crews c where c.id = pr.crew_id),
    'cartel', (select jsonb_build_object('id', ca.id, 'name', ca.name) from crews c join cartels ca on ca.id = c.cartel_id where c.id = pr.crew_id));
end $$;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
do $$ declare f record; begin
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('choose_name', 'update_profile', 'ensure_profile', 'report_profile', 'mod_queue',
             'mod_action', 'mod_log_list', 'mod_words', 'get_me', 'get_player') loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
  -- the sign-up form asks before there's an account
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'check_name' loop
    execute format('revoke all on function %s from public', f.sig);
    execute format('grant execute on function %s to anon, authenticated', f.sig);
  end loop;
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('_leet', '_word_pattern', '_is_blocked', '_name_problem', '_create_profile') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
end $$;
