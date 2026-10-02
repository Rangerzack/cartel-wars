-- Tests for Fight › Players filters (20261004000018_find_fighters): search by name, the status filters (can fight,
-- online, hospital, jail), the counts behind each chip, the sorts, and "can fight" from inside jail.
-- Run after the other suites (reuses their helpers): scripts/local-db.sh test
\set ON_ERROR_STOP on
\set QUIET on

insert into auth.users (id, raw_user_meta_data) values
  ('f1f1f1f1-0018-4000-8000-000000000001', '{"name":"FzMe"}'),
  ('f1f1f1f1-0018-4000-8000-000000000002', '{"name":"FzFree"}'),
  ('f1f1f1f1-0018-4000-8000-000000000003', '{"name":"FzHosp"}'),
  ('f1f1f1f1-0018-4000-8000-000000000004', '{"name":"FzJail"}'),
  ('f1f1f1f1-0018-4000-8000-000000000005', '{"name":"FzOld"}'),
  ('f1f1f1f1-0018-4000-8000-000000000006', '{"name":"Fz_Under"}');

select as_user('f1f1f1f1-0018-4000-8000-000000000001');
do $$ declare r jsonb; names text[]; c jsonb; begin
  update profiles set health = health_max, in_hospital = false, jail_until = null, immune_until = now() - interval '1 day',
         last_seen = now() - interval '1 minute', fights_won = 0, fights_lost = 0
   where name in ('FzMe', 'FzFree', 'FzHosp', 'FzJail', 'FzOld', 'Fz_Under');
  update profiles set fights_won = 9, reputation = 50 where name = 'FzFree';
  update profiles set health = 5, in_hospital = true, last_seen = now() - interval '20 minutes', fights_won = 3 where name = 'FzHosp';
  update profiles set jail_until = 'infinity', fights_won = 5 where name = 'FzJail';
  update profiles set last_seen = now() - interval '2 hours', fights_won = 1, reputation = 900 where name = 'FzOld';

  -- everyone matching but me, most recently seen first
  r := find_fighters('Fz');
  names := array(select e->>'name' from jsonb_array_elements(r->'players') e);
  assert not 'FzMe' = any(names), 'never yourself';
  assert cardinality(names) = 5 and names[5] = 'FzOld', 'all five, the long-gone one last: ' || names::text;
  c := r->'counts';
  assert (c->>'all')::int = 5 and (c->>'fight')::int = 3 and (c->>'online')::int = 3
     and (c->>'hospital')::int = 1 and (c->>'jail')::int = 1, 'counts: ' || c::text;

  -- each filter
  names := array(select e->>'name' from jsonb_array_elements(find_fighters('Fz', 'fight')->'players') e order by 1);
  assert names = array['FzFree', 'FzOld', 'Fz_Under'], 'can fight: out of the hospital and out of jail: ' || names::text;
  names := array(select e->>'name' from jsonb_array_elements(find_fighters('Fz', 'online')->'players') e order by 1);
  assert names = array['FzFree', 'FzJail', 'Fz_Under'], 'online: seen in the last 5 minutes: ' || names::text;
  names := array(select e->>'name' from jsonb_array_elements(find_fighters('Fz', 'hospital')->'players') e);
  assert names = array['FzHosp'], 'hospital';
  names := array(select e->>'name' from jsonb_array_elements(find_fighters('Fz', 'jail')->'players') e);
  assert names = array['FzJail'], 'jail';
  r := find_fighters('FzHosp', 'all');
  assert (r->'players'->0->>'hospital')::boolean and not (r->'players'->0->>'can_fight')::boolean
     and not (r->'players'->0->>'online')::boolean, 'flags on a row: ' || (r->'players'->0)::text;

  -- sorts
  assert find_fighters('Fz', 'all', 'wins')->'players'->0->>'name' = 'FzFree', 'most wins first';
  assert find_fighters('Fz', 'all', 'rep')->'players'->0->>'name' = 'FzOld', 'most rep first';
  names := array(select e->>'name' from jsonb_array_elements(find_fighters('Fz', 'all', 'name')->'players') e);
  assert array_position(names, 'FzFree') < array_position(names, 'FzHosp') and array_position(names, 'FzHosp') < array_position(names, 'FzJail')
     and array_position(names, 'FzJail') < array_position(names, 'FzOld'), 'by name: ' || names::text;

  -- an underscore is a character, not a wildcard; the limit holds
  names := array(select e->>'name' from jsonb_array_elements(find_fighters('z_U')->'players') e);
  assert names = array['Fz_Under'], 'underscore matched literally: ' || names::text;
  assert jsonb_array_length(find_fighters('Fz', 'all', 'seen', 2)->'players') = 2, 'limit';

  -- thugs: out of an empty search, in when you name one
  assert not exists (select 1 from jsonb_array_elements(find_fighters('', 'all', 'seen', 200)->'players') e
                     join profiles p on p.id = (e->>'id')::uuid where p.is_bot), 'no thugs on an empty search';
  assert exists (select 1 from jsonb_array_elements(find_fighters('Thug 5')->'players') e where e->>'name' = 'Thug 50'), 'thugs by name';

  -- locked up: the only people you can fight are other inmates
  update profiles set jail_until = 'infinity' where name = 'FzMe';
  names := array(select e->>'name' from jsonb_array_elements(find_fighters('Fz', 'fight')->'players') e);
  assert names = array['FzJail'], 'from jail, only inmates: ' || names::text;
  update profiles set jail_until = null where name = 'FzMe';
end $$;

select ' FIGHTERS TEST PASSED';
