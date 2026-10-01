-- Tests for report notifications (#13): off while notify_url is empty; with a URL, at most one per 10 minutes, the slot
-- claimed before the send; the report always goes in, without pg_net (local databases don't have it) and when the
-- notification itself fails.
-- Run after the other suites (reuses their helpers): scripts/local-db.sh test
\set ON_ERROR_STOP on
\set QUIET on

insert into auth.users (id, raw_user_meta_data) values
  ('ce111111-1111-1111-1111-111111111111', '{"name":"Tattler"}'),
  ('ce222222-2222-2222-2222-222222222222', '{"name":"Loudmouth"}'),
  ('ce333333-3333-3333-3333-333333333333', '{"name":"Nosy Parker"}'),
  ('ce444444-4444-4444-4444-444444444444', '{"name":"Rude Dude"}');

-- Off by default: both settings exist and are empty, and no report so far (this suite's or earlier ones') claimed a slot
select as_user('ce111111-1111-1111-1111-111111111111');
do $$ declare r jsonb; begin
  assert (select count(*) from app_text where key in ('notify_url', 'notify_secret') and value = '') = 2;
  assert _cfg_text('no_such_key') = '';
  r := report_profile('ce444444-4444-4444-4444-444444444444', 'name', 'rude');
  assert exists (select 1 from profile_reports where id = (r->>'id')::bigint), 'the report went in';
  assert not exists (select 1 from notify_state), 'no URL, no notification';
end $$;

-- With a URL, the next report claims the slot: sent_at is written first, then the send (a no-op without pg_net) ------
update app_text set value = 'http://127.0.0.1:9/functions/v1/report-notify' where key = 'notify_url';
select as_user('ce222222-2222-2222-2222-222222222222');
do $$ declare r jsonb; begin
  r := report_profile('ce444444-4444-4444-4444-444444444444', 'bio', 'rude bio');
  assert exists (select 1 from profile_reports where id = (r->>'id')::bigint), 'the report went in';
  assert (select sent_at from notify_state where key = 'report') = now(), 'slot claimed';
end $$;

-- A report inside the 10 minutes leaves the slot alone ------------------------------------------------------------------
select as_user('ce333333-3333-3333-3333-333333333333');
do $$ declare r jsonb; was timestamptz := now() - interval '5 minutes'; begin
  update notify_state set sent_at = was where key = 'report';
  r := report_profile('ce444444-4444-4444-4444-444444444444', 'avatar');
  assert exists (select 1 from profile_reports where id = (r->>'id')::bigint), 'the report went in';
  assert (select sent_at from notify_state where key = 'report') = was, 'still inside the window';
end $$;

-- 11 minutes on, the next report claims a new slot ----------------------------------------------------------------------
select as_user('ce111111-1111-1111-1111-111111111111');
do $$ begin
  update notify_state set sent_at = now() - interval '11 minutes' where key = 'report';
  perform report_profile('ce222222-2222-2222-2222-222222222222', 'other', 'spams reports');
  assert (select sent_at from notify_state where key = 'report') = now(), 'a new slot after the window';
end $$;

-- A notification that fails rolls back only itself: the report goes in and no slot is claimed. Renaming notify_state
-- away makes the trigger's slot claim fail.
set client_min_messages = error;    -- the trigger's warning
select as_user('ce222222-2222-2222-2222-222222222222');
do $$ declare r jsonb; was timestamptz := now() - interval '11 minutes'; begin
  update notify_state set sent_at = was where key = 'report';
  alter table notify_state rename to notify_state_away;
  r := report_profile('ce111111-1111-1111-1111-111111111111', 'name');
  alter table notify_state_away rename to notify_state;
  assert exists (select 1 from profile_reports where id = (r->>'id')::bigint), 'the report went in';
  assert (select sent_at from notify_state where key = 'report') = was, 'the failed attempt left the slot alone';
end $$;
reset client_min_messages;

-- Grants: none of it is reachable from the app --------------------------------------------------------------------------
do $$ declare f text; begin
  foreach f in array array['_cfg_text(text)', '_report_notify()'] loop
    assert not has_function_privilege('authenticated', f, 'execute') and not has_function_privilege('anon', f, 'execute'), f || ' should be private';
  end loop;
  foreach f in array array['app_text', 'notify_state'] loop
    assert not has_table_privilege('authenticated', f, 'select') and not has_table_privilege('anon', f, 'select'), f || ' should be private';
  end loop;
end $$;

-- leave notifications off for whatever runs next
update app_text set value = '' where key = 'notify_url';

select 'NOTIFY TEST PASSED';
