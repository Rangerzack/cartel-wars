-- Tests for the Daily Drop: subscribing, crates landing and stacking, the prize table and its odds, every prize's
-- effect, and the free refill / free hustler credits.
-- Run after the other suites (reuses their helpers): scripts/local-db.sh test
\set ON_ERROR_STOP on
\set QUIET on

insert into auth.users (id, raw_user_meta_data) values
  ('c2222222-2222-2222-2222-222222222222', '{"name":"Francesca"}'),
  ('c3333333-3333-3333-3333-333333333333', '{"name":"Krazy8"}'),
  ('c4444444-4444-4444-4444-444444444444', '{"name":"Domingo"}');

-- The prize table -------------------------------------------------------------------------------------------
do $$ declare c jsonb := get_catalog(); begin
  assert (select sum(weight) from drop_prizes) = 1000, 'weights add up to 1,000';
  assert jsonb_array_length(c->'drop_prizes') = 11, '11 prizes in the catalog';
  assert (select count(*) from drop_prizes where jackpot) = 2 and (select sum(weight) from drop_prizes where jackpot) = 100, 'jackpot tier is 100/1000';
  assert (c->'config'->>'drop_max_crates')::int = 7 and (c->'config'->>'drop_price_cents')::int = 299 and (c->'config'->>'drop_free')::int = 1;
  assert c->'drop_prizes'->0->>'code' = 'herb_1000' and c->'drop_prizes'->10->>'code' = 'cash_1m', 'catalog in table order';
end $$;

-- Subscribing and crates ------------------------------------------------------------------------------------
select as_user('c2222222-2222-2222-2222-222222222222');
do $$ declare u uuid := 'c2222222-2222-2222-2222-222222222222'; m jsonb; r jsonb; begin
  m := get_me();
  assert (m->'drop'->>'subscribed')::boolean = false and (m->'drop'->>'crates')::int = 0, 'new players start unsubscribed';
  assert (m->>'free_refills')::int = 0 and (m->>'free_hustlers')::int = 0;
  perform expect_error('select open_crate()', 'Subscribe to the Daily Drop');
  perform expect_error('select unsubscribe_drop()', 'not subscribed');

  -- subscribing leaves today's crate right away
  r := subscribe_drop();
  assert (r->>'crates')::int = 1, 'first crate on subscribe: ' || r::text;
  m := get_me();
  assert (m->'drop'->>'subscribed')::boolean and (m->'drop'->>'crates')::int = 1 and m->'drop'->>'until' is null;
  perform expect_error('select subscribe_drop()', 'already subscribed');
  -- nothing more today
  perform get_me();
  assert (select drop_crates from profiles where id = u) = 1, 'one crate a day';

  -- the rollover leaves one a day; they stack
  update profiles set drop_day = _game_day() - 1 where id = u;
  assert (get_me()->'drop'->>'crates')::int = 2, 'next day +1';
  update profiles set drop_day = _game_day() - 3 where id = u;
  assert (get_me()->'drop'->>'crates')::int = 5, 'three days away +3';
  assert (select drop_day from profiles where id = u) = _game_day();
  -- ... up to seven; days on a full stack are lost
  update profiles set drop_day = _game_day() - 10 where id = u;
  assert (get_me()->'drop'->>'crates')::int = 7, 'stack caps at 7';

  -- opening takes one
  r := open_crate();
  assert (r->>'crates')::int = 6 and r ? 'code' and r ? 'label' and r ? 'amount', 'open: ' || r::text;
  assert (select count(*) from drop_opens where player_id = u) = 1;
  assert get_me()->'drop'->'last'->>'label' = r->>'label', 'get_me shows the last prize';

  -- cancelling keeps the crates already left; no more land
  r := unsubscribe_drop();
  assert (r->>'crates')::int = 6;
  update profiles set drop_day = _game_day() - 3 where id = u;
  m := get_me();
  assert (m->'drop'->>'subscribed')::boolean = false and (m->'drop'->>'crates')::int = 6, 'no crates while cancelled';
  perform open_crate();
  assert (select drop_crates from profiles where id = u) = 5, 'earned crates still open after cancelling';
  -- coming back leaves today's crate only (not the days away)
  perform subscribe_drop();
  assert (select drop_crates from profiles where id = u) = 6, 'resubscribe: +1 for today';
  -- dropping and re-subscribing the same day doesn't farm crates
  perform unsubscribe_drop(); perform subscribe_drop();
  perform unsubscribe_drop(); perform subscribe_drop();
  assert (select drop_crates from profiles where id = u) = 6, 'no second crate the same day';

  -- run out
  update profiles set drop_crates = 0 where id = u;
  perform expect_error('select open_crate()', 'next one lands at 00:00 UTC');
end $$;

-- The nightly sweep leaves crates for subscribers who didn't log in ---------------------------------------------
do $$ declare u uuid := 'c2222222-2222-2222-2222-222222222222'; begin
  update profiles set daily_day = _game_day() - 1, drop_day = _game_day() - 1, drop_crates = 2 where id = u;
  perform _daily_sweep();
  assert (select drop_crates from profiles where id = u) = 3, 'sweep leaves the crate';
end $$;

-- A paid plan (for later): crates stop after the paid-through date ----------------------------------------------
do $$ declare u uuid := 'c2222222-2222-2222-2222-222222222222'; pr profiles; begin
  perform unsubscribe_drop();
  update profiles set drop_day = _game_day() - 1 where id = u;
  pr := _drop_subscribe(u, now() + interval '30 days');
  assert pr.drop_until is not null and pr.drop_crates = 4 and _drop_active(pr), 'paid subscribe';
  assert (get_me()->'drop'->>'subscribed')::boolean;
  -- ran out at 00:00 today, last seen three days ago: yesterday and the day before land, today doesn't
  update profiles set drop_until = _day_start(), drop_day = _game_day() - 3, drop_crates = 0 where id = u;
  pr := _tick(u);
  assert pr.drop_crates = 2 and pr.drop_day = _game_day() - 1, 'crates through the paid day only: ' || pr.drop_crates || ' ' || pr.drop_day;
  assert not _drop_active(pr) and (get_me()->'drop'->>'subscribed')::boolean = false, 'lapsed';
  -- back to the free plan
  update profiles set drop_since = null, drop_until = null where id = u;
  perform subscribe_drop();
  assert (select drop_until from profiles where id = u) is null;
end $$;

-- Every prize, and where the draw lands -----------------------------------------------------------------------
select as_user('c3333333-3333-3333-3333-333333333333');
do $$ declare u uuid := 'c3333333-3333-3333-3333-333333333333'; z record; r jsonb; b0 profiles; b1 profiles;
          st0 int; st1 int; th0 int; th1 int; used int; cap int; begin
  perform get_me();
  update profiles set drop_crates = 100 where id = u;
  for z in select d.*, sum(weight) over (order by sort) - weight as lo, sum(weight) over (order by sort) - 1 as hi
             from drop_prizes d order by sort loop
    -- both ends of each prize's range land on it
    select * into b0 from profiles where id = u;
    select coalesce(sum(qty) filter (where commodity = z.kind), 0) into st0 from storage where player_id = u;
    select coalesce(sum(qty), 0) into th0 from player_hoodlums where player_id = u and code = 'thug';
    r := _drop_open(u, z.lo::int);
    assert r->>'code' = z.code, format('draw %s → %s, wanted %s', z.lo, r->>'code', z.code);
    assert (r->>'jackpot')::boolean = z.jackpot and (r->>'amount')::bigint = z.amount;
    assert _drop_open(u, z.hi::int)->>'code' = z.code, format('draw %s → %s', z.hi, z.code);
    select * into b1 from profiles where id = u;
    select coalesce(sum(qty) filter (where commodity = z.kind), 0) into st1 from storage where player_id = u;
    select coalesce(sum(qty), 0) into th1 from player_hoodlums where player_id = u and code = 'thug';
    assert b1.drop_crates = b0.drop_crates - 2, 'each open takes a crate';
    -- two opens of the same prize: twice the amount, and nothing else moves
    assert b1.cash - b0.cash = case when z.kind = 'cash' then 2 * z.amount else 0 end, 'cash ' || z.code;
    assert b1.diamonds - b0.diamonds = case when z.kind = 'diamonds' then 2 * z.amount else 0 end, 'diamonds ' || z.code;
    assert b1.free_refills - b0.free_refills = case when z.kind = 'refills' then 2 * z.amount else 0 end, 'refills ' || z.code;
    assert b1.free_hustlers - b0.free_hustlers = case when z.kind = 'hustlers' then 2 * z.amount else 0 end, 'hustlers ' || z.code;
    assert th1 - th0 = case when z.kind = 'thugs' then 2 * z.amount else 0 end, 'thugs ' || z.code;
    if z.kind in ('herb', 'dust', 'pills') then assert st1 - st0 = 2 * z.amount, 'product ' || z.code; end if;
  end loop;
  assert (select count(*) from drop_opens where player_id = u) = 22;
  -- product lands past the storage cap; the cap still blocks new product afterwards
  select storage_cap into cap from profiles where id = u;
  select sum(qty) into used from storage where player_id = u;
  assert used > cap, 'crate product goes past the cap';
  assert (get_me()->>'storage_used')::int = used;

  -- the jackpot feed: jackpots only, newest first
  r := recent_drops(20);
  assert (select count(*) from jsonb_array_elements(r) e where e->>'player' = 'Krazy8') = 4, 'four jackpot opens: ' || r::text;
  assert r->0->>'label' = '$1,000,000' and r->0->>'player' = 'Krazy8' and r->3->>'label' = '25 Diamonds', 'newest first';
  assert jsonb_array_length(recent_drops(2)) = 2;
  assert not exists (select 1 from jsonb_array_elements(recent_drops(20)) e where e->>'label' not in ('25 Diamonds', '$1,000,000'));
end $$;

-- The odds: 4,000 random crates land close to the table ---------------------------------------------------------
do $$ declare u uuid := 'c3333333-3333-3333-3333-333333333333'; i int; z record; n int; want numeric; sd numeric; begin
  delete from drop_opens where player_id = u;
  update profiles set drop_crates = 4000 where id = u;
  for i in 1..4000 loop perform open_crate(); end loop;
  assert (select drop_crates from profiles where id = u) = 0;
  for z in select * from drop_prizes loop
    select count(*) into n from drop_opens where player_id = u and prize = z.code;
    want := 4000 * z.weight / 1000.0;
    sd := sqrt(want * (1 - z.weight / 1000.0));
    assert abs(n - want) < 5 * sd, format('%s: %s of 4000, expected about %s', z.code, n, want);
  end loop;
end $$;

-- Free refills --------------------------------------------------------------------------------------------------
select as_user('c4444444-4444-4444-4444-444444444444');
do $$ declare u uuid := 'c4444444-4444-4444-4444-444444444444'; r jsonb; begin
  perform get_me();
  perform expect_error('select refill(''stamina'', ''free'')', 'Already full');
  update profiles set stamina = 0, stamina_max = 40, free_refills = 0 where id = u;
  perform expect_error('select refill(''stamina'', ''free'')', 'No free refills');
  update profiles set free_refills = 2, refills_used = 0, health = 10 where id = u;
  r := refill('stamina', 'free');
  assert (r->>'gain')::int = 40, 'full refill: ' || r::text;
  assert (select free_refills from profiles where id = u) = 1 and (select refills_used from profiles where id = u) = 0,
    'uses a credit, not one of the three a day';
  perform expect_error('select refill(''health'', ''free'')', 'for stamina');
  -- after three product refills the free one is still a full one
  update profiles set stamina = 0, refills_used = 3 where id = u;
  assert (refill('stamina', 'free')->>'gain')::int = 40;
  assert (get_me()->>'free_refills')::int = 0;
end $$;

-- Free hustlers -------------------------------------------------------------------------------------------------
do $$ declare u uuid := 'c4444444-4444-4444-4444-444444444444'; r jsonb; begin
  insert into storage as st (player_id, commodity, qty) values (u, 'herb', 5000)
    on conflict (player_id, commodity) do update set qty = 5000;
  update profiles set path = 'trader', cash = 0, free_hustlers = 100 where id = u;
  r := hire_hustlers('herb', 10);
  assert (r->>'cost')::int = 0 and (r->>'free')::int = 10, 'ten on the house: ' || r::text;
  assert (select free_hustlers from profiles where id = u) = 90 and (select cash from profiles where id = u) = 0;
  -- a hire bigger than the credits pays for the rest; if it can't, nothing is spent
  perform expect_error('select hire_hustlers(''herb'', 100)', 'Hiring costs $4000');
  assert (select free_hustlers from profiles where id = u) = 90, 'failed hire keeps the credits';
  update profiles set cash = 5000 where id = u;
  r := hire_hustlers('herb', 100);
  assert (r->>'cost')::int = 4000 and (r->>'free')::int = 90;
  assert (select free_hustlers from profiles where id = u) = 0 and (select cash from profiles where id = u) = 1000;
  -- no credits: the usual price
  update profiles set cash = 400 where id = u;
  r := hire_hustlers('herb', 1);
  assert (r->>'cost')::int = 400 and (r->>'free')::int = 0;
  -- credits don't get round the path
  update profiles set path = 'producer', free_hustlers = 5 where id = u;
  perform expect_error('select hire_hustlers(''herb'', 1)', 'Only Traders');
end $$;

-- Thugs never get crates; the helpers stay private -----------------------------------------------------------------
do $$ declare t uuid; begin
  select id into t from profiles where is_bot limit 1;
  perform expect_error(format('select _drop_subscribe(%L, null)', t), 'Thugs don''t subscribe');
  update profiles set drop_day = _game_day() - 2 where id = t;
  perform _tick(t);
  assert (select drop_crates from profiles where id = t) = 0;
  assert not has_function_privilege('authenticated', '_drop_open(uuid, integer)', 'execute');
  assert not has_function_privilege('authenticated', '_drop_subscribe(uuid, timestamptz)', 'execute');
  assert not has_function_privilege('anon', 'open_crate()', 'execute');
  assert has_function_privilege('authenticated', 'open_crate()', 'execute');
  assert has_function_privilege('authenticated', 'subscribe_drop()', 'execute');
  assert has_function_privilege('authenticated', 'recent_drops(integer)', 'execute');
end $$;

select 'DROP TEST PASSED';
