-- Tests for 20261004000020_phase3: _win_frac as loops gives the counts by hand, and find_thugs still answers;
-- get_messages holds a read to 200 lines.
-- Run after the other suites (reuses their helpers): scripts/local-db.sh test
\set ON_ERROR_STOP on
\set QUIET on

insert into auth.users (id, raw_user_meta_data) values ('f3f3f3f3-0020-4000-8000-000000000001', '{"name":"P3Me"}');

select as_user('f3f3f3f3-0020-4000-8000-000000000001');
do $$ declare r jsonb; begin
  -- even bases, no edges, no combos: you win when your die beats theirs, 21 of the 49 rolls
  assert _win_frac(30, 30, 0, 0, 0, 0) = 21::numeric / 49, 'die against die: ' || _win_frac(30, 30, 0, 0, 0, 0);
  -- a combo swing of 0–1 on your side only: the ties now win half the time, 49 of 98
  assert _win_frac(30, 30, 0, 0, 1, 0) = 49::numeric / 98, 'with a swing: ' || _win_frac(30, 30, 0, 0, 1, 0);
  -- the edge caps at 10: +20 on your roll is the same as +10, which beats every roll of theirs
  assert _win_frac(30, 30, 20, 0, 0, 0) = _win_frac(30, 30, 10, 0, 0, 0), 'edge cap';
  assert _win_frac(30, 30, 10, 0, 0, 0) = 1, 'a sure thing';
  -- a far stronger defender: never
  assert _win_frac(10, 60, 0, 0, 2, 2) = 0, 'no chance';

  -- the thugs list still comes back whole, each with a percentage
  r := find_thugs();
  assert jsonb_array_length(r) > 0 and (select bool_and((e->>'win_pct')::int between 0 and 100) from jsonb_array_elements(r) e), 'find_thugs';

  -- chat: 250 lines, a read stops at 200 whatever it asks for, and 50 by default
  insert into messages (channel, sender_id, sender_name, body, created_at)
    select 'global', 'f3f3f3f3-0020-4000-8000-000000000001', 'P3Me', 'p3 line ' || g, now() - make_interval(secs => 251 - g) from generate_series(1, 250) g;
  assert jsonb_array_length(get_messages('global', 100000)) = 200, 'capped at 200';
  assert jsonb_array_length(get_messages('global')) = 50, '50 by default';
  assert jsonb_array_length(get_messages('global', 0)) = 1, 'at least one';
  assert (get_messages('global', 100) -> -1 ->> 'body') = 'p3 line 250', 'oldest first, newest last';
end $$;

select ' PHASE 3 TEST PASSED';
