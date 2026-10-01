-- Tests for in-app purchases (#15, #16, #17): the store catalog, iap_apply (packs credited once, refunds clawed back and
-- clamped, the Daily Drop paid through, lapsing and refunded, ignored products, events and players, one audit row per
-- call), purchased diamonds that can't be gifted and are spent first, a paid plan that can't be cancelled in the game,
-- the deletion tally, and grants.
-- Run after the other suites (reuses their helpers): scripts/local-db.sh test
\set ON_ERROR_STOP on
\set QUIET on

insert into auth.users (id, raw_user_meta_data) values
  ('ee111111-1111-1111-1111-111111111111', '{"name":"Whale"}'),
  ('ee222222-2222-2222-2222-222222222222', '{"name":"Pal"}'),
  ('ee333333-3333-3333-3333-333333333333', '{"name":"Subby"}'),
  ('ee444444-4444-4444-4444-444444444444', '{"name":"Freebie"}');

-- iap_apply as the webhook calls it: RevenueCat's event type, the transaction, the product, the player, the expiry
create function _iap(ev text, tx text, product text, who text, expires timestamptz default null, raw jsonb default '{}')
returns jsonb language sql as $$ select iap_apply('revenuecat', ev, tx, product, who::uuid, expires, raw) $$;
create temp table _test_store as select (select count(*) from iap_grants) as grants0;

-- The catalog: active packs in order, the subscription's product, no prices ------------------------------------------
select as_user('ee111111-1111-1111-1111-111111111111');
do $$ declare s jsonb := get_catalog()->'store'; begin
  assert jsonb_array_length(s->'packs') = 6, s::text;
  assert s->'packs'->0 = '{"id": "io.rangelab.cartelwars.diamonds.100", "diamonds": 100}'::jsonb, s::text;
  assert s->'packs'->5 = '{"id": "io.rangelab.cartelwars.diamonds.15000", "diamonds": 15000}'::jsonb, s::text;
  assert s->>'drop_product' = 'io.rangelab.cartelwars.drop.monthly';
  assert s::text not like '%price%', 'prices come from StoreKit';
  -- a pack switched off leaves the store
  update store_packs set active = false where id = 'io.rangelab.cartelwars.diamonds.15000';
  assert jsonb_array_length(get_catalog()->'store'->'packs') = 5;
  update store_packs set active = true where id = 'io.rangelab.cartelwars.diamonds.15000';
  -- new players: nothing bought, not on a paid plan
  assert (get_me()->'drop'->>'drop_paid')::boolean = false;
  assert (select diamonds_bought = 0 and diamonds_bought_unspent = 0 from profiles where id = auth.uid());
end $$;

-- A pack: credited once, with an activity line and an audit row ----------------------------------------------------------
do $$ declare u uuid := 'ee111111-1111-1111-1111-111111111111'; r jsonb; p profiles; begin
  update profiles set diamonds = 10 where id = u;    -- 10 earned
  r := _iap('NON_RENEWING_PURCHASE', 'tx-1', 'io.rangelab.cartelwars.diamonds.100', u::text, null, '{"environment": "SANDBOX"}');
  assert r = '{"credited": 100}', r::text;
  select * into p from profiles where id = u;
  assert p.diamonds = 110 and p.diamonds_bought = 100 and p.diamonds_bought_unspent = 100, row_to_json(p)::text;
  assert (select data from activity where player_id = u and kind = 'purchase') = '{"diamonds": 100}';
  assert (select diamonds from iap_grants where transaction_id = 'tx-1') = 100;
  assert (select raw->>'environment' from iap_grants where transaction_id = 'tx-1') = 'SANDBOX', 'the payload is kept';
  -- RevenueCat retries: the same event again changes nothing and isn't logged twice
  r := _iap('NON_RENEWING_PURCHASE', 'tx-1', 'io.rangelab.cartelwars.diamonds.100', u::text);
  assert r = '{"duplicate": true}', r::text;
  assert (select diamonds from profiles where id = u) = 110;
  assert (select count(*) from iap_grants where transaction_id = 'tx-1') = 1;
  assert (select count(*) from activity where player_id = u and kind = 'purchase') = 1;
  -- INITIAL_PURCHASE credits a pack too; RENEWAL isn't a pack event
  r := _iap('INITIAL_PURCHASE', 'tx-2', 'io.rangelab.cartelwars.diamonds.550', u::text);
  assert r = '{"credited": 550}', r::text;
  r := _iap('RENEWAL', 'tx-2', 'io.rangelab.cartelwars.diamonds.550', u::text);
  assert r = '{"ignored": "RENEWAL"}', r::text;
  select * into p from profiles where id = u;
  assert p.diamonds = 660 and p.diamonds_bought = 650 and p.diamonds_bought_unspent = 650, row_to_json(p)::text;
end $$;

-- #17: only earned diamonds can be sent; spending uses purchased ones first ------------------------------------------
do $$ declare u uuid := 'ee111111-1111-1111-1111-111111111111'; pal uuid := 'ee222222-2222-2222-2222-222222222222'; p profiles; r jsonb; begin
  perform expect_error(format('select send_diamonds(%L, 11)', pal), 'You can only send diamonds you earned in the game');
  r := send_diamonds(pal, 10);
  assert (r->>'sent')::int = 10;
  select * into p from profiles where id = u;
  assert p.diamonds = 650 and p.diamonds_bought_unspent = 650, 'a gift comes out of earned diamonds: ' || row_to_json(p)::text;
  assert (select diamonds_bought_unspent from profiles where id = pal) = 0, 'a gift is earned for the one who gets it';
  perform expect_error(format('select send_diamonds(%L, 1)', pal), 'You can only send diamonds you earned');
  perform expect_error(format('select send_diamonds(%L, 9999)', pal), 'Invalid amount');

  -- a diamond refill (6) spends purchased diamonds first
  update profiles set stamina = 0 where id = u;
  perform refill('stamina', 'diamonds');
  select * into p from profiles where id = u;
  assert p.diamonds = 644 and p.diamonds_bought_unspent = 644, row_to_json(p)::text;
  -- earning more makes that much sendable
  update profiles set diamonds = diamonds + 20 where id = u;
  perform expect_error(format('select send_diamonds(%L, 21)', pal), 'only send diamonds you earned');
  perform send_diamonds(pal, 20);
  select * into p from profiles where id = u;
  assert p.diamonds = 644 and p.diamonds_bought_unspent = 644, row_to_json(p)::text;
  -- any drop counts as spending, floored at 0 and never above what's left
  update profiles set diamonds = 600 where id = u;
  assert (select diamonds_bought_unspent from profiles where id = u) = 600;
  update profiles set diamonds = diamonds + 50 where id = u;    -- 50 earned on top
  update profiles set diamonds = 0 where id = u;
  assert (select diamonds_bought_unspent from profiles where id = u) = 0;
  assert (select diamonds_bought from profiles where id = u) = 650, 'the lifetime count never falls on spending';
end $$;

-- Refunds take the pack back, clamped at 0 ------------------------------------------------------------------------------
do $$ declare u uuid := 'ee111111-1111-1111-1111-111111111111'; pal uuid := 'ee222222-2222-2222-2222-222222222222'; p profiles; r jsonb; begin
  update profiles set diamonds = 0, diamonds_bought = 0, diamonds_bought_unspent = 0 where id = u;
  update profiles set diamonds = 40 where id = u;    -- 40 earned
  perform _iap('NON_RENEWING_PURCHASE', 'tx-3', 'io.rangelab.cartelwars.diamonds.100', u::text);
  -- refunded while all 100 are still there: they go, the 40 earned stay
  r := _iap('CANCELLATION', 'tx-3', 'io.rangelab.cartelwars.diamonds.100', u::text, null, '{"cancel_reason": "CUSTOMER_SUPPORT"}');
  assert r = '{"revoked": 100}', r::text;
  select * into p from profiles where id = u;
  assert p.diamonds = 40 and p.diamonds_bought = 0 and p.diamonds_bought_unspent = 0, row_to_json(p)::text;
  assert (select diamonds from iap_grants where transaction_id = 'tx-3' and event = 'CANCELLATION') = -100;
  assert (select data from activity where player_id = u and kind = 'purchase_refunded') = '{"bought": 100, "diamonds": 100}';
  assert (select raw->>'cancel_reason' from iap_grants where transaction_id = 'tx-3' and event = 'CANCELLATION') = 'CUSTOMER_SUPPORT';

  -- bought, then 110 of the 140 spent (purchased first), then refunded: only the 30 left can go, never below 0
  perform _iap('NON_RENEWING_PURCHASE', 'tx-4', 'io.rangelab.cartelwars.diamonds.100', u::text);
  update profiles set diamonds = 30 where id = u;
  r := _iap('REFUND', 'tx-4', 'io.rangelab.cartelwars.diamonds.100', u::text);
  assert r = '{"revoked": 30}', r::text;
  select * into p from profiles where id = u;
  assert p.diamonds = 0 and p.diamonds_bought_unspent = 0 and p.diamonds_bought = 0, row_to_json(p)::text;
  assert (select diamonds from iap_grants where transaction_id = 'tx-4' and event = 'REFUND') = -30;
  -- a second refund event for the same purchase takes nothing more
  update profiles set diamonds = 500 where id = u;
  r := _iap('CANCELLATION', 'tx-4', 'io.rangelab.cartelwars.diamonds.100', u::text);
  assert r = '{"ignored": "already refunded"}', r::text;
  assert (select diamonds from profiles where id = u) = 500;

  -- the refund takes what the purchase credited, even if the pack changed since
  perform _iap('NON_RENEWING_PURCHASE', 'tx-5', 'io.rangelab.cartelwars.diamonds.550', u::text);
  update store_packs set diamonds = 600 where id = 'io.rangelab.cartelwars.diamonds.550';
  r := _iap('CANCELLATION', 'tx-5', 'io.rangelab.cartelwars.diamonds.550', u::text);
  assert r = '{"revoked": 550}', r::text;
  update store_packs set diamonds = 550 where id = 'io.rangelab.cartelwars.diamonds.550';
  assert (select diamonds from profiles where id = u) = 500;
end $$;

-- The Daily Drop subscription --------------------------------------------------------------------------------------
select as_user('ee333333-3333-3333-3333-333333333333');
do $$ declare u uuid := 'ee333333-3333-3333-3333-333333333333'; m jsonb; r jsonb; t timestamptz := now() + interval '30 days'; p profiles;
         prod text := 'io.rangelab.cartelwars.drop.monthly'; begin
  r := _iap('INITIAL_PURCHASE', 'sub-1', prod, u::text, t);
  assert r ? 'subscribed', r::text;
  m := get_me()->'drop';
  assert (m->>'subscribed')::boolean and (m->>'drop_paid')::boolean and (m->>'crates')::int = 1, m::text;
  assert (select drop_until from profiles where id = u) = t, 'paid through the period''s end';
  -- Apple bills it, so it's cancelled in the device settings, not here
  perform expect_error('select unsubscribe_drop()', 'Manage your subscription in your device settings');
  perform expect_error('select subscribe_drop()', 'already subscribed');

  -- renewals move the date on; a late, older event never moves it back
  r := _iap('RENEWAL', 'sub-2', prod, u::text, t + interval '30 days');
  assert (select drop_until from profiles where id = u) = t + interval '30 days';
  r := _iap('UNCANCELLATION', 'sub-1', prod, u::text, t);
  assert (select drop_until from profiles where id = u) = t + interval '30 days', 'never shortened';
  assert (select drop_crates from profiles where id = u) = 1, 'still one crate a day';

  -- auto-renew off and billing trouble change nothing: it runs to the paid-through date
  r := _iap('CANCELLATION', 'sub-2', prod, u::text, t + interval '30 days', '{"cancel_reason": "UNSUBSCRIBE"}');
  assert r = '{"unchanged": "CANCELLATION"}', r::text;
  r := _iap('BILLING_ISSUE', 'sub-2', prod, u::text, t + interval '30 days');
  assert r = '{"unchanged": "BILLING_ISSUE"}', r::text;
  assert (get_me()->'drop'->>'subscribed')::boolean;

  -- EXPIRATION lets it lapse; the crates already left stay
  r := _iap('EXPIRATION', 'sub-2', prod, u::text, now() - interval '1 minute');
  assert r = '{"lapsed": true}', r::text;
  m := get_me()->'drop';
  assert not (m->>'subscribed')::boolean and (m->>'drop_paid')::boolean and (m->>'crates')::int = 1, m::text;
  perform expect_error('select unsubscribe_drop()', 'not subscribed');
  -- a subscription event for a period that's over, or without an end, leaves it off
  r := _iap('RENEWAL', 'sub-old', prod, u::text, now() - interval '1 day');
  assert r = '{"ignored": "already expired"}', r::text;
  r := _iap('RENEWAL', 'sub-none', prod, u::text, null);
  assert r = '{"ignored": "no expiry"}', r::text;
  assert not (get_me()->'drop'->>'subscribed')::boolean;

  -- back on, then refunded: it ends at once
  r := _iap('INITIAL_PURCHASE', 'sub-3', prod, u::text, now() + interval '30 days');
  assert (get_me()->'drop'->>'subscribed')::boolean;
  r := _iap('CANCELLATION', 'sub-3', prod, u::text, now() + interval '30 days', '{"cancel_reason": "CUSTOMER_SUPPORT"}');
  assert r = '{"ended": true}', r::text;
  select * into p from profiles where id = u;
  assert p.drop_until <= now() and not _drop_active(p), row_to_json(p)::text;
  -- events the subscription doesn't use
  r := _iap('TRANSFER', 'sub-3', prod, u::text);
  assert r = '{"ignored": "TRANSFER"}', r::text;
end $$;

-- A free-plan subscriber who starts paying keeps their start date --------------------------------------------------------
select as_user('ee444444-4444-4444-4444-444444444444');
do $$ declare u uuid := 'ee444444-4444-4444-4444-444444444444'; since timestamptz; begin
  perform subscribe_drop();
  since := (select drop_since from profiles where id = u);
  assert not (get_me()->'drop'->>'drop_paid')::boolean;
  perform _iap('INITIAL_PURCHASE', 'sub-4', 'io.rangelab.cartelwars.drop.monthly', u::text, now() + interval '30 days');
  assert (select drop_since from profiles where id = u) = since and (get_me()->'drop'->>'drop_paid')::boolean;
  assert (select drop_crates from profiles where id = u) = 1, 'no second crate the same day';
end $$;

-- Ignored calls still leave an audit row ---------------------------------------------------------------------------------
do $$ declare r jsonb; n0 bigint := (select grants0 from _test_store); begin
  r := _iap('TEST', 'evt-test', 'test_product', 'ee111111-1111-1111-1111-111111111111');
  assert r = '{"ignored": "unknown product"}', r::text;
  r := _iap('NON_RENEWING_PURCHASE', 'tx-ghost', 'io.rangelab.cartelwars.diamonds.100', '00000000-0000-0000-0000-00000000dead');
  assert r = '{"ignored": "unknown player"}', r::text;
  r := _iap('NON_RENEWING_PURCHASE', 'tx-anon', 'io.rangelab.cartelwars.diamonds.100', null);
  assert r = '{"ignored": "unknown player"}', r::text;
  assert (select player_id is null and diamonds = 0 from iap_grants where transaction_id = 'tx-ghost');
  -- every call above that wasn't a duplicate wrote exactly one row
  assert (select count(*) from iap_grants) = n0 + 25, (select count(*) from iap_grants) - n0;
  assert (select count(*) from iap_grants where event = 'TEST' and product_id = 'test_product') = 1;
  perform expect_error('select iap_apply(''revenuecat'', ''RENEWAL'', null, ''x'', null, null, null)', 'Missing transaction_id');
end $$;

-- Deleting an account that bought diamonds: the tally says it paid, the purchase rows stay without the player ----------
select as_user('ee222222-2222-2222-2222-222222222222');
do $$ declare u uuid := 'ee222222-2222-2222-2222-222222222222'; begin
  perform _iap('NON_RENEWING_PURCHASE', 'tx-pal', 'io.rangelab.cartelwars.diamonds.100', u::text);
  perform delete_account('Pal');
  assert (select had_purchases from deleted_accounts order by id desc limit 1), 'bought diamonds counts as paid';
  assert (select player_id is null and diamonds = 100 from iap_grants where transaction_id = 'tx-pal'), 'the record stays';
end $$;

-- Grants: the webhook's entry point is the service role's alone ----------------------------------------------------------
do $$ declare f text; begin
  foreach f in array array['iap_apply(text, text, text, text, uuid, timestamptz, jsonb)', '_diamonds_spent()'] loop
    assert not has_function_privilege('authenticated', f, 'execute') and not has_function_privilege('anon', f, 'execute'), f || ' should be private';
  end loop;
  foreach f in array array['get_catalog()', 'get_me()', 'send_diamonds(uuid, integer)', 'unsubscribe_drop()', 'delete_account(text)'] loop
    assert has_function_privilege('authenticated', f, 'execute') and not has_function_privilege('anon', f, 'execute'), f;
  end loop;
  foreach f in array array['store_packs', 'iap_grants'] loop
    assert not has_table_privilege('authenticated', f, 'select') and not has_table_privilege('anon', f, 'select'), f;
  end loop;
end $$;

drop function _iap(text, text, text, text, timestamptz, jsonb);
