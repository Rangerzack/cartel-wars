-- Season 1, day 3: a mission's unlocks open when the mission is reached, not when it's claimed. Get Armed opens the
-- shop and needs the shop to be done; First Blood opens Fight and needs a fight. So the tabs a player has are those
-- of every claimed mission plus the one they're on. Body from 20261030000022_season1; only the current-mission join
-- is new.
create or replace function _unlocked(p uuid) returns jsonb language plpgsql stable set search_path = public as $$
declare s seasons := _season(); always text[] := array['home', 'hood', 'profile', 'store', 'chat', 'forum', 'activity', 'accolades', 'missions'];
        gated text[] := array['items', 'actions', 'services', 'casino', 'economy', 'fight', 'crew', 'territory'];
        cur text;
begin
  if s.id is null then return to_jsonb(always || gated); end if;
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
           where n.nspname = 'public' and p.proname = '_unlocked' loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
end $$;
