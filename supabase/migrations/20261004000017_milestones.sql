-- Milestones, round 2 (Zack, 2026-10-01).
--
-- On top of the lifetime ladders (once each, unchanged), milestones that repeat forever, 30 diamonds every time:
--   every 250 actions · every 500 fight wins · every 500 turf attacks (any attack on a block; spying isn't one)
--   · every $10,000,000 wagered at the casino (every game: slots, roulette, craps, blackjack, poker).
-- Two new lifetime ladders: total fights (won or lost) and total cash wagered at the casino.
-- Players already past a step are paid for it now (Zack: "pay what's been earned").
--
-- The counts: actions and fights were already on profiles; turf_attacks and casino_wagered are new, kept by triggers
-- on territory_log and casino_bets (every game writes there), so no attack or casino RPC changes. milestone_defs rows
-- with repeat = true are the repeating ones (n is the step); milestone_repeats holds how many of each a player has been
-- paid. Each payout writes one 'milestone' line to the activity feed per kind.

-- a live game holds row locks on profiles all the time: give up rather than queue every player behind this ALTER
set local lock_timeout = '15s';

alter table profiles add column if not exists turf_attacks bigint not null default 0;
alter table profiles add column if not exists casino_wagered bigint not null default 0;

-- ---------------------------------------------------------------------------
-- Definitions: repeating steps, and the fights and casino ladders
-- ---------------------------------------------------------------------------
alter table milestone_defs add column if not exists repeat boolean not null default false;
alter table milestone_defs alter column n type bigint;
alter table milestone_defs drop constraint if exists milestone_defs_kind_check;
alter table milestone_defs add constraint milestone_defs_kind_check check (kind in ('actions', 'wins', 'fights', 'turf', 'wagered'));

insert into milestone_defs (key, kind, n, reward, repeat) values
  ('every_actions', 'actions', 250, 30, true), ('every_wins', 'wins', 500, 30, true),
  ('every_turf', 'turf', 500, 30, true), ('every_wagered', 'wagered', 10000000, 30, true),
  ('fights_100', 'fights', 100, 5, false), ('fights_500', 'fights', 500, 15, false), ('fights_1000', 'fights', 1000, 30, false),
  ('fights_2500', 'fights', 2500, 50, false), ('fights_5000', 'fights', 5000, 75, false), ('fights_10000', 'fights', 10000, 100, false),
  ('fights_25000', 'fights', 25000, 150, false), ('fights_50000', 'fights', 50000, 200, false),
  ('wagered_1000000', 'wagered', 1000000, 5, false), ('wagered_5000000', 'wagered', 5000000, 10, false),
  ('wagered_10000000', 'wagered', 10000000, 20, false), ('wagered_25000000', 'wagered', 25000000, 30, false),
  ('wagered_50000000', 'wagered', 50000000, 50, false), ('wagered_100000000', 'wagered', 100000000, 75, false),
  ('wagered_250000000', 'wagered', 250000000, 100, false), ('wagered_500000000', 'wagered', 500000000, 150, false),
  ('wagered_1000000000', 'wagered', 1000000000, 250, false)
on conflict (key) do update set kind = excluded.kind, n = excluded.n, reward = excluded.reward, repeat = excluded.repeat;

create table if not exists milestone_repeats (
  player_id uuid not null references profiles(id) on delete cascade,
  key       text not null,                 -- milestone_defs.key of a repeating step
  paid      integer not null default 0,    -- steps paid so far
  primary key (player_id, key)
);
alter table milestone_repeats enable row level security;
revoke all on milestone_repeats from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Paying them
-- ---------------------------------------------------------------------------
create or replace function _milestone_total(pr profiles, kind text) returns bigint
language sql stable set search_path = public as $$
  select case kind when 'actions' then pr.actions_done when 'wins' then pr.fights_won
                   when 'fights' then pr.fights_won + pr.fights_lost when 'turf' then pr.turf_attacks
                   when 'wagered' then pr.casino_wagered else 0 end::bigint $$;

create or replace function _award_milestones(p uuid) returns void
language plpgsql set search_path = public as $$
declare pr profiles; m milestone_defs; due bigint; got int; pay jsonb := '{}'; reached jsonb := '{}'; k text;
begin
  select * into pr from profiles where id = p;
  if pr.id is null or pr.is_bot then return; end if;
  -- the lifetime ladders: each step once
  for m in select d.* from milestone_defs d where not d.repeat and _milestone_total(pr, d.kind) >= d.n order by d.kind, d.n loop
    insert into milestones (player_id, key) values (p, m.key) on conflict do nothing;
    if found then
      update profiles set diamonds = diamonds + m.reward where id = p;
      pay := pay || jsonb_build_object(m.kind, coalesce((pay->>m.kind)::int, 0) + m.reward);
      reached := reached || jsonb_build_object(m.kind, greatest(coalesce((reached->>m.kind)::bigint, 0), m.n));
    end if;
  end loop;
  -- the repeats: every n, once for each n reached (the row is locked, so two calls at once can't both pay a step)
  for m in select d.* from milestone_defs d where d.repeat loop
    due := floor(_milestone_total(pr, m.kind) / m.n);
    continue when due < 1;
    insert into milestone_repeats (player_id, key) values (p, m.key) on conflict do nothing;
    select paid into got from milestone_repeats where player_id = p and key = m.key for update;
    continue when due <= got;
    update milestone_repeats set paid = due where player_id = p and key = m.key;
    update profiles set diamonds = diamonds + (due - got) * m.reward where id = p;
    pay := pay || jsonb_build_object(m.kind, coalesce((pay->>m.kind)::int, 0) + (due - got) * m.reward);
    reached := reached || jsonb_build_object(m.kind, greatest(coalesce((reached->>m.kind)::bigint, 0), due * m.n));
  end loop;
  -- one feed line per kind: the highest step reached and what it paid
  for k in select jsonb_object_keys(pay) loop
    insert into activity (player_id, kind, data)
    values (p, 'milestone', jsonb_build_object('what', k, 'n', (reached->>k)::bigint, 'diamonds', (pay->>k)::int));
  end loop;
end $$;

-- ---------------------------------------------------------------------------
-- The new counts, kept where every turf attack and every casino bet is written
-- ---------------------------------------------------------------------------
create or replace function _turf_counted() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.attacker_id is not null then
    update profiles set turf_attacks = turf_attacks + 1 where id = new.attacker_id;
    perform _award_milestones(new.attacker_id);
  end if;
  return null;
end $$;
drop trigger if exists territory_log_counted on territory_log;
create trigger territory_log_counted after insert on territory_log for each row execute function _turf_counted();

create or replace function _wager_counted() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  if new.wager > 0 then
    update profiles set casino_wagered = casino_wagered + new.wager where id = new.player_id;
    perform _award_milestones(new.player_id);
  end if;
  return null;
end $$;
drop trigger if exists casino_bets_counted on casino_bets;
create trigger casino_bets_counted after insert on casino_bets for each row execute function _wager_counted();

-- ---------------------------------------------------------------------------
-- get_me: the two new counts, for the progress on the Milestones card
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
              'drop_paid', pr.drop_until is not null,   -- only the store webhook sets drop_until
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
    -- the market: street details (for previewing a hustle), my open buy orders; and today's drug refills
    'street', _street_json(),
    'orders', (select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'commodity', o.commodity, 'qty', o.qty, 'filled', o.filled,
                    'unit_price', o.unit_price, 'expires_at', o.expires_at) order by o.created_at desc), '[]'::jsonb)
               from buy_orders o where o.buyer_id = u and o.status = 'open'),
    -- drug refills: full ones per drug today (3, or 5 on the Daily Drop), how many of each are used, and what one
    -- restores after that (a share of max stamina)
    'refills', jsonb_build_object('full', _refill_full_n(pr), 'used', _drug_refills_today(pr), 'late_share', _cfg('refill_late_share'),
                                  'sub_full', (_cfg('refill_full') + _cfg('refill_sub_extra'))::int),
    'path_due', _path_due(pr),  -- why a path is required: 'rep' or 'grow'
    'heat_yellow', _heat_yellow(pr), 'heat_red', _heat_red(pr),  -- this player's lines (heat upgrades move them up)
    -- milestone progress the profile row doesn't already carry: turf attacks made and cash wagered at the casino
    'turf_attacks', pr.turf_attacks, 'casino_wagered', pr.casino_wagered,
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

-- ---------------------------------------------------------------------------
-- Back pay: the counts from history, then everything already earned
-- ---------------------------------------------------------------------------
update profiles p set
  turf_attacks = (select count(*) from territory_log t where t.attacker_id = p.id),
  casino_wagered = (select coalesce(sum(b.wager), 0) from casino_bets b where b.player_id = p.id);
do $$ declare r record; begin
  for r in select id from profiles where not is_bot loop perform _award_milestones(r.id); end loop;
end $$;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
do $$ declare f record; begin
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'get_me' loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('_milestone_total', '_award_milestones', '_turf_counted', '_wager_counted') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
end $$;
