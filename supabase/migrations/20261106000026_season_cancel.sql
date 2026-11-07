-- Cancelling a scheduled season leaves a trace (sprint day 5, later the same day). 20261106000025 cancelled by
-- deleting the row; an admin action that destroys a row is the one kind the shared database's tooling refuses to
-- run unattended, and a season that was scheduled and taken back is worth remembering anyway. So: seasons gain
-- cancelled_at, a cancelled season is invisible to _season() and to the overlap check, and the list shows it as
-- 'cancelled'. Bodies of _season, season_start and season_list from 20261030000022 / 20261106000025; only the
-- cancelled_at clauses are new.
alter table seasons add column if not exists cancelled_at timestamptz;

create or replace function _season() returns seasons language sql stable set search_path = public as $$
  select s from seasons s where s.cancelled_at is null and s.starts_at <= now() and s.ends_at > now() order by s.starts_at desc limit 1 $$;

create or replace function season_start(nm text, from_at timestamptz default now(), months int default 3,
                                        defenders int[] default array[12, 22, 32, 45, 60, 75, 95]) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); s seasons; draw text[];
begin
  if not _is_admin(u) then perform _fail('Admins only'); end if;
  if nullif(trim(nm), '') is null then perform _fail('Name the season'); end if;
  if array_length(defenders, 1) <> 7 then perform _fail('Seven defender numbers: six blocks and the boss'); end if;
  if months < 1 then perform _fail('A season is at least a month'); end if;
  if exists (select 1 from seasons x where x.cancelled_at is null and x.starts_at < from_at + make_interval(months => months) and x.ends_at > from_at) then
    perform _fail('That overlaps a season'); end if;
  select array_agg(code) into draw from (select code from business_defs order by random() limit 6) x;
  insert into seasons (name, starts_at, ends_at, home_businesses, home_defenders)
    values (trim(nm), from_at, from_at + make_interval(months => months), draw, defenders) returning * into s;
  return to_jsonb(s);
end $$;

create or replace function season_list() returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid();
begin
  if not _is_admin(u) then perform _fail('Admins only'); end if;
  return coalesce((select jsonb_agg(jsonb_build_object(
      'id', s.id, 'name', s.name, 'starts_at', s.starts_at, 'ends_at', s.ends_at, 'cancelled_at', s.cancelled_at,
      'status', case when s.cancelled_at is not null then 'cancelled' when s.ends_at <= now() then 'over'
                     when s.starts_at > now() then 'scheduled' else 'running' end,
      'businesses', (select jsonb_agg(jsonb_build_object('code', c, 'name', d.name, 'icon', d.icon) order by i)
                       from unnest(s.home_businesses) with ordinality as b(c, i) join business_defs d on d.code = b.c),
      'defenders', to_jsonb(s.home_defenders),
      'players', (select count(*) from home_hoods h where h.season_id = s.id),
      'bosses', (select count(*) from home_hoods h where h.season_id = s.id and h.boss_cleared_at is not null))
      order by s.starts_at desc) from seasons s), '[]'::jsonb);
end $$;

create or replace function season_cancel(sid int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); s seasons;
begin
  if not _is_admin(u) then perform _fail('Admins only'); end if;
  perform _nn(sid, 'season');
  select * into s from seasons where id = sid for update;
  if s.id is null then perform _fail('No such season'); end if;
  if s.cancelled_at is not null then perform _fail('That season is already cancelled'); end if;
  if s.starts_at <= now() then perform _fail('That season has started — end it instead'); end if;
  update seasons set cancelled_at = now() where id = sid returning * into s;
  return jsonb_build_object('cancelled', sid, 'season', to_jsonb(s));
end $$;

do $$ declare f record; begin
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('_season') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('season_start', 'season_list', 'season_end', 'season_cancel') loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
