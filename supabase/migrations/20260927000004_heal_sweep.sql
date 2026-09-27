-- Players heal (and leave the hospital) on their own, even while offline.
-- Regen is lazy — it's applied when a player's row is next touched — so someone knocked out who then logs
-- off used to sit at 0 health with the 🏥 on the Fight list until they came back. A once-a-minute sweep now
-- runs the normal tick for everyone who's below full health, so health, the hospital flag, stamina, heat
-- and jail release stay current for all players (and the NPC thugs) whether they're online or not.
-- The sweep doesn't touch last_seen, so offline players don't look online.

create or replace function _heal_sweep() returns integer language plpgsql set search_path = public as $$
declare r record; n int := 0;
begin
  for r in select id from profiles
            where health < health_max
              and health_tick <= now() - make_interval(mins => _cfg('health_regen_minutes')::int)
            for update skip locked          -- someone mid-action gets their tick from that action instead
  loop
    perform _tick(r.id);
    n := n + 1;
  end loop;
  return n;
end $$;
revoke all on function _heal_sweep() from public, anon, authenticated;

-- Run it every minute with pg_cron where it's available (the hosted project). Local test databases
-- don't have pg_cron; tests call _heal_sweep() directly.
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    begin
      create extension if not exists pg_cron;
      perform cron.schedule('heal-sweep', '* * * * *', 'select public._heal_sweep()');
    exception when others then
      raise notice 'pg_cron not usable here (%) — _heal_sweep() is not scheduled', sqlerrm;
    end;
  end if;
end $$;

-- Catch everyone up now instead of waiting for the first run.
select _heal_sweep();
