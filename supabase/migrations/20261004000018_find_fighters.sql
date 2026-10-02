-- Fight › Players filters (Zack, 2026-10-02): search by name plus a status filter — who you can fight right now,
-- who's online, who's in the hospital, who's in jail — and a sort.
--
-- A new RPC rather than a new signature for find_players: the name directory (lib/names.ts) and the live client keep
-- calling find_players unchanged while staging and live share this database.
--
-- "Can fight" mirrors attack()'s checks from the caller's side: not in the hospital, no new-player immunity, and on
-- the same side of the bars (an inmate can only fight inmates, and only inmates can get at one). Online is seen in
-- the last 5 minutes (an open game refreshes get_me every 10 seconds). Thugs stay out of an empty search, as before.
-- The counts cover the whole search, so each chip can say how many it would show.

create or replace function find_fighters(q text default '', status text default 'all', sort text default 'seen',
                                         limit_n integer default 50) returns jsonb
language plpgsql security definer set search_path = public stable as $$
declare u uuid := _uid(); my_jail boolean; pat text;
begin
  select _jailed(p) into my_jail from profiles p where p.id = u;
  q := btrim(coalesce(q, ''));
  -- a literal match: % and _ in a name search are just characters
  pat := '%' || replace(replace(replace(q, '\', '\\'), '%', '\%'), '_', '\_') || '%';
  return (
    with tagged as (
      select p.id, p.name, p.avatar, p.crew_id, p.fights_won, p.fights_lost, p.reputation, p.last_seen,
             _hospital(p) as hosp, _jailed(p) as jail, p.immune_until > now() as imm,
             p.last_seen > now() - interval '5 minutes' as online,
             not _hospital(p) and not (p.immune_until > now()) and _jailed(p) = coalesce(my_jail, false) as can_fight
      from profiles p
      where p.id <> u and (q = '' or p.name ilike pat) and (q <> '' or not p.is_bot)
    ), picked as (
      select t.*, row_number() over (order by
               case when sort = 'wins' then t.fights_won end desc nulls last,
               case when sort = 'rep' then t.reputation end desc nulls last,
               case when sort = 'name' then lower(t.name) end,
               t.last_seen desc nulls last, t.id) as rn
      from tagged t
      where case status when 'fight' then t.can_fight when 'online' then t.online
                        when 'hospital' then t.hosp when 'jail' then t.jail else true end
      order by rn
      limit greatest(1, least(coalesce(limit_n, 50), 200))
    )
    select jsonb_build_object(
      'players', (select coalesce(jsonb_agg(jsonb_build_object('id', k.id, 'name', k.name, 'avatar', k.avatar,
                    'crew', (select jsonb_build_object('name', c.name, 'emblem', c.emblem) from crews c where c.id = k.crew_id),
                    'fights', k.fights_won + k.fights_lost, 'fights_won', k.fights_won, 'reputation', k.reputation,
                    'hospital', k.hosp, 'jailed', k.jail, 'immune', k.imm, 'online', k.online, 'can_fight', k.can_fight,
                    'last_seen', k.last_seen) order by k.rn), '[]'::jsonb) from picked k),
      'counts', (select jsonb_build_object('all', count(*), 'fight', count(*) filter (where can_fight),
                    'online', count(*) filter (where online), 'hospital', count(*) filter (where hosp),
                    'jail', count(*) filter (where jail)) from tagged)
    )
  );
end $$;

do $$ declare f record; begin
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'find_fighters' loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
