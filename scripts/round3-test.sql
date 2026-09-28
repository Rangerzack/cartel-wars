-- Tests for round 3: the 00:00 UTC rollover (refills, daily cash), head-to-head fights with +1 edges,
-- the thug list, and rare finds on actions.
-- Run after the other suites (reuses their helpers): scripts/local-db.sh test
\set ON_ERROR_STOP on
\set QUIET on

insert into auth.users (id, raw_user_meta_data) values
  ('e1111111-1111-1111-1111-111111111111', '{"name":"Gale"}'),
  ('e2222222-2222-2222-2222-222222222222', '{"name":"Todd"}'),
  ('e3333333-3333-3333-3333-333333333333', '{"name":"Lydia"}');

-- A fresh, bare-handed fighter with nothing that tilts the edges.
create or replace function reset_fighter(p uuid) returns void language sql as $$
  delete from setup_items where player_id = p;
  delete from inventory where player_id = p;
  update profiles set cash = 1000, bank = 0, heat = 0, health = 100, health_max = 100, stamina = 25, jail_until = null,
         in_hospital = false, last_tick = now(), stamina_tick = now(), health_tick = now() where id = p;
  delete from fights where attacker_id = p or defender_id = p;
$$;

-- Game clock -------------------------------------------------------------------------------------------
do $$ begin
  assert _game_day() = (now() at time zone 'utc')::date;
  assert _day_start() <= now() and _day_start() > now() - interval '1 day', 'day start: ' || _day_start();
  assert to_char(_day_start() at time zone 'utc', 'HH24:MI:SS') = '00:00:00', 'midnight UTC';
end $$;

-- Refills come back at the rollover, not 24 hours after the first one ------------------------------------
select as_user('e1111111-1111-1111-1111-111111111111');
do $$ declare u uuid := auth.uid(); begin
  perform get_me();
  -- first refill yesterday evening: back as soon as the day rolls over, even though 24 hours haven't passed
  update profiles set refills_used = 3, refills_reset_at = _day_start() - interval '1 hour' where id = u;
  perform _tick(u);
  assert (select refills_used from profiles where id = u) = 0, 'refills reset at 00:00 UTC';
  -- first refill after today's rollover: still used up
  update profiles set refills_used = 3, refills_reset_at = _day_start() + interval '1 second' where id = u;
  perform _tick(u);
  assert (select refills_used from profiles where id = u) = 3, 'refills used today stay used';
  assert (get_me()->>'refills_used')::int = 3;
end $$;

-- Daily cash --------------------------------------------------------------------------------------------
do $$ declare u uuid := 'e1111111-1111-1111-1111-111111111111'; c bigint; a activity; t uuid := (select id from profiles where name = 'Thug 5'); tc bigint; n int; row jsonb; begin
  assert (select daily_day from profiles where id = u) = _game_day(), 'new accounts start paid up for today';
  assert (get_catalog()->'config'->>'daily_cash')::int = 50000;
  delete from activity where player_id = u;
  c := (select cash from profiles where id = u);
  perform _tick(u);
  assert (select cash from profiles where id = u) = c, 'nothing twice in one day';

  -- one day behind: one payment, on hand, plus a feed line
  update profiles set daily_day = _game_day() - 1 where id = u;
  perform _tick(u);
  assert (select cash from profiles where id = u) = c + 50000, 'paid 50k on hand';
  assert (select bank from profiles where id = u) = 0, 'not banked';
  assert (select daily_day from profiles where id = u) = _game_day();
  select * into a from activity where player_id = u and kind = 'daily_cash';
  assert (a.data->>'cash')::bigint = 50000 and (a.data->>'days')::int = 1 and not a.seen, 'feed line: ' || a.data::text;

  -- a missed run pays every day missed, folded into the same unseen line
  update profiles set daily_day = _game_day() - 2 where id = u;
  perform _tick(u);
  assert (select cash from profiles where id = u) = c + 150000, 'caught up two days';
  assert (select count(*) from activity where player_id = u and kind = 'daily_cash') = 1, 'one line';
  assert (select (data->>'cash')::bigint from activity where player_id = u and kind = 'daily_cash') = 150000;
  assert (select (data->>'days')::int from activity where player_id = u and kind = 'daily_cash') = 3;
  -- after it's been seen, the next day starts a new line
  update activity set seen = true where player_id = u;
  update profiles set daily_day = _game_day() - 1 where id = u;
  perform _tick(u);
  assert (select count(*) from activity where player_id = u and kind = 'daily_cash') = 2, 'fresh line after seen';

  -- thugs get it too, on top of a full stash, with no feed line; the hourly refill doesn't eat it
  delete from activity where player_id = t;
  update profiles set cash = _bot_cash_cap(5), daily_day = _game_day() - 3 where id = t;
  row := (select e from jsonb_array_elements(find_thugs()) e where e->>'name' = 'Thug 5');
  assert (row->>'stash')::bigint = _bot_cash_cap(5) + 150000, 'thug list counts unswept daily cash: ' || row::text;
  perform _tick(t);
  assert (select cash from profiles where id = t) = _bot_cash_cap(5) + 150000, 'thug paid three days';
  assert (select daily_day from profiles where id = t) = _game_day();
  assert not exists (select 1 from activity where player_id = t), 'no feed line for thugs';
  update profiles set stamina_tick = now() - interval '2 hours' where id = t;
  perform _tick(t);
  assert (select cash from profiles where id = t) = _bot_cash_cap(5) + 150000, 'refill leaves the extra alone';
  -- once hunters drain it below the cap, the refill only brings it back to the cap
  update profiles set cash = 1000, stamina_tick = now() - interval '2 hours' where id = t;
  perform _tick(t);
  assert (select cash from profiles where id = t) = _bot_cash_cap(5), 'refill tops up to the cap only';

  -- the rollover sweep pays everyone behind, offline or not, without touching last_seen
  update profiles set daily_day = _game_day() - 1, last_seen = now() - interval '30 days'
   where id in ('e2222222-2222-2222-2222-222222222222', 'e3333333-3333-3333-3333-333333333333');
  c := (select cash from profiles where id = 'e2222222-2222-2222-2222-222222222222');
  n := _daily_sweep();
  assert n >= 2, 'swept ' || n;
  assert (select cash from profiles where id = 'e2222222-2222-2222-2222-222222222222') = c + 50000, 'offline player paid';
  assert (select last_seen from profiles where id = 'e2222222-2222-2222-2222-222222222222') < now() - interval '29 days', 'still looks offline';
  assert not exists (select 1 from profiles where daily_day < _game_day()), 'everyone paid up, thugs included';
  assert _daily_sweep() = 0, 'second run pays nobody';
end $$;

-- Edges --------------------------------------------------------------------------------------------------
do $$ declare a profiles; d profiles; e record; begin
  select * into a from profiles where id = 'e1111111-1111-1111-1111-111111111111';
  select * into d from profiles where id = 'e2222222-2222-2222-2222-222222222222';
  a.cash := 100; d.cash := 100; a.heat := 10; d.heat := 10;
  select * into e from _fight_edges(a, d);
  assert e.edge_a = 0 and e.edge_d = 1 and jsonb_array_length(e.edges) = 1, 'ties give nothing; defender +1: ' || e.edges::text;
  a.cash := 500; d.heat := 30;
  select * into e from _fight_edges(a, d);
  assert e.edge_a = 1 and e.edge_d = 2, 'cash to attacker, heat to defender';
  assert e.edges @> '[{"k":"cash","side":"you"},{"k":"heat","side":"them"},{"k":"defender","side":"them"}]'::jsonb, e.edges::text;
  a.heat := 31;
  select * into e from _fight_edges(a, d);
  assert e.edge_a = 2 and e.edge_d = 1 and e.edges @> '[{"k":"heat","side":"you"}]'::jsonb, 'most heat wins the heat edge';
end $$;

-- Head-to-head odds: two bare-handed players are a coin flip that the edges tilt --------------------------
select as_user('e1111111-1111-1111-1111-111111111111');
do $$ declare u uuid := auth.uid(); t uuid := 'e2222222-2222-2222-2222-222222222222'; p jsonb; begin
  perform reset_fighter(u); perform reset_fighter(t);
  -- 30 vs 30 base; defender +1 only: attacker needs to roll 2 higher → 15 of 49
  p := fight_preview(t);
  assert (p->>'base_you')::numeric = 30 and (p->>'base_them')::numeric = 30, p::text;
  assert (p->>'win_exact')::numeric = 30.6 and (p->>'win_pct')::int = 31, 'defender edge: ' || p::text;
  assert (p->>'edge_you')::int = 0 and (p->>'edge_them')::int = 1;
  -- more cash on hand evens it: attacker must roll higher → 21 of 49
  update profiles set cash = 5000 where id = u;
  p := fight_preview(t);
  assert (p->>'win_exact')::numeric = 42.9, 'cash edge: ' || p::text;
  -- and more heat tips it: attacker wins ties and better → 28 of 49
  update profiles set heat = 20 where id = u;
  p := fight_preview(t);
  assert (p->>'win_exact')::numeric = 57.1, 'heat edge: ' || p::text;
  assert p->'edges' @> '[{"k":"cash","side":"you"},{"k":"heat","side":"you"},{"k":"defender","side":"them"}]'::jsonb;
  -- the loser's hit glances: their score runs 31–37, so a lost fight costs its full 32–37 and a won one 11–13
  assert (p->>'dmg_max')::int = 37 and (p->>'dmg_min')::int = 11, 'damage range: ' || p::text;
end $$;

-- Gear decides lopsided fights: six Miniguns vs bare hands, and the reverse ------------------------------
do $$ declare u uuid := 'e1111111-1111-1111-1111-111111111111'; t uuid := 'e2222222-2222-2222-2222-222222222222'; p jsonb; r jsonb; i int; begin
  perform reset_fighter(u); perform reset_fighter(t);
  insert into inventory (player_id, item_id, qty) select u, id, 6 from item_defs where name = 'Minigun';
  insert into setup_items (player_id, setup, item_id, qty) select u, 'offense', id, 6 from item_defs where name = 'Minigun';
  p := fight_preview(t);
  assert (p->>'win_pct')::int = 100, 'armed attacker: ' || p::text;
  for i in 1..5 loop
    update profiles set health = 100, stamina = 25 where id in (u, t);
    r := attack(t);
    assert (r->>'won')::boolean, 'armed attacker wins: ' || r::text;
    assert (r->>'my_score')::numeric > (r->>'their_score')::numeric;
    assert abs((r->>'damage_dealt')::int - round((r->>'my_score')::numeric)) <= 1, 'winner lands the full hit: ' || r::text;
    assert abs((r->>'damage_taken')::int - round(0.35 * (r->>'their_score')::numeric)) <= 1, 'loser glances: ' || r::text;
    assert r ? 'edges' and (r->>'my_att')::int = 920 and (r->>'their_def')::int = 20;
  end loop;
  -- now the bare-handed one swings at the armed one's defense setup
  delete from setup_items where player_id = u;
  insert into setup_items (player_id, setup, item_id, qty) select u, 'defense', id, 6 from item_defs where name = 'Minigun';
end $$;
select as_user('e2222222-2222-2222-2222-222222222222');
do $$ declare u uuid := auth.uid(); t uuid := 'e1111111-1111-1111-1111-111111111111'; p jsonb; r jsonb; begin
  update profiles set health = 100, stamina = 25 where id in (u, t);
  p := fight_preview(t);
  assert (p->>'win_pct')::int = 0, 'bare hands vs a loaded defense: ' || p::text;
  r := attack(t);
  assert not (r->>'won')::boolean, 'defender wins: ' || r::text;
  assert abs((r->>'damage_taken')::int - least(80, round((r->>'their_score')::numeric))) <= 1, 'the defender''s full hit lands: ' || r::text;
  assert abs((r->>'damage_dealt')::int - round(0.35 * (r->>'my_score')::numeric)) <= 1, 'attacker only glances';
  assert (select winner_id from fights where attacker_id = u order by created_at desc limit 1) = t;
end $$;

-- Thugs fight at half strength at the bottom, full at the top ---------------------------------------------
do $$ declare t1 profiles; t200 profiles; me profiles; begin
  select * into t1 from profiles where name = 'Thug 1';
  select * into t200 from profiles where name = 'Thug 200';
  select * into me from profiles where id = 'e1111111-1111-1111-1111-111111111111';
  assert _bot_strength(t1) = 0.5 and _bot_strength(t200) = 1 and _bot_strength(me) = 1;
end $$;

select as_user('e3333333-3333-3333-3333-333333333333');
do $$ declare u uuid := auth.uid(); p jsonb; list jsonb; row jsonb; t uuid := (select id from profiles where name = 'Thug 1'); i int; begin
  perform get_me();
  perform reset_fighter(u);
  -- a bare-handed newcomer against Thug 1: 40 vs 20 before rolls
  p := fight_preview(t);
  assert (p->>'win_pct')::int = 100 and (p->>'base_you')::numeric = 40 and (p->>'base_them')::numeric = 20, 'Thug 1 is a punching bag: ' || p::text;
  list := find_thugs();
  assert jsonb_array_length(list) = 200, 'all thugs listed';
  row := list->0;
  assert row->>'name' = 'Thug 1' and (row->>'level')::int = 1 and (row->>'win_pct')::int = 100, row::text;
  assert (select (e->>'win_pct')::int from jsonb_array_elements(list) e where e->>'name' = 'Thug 200') = 0, 'Thug 200 is out of reach';
  assert (select (e->>'stash')::bigint from jsonb_array_elements(list) e where e->>'name' = 'Thug 200') = _bot_cash_cap(200);
  -- hit Thug 1 three times and it shows as dry for you
  for i in 1..3 loop update profiles set health = 100, stamina = 25 where id in (u, t); perform attack(t); end loop;
  row := (select e from jsonb_array_elements(find_thugs()) e where e->>'name' = 'Thug 1');
  assert (row->>'hits')::int = 3 and (row->>'dry')::boolean, 'dry after three: ' || row::text;
  -- a drained stash shows its refill: 30 minutes after being emptied, half the cap is back
  update profiles set cash = 0, stamina_tick = now() - interval '30 minutes 5 seconds' where name = 'Thug 2';
  row := (select e from jsonb_array_elements(find_thugs()) e where e->>'name' = 'Thug 2');
  assert (row->>'stash')::bigint = ceil(_bot_cash_cap(2) * 30 / 60.0), 'refill counted: ' || row::text;
end $$;

-- Rare finds ----------------------------------------------------------------------------------------------
do $$ declare u uuid := 'e3333333-3333-3333-3333-333333333333'; a action_defs; r jsonb; tow int := (select id from item_defs where name = 'TOW Missile'); c jsonb; begin
  -- four drop-only items, each the best of its kind
  assert (select count(*) from item_defs where drop_only) = 4;
  assert (select att from item_defs where name = 'TOW Missile') > (select max(att) from item_defs where category = 'weapon' and not drop_only);
  assert (select def from item_defs where name = 'EOD Bomb Suit') > (select max(def) from item_defs where category = 'protection' and not drop_only);
  assert (select def from item_defs where name = 'MRAP') > (select max(def) from item_defs where category = 'transport' and not drop_only);
  assert (select att from item_defs where name = 'Zip Gun') > (select max(att) from item_defs where category = 'jail_weapon' and not drop_only);
  -- every job can turn one up except bribing your way into jail
  assert (select count(*) from action_defs where drop_item is null) = 1
     and (select effect from action_defs where drop_item is null) = 'go_to_jail', 'drop table covers the jobs';
  assert not exists (select 1 from action_defs ad join item_defs d on d.id = ad.drop_item where ad.is_jail <> (d.category = 'jail_weapon')), 'jail jobs drop the jail weapon';

  select * into a from action_defs where name = 'Take Down a Rival Don';
  assert a.drop_item = tow;
  -- 12 stamina → 1 in 500
  assert _rare_roll(u, a, 1.0 / 500 + 0.0000001) is null and _rare_roll(u, a, 0.99) is null, 'misses';
  r := _rare_roll(u, a, 1.0 / 500 - 0.0000001);
  assert r->>'name' = 'TOW Missile' and (r->>'att')::int = 185 and (r->>'owned')::int = 1, 'found: ' || r::text;
  assert (select qty from inventory where player_id = u and item_id = tow) = 1;
  assert exists (select 1 from rare_finds where player_id = u and item_id = tow and action_id = a.id);
  -- a cheap job has proportionally lower odds: 1 stamina → 1 in 6000
  select * into a from action_defs where name = 'Sling on the Corner';
  assert _rare_roll(u, a, 1.0 / 5000) is null, '1-stamina job misses at 1 in 5000';
  select * into a from action_defs where effect = 'go_to_jail';
  assert _rare_roll(u, a, 0) is null, 'no find from bribing into jail';

  perform as_user(u::text);
  c := recent_finds();
  assert c->0->>'item' = 'TOW Missile' and c->0->>'player' = 'Lydia' and c->0->>'action' = 'Take Down a Rival Don', c::text;
  -- can't be bought or sold, but it equips and counts
  perform expect_error(format('select buy_item(%s)', tow), 'can only be found on actions');
  perform expect_error(format('select sell_item(%s)', tow), 'Rare finds cannot be sold');
  perform equip('offense', tow, 1);
  assert (get_me()->'power'->'offense'->>'att')::int = 20 + 185, 'TOW counts: ' || (get_me()->'power'->'offense')::text;
  -- do_action reports finds (usually none)
  update profiles set stamina = 25, heat = 0, jail_until = null where id = u;
  r := do_action((select id from action_defs where name = 'Sling on the Corner'));
  assert r ? 'found', 'do_action has a found key: ' || r::text;
  assert (get_catalog()->'config'->>'drop_stamina')::int = 6000;
  assert (select (e->>'drop_only')::boolean from jsonb_array_elements(get_catalog()->'items') e where e->>'name' = 'MRAP'), 'catalog marks finds';
end $$;

select 'ROUND 3 TEST PASSED';
