-- Tests for combos (the counter wheel, completing and picking combos, combo rolls in fights, hidden defense
-- combos and intel), the military tier, and jail-only fights.
-- Run after the other suites (reuses their helpers): scripts/local-db.sh test
\set ON_ERROR_STOP on
\set QUIET on

insert into auth.users (id, raw_user_meta_data) values
  ('c5555555-5555-5555-5555-555555555555', '{"name":"Marco"}'),
  ('c6666666-6666-6666-6666-666666666666', '{"name":"Leonel"}'),
  ('c7777777-7777-7777-7777-777777777777', '{"name":"Werner"}');

-- Give a player n of an item and put them in a setup.
create or replace function kit(p uuid, s setup_kind, item text, n integer default 1) returns void language sql as $$
  insert into inventory (player_id, item_id, qty) select p, id, n from item_defs where name = item
    on conflict (player_id, item_id) do update set qty = greatest(inventory.qty, excluded.qty);
  insert into setup_items (player_id, setup, item_id, qty) select p, s, id, n from item_defs where name = item
    on conflict (player_id, setup, item_id) do update set qty = excluded.qty;
$$;
create or replace function unkit(p uuid, s setup_kind, item text) returns void language sql as $$
  delete from setup_items where player_id = p and setup = s and item_id = (select id from item_defs where name = item) $$;

-- The wheel -------------------------------------------------------------------------------------------------
do $$ declare r record; c jsonb := get_catalog(); begin
  assert (select count(*) from combo_styles) = 5, 'five styles';
  for r in select s.code, (select count(*) from combo_counters where style = s.code) beats,
                  (select count(*) from combo_counters where beats = s.code) beaten from combo_styles s loop
    assert r.beats = 2 and r.beaten = 2, 'each style beats two and loses to two: ' || r.code;
  end loop;
  assert not exists (select 1 from combo_counters where style = beats), 'nothing beats itself';
  assert not exists (select 1 from combo_counters a join combo_counters b on b.style = a.beats and b.beats = a.style), 'no mutual counters';
  assert jsonb_array_length(c->'combo_styles') = 5 and jsonb_array_length(c->'combo_styles'->0->'beats') = 2;
  assert jsonb_array_length(c->'combos') = (select count(*) from combo_defs);
  assert (c->'config'->>'combo_counter')::int = 10 and (c->'config'->>'combo_neutral')::int = 5;
  -- every combo has at least two parts, every style has at least two combos
  assert not exists (select 1 from combo_defs d where (select count(distinct part) from combo_parts where combo = d.code) < 2);
  assert not exists (select 1 from combo_styles s where (select count(*) from combo_defs where style = s.code) < 2);
  -- the matchup matrix: 10 when you counter, 0 when you're countered, 5 otherwise; nothing without a combo
  for r in select a.code ac, b.code bc, a.style sa, b.style sb from combo_defs a, combo_defs b loop
    assert _combo_max(r.ac, r.bc) = case when exists (select 1 from combo_counters where style = r.sa and beats = r.sb) then 10
                                         when exists (select 1 from combo_counters where style = r.sb and beats = r.sa) then 0
                                         else 5 end, format('%s vs %s', r.ac, r.bc);
  end loop;
  assert _combo_max(null, 'grenadier') = 0 and _combo_max('grenadier', null) = 5;
  -- what that does at even gear (30 vs 30, defender +1): about 35% mirror, 78% countering, 6% countered
  assert round(100 * _win_frac(30, 30, 0, 1, 5, 5)) = 35, 'mirror: ' || _win_frac(30, 30, 0, 1, 5, 5);
  assert round(100 * _win_frac(30, 30, 0, 1, 10, 0)) = 78, 'counter: ' || _win_frac(30, 30, 0, 1, 10, 0);
  assert round(100 * _win_frac(30, 30, 0, 1, 0, 10)) = 6, 'countered: ' || _win_frac(30, 30, 0, 1, 0, 10);
  assert _win_frac(30, 30, 0, 1, 0, 0) = 15 / 49.0, 'no combos: 15 of 49';
end $$;

-- The military tier -----------------------------------------------------------------------------------------
do $$ begin
  assert (select count(*) from item_defs where name in ('Striker GMG', 'Grenade Launcher', 'LMG', 'MIL-Spec Rifle', 'Dazzler Gun',
          'HUMVEE 50mm Cannon', 'Rocket Launcher', 'Stinger', 'HUMVEE Stinger', 'Metal Storm', 'Kevlar Shorts', 'Kevlar Pads',
          'Kevlar Jacket', 'Smoke Grenade', 'Flashbang', 'HUMVEE Bullbar', 'HUMVEE Armour', 'Grenade')) = 18;
  assert not exists (select 1 from item_defs where name = 'Grenades'), 'Grenades became the Grenade';
  assert not exists (select 1 from item_defs where sort between 27 and 58 and category in ('weapon', 'protection') and not drop_only
                       and rep_price = 0 and name <> 'Kevlar Vest' and price >= 500000 and price <> 6000 * (att + def)), '$6,000 a point';
  assert not exists (select 1 from item_defs where price >= 500000 and category in ('weapon', 'protection') and (att = 0 or def = 0)
                       and not drop_only and name not in ('Minigun')), 'military gear carries both stats';
  -- the rare finds are still the best of their kind
  assert (select att from item_defs where name = 'TOW Missile') > (select max(att) from item_defs where category = 'weapon' and not drop_only);
  assert (select def from item_defs where name = 'EOD Bomb Suit') > (select max(def) from item_defs where category = 'protection' and not drop_only);
  -- jail weapons still sort after the regular ones
  assert (select min(sort) from item_defs where category = 'jail_weapon') > (select max(sort) from item_defs where category = 'weapon');
end $$;

-- Completing and picking a combo ----------------------------------------------------------------------------
select as_user('c5555555-5555-5555-5555-555555555555');
do $$ declare u uuid := auth.uid(); m jsonb; r jsonb; begin
  perform get_me(); perform reset_fighter(u);
  assert _active_combo(u, 'offense') is null and get_me()->'combos'->'offense'->>'active' is null, 'bare hands, no combo';
  -- a weapon alone isn't a combo; add the vest and Spray and Pray lights up
  perform kit(u, 'offense', 'Uzi');
  assert _active_combo(u, 'offense') is null;
  perform kit(u, 'offense', 'Tactical Vest');
  m := get_me();
  assert m->'combos'->'offense'->>'active' = 'spray_pray' and (m->'power'->'offense'->>'combo')::boolean, m->'combos'::text;
  assert m->'combos'->'offense'->'complete' = '["spray_pray"]'::jsonb and m->'combos'->'defense'->>'active' is null;
  -- a second combo in the same setup: both tier 1, so the first on the list runs until you pick
  perform kit(u, 'offense', 'Sawed-off Shotgun'); perform kit(u, 'offense', 'Riot Shield');
  assert _setup_combos(u, 'offense') = array['riot_squad', 'spray_pray'], _setup_combos(u, 'offense')::text;
  assert _active_combo(u, 'offense') = 'riot_squad';
  r := set_combo('offense', 'spray_pray');
  assert r->>'active' = 'spray_pray' and get_me()->'combos'->'offense'->>'chosen' = 'spray_pray';
  perform expect_error('select set_combo(''offense'', ''fireteam'')', 'doesn''t complete');
  perform expect_error('select set_combo(''offense'', ''nope'')', 'No such combo');
  -- the pick lapses while it's incomplete and comes back when it's whole again
  perform unkit(u, 'offense', 'Uzi');
  assert _active_combo(u, 'offense') = 'riot_squad', 'falls back';
  perform kit(u, 'offense', 'MAC-10');
  assert _active_combo(u, 'offense') = 'spray_pray', 'the pick holds for either SMG';
  perform set_combo('offense', null);
  assert _active_combo(u, 'offense') = 'riot_squad' and get_me()->'combos'->'offense'->>'chosen' is null;
  -- a higher tier wins the automatic pick
  perform kit(u, 'offense', 'Grenade'); perform kit(u, 'offense', 'Grenade Launcher'); perform kit(u, 'offense', 'Striker GMG');
  assert _active_combo(u, 'offense') = 'grenadier', 'elite first';
  -- an all-protection kit works in jail; so do the jail combos
  perform kit(u, 'jail', 'Kevlar Vest'); perform kit(u, 'jail', 'Kevlar Shorts'); perform kit(u, 'jail', 'Kevlar Pads');
  assert _active_combo(u, 'jail') is null, 'three of four pieces';
  perform kit(u, 'jail', 'Kevlar Jacket');
  assert _active_combo(u, 'jail') = 'kevlar_squad';
  perform kit(u, 'jail', 'Sharpened Spoon'); perform kit(u, 'jail', 'Prison Yard Muscle');
  assert _setup_combos(u, 'jail') @> array['kevlar_squad', 'yard_muscle'];
end $$;

-- Jail: inside fights inside -------------------------------------------------------------------------------
do $$ declare u uuid := 'c5555555-5555-5555-5555-555555555555'; t uuid := 'c6666666-6666-6666-6666-666666666666'; r jsonb; begin
  perform set_config('request.jwt.claims', json_build_object('sub', t)::text, false); perform get_me();
  perform reset_fighter(t);
  perform set_config('request.jwt.claims', json_build_object('sub', u)::text, false);
  update profiles set jail_until = now() + interval '1 hour', health = 100, stamina = 25 where id = u;
  perform expect_error(format('select attack(%L)', t), 'only fight other inmates');
  perform expect_error(format('select fight_preview(%L)', t), 'only fight other inmates');
  perform set_config('request.jwt.claims', json_build_object('sub', t)::text, false);
  perform expect_error(format('select attack(%L)', u), 'only other inmates');
  perform expect_error(format('select fight_preview(%L)', u), 'only other inmates');
  -- both inside: a jail fight, jail setups on both sides
  update profiles set jail_until = now() + interval '1 hour', health = 100, stamina = 25 where id = t;
  r := attack(u);
  assert r ? 'won' and r->>'their_combo' = (select _active_combo(u, 'jail')), 'jail fight with jail combos: ' || r::text;
  update profiles set jail_until = null where id in (u, t);
  delete from fights where attacker_id in (u, t);
end $$;

-- Combos in a fight, and what the attacker knows ---------------------------------------------------------------
do $$ declare u uuid := 'c5555555-5555-5555-5555-555555555555'; t uuid := 'c6666666-6666-6666-6666-666666666666';
          p jsonb; r jsonb; f fights; a activity; i int; begin
  perform reset_fighter(u); perform reset_fighter(t);
  -- Marco attacks with Riot Squad (Armored); Leonel defends with Spray and Pray (Blitz). Armored beats Blitz.
  perform kit(u, 'offense', 'Sawed-off Shotgun'); perform kit(u, 'offense', 'Riot Shield');
  perform kit(t, 'defense', 'Uzi'); perform kit(t, 'defense', 'Tactical Vest');
  perform set_config('request.jwt.claims', json_build_object('sub', u)::text, false);
  -- first look: Leonel runs a combo, but which one is a secret, so the odds assume neither counters
  p := fight_preview(t);
  assert p->>'my_combo' = 'riot_squad' and (p->>'their_has_combo')::boolean and not (p->>'their_combo_known')::boolean
     and p->>'their_combo' is null, p::text;
  assert (p->>'my_combo_max')::int = 5 and (p->>'their_combo_max')::int = 5, p::text;
  -- an old fight from before combos says nothing
  insert into fights (attacker_id, defender_id, attacker_dmg, defender_dmg, winner_id, defender_combo, combos_logged)
  values (u, t, 1, 1, u, 'back_alley', false);
  assert not (fight_preview(t)->>'their_combo_known')::boolean, 'pre-combo fights are no intel';
  delete from fights where attacker_id = u and not combos_logged;
  -- the fight: Marco's roll is 0–10, Leonel's nothing
  update profiles set health = 100, stamina = 25 where id in (u, t);
  r := attack(t);
  assert r->>'my_combo' = 'riot_squad' and r->>'their_combo' = 'spray_pray', r::text;
  assert (r->>'my_combo_max')::int = 10 and (r->>'their_combo_max')::int = 0 and (r->>'their_combo_bonus')::int = 0, r::text;
  assert (r->>'my_combo_bonus')::int between 0 and 10;
  select * into f from fights where attacker_id = u order by id desc limit 1;
  assert f.attacker_combo = 'riot_squad' and f.defender_combo = 'spray_pray' and f.combos_logged
     and f.attacker_combo_bonus = (r->>'my_combo_bonus')::int and f.defender_combo_bonus = 0, 'logged';
  -- now Marco knows what Leonel runs
  p := fight_preview(t);
  assert (p->>'their_combo_known')::boolean and p->>'their_combo' = 'spray_pray' and p->>'their_combo_seen_at' is not null
     and (p->>'my_combo_max')::int = 10 and (p->>'their_combo_max')::int = 0, p::text;
  -- Leonel sees what hit him, in his fight log and his activity
  perform set_config('request.jwt.claims', json_build_object('sub', t)::text, false);
  assert get_fights(5)->0->>'attacker_combo' = 'riot_squad' and get_fights(5)->0->>'defender_combo' = 'spray_pray';
  select * into a from activity where player_id = t and kind = 'attacked' order by updated_at desc limit 1;
  assert a.data->>'combo' = 'riot_squad', 'activity names the combo: ' || a.data::text;
  -- ... and switches to Back Alley (Blackout), which beats Armored
  perform unkit(t, 'defense', 'Uzi'); perform unkit(t, 'defense', 'Tactical Vest');
  perform kit(t, 'defense', 'Machete'); perform kit(t, 'defense', 'Helmet');
  perform set_config('request.jwt.claims', json_build_object('sub', u)::text, false);
  p := fight_preview(t);
  assert p->>'their_combo' = 'spray_pray' and (p->>'my_combo_max')::int = 10, 'Marco''s intel is stale: ' || p::text;
  update profiles set health = 100, stamina = 25 where id in (u, t);
  r := attack(t);
  assert r->>'their_combo' = 'back_alley' and (r->>'my_combo_max')::int = 0 and (r->>'their_combo_max')::int = 10, 'countered: ' || r::text;
  assert fight_preview(t)->>'their_combo' = 'back_alley', 'intel updated';
  -- a bare-handed defender has nothing to hide
  delete from setup_items where player_id = t;
  p := fight_preview(t);
  assert (p->>'their_combo_known')::boolean and p->>'their_combo' is null and not (p->>'their_has_combo')::boolean
     and (p->>'my_combo_max')::int = 5 and (p->>'their_combo_max')::int = 0, p::text;
end $$;

-- Thugs' combos are public; the city board counts what active players run -----------------------------------------
select as_user('c7777777-7777-7777-7777-777777777777');
do $$ declare u uuid := auth.uid(); list jsonb; t200 jsonb; p jsonb; m jsonb; begin
  perform get_me(); perform reset_fighter(u);
  list := find_thugs();
  t200 := (select e from jsonb_array_elements(list) e where e->>'name' = 'Thug 200');
  assert t200->>'combo' = _active_combo((select id from profiles where name = 'Thug 200'), 'defense'), t200::text;
  assert (select bool_and((e->>'win_pct')::int between 0 and 100) from jsonb_array_elements(list) e), 'odds for every thug';
  p := fight_preview((select id from profiles where name = 'Thug 200'));
  assert (p->>'their_combo_known')::boolean and p->>'their_combo' is not distinct from t200->>'combo';
  update profiles set last_seen = now() where id in ('c5555555-5555-5555-5555-555555555555', 'c6666666-6666-6666-6666-666666666666');
  m := combo_meta();
  assert (m->>'players')::int >= 2 and (m->'offense'->>'riot_squad')::int >= 1 and (m->'attacks'->'riot_squad'->>'n')::int >= 1, m::text;
  assert not has_function_privilege('authenticated', '_combo_max(text, text)', 'execute');
  assert not has_function_privilege('authenticated', '_active_combo(uuid, setup_kind)', 'execute');
  assert has_function_privilege('authenticated', 'set_combo(setup_kind, text)', 'execute');
  assert has_function_privilege('authenticated', 'combo_meta()', 'execute');
  assert not has_function_privilege('anon', 'combo_meta()', 'execute');
end $$;

-- leave the fighters out of anything that runs after
delete from fights where attacker_id in ('c5555555-5555-5555-5555-555555555555', 'c6666666-6666-6666-6666-666666666666', 'c7777777-7777-7777-7777-777777777777');

select 'COMBO TEST PASSED';
