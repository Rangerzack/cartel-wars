-- Tests for the launch fixes (20261125000029_launch_fixes, docs/LAUNCH.md): fights cost no stamina; sandbox purchases
-- credit only testers and admins (production purchases credit anyone); only admins can mark a tester; the Daily Drop
-- is paused (no subscribing, crates already left still open); store products are on the new bundle id.
-- Run after the other suites (reuses their helpers): scripts/local-db.sh test
\set ON_ERROR_STOP on
\set QUIET on

insert into auth.users (id, raw_user_meta_data) values
  ('1a000000-0029-4000-8000-000000000001', '{"name":"LxHitter"}'),
  ('1a000000-0029-4000-8000-000000000002', '{"name":"LxTarget"}'),
  ('1a000000-0029-4000-8000-000000000003', '{"name":"LxBuyer"}'),
  ('1a000000-0029-4000-8000-000000000004', '{"name":"LxTester"}'),
  ('1a000000-0029-4000-8000-000000000005', '{"name":"LxAdmin"}');
update profiles set health = health_max, in_hospital = false, jail_until = null, heat = 0, immune_until = now() - interval '1 day',
       stamina_tick = now(), cash = 100000
 where id::text like '1a000000-0029-%';

-- Fights cost no stamina: a fight on 0 stamina goes through and takes nothing ----------------------------------------------
select as_user('1a000000-0029-4000-8000-000000000001');
do $$ declare me uuid := '1a000000-0029-4000-8000-000000000001'; them uuid := '1a000000-0029-4000-8000-000000000002'; begin
  update profiles set stamina = 0, stamina_tick = now() where id = me;
  perform attack(them);
  assert (select stamina from profiles where id = me) = 0, 'a fight takes no stamina';
  update profiles set stamina = 7, stamina_tick = now(), health = health_max, in_hospital = false, jail_until = null, heat = 0 where id = me;
  update profiles set health = health_max, in_hospital = false where id = them;
  perform attack(them);
  assert (select stamina from profiles where id = me) = 7, 'still nothing at 7';
  assert (fight_preview(them)->>'stamina_cost')::int = 0, 'the preview quotes 0';
end $$;

-- Sandbox purchases credit testers and admins only; production credits anyone ---------------------------------------------
do $$ declare buyer uuid := '1a000000-0029-4000-8000-000000000003'; tester uuid := '1a000000-0029-4000-8000-000000000004';
             adm uuid := '1a000000-0029-4000-8000-000000000005'; r jsonb; d0 int; begin
  update profiles set iap_tester = true where id = tester;
  update profiles set is_admin = true where id = adm;
  select diamonds into d0 from profiles where id = buyer;
  r := iap_apply('revenuecat', 'NON_RENEWING_PURCHASE', 'lx-sb-1', 'io.github.rangerzack.thugempire.diamonds.100', buyer, null, '{"environment": "SANDBOX"}');
  assert r->>'ignored' = 'sandbox purchase by a non-tester', r::text;
  assert (select diamonds from profiles where id = buyer) = d0, 'no diamonds from a non-tester sandbox buy';
  assert exists (select 1 from iap_grants where transaction_id = 'lx-sb-1' and player_id = buyer), 'still on the record';
  -- a retry of the same event is a duplicate, not a second chance
  r := iap_apply('revenuecat', 'NON_RENEWING_PURCHASE', 'lx-sb-1', 'io.github.rangerzack.thugempire.diamonds.100', buyer, null, '{"environment": "SANDBOX"}');
  assert (r->>'duplicate')::boolean, r::text;
  -- a real purchase credits anyone
  r := iap_apply('revenuecat', 'NON_RENEWING_PURCHASE', 'lx-pr-1', 'io.github.rangerzack.thugempire.diamonds.100', buyer, null, '{"environment": "PRODUCTION"}');
  assert (r->>'credited')::int = 100, r::text;
  assert (select diamonds from profiles where id = buyer) = d0 + 100;
  -- testers and admins get sandbox credit (App Review's demo account is marked as a tester)
  r := iap_apply('revenuecat', 'NON_RENEWING_PURCHASE', 'lx-sb-2', 'io.github.rangerzack.thugempire.diamonds.100', tester, null, '{"environment": "sandbox"}');
  assert (r->>'credited')::int = 100, r::text;
  r := iap_apply('revenuecat', 'NON_RENEWING_PURCHASE', 'lx-sb-3', 'io.github.rangerzack.thugempire.diamonds.100', adm, null, '{"environment": "SANDBOX"}');
  assert (r->>'credited')::int = 100, r::text;
end $$;

-- Only admins mark testers ------------------------------------------------------------------------------------------------
select as_user('1a000000-0029-4000-8000-000000000003');
select expect_error($q$select admin_set_iap_tester('1a000000-0029-4000-8000-000000000003', true)$q$, 'Admins only');
do $$ begin assert not (select iap_tester from profiles where id = '1a000000-0029-4000-8000-000000000003'); end $$;
select as_user('1a000000-0029-4000-8000-000000000005');
do $$ begin
  perform admin_set_iap_tester('1a000000-0029-4000-8000-000000000003', true);
  assert (select iap_tester from profiles where id = '1a000000-0029-4000-8000-000000000003');
  perform admin_set_iap_tester('1a000000-0029-4000-8000-000000000003', false);
  assert not (select iap_tester from profiles where id = '1a000000-0029-4000-8000-000000000003');
end $$;

-- The Daily Drop is paused for 1.0: no subscribing, but crates already left open --------------------------------------------
insert into app_text (key, value) values ('drop_paused', '1') on conflict (key) do update set value = '1';
select as_user('1a000000-0029-4000-8000-000000000003');
select expect_error('select subscribe_drop()', 'paused until the next update');
do $$ declare u uuid := '1a000000-0029-4000-8000-000000000003'; r jsonb; begin
  update profiles set drop_since = null, drop_until = null, drop_crates = 2 where id = u;
  r := open_crate();
  assert (select drop_crates from profiles where id = u) = 1, 'a crate already left still opens: ' || r::text;
  assert (select count(*) from store_packs where id not like 'io.github.rangerzack.thugempire.diamonds.%') = 0, 'packs on the new bundle id';
  assert _cfg_text('store_drop_product') = 'io.github.rangerzack.thugempire.drop.monthly';
end $$;

select '  LAUNCH TEST PASSED';
