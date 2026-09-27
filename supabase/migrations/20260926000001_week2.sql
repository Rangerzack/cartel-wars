-- Week 2 of the UX sprint.
--  * Activity feed: things that happen to you while you're away (attacks, crew fights, sieges and block
--    changes, marketplace sales, crew applications / joins / kicks). Written by triggers on the existing
--    tables, so no game RPC changes. Read with get_activity(); activity_mark_seen() clears the badge.
--  * Unread DMs: a read marker per player per DM conversation; get_conversations() and get_me() report unread.
--  * A rookie poker table (first 7 days only) with stakes a new player can afford.
--  * fight_preview(target): win odds and what the fight will cost you, before you swing.

-- ---------------------------------------------------------------------------
-- Activity feed
-- ---------------------------------------------------------------------------
create table if not exists activity (
  id         bigserial primary key,
  player_id  uuid not null references profiles(id) on delete cascade,
  kind       text not null,        -- attacked | crew_fight | siege | block_lost | block_taken | sold | applied | joined | kicked
  actor_id   uuid references profiles(id) on delete set null,
  crew_id    uuid references crews(id) on delete set null,     -- the other crew involved (or the crew joined/left)
  block_id   integer references blocks(id) on delete cascade,
  data       jsonb not null default '{}'::jsonb,
  seen       boolean not null default false,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);
create index if not exists activity_player_idx on activity(player_id, updated_at desc);
create index if not exists activity_unseen_idx on activity(player_id) where not seen;
alter table activity enable row level security;
revoke all on activity from anon, authenticated;

-- Someone attacked you. Repeat hits from the same attacker within the hour fold into one unseen line.
create or replace function _act_fight() returns trigger language plpgsql security definer set search_path = public as $$
declare a activity; held boolean := new.winner_id = new.defender_id; hosp boolean;
begin
  select health <= 19 into hosp from profiles where id = new.defender_id;
  select * into a from activity
   where player_id = new.defender_id and kind = 'attacked' and actor_id = new.attacker_id
     and not seen and updated_at > now() - interval '1 hour'
   order by updated_at desc limit 1 for update;
  if a.id is null then
    insert into activity (player_id, kind, actor_id, data) values (new.defender_id, 'attacked', new.attacker_id,
      jsonb_build_object('n', 1, 'held', held::int,
                         'cash_won', case when held then new.cash_taken else 0 end,
                         'cash_lost', case when held then 0 else new.cash_taken end,
                         'hospital', coalesce(hosp, false)));
  else
    update activity set updated_at = now(), data = jsonb_build_object(
        'n', coalesce((a.data->>'n')::int, 1) + 1,
        'held', coalesce((a.data->>'held')::int, 0) + held::int,
        'cash_won', coalesce((a.data->>'cash_won')::bigint, 0) + case when held then new.cash_taken else 0 end,
        'cash_lost', coalesce((a.data->>'cash_lost')::bigint, 0) + case when held then 0 else new.cash_taken end,
        'hospital', coalesce((a.data->>'hospital')::boolean, false) or coalesce(hosp, false))
     where id = a.id;
  end if;
  return null;
end $$;
drop trigger if exists fights_activity on fights;
create trigger fights_activity after insert on fights for each row execute function _act_fight();

-- Another crew launched a crew fight on yours: everyone in the defending crew hears about it.
create or replace function _act_crew_fight() returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into activity (player_id, kind, actor_id, crew_id, data)
  select p.id, 'crew_fight', new.started_by, new.attacker_crew, jsonb_build_object('held', not new.won, 'cash', new.cash_taken)
    from profiles p where p.crew_id = new.defender_crew;
  return null;
end $$;
drop trigger if exists crew_fights_activity on crew_fights;
create trigger crew_fights_activity after insert on crew_fights for each row execute function _act_crew_fight();

-- A crew landed its first hit on one of your crew's blocks (a siege started). Progress is read live.
create or replace function _act_siege() returns trigger language plpgsql security definer set search_path = public as $$
declare owner uuid;
begin
  select owner_crew_id into owner from blocks where id = new.block_id;
  if owner is null or owner = new.crew_id then return null; end if;
  insert into activity (player_id, kind, actor_id, crew_id, block_id)
  select p.id, 'siege', auth.uid(), new.crew_id, new.block_id from profiles p where p.crew_id = owner;
  return null;
end $$;
drop trigger if exists block_siege_activity on block_siege;
create trigger block_siege_activity after insert on block_siege for each row execute function _act_siege();

-- A block changed hands: the old crew lost it, the rest of the new crew took it.
create or replace function _act_block_owner() returns trigger language plpgsql security definer set search_path = public as $$
begin
  if new.owner_crew_id is null then return null; end if;        -- disbanded / wiped, not a takeover
  if old.owner_crew_id is not null then
    insert into activity (player_id, kind, actor_id, crew_id, block_id)
    select p.id, 'block_lost', auth.uid(), new.owner_crew_id, new.id from profiles p where p.crew_id = old.owner_crew_id;
  end if;
  insert into activity (player_id, kind, actor_id, crew_id, block_id)
  select p.id, 'block_taken', auth.uid(), old.owner_crew_id, new.id from profiles p
   where p.crew_id = new.owner_crew_id and p.id is distinct from auth.uid();
  return null;
end $$;
drop trigger if exists blocks_owner_activity on blocks;
create trigger blocks_owner_activity after update of owner_crew_id on blocks for each row
  when (old.owner_crew_id is distinct from new.owner_crew_id) execute function _act_block_owner();

-- Someone bought from your marketplace listing. Several buys by the same buyer within the hour fold together.
create or replace function _act_listing_sale() returns trigger language plpgsql security definer set search_path = public as $$
declare buyer uuid := auth.uid(); units int; cash bigint; a activity;
begin
  if buyer is null or buyer = new.seller_id then return null; end if;
  units := case when new.status = 'sold' then old.qty else old.qty - new.qty end;
  if units <= 0 then return null; end if;
  cash := units::bigint * new.unit_price;
  select * into a from activity
   where player_id = new.seller_id and kind = 'sold' and actor_id = buyer and data->>'commodity' = new.commodity
     and not seen and updated_at > now() - interval '1 hour'
   order by updated_at desc limit 1 for update;
  if a.id is null then
    insert into activity (player_id, kind, actor_id, data)
    values (new.seller_id, 'sold', buyer, jsonb_build_object('commodity', new.commodity, 'units', units, 'cash', cash));
  else
    update activity set updated_at = now(), data = jsonb_build_object('commodity', new.commodity,
        'units', (a.data->>'units')::int + units, 'cash', (a.data->>'cash')::bigint + cash)
     where id = a.id;
  end if;
  return null;
end $$;
drop trigger if exists listings_sale_activity on listings;
create trigger listings_sale_activity after update on listings for each row
  when (old.status = 'open' and (new.status = 'sold' or (new.status = 'open' and new.qty < old.qty)))
  execute function _act_listing_sale();

-- Someone applied to your crew (Capo and Co-Capo decide, so they both hear).
create or replace function _act_application() returns trigger language plpgsql security definer set search_path = public as $$
begin
  insert into activity (player_id, kind, actor_id, crew_id)
  select x, 'applied', new.player_id, new.crew_id
    from crews c cross join lateral unnest(array[c.capo_id, c.co_capo_id]) x
   where c.id = new.crew_id and x is not null;
  return null;
end $$;
drop trigger if exists crew_applications_activity on crew_applications;
create trigger crew_applications_activity after insert on crew_applications for each row execute function _act_application();

-- Someone else put you in a crew (accepted your application) or took you out of one (kicked you).
create or replace function _act_crew_membership() returns trigger language plpgsql security definer set search_path = public as $$
declare actor uuid := auth.uid();
begin
  if actor is null or actor = new.id then return null; end if;
  if old.crew_id is null and new.crew_id is not null then
    insert into activity (player_id, kind, actor_id, crew_id) values (new.id, 'joined', actor, new.crew_id);
  elsif old.crew_id is not null and new.crew_id is null then
    insert into activity (player_id, kind, actor_id, crew_id) values (new.id, 'kicked', actor, old.crew_id);
  end if;
  return null;
end $$;
drop trigger if exists profiles_crew_activity on profiles;
create trigger profiles_crew_activity after update of crew_id on profiles for each row
  when (old.crew_id is distinct from new.crew_id) execute function _act_crew_membership();

create or replace function get_activity(limit_n integer default 30) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid();
begin
  delete from activity where player_id = u and updated_at < now() - interval '30 days';
  return (select coalesce(jsonb_agg(x.j order by x.at desc, x.id desc), '[]'::jsonb) from (
    select a.updated_at as at, a.id, jsonb_build_object(
             'id', a.id, 'kind', a.kind, 'at', a.updated_at, 'seen', a.seen, 'data', a.data,
             'actor_id', a.actor_id, 'actor', p.name,
             'crew_id', a.crew_id, 'crew', c.name, 'crew_emblem', c.emblem,
             'block_id', a.block_id, 'block', b.name, 'hood_id', b.hood_id,
             'siege_wins', case when a.kind = 'siege' then (select s.wins from block_siege s where s.block_id = a.block_id and s.crew_id = a.crew_id) end,
             'siege_need', case when a.kind = 'siege' then _cfg('siege_wins') end) as j
      from activity a
      left join profiles p on p.id = a.actor_id
      left join crews c on c.id = a.crew_id
      left join blocks b on b.id = a.block_id
     where a.player_id = u
     order by a.updated_at desc, a.id desc
     limit greatest(1, least(coalesce(limit_n, 30), 100))) x);
end $$;

create or replace function activity_mark_seen() returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); n int;
begin
  update activity set seen = true where player_id = u and not seen;
  get diagnostics n = row_count;
  return jsonb_build_object('cleared', n);
end $$;

-- ---------------------------------------------------------------------------
-- Unread DMs
-- ---------------------------------------------------------------------------
create table if not exists chat_reads (
  player_id uuid not null references profiles(id) on delete cascade,
  channel   text not null,
  read_at   timestamptz not null default '-infinity',
  primary key (player_id, channel)
);
alter table chat_reads enable row level security;
revoke all on chat_reads from anon, authenticated;

-- Every DM gives both sides a read marker; the sender has obviously read their own message.
create or replace function _dm_reads() returns trigger language plpgsql security definer set search_path = public as $$
declare a uuid := split_part(new.channel, ':', 2)::uuid; b uuid := split_part(new.channel, ':', 3)::uuid; other uuid;
begin
  other := case when new.sender_id = a then b else a end;
  insert into chat_reads (player_id, channel, read_at) values (new.sender_id, new.channel, new.created_at)
    on conflict (player_id, channel) do update set read_at = greatest(chat_reads.read_at, excluded.read_at);
  insert into chat_reads (player_id, channel) select other, new.channel where exists (select 1 from profiles where id = other)
    on conflict (player_id, channel) do nothing;
  return null;
end $$;
drop trigger if exists messages_dm_reads on messages;
create trigger messages_dm_reads after insert on messages for each row
  when (new.channel like 'dm:%') execute function _dm_reads();

-- Everything sent before today counts as read, so nobody opens the game to a wall of old "unread" DMs.
insert into chat_reads (player_id, channel, read_at)
select v.p, m.channel, now()
  from (select distinct channel from messages where channel like 'dm:%') m
 cross join lateral (values (split_part(m.channel, ':', 2)::uuid), (split_part(m.channel, ':', 3)::uuid)) v(p)
 where exists (select 1 from profiles where id = v.p)
on conflict (player_id, channel) do nothing;

create or replace function mark_read(ch text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid();
begin
  if ch is null or ch not like 'dm:%' or position(u::text in ch) = 0 then return jsonb_build_object('ok', false); end if;
  insert into chat_reads (player_id, channel, read_at) values (u, ch, now())
    on conflict (player_id, channel) do update set read_at = now();
  return jsonb_build_object('ok', true);
end $$;

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
         order by channel, created_at desc) x $$;

-- get_me: same as before plus unread_activity / unread_dms for the tab badges.
create or replace function get_me() returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; po record; pd record; pj record;
begin
  perform _refresh_prices();
  perform _tick_world();
  pr := _tick(u);
  update profiles set last_seen = now() where id = u;
  select * into po from _power(u, 'offense');
  select * into pd from _power(u, 'defense');
  select * into pj from _power(u, 'jail');
  return jsonb_build_object(
    'id', pr.id, 'name', pr.name, 'created_at', pr.created_at, 'avatar', pr.avatar, 'bio', pr.bio, 'reputation', pr.reputation,
    'cash', pr.cash, 'bank', pr.bank, 'diamonds', pr.diamonds,
    'stamina', pr.stamina, 'stamina_max', pr.stamina_max,
    'health', pr.health, 'health_max', pr.health_max,
    'heat', pr.heat, 'heat_max', pr.heat_max,
    'heat_level', case when pr.heat >= _cfg('heat_red') then 'red' when pr.heat >= _cfg('heat_yellow') then 'yellow' else 'green' end,
    'jailed', _jailed(pr), 'jail_until', pr.jail_until,
    'hospital', _hospital(pr),
    'health_next', pr.health_tick + make_interval(mins => _cfg('health_regen_minutes')::int),
    'health_bought', pr.health_bought,
    'rep_earned', pr.rep_earned, 'path', pr.path,
    'path_required', pr.path is null and pr.rep_earned >= _cfg('path_rep'),
    'immune_until', pr.immune_until, 'immune', pr.immune_until > now(),
    'inventory_slots', pr.inventory_slots, 'storage_cap', pr.storage_cap,
    'refills_used', pr.refills_used,
    'actions_done', pr.actions_done, 'fights_won', pr.fights_won, 'fights_lost', pr.fights_lost,
    'market_volume', pr.market_volume, 'imports', pr.imports,
    'next_tick', pr.last_tick + make_interval(mins => _cfg('regen_minutes')::int),
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
                      'rate', c.grow_rate * g.level, 'cap', c.grow_cap * g.level,
                      'produced', least(c.grow_cap * g.level, g.banked + case when g.running
                          then floor(extract(epoch from now() - g.started_at) / 3600 * c.grow_rate * g.level)::int else 0 end),
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
    'transport_capacity', (select coalesce(max(d.capacity), 0) from inventory i join item_defs d on d.id = i.item_id
                           where i.player_id = u and i.qty > 0 and d.category = 'transport'),
    'listings', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'commodity', commodity, 'qty', qty,
                      'unit_price', unit_price, 'expires_at', expires_at, 'held', status = 'returned') order by created_at desc), '[]'::jsonb)
                 from listings where seller_id = u and status in ('open', 'returned')),
    'ribbons', _ribbons(u),
    'server_time', now()
  ) || jsonb_build_object(   -- a second object: jsonb_build_object takes at most 100 arguments
    'unread_activity', (select count(*) from activity where player_id = u and not seen),
    'unread_dms', (select count(*) from chat_reads r where r.player_id = u
                     and exists (select 1 from messages m where m.channel = r.channel and m.created_at > r.read_at and m.sender_id <> u))
  );
end $$;

-- ---------------------------------------------------------------------------
-- Rookie poker table: stakes a new player can cover, for accounts in their first week.
-- ---------------------------------------------------------------------------
alter table poker_tables add column if not exists max_age_days integer;   -- null = open to everyone
insert into poker_tables (name, small_blind, big_blind, min_buyin, max_buyin, max_age_days)
select 'Rookie Room · 100/200', 100, 200, 4000, 20000, 7
 where not exists (select 1 from poker_tables where max_age_days is not null);

create or replace function poker_lobby() returns jsonb
language sql security definer set search_path = public stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name, 'small_blind', t.small_blind, 'big_blind', t.big_blind,
           'min_buyin', t.min_buyin, 'max_buyin', t.max_buyin, 'seats', t.seats,
           'rookie_days', t.max_age_days,
           'eligible', t.max_age_days is null or (select p.created_at > now() - make_interval(days => t.max_age_days) from profiles p where p.id = auth.uid()),
           'seated', (select count(*) from poker_seats s where s.table_id = t.id),
           'players', (select coalesce(jsonb_agg(p.name), '[]'::jsonb) from poker_seats s join profiles p on p.id = s.player_id where s.table_id = t.id),
           'mine', exists (select 1 from poker_seats s where s.table_id = t.id and s.player_id = auth.uid())) order by t.big_blind, t.id), '[]'::jsonb)
  from poker_tables t $$;

create or replace function poker_join(tid integer, seat_no integer, buyin bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pr profiles; t poker_tables; cur poker_seats;
begin
  perform _nn(buyin, 'buy-in'); perform _nn(seat_no, 'seat');
  pr := _casino_player(null);
  select * into t from poker_tables where id = tid;
  if t.id is null then perform _fail('No such table'); end if;
  select * into cur from poker_seats where player_id = pr.id;
  if cur.player_id is not null then
    if cur.table_id <> tid then perform _fail('You are already seated at another table'); end if;
    -- rebuy / top up
    if buyin <= 0 or cur.stack + buyin > t.max_buyin then perform _fail(format('Stack can''t exceed $%s', t.max_buyin)); end if;
    if pr.cash < buyin then perform _fail('Not enough cash'); end if;
    update profiles set cash = cash - buyin where id = pr.id;
    update poker_seats set stack = stack + buyin, sitting_out = false, missed = 0 where player_id = pr.id;
    perform _poker_tick(tid);
    return poker_state(tid);
  end if;
  if t.max_age_days is not null and pr.created_at < now() - make_interval(days => t.max_age_days) then
    perform _fail(format('The Rookie Room is for players in their first %s days', t.max_age_days)); end if;
  if seat_no < 0 or seat_no >= t.seats then perform _fail('Bad seat'); end if;
  if exists (select 1 from poker_seats where table_id = tid and seat = seat_no) then perform _fail('That seat is taken'); end if;
  if buyin < t.min_buyin or buyin > t.max_buyin then perform _fail(format('Buy in for $%s to $%s', t.min_buyin, t.max_buyin)); end if;
  if pr.cash < buyin then perform _fail('Not enough cash on hand — withdraw from the bank first'); end if;
  update profiles set cash = cash - buyin where id = pr.id;
  insert into poker_seats (table_id, seat, player_id, stack) values (tid, seat_no, pr.id, buyin);
  perform _poker_tick(tid);
  return poker_state(tid);
end $$;

-- ---------------------------------------------------------------------------
-- Fight preview: simulate the fight a few hundred times with the same formula attack() uses.
-- Keep in step with attack() in 20260921000002_functions.sql.
-- ---------------------------------------------------------------------------
create or replace function fight_preview(target uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); me profiles; them profiles; pa record; pd record; sa setup_kind; sd setup_kind;
        sitb int; recent int; n int := 400; wins int := 0; dmin int := 1000000; dmax int := 0; i int; a int; d int;
        heat_after int; red int := _cfg('heat_red')::int;
begin
  perform _nn(target, 'target');
  if target = u then perform _fail('You cannot attack yourself'); end if;
  me := _tick(u);
  select * into them from profiles where id = target;
  if them.id is null then perform _fail('No such player'); end if;
  sa := case when _jailed(me) then 'jail' else 'offense' end;
  sd := case when _jailed(them) then 'jail' else 'defense' end;
  select * into pa from _power(u, sa);
  select * into pd from _power(target, sd);
  sitb := case when me.health::numeric / me.health_max > them.health::numeric / them.health_max then 2 else 0 end
        + case when me.heat < them.heat then 1 else 0 end
        + case when me.stamina > them.stamina then 1 else 0 end;
  for i in 1..n loop
    a := greatest(0, least(80, round(60.0 * pa.att / (pa.att + pd.def))::int + least(10, _rand_between(0, 6) + sitb)
           + case when pa.combo then _rand_between(0, 10) else 0 end - case when pd.combo then _rand_between(0, 10) else 0 end));
    d := greatest(0, round(0.35 * (60.0 * pd.att / (pd.att + pa.def) + _rand_between(0, 10)))::int);
    if a > d then wins := wins + 1; end if;
    dmin := least(dmin, d); dmax := greatest(dmax, d);
  end loop;
  select count(*) into recent from fights where attacker_id = u and defender_id = target and created_at > now() - interval '1 hour';
  heat_after := least(me.heat_max, me.heat + 4);
  return jsonb_build_object(
    'win_pct', round(100.0 * wins / n)::int,
    'dmg_min', dmin, 'dmg_max', dmax,
    'my_health', me.health, 'hospital_risk', me.health - dmax <= 19,
    'dry', recent >= 3, 'hits_this_hour', recent,
    'stamina_cost', 2, 'heat_gain', 4,
    'bust_pct', case when _jailed(me) or heat_after < red then 0 else round(100.0 * (heat_after - red + 1) / 40)::int end,
    'setup', sa, 'their_setup', sd);
end $$;

-- Grants: new RPCs to signed-in players only; trigger functions stay private.
do $$ declare f record; begin
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('get_activity', 'activity_mark_seen', 'mark_read', 'fight_preview') loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('_act_fight', '_act_crew_fight', '_act_siege', '_act_block_owner',
                                                         '_act_listing_sale', '_act_application', '_act_crew_membership', '_dm_reads') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
end $$;
