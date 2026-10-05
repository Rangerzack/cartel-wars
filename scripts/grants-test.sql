-- Who can call what, checked on the bare migrations before any suite adds its test helpers (Phase 6, 20261005000021_qa):
--  - no private helper (name starting with _) is callable by a signed-in player or by anyone signed out
--  - signed out, only check_name is callable (the sign-up form's name check)
-- A new migration that forgets its grants loop fails here, not on the live site.
-- Run first: scripts/local-db.sh test
\set ON_ERROR_STOP on
\set QUIET on

do $$ declare bad text; begin
  select string_agg(p.proname, ', ' order by p.proname) into bad from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname like '\_%'
     and (has_function_privilege('authenticated', p.oid, 'execute') or has_function_privilege('anon', p.oid, 'execute'));
  assert bad is null, 'private helpers anyone can call: ' || bad;
  select string_agg(p.proname, ', ' order by p.proname) into bad from pg_proc p join pg_namespace n on n.oid = p.pronamespace
   where n.nspname = 'public' and p.proname <> 'check_name' and p.prorettype <> 'trigger'::regtype
     and has_function_privilege('anon', p.oid, 'execute');
  assert bad is null, 'callable signed out: ' || bad;
end $$;

select ' GRANTS TEST PASSED';
