-- Tests for the NPC thugs (Thug 1 … Thug 200). Run after the other suites: scripts/local-db.sh test
\set ON_ERROR_STOP on
\set QUIET on

do $$ declare lo record; hi record; mid record; begin
  assert (select count(*) from profiles where is_bot) = 200, 'two hundred thugs';
  assert (select count(*) from profiles where is_bot and name ~ '^Thug [0-9]+$') = 200;
  select * into lo from _power((select id from profiles where name = 'Thug 1'), 'defense');
  select * into mid from _power((select id from profiles where name = 'Thug 100'), 'defense');
  select * into hi from _power((select id from profiles where name = 'Thug 200'), 'defense');
  assert lo.att = 20 and lo.def = 20, 'Thug 1 is bare-handed: ' || lo::text;
  assert mid.att > lo.att and mid.def > lo.def and hi.att > mid.att and hi.def > mid.def, 'strength climbs: ' || mid::text || hi::text;
  assert hi.att = 480 and hi.def = 315, 'Thug 200 is stacked: ' || hi::text;
  assert (select health_max from profiles where name = 'Thug 200') = 200 and (select health_max from profiles where name = 'Thug 1') = 100;
  assert (select cash from profiles where name = 'Thug 1') = 2000 and (select cash from profiles where name = 'Thug 200') = 500000, 'stash scales';
  assert (select bool_and(not exists (select 1 from auth.users u where u.id = p.id and u.email not like 'thug-%@bots.cartelwars.invalid')) from profiles p where is_bot);
end $$;

insert into auth.users (id, raw_user_meta_data) values ('c1111111-1111-1111-1111-111111111111', '{"name":"Hunter"}');
select as_user('c1111111-1111-1111-1111-111111111111');
do $$ declare t uuid := (select id from profiles where name = 'Thug 50'); r jsonb; before bigint; after_hit bigint; begin
  perform get_me();
  assert exists (select 1 from jsonb_array_elements(find_players('Thug 5')) e where e->>'name' = 'Thug 50'), 'thugs show up in search';
  -- make the hunter strong enough to win
  update profiles set cash = 0, stamina = 25, health = 100 where id = auth.uid();
  insert into inventory (player_id, item_id, qty) select auth.uid(), id, 6 from item_defs where name = 'Minigun';
  insert into setup_items (player_id, setup, item_id, qty) select auth.uid(), 'offense', id, 6 from item_defs where name = 'Minigun';
  before := (select cash from profiles where id = t);
  r := attack(t);
  assert (r->>'won')::boolean and (r->>'cash')::bigint > 0, 'beat Thug 50 and took cash: ' || r::text;
  after_hit := (select cash from profiles where id = t);
  assert after_hit = before - (r->>'cash')::bigint;
  assert not exists (select 1 from activity where player_id = t), 'no feed for thugs';
  -- half an hour later the stash is half refilled (capped at the level's stash)
  update profiles set stamina_tick = now() - interval '30 minutes 10 seconds' where id = t;
  perform _tick(t);
  assert (select cash from profiles where id = t) = least(_bot_cash_cap(50), after_hit + ceil(_bot_cash_cap(50) * 30 / 60.0)::bigint),
    'stash refills: ' || (select cash from profiles where id = t);
  update profiles set stamina_tick = now() - interval '2 hours' where id = t;
  perform _tick(t);
  assert (select cash from profiles where id = t) = _bot_cash_cap(50), 'full after an hour';
  -- cash won off a failed attacker is kept above the cap
  update profiles set cash = _bot_cash_cap(50) + 999, stamina_tick = now() - interval '5 minutes' where id = t;
  perform _tick(t);
  assert (select cash from profiles where id = t) = _bot_cash_cap(50) + 999, 'extra cash kept';
end $$;

-- Offline healing: the once-a-minute sweep ticks anyone below full health ------------------------------
do $$ declare p uuid := 'c1111111-1111-1111-1111-111111111111'; seen timestamptz; n int; begin
  update profiles set health = 0, health_tick = now() - interval '3 minutes 5 seconds', last_seen = now() - interval '2 hours' where id = p;
  assert (select in_hospital from profiles where id = p), 'knocked out';
  seen := (select last_seen from profiles where id = p);
  update profiles set health = 40, health_tick = now() - interval '2 minutes' where name = 'Thug 7';
  n := _heal_sweep();
  assert n >= 2, 'swept: ' || n;
  assert (select health from profiles where id = p) = 30 and not (select in_hospital from profiles where id = p), 'healed and out while offline';
  assert (select last_seen from profiles where id = p) = seen, 'sweeping does not make you look online';
  assert (select health from profiles where name = 'Thug 7') = 60, 'thugs heal too';
  -- players at full health, or ticked less than a minute ago, are left alone
  update profiles set health = 50, health_tick = now() - interval '20 seconds' where name = 'Thug 8';
  perform _heal_sweep();
  assert (select health from profiles where name = 'Thug 8') = 50, 'not due yet';
end $$;

select 'BOTS TEST PASSED';
