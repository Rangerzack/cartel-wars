-- Jail and heat (Zack, 2026-10-02): "when you go to jail it should max out your heat and if you bail you should
-- have zero heat".
--  * Every way in (a bust from red heat on a job, an attack or a crew fight, the Bribe Police job, the 💎50 turn-in)
--    sets heat to your max heat, upgrades included. Every way out (posting bail) sets it to 0.
--  * One trigger on profiles does it, so every path that moves jail_until gets it: it fires only when you go from
--    outside to inside or back. A job or fight in jail writes jail_until unchanged and leaves heat alone, and so does
--    the usual cooling (−1 every 10 minutes) while you're inside.
--  * _bust_roll sets max heat too (it used to drop you to your yellow line), so the jail RPCs' own answers agree
--    with what gets saved.
--  * Anyone inside right now goes to max heat, as if they'd just walked in.

create or replace function _jail_heat() returns trigger
language plpgsql set search_path = public as $$
declare was boolean := old.jail_until is not null and old.jail_until > now();
        now_in boolean := new.jail_until is not null and new.jail_until > now();
begin
  if now_in and not was then new.heat := new.heat_max;     -- walked in: the heat's all the way up
  elsif was and not now_in then new.heat := 0;              -- bailed out: clean slate
  end if;
  return new;
end $$;

create or replace trigger profiles_jail_heat before update of jail_until on profiles
  for each row when (old.jail_until is distinct from new.jail_until) execute function _jail_heat();

create or replace function _bust_roll(pr profiles) returns profiles
language plpgsql set search_path = public as $$
begin
  if _jailed(pr) then return pr; end if;
  if pr.heat >= _heat_red(pr) and random() < (pr.heat - _heat_red(pr) + 1) / 40.0 then
    pr.jail_until := 'infinity';                                 -- inside until you post bail
    pr.heat := pr.heat_max;                                      -- with the heat all the way up (_jail_heat)
  end if;
  return pr;
end $$;

-- whoever's inside now: max heat, the same as walking in today
update profiles set heat = heat_max where jail_until > now() and heat < heat_max;

do $$ declare f record; begin
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('_jail_heat', '_bust_roll') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
end $$;
