-- The moderation routine (#13): tell the admin when reports come in. Apple guideline 1.2 asks for "timely responses to
-- concerns", and Zack, the only admin, only saw the queue when he opened the game.
--
--  * Each new report calls the report-notify edge function (supabase/functions/report-notify), which posts to Discord or
--    sends an email: how many players have open reports, how many reports that is, and the latest one. See docs/ops.md.
--  * At most one call every 10 minutes (notify_state 'report'), so a burst of reports can't flood the admin. The slot is
--    claimed (sent_at written) before the call goes out; the next call after the window carries the counts.
--  * The function's URL and shared secret are text and set by hand on the live project, so they live in a small app_text
--    table (read with _cfg_text) rather than _cfg, which is a numeric constant function. Both start empty: no URL, no call.
--  * The call goes out through pg_net where it's installed (the hosted project). Local test databases don't have pg_net,
--    so there the trigger claims the slot and sends nothing. A failed notification never fails the report.

-- ---------------------------------------------------------------------------
-- Text settings and the throttle
-- ---------------------------------------------------------------------------
create table if not exists app_text (
  key   text primary key,
  value text not null default ''
);
alter table app_text enable row level security;
revoke all on app_text from anon, authenticated;
-- set on live by SQL: update app_text set value = '…' where key = 'notify_url';
insert into app_text (key, value) values ('notify_url', ''), ('notify_secret', '') on conflict (key) do nothing;

create or replace function _cfg_text(k text) returns text
language sql stable set search_path = public as $$ select coalesce((select value from app_text where key = k), '') $$;

create table if not exists notify_state (key text primary key, sent_at timestamptz);
alter table notify_state enable row level security;
revoke all on notify_state from anon, authenticated;

-- pg_net makes the HTTP call from the trigger, where it's available (the hosted project).
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_net') then
    begin
      create extension if not exists pg_net;
    exception when others then
      raise notice 'pg_net not usable here (%) — report notifications are off', sqlerrm;
    end;
  end if;
end $$;

-- ---------------------------------------------------------------------------
-- The trigger
-- ---------------------------------------------------------------------------
-- Claim the 10-minute slot first, then queue the call, so a second report inside the window sends nothing even while
-- the first call is in flight. It all sits in one exception block: if anything fails, the attempt (slot included) rolls
-- back, the report still goes in, and the next report tries again.
-- Counts come from whichever table fired it, using reason, note, target_id, reporter_id, created_at and status.
create or replace function _report_notify() returns trigger
language plpgsql security definer set search_path = public as $$
declare endpoint text; claimed boolean; targets int; total int;
begin
  begin
    endpoint := _cfg_text('notify_url');
    if endpoint = '' then return new; end if;     -- off
    insert into notify_state (key, sent_at) values ('report', now())
    on conflict (key) do update set sent_at = excluded.sent_at
      where notify_state.sent_at is null or notify_state.sent_at <= now() - interval '10 minutes'
    returning true into claimed;
    if claimed is null then return new; end if;    -- inside the window
    execute format('select count(distinct target_id), count(*) from %I.%I where status = ''open''', tg_table_schema, tg_table_name)
       into targets, total;
    if exists (select 1 from pg_extension where extname = 'pg_net') then
      perform net.http_post(
        url := endpoint,
        body := jsonb_build_object('kind', 'report', 'open_targets', targets, 'open_reports', total,
                  'latest', jsonb_build_object('reason', new.reason, 'note', new.note,
                              'target', (select name from profiles where id = new.target_id),
                              'reporter', (select name from profiles where id = new.reporter_id),
                              'at', new.created_at)),
        headers := jsonb_build_object('Content-Type', 'application/json', 'x-report-secret', _cfg_text('notify_secret')));
    end if;
  exception when others then
    raise warning 'report notification failed: %', sqlerrm;
  end;
  return new;
end $$;

-- #10: if reports move to a new table, attach this trigger there too (renaming profile_reports keeps it attached).
drop trigger if exists profile_reports_notify on profile_reports;
create trigger profile_reports_notify after insert on profile_reports for each row execute function _report_notify();

-- ---------------------------------------------------------------------------
-- Grants: nothing new is public
-- ---------------------------------------------------------------------------
do $$ declare f record; begin
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('_cfg_text', '_report_notify') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
end $$;
