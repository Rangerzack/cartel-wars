-- Tests for the launch fixes (20261125000029_launch_fixes, docs/LAUNCH.md): attack() takes the 2 stamina it quotes,
-- refuses below 2 and allows exactly 2; sandbox purchases credit only
-- testers and admins (production purchases credit anyone); only admins can mark a tester.
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

-- attack() takes 2 stamina, at exactly 2 too, and refuses at 1 ----------------------------------------------------------
select as_user('1a000000-0029-4000-8000-000000000001');
do $$ declare me uuid := '1a000000-0029-4000-8000-000000000001'; them uuid := '1a000000-0029-4000-8000-000000000002';
             r jsonb; before int; begin
  update profiles set stamina = 10 where id = me;
  r := attack(them);
  assert (select stamina from profiles where id = me) = 8, 'a fight takes 2 stamina';
  assert (r->>'stamina')::int = 8, 'the result reports the stamina left: ' || r::text;
  -- exactly 2 is enough
  update profiles set stamina = 2, health = health_max, in_hospital = false, jail_until = null, heat = 0 where id in (me, them);
  update profiles set health = health_max, in_hospital = false where id = them;
  r := attack(them);
  assert (select stamina from profiles where id = me) = 0, 'exactly 2 stamina fights, leaving 0';
  -- 1 is not
  update profiles set stamina = 1, health = health_max, in_hospital = false, jail_until = null, heat = 0 where id = me;
  update profiles set health = health_max, in_hospital = false where id = them;
  perform expect_error(format('select attack(%L)', them), 'at least 2 stamina');
  assert (select stamina from profiles where id = me) = 1, 'a refused fight takes nothing';
  -- the preview still quotes what the fight takes
  update profiles set stamina = 10 where id = me;
  assert (fight_preview(them)->>'stamina_cost')::int = 2;
end $$;

-- Sandbox purchases credit testers and admins only; production credits anyone ---------------------------------------------
do $$ declare buyer uuid := '1a000000-0029-4000-8000-000000000003'; tester uuid := '1a000000-0029-4000-8000-000000000004';
             adm uuid := '1a000000-0029-4000-8000-000000000005'; r jsonb; d0 int; begin
  update profiles set iap_tester = true where id = tester;
  update profiles set is_admin = true where id = adm;
  select diamonds into d0 from profiles where id = buyer;
  r := iap_apply('revenuecat', 'NON_RENEWING_PURCHASE', 'lx-sb-1', 'io.rangelab.cartelwars.diamonds.100', buyer, null, '{"environment": "SANDBOX"}');
  assert r->>'ignored' = 'sandbox purchase by a non-tester', r::text;
  assert (select diamonds from profiles where id = buyer) = d0, 'no diamonds from a non-tester sandbox buy';
  assert exists (select 1 from iap_grants where transaction_id = 'lx-sb-1' and player_id = buyer), 'still on the record';
  -- a retry of the same event is a duplicate, not a second chance
  r := iap_apply('revenuecat', 'NON_RENEWING_PURCHASE', 'lx-sb-1', 'io.rangelab.cartelwars.diamonds.100', buyer, null, '{"environment": "SANDBOX"}');
  assert (r->>'duplicate')::boolean, r::text;
  -- a real purchase credits anyone
  r := iap_apply('revenuecat', 'NON_RENEWING_PURCHASE', 'lx-pr-1', 'io.rangelab.cartelwars.diamonds.100', buyer, null, '{"environment": "PRODUCTION"}');
  assert (r->>'credited')::int = 100, r::text;
  assert (select diamonds from profiles where id = buyer) = d0 + 100;
  -- testers and admins get sandbox credit (App Review's demo account is marked as a tester)
  r := iap_apply('revenuecat', 'NON_RENEWING_PURCHASE', 'lx-sb-2', 'io.rangelab.cartelwars.diamonds.100', tester, null, '{"environment": "sandbox"}');
  assert (r->>'credited')::int = 100, r::text;
  r := iap_apply('revenuecat', 'NON_RENEWING_PURCHASE', 'lx-sb-3', 'io.rangelab.cartelwars.diamonds.100', adm, null, '{"environment": "SANDBOX"}');
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

select '  LAUNCH TEST PASSED';
