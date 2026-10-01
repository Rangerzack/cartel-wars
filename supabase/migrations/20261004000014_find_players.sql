-- Fight › Players opens on an empty search, sorted by last seen, and the 200 NPC thugs filled most of it: 32 of the
-- first 40 rows were "Thug n · 0W · 0L". Thugs have their own tab with odds and paydays, so an empty search now lists
-- real players only. Typing a name still finds a thug. The body is the one from 20260927000001_fast_regen.sql; only
-- the is_bot line is new.
create or replace function find_players(q text default '', limit_n integer default 40) returns jsonb
language sql security definer set search_path = public stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'avatar', p.avatar,
           'crew', (select jsonb_build_object('name', c.name, 'emblem', c.emblem) from crews c where c.id = p.crew_id),
           'fights', p.fights_won + p.fights_lost, 'fights_won', p.fights_won,
           'hospital', p.in_hospital or p.health <= 19, 'jailed', p.jail_until is not null and p.jail_until > now(),
           'immune', p.immune_until > now(), 'last_seen', p.last_seen)), '[]'::jsonb)
  from (select * from profiles where id <> auth.uid() and (q = '' or name ilike '%' || q || '%')
          and (q <> '' or not is_bot)
        order by last_seen desc limit limit_n) p $$;

do $$ declare f record; begin
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'find_players' loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
