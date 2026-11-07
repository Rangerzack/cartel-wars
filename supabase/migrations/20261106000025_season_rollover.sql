-- Season rollover (sprint day 5, 2026-11-06): what an admin needs to turn Season 1 into Season 2 without the SQL
-- editor, and the one rule the rehearsal turned up.
--
--  · season_list()    admins: every season with its status (scheduled, running, over), the draw by name, how many
--                     players had a hood and how many took the boss.
--  · season_end(id)   admins: ends the running season now (ends_at = now()). Starting the next one is season_start,
--                     which already takes a start time, so the usual move is to schedule Season 2 to begin the
--                     moment Season 1 ends and never have a gap.
--  · _unlocked        the gate is a first-season thing. A player who had a hood in an earlier season keeps the whole
--                     city open in the next one; Marcus's missions still run for them as a seasonal reward track.
--                     Without this, every rollover would lock Crew, Territory and Fight for every veteran until they
--                     replayed fourteen missions — a tutorial the second time is a nag. New signups are gated as before.
--
-- What a rollover resets: the hood (six fresh held blocks on a new draw), the missions, the hood's perks. What it never
-- touches: profiles (cash, bank, diamonds, gear, slots, crew, reputation), inventories, grow houses, territory. The old
-- season's rows stay as history under their season_id.

create or replace function season_list() returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid();
begin
  if not _is_admin(u) then perform _fail('Admins only'); end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', s.id, 'name', s.name, 'starts_at', s.starts_at, 'ends_at', s.ends_at,
      'status', case when s.ends_at <= now() then 'over' when s.starts_at > now() then 'scheduled' else 'running' end,
      'businesses', (select jsonb_agg(jsonb_build_object('code', c, 'name', d.name, 'icon', d.icon) order by i)
                       from unnest(s.home_businesses) with ordinality as b(c, i) join business_defs d on d.code = b.c),
      'defenders', to_jsonb(s.home_defenders),
      'players', (select count(*) from home_hoods h where h.season_id = s.id),
      'bosses', (select count(*) from home_hoods h where h.season_id = s.id and h.boss_cleared_at is not null))
      order by s.starts_at desc) from seasons s), '[]'::jsonb);
end $$;

create or replace function season_end(sid int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); s seasons;
begin
  if not _is_admin(u) then perform _fail('Admins only'); end if;
  perform _nn(sid, 'season');
  select * into s from seasons where id = sid for update;
  if s.id is null then perform _fail('No such season'); end if;
  if s.ends_at <= now() then perform _fail('That season is already over'); end if;
  if s.starts_at > now() then perform _fail('That season hasn''t started — delete it instead'); end if;
  update seasons set ends_at = now() where id = sid returning * into s;
  return to_jsonb(s);
end $$;

-- A scheduled season that hasn't started can be taken back.
create or replace function season_cancel(sid int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); s seasons;
begin
  if not _is_admin(u) then perform _fail('Admins only'); end if;
  perform _nn(sid, 'season');
  select * into s from seasons where id = sid for update;
  if s.id is null then perform _fail('No such season'); end if;
  if s.starts_at <= now() then perform _fail('That season has started — end it instead'); end if;
  delete from seasons where id = sid;
  return jsonb_build_object('cancelled', sid);
end $$;

-- Body from 20261103000023_gate_current; the veteran rule is new.
create or replace function _unlocked(p uuid) returns jsonb language plpgsql stable set search_path = public as $$
declare s seasons := _season(); always text[] := array['home', 'hood', 'profile', 'store', 'chat', 'forum', 'activity', 'accolades', 'missions'];
        gated text[] := array['items', 'actions', 'services', 'casino', 'economy', 'fight', 'crew', 'territory'];
        cur text;
begin
  if s.id is null then return to_jsonb(always || gated); end if;
  -- a veteran: a hood in a season that started before this one. The campaign still runs; the city stays open.
  if exists (select 1 from home_hoods h join seasons x on x.id = h.season_id
              where h.player_id = p and x.id <> s.id and x.starts_at < s.starts_at) then
    return to_jsonb(always || gated);
  end if;
  -- the mission the player is on: the first unclaimed one on the free track
  select d.key into cur from _mission_defs(s.id) d
   where not d.pass_only and not exists (select 1 from missions m where m.player_id = p and m.season_id = s.id and m.key = d.key and m.claimed_at is not null)
   order by d.seq limit 1;
  return to_jsonb(always || coalesce((select array_agg(distinct x) from mission_defs d cross join unnest(d.unlocks) x
                                       where d.key = cur
                                          or exists (select 1 from missions m where m.player_id = p and m.season_id = s.id and m.key = d.key and m.claimed_at is not null)), '{}'::text[]));
end $$;

do $$ declare f record; begin
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('_unlocked') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('season_list', 'season_end', 'season_cancel') loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
