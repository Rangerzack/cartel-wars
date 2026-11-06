-- The season board (sprint 2, item 1): who's furthest through the season. Read from rows the hood and the campaign
-- already keep, nothing new is written. The order: the boss down first, then blocks taken, then missions claimed,
-- then whoever got there first. Bots are off the board. Anyone signed in can read it; it sits under the campaign
-- log (/missions).
create or replace function _season_rank(sid int) returns table (player_id uuid, boss boolean, cleared int, claimed int, at timestamptz, rank int)
language sql stable set search_path = public as $$
  select x.player_id, x.boss, x.cleared, x.claimed, x.at,
         (rank() over (order by x.boss desc, x.cleared desc, x.claimed desc, x.at asc nulls last))::int
    from (select h.player_id, h.boss_cleared_at is not null as boss,
                 (select count(*) from home_blocks b where b.player_id = h.player_id and b.season_id = sid and b.cleared_at is not null)::int as cleared,
                 (select count(*) from missions m where m.player_id = h.player_id and m.season_id = sid and m.claimed_at is not null)::int as claimed,
                 greatest(h.boss_cleared_at,
                          (select max(b.cleared_at) from home_blocks b where b.player_id = h.player_id and b.season_id = sid),
                          (select max(m.claimed_at) from missions m where m.player_id = h.player_id and m.season_id = sid)) as at
            from home_hoods h join profiles p on p.id = h.player_id
           where h.season_id = sid and not p.is_bot) x $$;

create or replace function season_board(limit_n int default 10) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); s seasons := _season(); rows_ jsonb; mine jsonb; n int;
begin
  if s.id is null then return jsonb_build_object('season', null, 'rows', '[]'::jsonb, 'me', null, 'players', 0); end if;
  n := greatest(1, least(coalesce(limit_n, 10), 50));
  select jsonb_agg(jsonb_build_object('rank', r.rank, 'id', p.id, 'name', p.name, 'avatar', p.avatar,
                                      'emblem', (select c.emblem from crews c where c.id = p.crew_id),
                                      'boss', r.boss, 'cleared', r.cleared, 'claimed', r.claimed, 'at', r.at, 'me', p.id = u)
                   order by r.rank, p.name)
    into rows_ from _season_rank(s.id) r join profiles p on p.id = r.player_id where r.rank <= n;
  select jsonb_build_object('rank', r.rank, 'boss', r.boss, 'cleared', r.cleared, 'claimed', r.claimed) into mine
    from _season_rank(s.id) r where r.player_id = u;
  return jsonb_build_object('season', jsonb_build_object('id', s.id, 'name', s.name, 'ends_at', s.ends_at),
                            'rows', coalesce(rows_, '[]'::jsonb), 'me', mine,
                            'players', (select count(*) from _season_rank(s.id)));
end $$;

do $$ declare f record; begin
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('_season_rank') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('season_board') loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
