-- Boost side lock lasts only while the boost runs. While a +50 boost is running you can't buy the other side
-- (buying the same side adds another 24 hours); once it runs out you can pick either side again.

create or replace function buy_boost(side text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; cost int := _cfg('boost_diamonds')::int; until timestamptz;
begin
  perform _nn(side, 'side');
  pr := _tick(u);
  if side not in ('attack', 'defense') then perform _fail('Boost attack or defense'); end if;
  if _boost_active(pr) and pr.boost_side <> side then
    perform _fail(format('Your %s boost is still running — you can switch to %s once it runs out', pr.boost_side, side));
  end if;
  if pr.diamonds < cost then perform _fail(format('Costs %s diamonds', cost)); end if;
  -- same side while running: add to it; otherwise a fresh 24 hours on the side just picked
  until := case when _boost_active(pr) then pr.boost_until else now() end + make_interval(hours => _cfg('boost_hours')::int);
  update profiles set diamonds = diamonds - cost, boost_side = side, boost_until = until where id = u;
  return jsonb_build_object('side', side, 'until', until, 'cost', cost);
end $$;

do $$ declare f record; begin
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('buy_boost') loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
