-- Phase 3 (UX), the two server pieces:
--  * The Thugs list was slow to open (0.6 s live, 2.3 s on a dev box): 90% of find_thugs went to _win_frac, a SQL
--    function Postgres couldn't inline, so it planned its query afresh for each of the 200 thugs (~10 ms a time). The
--    same count as plain loops in plpgsql: every die roll (0–6 each side, capped at 10 with the edges) and every combo
--    swing (0..amax against 0..dmax), wins over all of them. Same inputs, same answer to the last digit — checked
--    against the old function on 6,480 input sets before this went in. Only find_thugs calls it.
--  * Chat's "Load older messages" asks get_messages for 50 more lines at a time; the server now holds any one read to
--    200 lines (it took whatever limit it was sent).

create or replace function _win_frac(ba numeric, bd numeric, ea integer, ed integer, amax integer, dmax integer)
returns numeric language plpgsql immutable set search_path = public as $$
declare wins bigint := 0; total bigint := 0; a numeric; d numeric;
begin
  for ra in 0..6 loop
    a := ba + least(10, ra + ea);
    for rd in 0..6 loop
      d := bd + least(10, rd + ed);
      for ca in 0..amax loop
        for cd in 0..dmax loop
          total := total + 1;
          if a + (ca - cd) > d then wins := wins + 1; end if;
        end loop;
      end loop;
    end loop;
  end loop;
  return wins::numeric / total;
end $$;

create or replace function get_messages(channel text, limit_n integer default 50) returns jsonb
language plpgsql security definer set search_path = public stable as $$
declare u uuid := _uid();
begin
  if not _can_use_channel(u, channel) then perform _fail('You cannot read that channel'); end if;
  return (select coalesce(jsonb_agg(to_jsonb(m) order by m.created_at), '[]'::jsonb)
          from (select x.id, x.sender_id, x.sender_name, x.body, x.created_at, x.deleted from messages x
                 where x.channel = get_messages.channel
                   and (get_messages.channel like 'dm:%' or not _has_blocked(u, x.sender_id))
                 order by x.created_at desc limit least(greatest(coalesce(limit_n, 50), 1), 200)) m);
end $$;

do $$ declare f record; begin
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('_win_frac') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
end $$;
