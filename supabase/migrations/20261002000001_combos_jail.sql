-- Combos: counter-play, the military tier, and jail-only fights.
--
-- Combos. A combo is a set of items in one setup (a weapon and a vest, or a whole kit). Every combo belongs to
-- one of five styles, and the styles sit on a counter wheel — each beats two and loses to two:
--
--   Armored   beats Infantry and Blitz        loses to Anti-Tank and Blackout
--   Anti-Tank beats Armored and Blitz         loses to Infantry and Blackout
--   Infantry  beats Anti-Tank and Blackout    loses to Armored and Blitz
--   Blitz     beats Infantry and Blackout     loses to Armored and Anti-Tank
--   Blackout  beats Anti-Tank and Armored     loses to Blitz and Infantry
--
-- In a fight each side's combo adds a roll on top of its score: 0–10 when it counters the other side's combo,
-- 0–5 when neither counters (or the other side has none), and nothing when it's countered. So +10 at most.
-- At even gear a counter takes the attacker from 35% to about 78%; being countered drops them to about 6%.
-- A 20% gear edge still mostly wins unless you're countered, which brings it back to a coin flip.
--
-- Which combo a player defends with is hidden (whether they run one isn't): the fight preview only knows what
-- they ran the last time you hit them, and the defender sees which combo hit them in the fight log and their
-- activity. Thugs' combos are public. A player whose setup completes several combos picks which one it runs
-- (set_combo); otherwise the best tier is used.
--
-- Street combos use cheap shop gear so new players can play the wheel; the elite ones use the military tier,
-- the items from the original game's top setups. Each one's total (attack + defense) is set so a slot of it
-- is worth about a Minigun; the split between attack and defense is fitted to the ten top setups from the
-- original game, which come out at about twice their original numbers here (our gear runs about twice
-- theirs) with the same balance of attack to defense. They cost $6,000 per point. The old "Grenades"
-- becomes the Grenade, and the EOD suit goes to 140 defense so the rare finds stay the best per slot.
--
-- Jail. Jailed players can only fight other jailed players, and nobody outside can attack someone inside.

-- ---------------------------------------------------------------------------
-- The military tier
-- ---------------------------------------------------------------------------
update item_defs set sort = sort + 70 where category = 'jail_weapon' and sort < 100;   -- make room after the TOW
update item_defs set name = 'Grenade', att = 5, def = 110, price = 690000, combo_tag = null, sort = 51 where name = 'Grenades';
-- the EOD suit stays the best defense per slot, as a rare find should
update item_defs set def = 140 where name = 'EOD Bomb Suit';

insert into item_defs (name, category, att, def, capacity, price, rep_price, combo_tag, sort, drop_only)
select v.name, v.category::item_category, v.att, v.def, 0, 6000 * (v.att + v.def), 0, null, v.sort, false
  from (values ('Striker GMG',        'weapon',   75,   50, 27),
               ('Grenade Launcher',   'weapon',   25,  110, 28),
               ('LMG',                'weapon',   25,  100, 29),
               ('MIL-Spec Rifle',     'weapon',   25,  105, 30),
               ('Dazzler Gun',        'weapon',   55,   85, 31),
               ('HUMVEE 50mm Cannon', 'weapon',   30,  115, 32),
               ('Rocket Launcher',    'weapon',  125,   25, 33),
               ('Stinger',            'weapon',  110,   55, 34),
               ('HUMVEE Stinger',     'weapon',  140,   25, 35),
               ('Metal Storm',        'weapon',   80,   90, 36),
               ('Kevlar Shorts',      'protection',   35,   55, 52),
               ('Kevlar Pads',        'protection',   35,   55, 53),
               ('Kevlar Jacket',      'protection',   45,   70, 54),
               ('Smoke Grenade',      'protection',    5,  115, 55),
               ('Flashbang',          'protection',   40,   95, 56),
               ('HUMVEE Bullbar',     'protection',   10,  125, 57),
               ('HUMVEE Armour',      'protection',   10,  125, 58))
       v(name, category, att, def, sort)
 where not exists (select 1 from item_defs d where d.name = v.name);

-- ---------------------------------------------------------------------------
-- The wheel and the combos
-- ---------------------------------------------------------------------------
create table if not exists combo_styles (
  code  text primary key,
  name  text not null,
  icon  text not null,
  blurb text not null,
  sort  integer not null
);
create table if not exists combo_counters (
  style text not null references combo_styles(code),
  beats text not null references combo_styles(code),
  primary key (style, beats)
);
create table if not exists combo_defs (
  code  text primary key,
  name  text not null,
  style text not null references combo_styles(code),
  tier  integer not null check (tier between 1 and 3),   -- 1 street · 2 pro · 3 elite
  sort  integer not null
);
-- A combo is complete when, for every part, at least one of that part's items is in the setup.
create table if not exists combo_parts (
  combo   text not null references combo_defs(code) on delete cascade,
  part    integer not null,
  item_id integer not null references item_defs(id),
  primary key (combo, part, item_id)
);
-- The combo a setup runs when it completes more than one (none = the best tier).
create table if not exists setup_combos (
  player_id uuid not null references profiles(id) on delete cascade,
  setup     setup_kind not null,
  combo     text not null references combo_defs(code) on delete cascade,
  primary key (player_id, setup)
);
alter table combo_styles   enable row level security;
alter table combo_counters enable row level security;
alter table combo_defs     enable row level security;
alter table combo_parts    enable row level security;
alter table setup_combos   enable row level security;
revoke all on combo_styles, combo_counters, combo_defs, combo_parts, setup_combos from anon, authenticated;

insert into combo_styles (code, name, icon, blurb, sort) values
  ('armored',  'Armored',   '🚙', 'Vehicles, riot gear and plate: small arms and grenades bounce off.', 1),
  ('antitank', 'Anti-Tank', '🚀', 'Launchers and heavy guns: they crack armor and outrange grenades.',  2),
  ('infantry', 'Infantry',  '🪖', 'Rifles and Kevlar: they rush launcher crews and fight through smoke.', 3),
  ('blitz',    'Blitz',     '💣', 'Grenades and spray fire: they shred squads and blow the smoke away.', 4),
  ('blackout', 'Blackout',  '🔦', 'Dazzlers, flashbangs and smoke: blind the gunners, blind the drivers.', 5)
on conflict (code) do update set name = excluded.name, icon = excluded.icon, blurb = excluded.blurb, sort = excluded.sort;

insert into combo_counters (style, beats) values
  ('armored', 'infantry'), ('armored', 'blitz'),
  ('antitank', 'armored'), ('antitank', 'blitz'),
  ('infantry', 'antitank'), ('infantry', 'blackout'),
  ('blitz', 'infantry'), ('blitz', 'blackout'),
  ('blackout', 'antitank'), ('blackout', 'armored')
on conflict do nothing;

insert into combo_defs (code, name, style, tier, sort) values
  ('back_alley',     'Back Alley',     'blackout', 1,  1),
  ('street_soldier', 'Street Soldier', 'infantry', 1,  2),
  ('riot_squad',     'Riot Squad',     'armored',  1,  3),
  ('spray_pray',     'Spray and Pray', 'blitz',    1,  4),
  ('fireteam',       'Fireteam',       'infantry', 2,  5),
  ('heavy_weapons',  'Heavy Weapons',  'antitank', 2,  6),
  ('armored_escort', 'Armored Escort', 'armored',  2,  7),
  ('blackout',       'Blackout',       'blackout', 3,  8),
  ('kevlar_squad',   'Kevlar Squad',   'infantry', 3,  9),
  ('humvee_convoy',  'HUMVEE Convoy',  'armored',  3, 10),
  ('grenadier',      'Grenadier',      'blitz',    3, 11),
  ('tank_hunters',   'Tank Hunters',   'antitank', 3, 12),
  ('yard_muscle',    'Yard Muscle',    'armored',  1, 13),   -- jail
  ('lights_out',     'Lights Out',     'blackout', 1, 14)    -- jail
on conflict (code) do update set name = excluded.name, style = excluded.style, tier = excluded.tier, sort = excluded.sort;

delete from combo_parts;
insert into combo_parts (combo, part, item_id)
select v.combo, v.part, d.id
  from (values
    ('back_alley', 1, 'Brass Knuckles'), ('back_alley', 1, 'Switchblade'), ('back_alley', 1, 'Baseball Bat'),
    ('back_alley', 1, 'Machete'), ('back_alley', 1, 'Diamond Grill Knuckles'), ('back_alley', 1, 'Escobar''s Machete'),
    ('back_alley', 2, 'Leather Jacket'), ('back_alley', 2, 'Helmet'),
    ('street_soldier', 1, 'Glock 18'), ('street_soldier', 1, 'Gold-plated Desert Eagle'),
    ('street_soldier', 2, 'Kevlar Vest'), ('street_soldier', 2, 'Cartel Plate Carrier'),
    ('riot_squad', 1, 'Sawed-off Shotgun'), ('riot_squad', 2, 'Riot Shield'),
    ('spray_pray', 1, 'Uzi'), ('spray_pray', 1, 'MAC-10'), ('spray_pray', 2, 'Tactical Vest'),
    ('fireteam', 1, 'AK-47'), ('fireteam', 1, 'M4 Carbine'), ('fireteam', 1, 'Sniper Rifle'),
    ('fireteam', 1, 'MIL-Spec Rifle'), ('fireteam', 1, 'LMG'),
    ('fireteam', 2, 'Body Armor'), ('fireteam', 2, 'Kevlar Jacket'),
    ('heavy_weapons', 1, 'RPG'), ('heavy_weapons', 1, 'Minigun'), ('heavy_weapons', 1, 'TOW Missile'),
    ('heavy_weapons', 2, 'Bulletproof Plate'), ('heavy_weapons', 2, 'EOD Bomb Suit'),
    ('armored_escort', 1, 'Armored SUV'), ('armored_escort', 1, 'Armored Limousine'), ('armored_escort', 1, 'MRAP'),
    ('armored_escort', 2, 'Body Armor'), ('armored_escort', 2, 'Bulletproof Plate'), ('armored_escort', 2, 'EOD Bomb Suit'),
    ('blackout', 1, 'Dazzler Gun'), ('blackout', 2, 'Flashbang'), ('blackout', 3, 'Smoke Grenade'),
    ('kevlar_squad', 1, 'Kevlar Vest'), ('kevlar_squad', 2, 'Kevlar Shorts'), ('kevlar_squad', 3, 'Kevlar Pads'),
    ('kevlar_squad', 4, 'Kevlar Jacket'),
    ('humvee_convoy', 1, 'HUMVEE Armour'), ('humvee_convoy', 2, 'HUMVEE Bullbar'),
    ('humvee_convoy', 3, 'HUMVEE Stinger'), ('humvee_convoy', 3, 'HUMVEE 50mm Cannon'),
    ('grenadier', 1, 'Grenade'), ('grenadier', 2, 'Grenade Launcher'), ('grenadier', 3, 'Striker GMG'),
    ('tank_hunters', 1, 'Stinger'), ('tank_hunters', 2, 'Rocket Launcher'),
    ('tank_hunters', 3, 'Metal Storm'), ('tank_hunters', 3, 'TOW Missile'),
    ('yard_muscle', 1, 'Shank'), ('yard_muscle', 1, 'Toothbrush Shiv'), ('yard_muscle', 1, 'Razor Blade Comb'),
    ('yard_muscle', 1, 'Sharpened Spoon'), ('yard_muscle', 1, 'Prison Tattoo Needle'), ('yard_muscle', 1, 'Zip Gun'),
    ('yard_muscle', 2, 'Prison Yard Muscle'),
    ('lights_out', 1, 'Sock of Batteries'), ('lights_out', 1, 'Cell Block Pipe'),
    ('lights_out', 2, 'Leather Jacket'), ('lights_out', 2, 'Helmet')
  ) v(combo, part, item) join item_defs d on d.name = v.item;

alter table fights add column if not exists attacker_combo       text references combo_defs(code) on delete set null;
alter table fights add column if not exists defender_combo       text references combo_defs(code) on delete set null;
alter table fights add column if not exists attacker_combo_bonus integer not null default 0;
alter table fights add column if not exists defender_combo_bonus integer not null default 0;
-- fights from before combos existed say nothing about what the defender ran
alter table fights add column if not exists combos_logged boolean not null default false;
alter table fights alter column combos_logged set default true;

-- ---------------------------------------------------------------------------
-- Combo helpers
-- ---------------------------------------------------------------------------
-- Every combo a setup completes, best first.
create or replace function _setup_combos(p uuid, s setup_kind) returns text[]
language sql stable set search_path = public as $$
  select coalesce(array_agg(c.code order by c.tier desc, c.sort), '{}')
    from combo_defs c
   where not exists (
     select 1 from (select distinct part from combo_parts where combo = c.code) pt
      where not exists (select 1 from combo_parts cp join setup_items si on si.item_id = cp.item_id
                         where cp.combo = c.code and cp.part = pt.part and si.player_id = p and si.setup = s and si.qty > 0)) $$;

-- The combo a setup runs: the one the player picked if it's still complete, else the best it completes.
create or replace function _active_combo(p uuid, s setup_kind) returns text
language sql stable set search_path = public as $$
  select coalesce((select sc.combo from setup_combos sc where sc.player_id = p and sc.setup = s
                     and sc.combo = any(_setup_combos(p, s))),
                  (_setup_combos(p, s))[1]) $$;

-- The most a combo can add in this matchup: 0–10 when it counters theirs, 0 when theirs counters it,
-- 0–5 otherwise (mirror, no counter, or they run none). No combo, nothing.
create or replace function _combo_max(mine text, theirs text) returns integer
language sql stable set search_path = public as $$
  select case
    when mine is null then 0
    when theirs is not null and exists (select 1 from combo_defs a join combo_defs b on b.code = theirs
                                          join combo_counters k on k.style = b.style and k.beats = a.style
                                         where a.code = mine) then 0
    when theirs is not null and exists (select 1 from combo_defs a join combo_defs b on b.code = theirs
                                          join combo_counters k on k.style = a.style and k.beats = b.style
                                         where a.code = mine) then _cfg('combo_counter')::int
    else _cfg('combo_neutral')::int end $$;

-- Share of fights won, counting every roll: the 0–6 rolls and both combo rolls.
create or replace function _win_frac(ba numeric, bd numeric, ea integer, ed integer, amax integer, dmax integer)
returns numeric language sql immutable set search_path = public as $$
  with k as (select ca - cd as k, count(*) as w from generate_series(0, amax) ca, generate_series(0, dmax) cd group by 1)
  select coalesce(sum(k.w) filter (where ba + least(10, ra + ea) + k.k > bd + least(10, rd + ed)), 0)::numeric / sum(k.w)
    from generate_series(0, 6) ra, generate_series(0, 6) rd, k $$;

-- Setup power. The combo flag now means "this setup runs a combo".
create or replace function _power(p uuid, s setup_kind, out att integer, out def integer, out combo boolean)
language plpgsql stable set search_path = public as $$
begin
  select 20 + coalesce(sum(case when d.category <> 'transport' then d.att * si.qty end), 0)
            + coalesce(max(case when d.category = 'transport' then d.att end), 0),
         20 + coalesce(sum(case when d.category <> 'transport' then d.def * si.qty end), 0)
            + coalesce(max(case when d.category = 'transport' then d.def end), 0)
    into att, def
    from setup_items si join item_defs d on d.id = si.item_id
   where si.player_id = p and si.setup = s and si.qty > 0;
  att := coalesce(att, 20); def := coalesce(def, 20);
  combo := _active_combo(p, s) is not null;
end $$;

-- Both sides of a fight: setups, power (thugs scaled), base scores, edges, and each side's combo and its cap.
drop function if exists _fight_setup(profiles, profiles);
create function _fight_setup(me profiles, them profiles,
  out sa setup_kind, out sd setup_kind, out a_att numeric, out a_def numeric, out a_combo boolean,
  out d_att numeric, out d_def numeric, out d_combo boolean, out base_a numeric, out base_d numeric,
  out edge_a integer, out edge_d integer, out edges jsonb,
  out a_code text, out d_code text, out a_max integer, out d_max integer)
language plpgsql stable set search_path = public as $$
declare pa record; pd record; f numeric := _bot_strength(them); e record;
begin
  sa := case when _jailed(me) then 'jail' else 'offense' end;
  sd := case when _jailed(them) then 'jail' else 'defense' end;
  select * into pa from _power(me.id, sa);
  select * into pd from _power(them.id, sd);
  a_att := pa.att; a_def := pa.def;
  d_att := pd.att * f; d_def := pd.def * f;
  base_a := 60.0 * a_att / (a_att + d_def);
  base_d := 60.0 * d_att / (d_att + a_def);
  select * into e from _fight_edges(me, them);
  edge_a := e.edge_a; edge_d := e.edge_d; edges := e.edges;
  a_code := _active_combo(me.id, sa); d_code := _active_combo(them.id, sd);
  a_combo := a_code is not null; d_combo := d_code is not null;
  a_max := _combo_max(a_code, d_code); d_max := _combo_max(d_code, a_code);
end $$;

-- Inside and outside don't mix.
create or replace function _jail_check(me profiles, them profiles) returns void
language plpgsql stable set search_path = public as $$
begin
  if _jailed(me) and not _jailed(them) then perform _fail('You''re locked up — you can only fight other inmates'); end if;
  if _jailed(them) and not _jailed(me) then perform _fail('They''re locked up — only other inmates can get at them'); end if;
end $$;

-- ---------------------------------------------------------------------------
-- Fights
-- ---------------------------------------------------------------------------
create or replace function attack(target uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); me profiles; them profiles; fs record;
        roll_a int; roll_d int; ca int; cd int; s_a numeric; s_d numeric; dmg_a int; dmg_d int; taken bigint := 0; win boolean; pct numeric;
        counter numeric := _cfg('counter_pct') / 100.0; f fights; recent int;
begin
  perform _nn(target, 'target');
  if target = u then perform _fail('You cannot attack yourself'); end if;
  if not exists (select 1 from profiles where id = target) then perform _fail('No such player'); end if;
  -- lock in id order to avoid deadlocks
  if u < target then me := _tick(u); them := _tick(target); else them := _tick(target); me := _tick(u); end if;

  if _hospital(me) then perform _fail('You are in the hospital'); end if;
  if _hospital(them) then perform _fail('That player is in the hospital'); end if;
  if me.stamina < 2 then perform _fail('You need at least 2 stamina to fight'); end if;
  perform _jail_check(me, them);
  if them.immune_until > now() then perform _fail('That player has new-player immunity'); end if;
  if me.immune_until > now() then me.immune_until := now(); end if;   -- attacking forfeits your own immunity
  -- the same wallet can only be shaken down so often: after 3 hits on a target in an hour the cash dries up
  select count(*) into recent from fights where attacker_id = u and defender_id = target and created_at > now() - interval '1 hour';

  select * into fs from _fight_setup(me, them);
  roll_a := _rand_between(0, 6); roll_d := _rand_between(0, 6);
  ca := _rand_between(0, fs.a_max); cd := _rand_between(0, fs.d_max);
  s_a := fs.base_a + least(10, roll_a + fs.edge_a) + ca;
  s_d := fs.base_d + least(10, roll_d + fs.edge_d) + cd;
  win := s_a > s_d;                                   -- a tie goes to the defender
  -- the winner's hit lands in full, the loser's only glances
  dmg_a := least(80, round(case when win then s_a else counter * s_a end))::int;
  dmg_d := least(80, round(case when win then counter * s_d else s_d end))::int;

  pct := case when recent >= 3 then 0 else _rand_between(5, 10) / 100.0 end;
  if win then
    taken := floor(them.cash * pct);
    me.cash := me.cash + taken; them.cash := them.cash - taken;
    me.fights_won := me.fights_won + 1; them.fights_lost := them.fights_lost + 1;
  else
    taken := floor(me.cash * pct);
    them.cash := them.cash + taken; me.cash := me.cash - taken;
    them.fights_won := them.fights_won + 1; me.fights_lost := me.fights_lost + 1;
  end if;
  them.health := greatest(0, them.health - dmg_a);
  me.health   := greatest(0, me.health - dmg_d);
  me.heat := least(me.heat_max, me.heat + 4);
  me := _bust_roll(me);

  update profiles set cash = me.cash, health = me.health, heat = me.heat, jail_until = me.jail_until,
         fights_won = me.fights_won, fights_lost = me.fights_lost, immune_until = me.immune_until where id = u;
  update profiles set cash = them.cash, health = them.health, fights_won = them.fights_won, fights_lost = them.fights_lost where id = target;

  insert into fights (attacker_id, defender_id, attacker_dmg, defender_dmg, cash_taken, winner_id,
                      attacker_combo, defender_combo, attacker_combo_bonus, defender_combo_bonus)
  values (u, target, dmg_a, dmg_d, taken, case when win then u else target end, fs.a_code, fs.d_code, ca, cd)
  returning * into f;
  if win then perform _event(u, 'fight_win'); else perform _event(target, 'defense'); end if;
  perform _award_milestones(u);
  return jsonb_build_object('won', win, 'damage_dealt', dmg_a, 'damage_taken', dmg_d, 'cash', taken, 'dry', recent >= 3,
                            'their_health', them.health, 'my_health', me.health,
                            'hospitalized_them', them.health <= 19, 'hospitalized_me', me.health <= 19,
                            'busted', _jailed(me) and fs.sa <> 'jail',
                            'my_att', round(fs.a_att)::int, 'my_def', round(fs.a_def)::int,
                            'their_att', round(fs.d_att)::int, 'their_def', round(fs.d_def)::int,
                            'my_score', round(s_a, 1), 'their_score', round(s_d, 1),
                            'my_roll', roll_a, 'their_roll', roll_d, 'edges', fs.edges,
                            'my_combo', fs.a_code, 'their_combo', fs.d_code,
                            'my_combo_bonus', ca, 'their_combo_bonus', cd,
                            'my_combo_max', fs.a_max, 'their_combo_max', fs.d_max);
end $$;

-- Fight preview: odds over every roll, what it costs, the edges. Which combo a player defends with is hidden:
-- the preview uses what they ran the last time you hit them, or — if you never have — assumes it neither
-- counters yours nor is countered by it. Whether they run one at all shows, and thugs' combos are known.
-- Keep in step with attack().
create or replace function fight_preview(target uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); me profiles; them profiles; fs record; recent int; heat_after int; red int := _cfg('heat_red')::int;
        counter numeric := _cfg('counter_pct') / 100.0; wins bigint; n bigint; dmin int; dmax int;
        known boolean; seen_combo text; seen_at timestamptz; their text; amax int; dmx int;
begin
  perform _nn(target, 'target');
  if target = u then perform _fail('You cannot attack yourself'); end if;
  if not exists (select 1 from profiles where id = target) then perform _fail('No such player'); end if;
  -- tick both (heat and cash feed the edges), locking in id order like attack()
  if u < target then me := _tick(u); them := _tick(target); else them := _tick(target); me := _tick(u); end if;
  perform _jail_check(me, them);
  select * into fs from _fight_setup(me, them);
  -- Whether they run a combo shows (you can see they're kitted out); which one doesn't, unless they're a thug
  -- or you've hit them before — then it's what they ran that time, which may have changed since.
  if them.is_bot or fs.d_code is null then
    known := true; their := fs.d_code;
  else
    select f.defender_combo, f.created_at into seen_combo, seen_at
      from fights f where f.attacker_id = u and f.defender_id = target and f.combos_logged and f.defender_combo is not null
     order by f.id desc limit 1;
    known := seen_combo is not null; their := seen_combo;
  end if;
  if known then
    amax := _combo_max(fs.a_code, their); dmx := _combo_max(their, fs.a_code);
  else
    amax := _combo_max(fs.a_code, null); dmx := _cfg('combo_neutral')::int;   -- neither counters, as far as you know
  end if;
  select count(*) filter (where x.sa > x.sd), count(*),
         min(least(80, round(case when x.sa > x.sd then counter * x.sd else x.sd end))::int),
         max(least(80, round(case when x.sa > x.sd then counter * x.sd else x.sd end))::int)
    into wins, n, dmin, dmax
    from (select fs.base_a + least(10, ra + fs.edge_a) + ca as sa, fs.base_d + least(10, rd + fs.edge_d) + cd as sd
            from generate_series(0, 6) ra, generate_series(0, 6) rd,
                 generate_series(0, amax) ca, generate_series(0, dmx) cd) x;
  select count(*) into recent from fights where attacker_id = u and defender_id = target and created_at > now() - interval '1 hour';
  heat_after := least(me.heat_max, me.heat + 4);
  return jsonb_build_object(
    'win_pct', round(100.0 * wins / n)::int,
    'win_exact', round(100.0 * wins / n, 1),
    'dmg_min', dmin, 'dmg_max', dmax,
    'my_health', me.health, 'hospital_risk', me.health - dmax <= 19,
    'dry', recent >= 3, 'hits_this_hour', recent,
    'stamina_cost', 2, 'heat_gain', 4,
    'bust_pct', case when _jailed(me) or heat_after < red then 0 else round(100.0 * (heat_after - red + 1) / 40)::int end,
    'setup', fs.sa, 'their_setup', fs.sd,
    'edges', fs.edges, 'edge_you', fs.edge_a, 'edge_them', fs.edge_d,
    'base_you', round(fs.base_a, 1), 'base_them', round(fs.base_d, 1),
    'combo_you', fs.a_code is not null, 'combo_them', dmx > 0,
    'my_combo', fs.a_code, 'their_combo', their, 'their_combo_known', known, 'their_combo_seen_at', seen_at,
    'their_has_combo', fs.d_code is not null,
    'my_combo_max', amax, 'their_combo_max', dmx,
    'my_att', round(fs.a_att)::int, 'my_def', round(fs.a_def)::int,
    'their_att', round(fs.d_att)::int, 'their_def', round(fs.d_def)::int);
end $$;

-- ---------------------------------------------------------------------------
-- Picking a combo, and the city's combos
-- ---------------------------------------------------------------------------
-- Run this combo in this setup (it has to be complete there); null goes back to the best one.
create or replace function set_combo(s setup_kind, combo text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid();
begin
  perform _nn(s, 'setup');
  perform _tick(u);
  if combo is null then
    delete from setup_combos where player_id = u and setup = s;
  else
    if not exists (select 1 from combo_defs where code = combo) then perform _fail('No such combo'); end if;
    if not (combo = any(_setup_combos(u, s))) then perform _fail('That setup doesn''t complete that combo'); end if;
    insert into setup_combos (player_id, setup, combo) values (u, s, combo)
      on conflict (player_id, setup) do update set combo = excluded.combo;
  end if;
  return jsonb_build_object('setup', s, 'active', _active_combo(u, s));
end $$;

-- What the city runs: combos in the offense and defense setups of everyone active in the last 7 days
-- (thugs aside), and how combos have done in the last week's fights.
create or replace function combo_meta() returns jsonb
language sql security definer set search_path = public stable as $$
  with active as (select id from profiles where not is_bot and last_seen > now() - interval '7 days'),
       runs as (select _active_combo(a.id, 'offense') as off, _active_combo(a.id, 'defense') as def from active a),
       wk as (select f.* from fights f join profiles d on d.id = f.defender_id
               where f.created_at > now() - interval '7 days' and not d.is_bot)
  select jsonb_build_object(
    'players', (select count(*) from active),
    'offense', (select coalesce(jsonb_object_agg(off, n), '{}'::jsonb) from (select off, count(*) n from runs where off is not null group by 1) x),
    'defense', (select coalesce(jsonb_object_agg(def, n), '{}'::jsonb) from (select def, count(*) n from runs where def is not null group by 1) x),
    'fights', (select count(*) from wk),
    'attacks', (select coalesce(jsonb_object_agg(attacker_combo, jsonb_build_object('n', n, 'won', won)), '{}'::jsonb)
                  from (select attacker_combo, count(*) n, count(*) filter (where winner_id = attacker_id) won
                          from wk where attacker_combo is not null group by 1) x)) $$;

create or replace function get_fights(limit_n integer default 30) returns jsonb
language sql security definer set search_path = public stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'attacker', a.name, 'attacker_id', f.attacker_id,
           'defender', d.name, 'defender_id', f.defender_id, 'attacker_dmg', f.attacker_dmg, 'defender_dmg', f.defender_dmg,
           'cash', f.cash_taken, 'won', f.winner_id = auth.uid(), 'i_attacked', f.attacker_id = auth.uid(), 'at', f.created_at,
           'attacker_combo', f.attacker_combo, 'defender_combo', f.defender_combo,
           'attacker_combo_bonus', f.attacker_combo_bonus, 'defender_combo_bonus', f.defender_combo_bonus)
           order by f.id desc), '[]'::jsonb)
  from (select * from fights where attacker_id = auth.uid() or defender_id = auth.uid()
        order by id desc limit limit_n) f
  join profiles a on a.id = f.attacker_id join profiles d on d.id = f.defender_id $$;

-- Every thug with its stash and your odds against it, combos included (thugs' combos are no secret).
create or replace function find_thugs() returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); me profiles; t profiles; po record; pd record; e record; f numeric; a_att numeric; a_def numeric;
        d_att numeric; d_def numeric; my_setup setup_kind; my_combo text; their_combo text; cap bigint; stash bigint;
        sticks int; hits jsonb; out jsonb := '[]'::jsonb;
begin
  me := _tick(u);
  my_setup := case when _jailed(me) then 'jail'::setup_kind else 'offense'::setup_kind end;
  select * into po from _power(u, my_setup);
  a_att := po.att; a_def := po.def; my_combo := _active_combo(u, my_setup);
  select coalesce(jsonb_object_agg(defender_id, n), '{}'::jsonb) into hits
    from (select defender_id, count(*) n from fights where attacker_id = u and created_at > now() - interval '1 hour' group by 1) h;
  for t in select * from profiles where is_bot and bot_level is not null order by bot_level loop
    -- the stash refills lazily; show what it would be if you hit it now
    cap := _bot_cash_cap(t.bot_level);
    sticks := floor(extract(epoch from now() - t.stamina_tick) / 60 / _cfg('stamina_regen_minutes'))::int;
    stash := case when t.cash >= cap then t.cash
                  else least(cap, t.cash + ceil(cap * greatest(0, sticks) * _cfg('stamina_regen_minutes') / 60.0)::bigint) end
             + greatest(0, _game_day() - t.daily_day) * _cfg('daily_cash')::bigint;   -- daily cash not yet swept in
    t.cash := stash;
    f := _bot_strength(t);
    select * into pd from _power(t.id, 'defense');
    d_att := pd.att * f; d_def := pd.def * f; their_combo := _active_combo(t.id, 'defense');
    select * into e from _fight_edges(me, t);
    out := out || jsonb_build_object('id', t.id, 'name', t.name, 'avatar', t.avatar, 'level', t.bot_level,
      'stash', stash, 'health', t.health, 'health_max', t.health_max, 'hospital', _hospital(t),
      'win_pct', round(100 * _win_frac(60.0 * a_att / (a_att + d_def), 60.0 * d_att / (d_att + a_def), e.edge_a, e.edge_d,
                                       _combo_max(my_combo, their_combo), _combo_max(their_combo, my_combo)))::int,
      'combo', their_combo,
      'hits', coalesce((hits->>t.id::text)::int, 0), 'dry', coalesce((hits->>t.id::text)::int, 0) >= 3);
  end loop;
  return out;
end $$;

-- ---------------------------------------------------------------------------
-- Tunables
-- ---------------------------------------------------------------------------
create or replace function _cfg(key text) returns numeric language sql immutable set search_path = public as $$
  select case key
    when 'regen_minutes'      then 10     -- heat cools 1 point every 10 min
    -- Regen boost (10x): stamina +2 every minute (was every 10), health +10 every minute (was +5 every 5).
    -- To go back: stamina_regen_minutes 10, health_regen_minutes 5, health_regen_amount 5.
    when 'stamina_regen_minutes' then 1
    when 'stamina_regen_amount'  then 2
    when 'health_regen_minutes' then 1
    when 'health_regen_amount'  then 10
    when 'hospital_release_pct' then 20   -- knocked out at 19 health or less; back out at this % of max health
    when 'heat_yellow'        then 40
    when 'heat_red'           then 75
    when 'jail_minutes'       then 120
    when 'bail_base'          then 2000
    when 'bail_per_minute'    then 50
    when 'bribe_per_heat'     then 40
    when 'hospital_per_point' then 40     -- base $ per health point
    when 'health_price_scale' then 100    -- price per point grows by 1x for every 100 points bought in 24h
    when 'refill_diamonds'    then 6
    when 'hustler_price'      then 400
    when 'hustler_hours'      then 4
    when 'listing_min'        then 25
    when 'listing_max'        then 1000
    when 'crew_max'           then 12
    when 'immunity_hours'     then 0      -- new-player immunity removed
    when 'starter_cash'       then 10000
    when 'starter_diamonds'   then 25
    when 'extra_grow_diamonds' then 20
    when 'crew_fight_stamina' then 5
    when 'crew_fight_cooldown_min' then 60
    when 'crew_fight_stake_pct' then 5
    when 'path_rep'           then 100    -- lifetime reputation at which a player must pick Producer or Trader
    when 'path_switch_diamonds' then 50   -- cost to switch paths afterwards
    when 'siege_wins'         then 50     -- successful hits a crew needs to take an owned block
    when 'siege_min_thugs'    then 51     -- thugs needed to launch a turf attack
    when 'block_bonus_hours'  then 24     -- each block pays its bonus on this cycle
    when 'block_bonus_pct'    then 75     -- ... this % of its sixth of the hood's daily income (was 100)
    when 'daily_cash'         then 50000  -- cash on hand every player account gets at 00:00 UTC
    when 'counter_pct'        then 35     -- the losing side's hit lands at this % of its score
    when 'bot_min_strength'   then 0.5    -- Thug 1 fights at this share of its gear, rising to 1.0 at Thug 200
    when 'drop_stamina'       then 6000   -- rare-find chance per action = stamina_cost / this (12 stamina → 1 in 500)
    when 'drop_max_crates'    then 7      -- Daily Drop: unopened crates stack up to this many
    when 'drop_price_cents'   then 299    -- Daily Drop: $2.99 a month once it's paid
    when 'drop_free'          then 1      -- Daily Drop: 1 = free to subscribe for now
    when 'combo_counter'      then 10     -- a combo that counters the other side's rolls 0–this
    when 'combo_neutral'      then 5      -- ... one that neither counters nor is countered rolls 0–this (countered: nothing)
    else 0 end $$;

-- ---------------------------------------------------------------------------
-- Reads
-- ---------------------------------------------------------------------------
create or replace function get_catalog() returns jsonb
language sql security definer set search_path = public stable as $$
  select jsonb_build_object(
    'actions', (select jsonb_agg(to_jsonb(a) order by a.sort) from action_defs a),
    'items', (select jsonb_agg(to_jsonb(i) order by i.sort) from item_defs i),
    'commodities', (select jsonb_agg(to_jsonb(c) order by c.sort) from commodities c),
    'hoodlums', (select jsonb_agg(to_jsonb(h)) from hoodlum_defs h),
    'businesses', (select jsonb_agg(to_jsonb(b) order by b.sort) from business_defs b),
    'drop_prizes', (select jsonb_agg(to_jsonb(z) order by z.sort) from drop_prizes z),
    'combo_styles', (select jsonb_agg(jsonb_build_object('code', s.code, 'name', s.name, 'icon', s.icon, 'blurb', s.blurb,
                       'beats', (select coalesce(jsonb_agg(k.beats order by b.sort), '[]'::jsonb) from combo_counters k
                                   join combo_styles b on b.code = k.beats where k.style = s.code)) order by s.sort) from combo_styles s),
    'combos', (select jsonb_agg(jsonb_build_object('code', c.code, 'name', c.name, 'style', c.style, 'tier', c.tier,
                 'parts', (select jsonb_agg(p.items order by p.part) from (select part, jsonb_agg(item_id order by item_id) items
                             from combo_parts where combo = c.code group by part) p)) order by c.sort) from combo_defs c),
    'config', jsonb_build_object(
      'bribe_per_heat', _cfg('bribe_per_heat'), 'hospital_per_point', _cfg('hospital_per_point'),
      'refill_diamonds', _cfg('refill_diamonds'), 'hustler_price', _cfg('hustler_price'),
      'hustler_hours', _cfg('hustler_hours'), 'listing_min', _cfg('listing_min'), 'listing_max', _cfg('listing_max'),
      'crew_max', _cfg('crew_max'), 'bail_base', _cfg('bail_base'), 'bail_per_minute', _cfg('bail_per_minute'),
      'extra_grow_diamonds', _cfg('extra_grow_diamonds'), 'heat_yellow', _cfg('heat_yellow'), 'heat_red', _cfg('heat_red'),
      'health_price_scale', _cfg('health_price_scale'), 'health_regen_minutes', _cfg('health_regen_minutes'),
      'health_regen_amount', _cfg('health_regen_amount'), 'path_rep', _cfg('path_rep'),
      'path_switch_diamonds', _cfg('path_switch_diamonds'), 'siege_wins', _cfg('siege_wins'),
      'siege_min_thugs', _cfg('siege_min_thugs'), 'block_bonus_hours', _cfg('block_bonus_hours'),
      'stamina_regen_minutes', _cfg('stamina_regen_minutes'), 'stamina_regen_amount', _cfg('stamina_regen_amount'),
      'regen_minutes', _cfg('regen_minutes'), 'hospital_release_pct', _cfg('hospital_release_pct'),
      'daily_cash', _cfg('daily_cash'), 'counter_pct', _cfg('counter_pct'), 'drop_stamina', _cfg('drop_stamina'),
      'bot_min_strength', _cfg('bot_min_strength'), 'jail_minutes', _cfg('jail_minutes'),
      'drop_max_crates', _cfg('drop_max_crates'), 'drop_price_cents', _cfg('drop_price_cents'), 'drop_free', _cfg('drop_free'),
      'combo_counter', _cfg('combo_counter'), 'combo_neutral', _cfg('combo_neutral'))
  ) $$;

-- get_me: which combos each setup completes, which one it runs, and which one the player picked.
create or replace function get_me() returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; po record; pd record; pj record; pk jsonb;
begin
  perform _refresh_prices();
  perform _tick_world();
  pr := _tick(u);
  update profiles set last_seen = now() where id = u;
  select * into po from _power(u, 'offense');
  select * into pd from _power(u, 'defense');
  select * into pj from _power(u, 'jail');
  pk := _perks(u);
  return jsonb_build_object(
    'id', pr.id, 'name', pr.name, 'created_at', pr.created_at, 'avatar', pr.avatar, 'bio', pr.bio, 'reputation', pr.reputation,
    'cash', pr.cash, 'bank', pr.bank, 'diamonds', pr.diamonds,
    'stamina', pr.stamina, 'stamina_max', pr.stamina_max,
    'health', pr.health, 'health_max', pr.health_max,
    'heat', pr.heat, 'heat_max', pr.heat_max,
    'heat_level', case when pr.heat >= _cfg('heat_red') then 'red' when pr.heat >= _cfg('heat_yellow') then 'yellow' else 'green' end,
    'jailed', _jailed(pr), 'jail_until', pr.jail_until,
    'hospital', _hospital(pr),
    'health_next', pr.health_tick + make_interval(mins => _cfg('health_regen_minutes')::int),
    'health_bought', pr.health_bought,
    'rep_earned', pr.rep_earned, 'path', pr.path,
    'path_required', pr.path is null and pr.rep_earned >= _cfg('path_rep'),
    'immune_until', pr.immune_until, 'immune', pr.immune_until > now(),
    'inventory_slots', pr.inventory_slots, 'storage_cap', floor(pr.storage_cap * (1 + _pk(pk, 'warehouse')))::int,
    'refills_used', pr.refills_used,
    'actions_done', pr.actions_done, 'fights_won', pr.fights_won, 'fights_lost', pr.fights_lost,
    'market_volume', pr.market_volume, 'imports', pr.imports,
    'next_tick', pr.stamina_tick + make_interval(mins => _cfg('stamina_regen_minutes')::int),   -- next stamina regen
    'power', jsonb_build_object('offense', to_jsonb(po), 'defense', to_jsonb(pd), 'jail', to_jsonb(pj)),
    'crew', (select jsonb_build_object('id', c.id, 'name', c.name, 'emblem', c.emblem, 'capo_id', c.capo_id,
                                       'is_capo', c.capo_id = u, 'co_capo_id', c.co_capo_id, 'is_co_capo', c.co_capo_id = u,
                                       'cartel_id', c.cartel_id,
                                       'members', (select count(*) from profiles where crew_id = c.id),
                                       'applications', case when _crew_boss(c, u) then (select count(*) from crew_applications where crew_id = c.id) else 0 end,
                                       'invites', case when c.capo_id = u and c.cartel_id is null then (select count(*) from cartel_invites where crew_id = c.id) else 0 end)
             from crews c where c.id = pr.crew_id),
    'cartel', (select jsonb_build_object('id', ca.id, 'name', ca.name, 'don_id', ca.don_id, 'is_don', ca.don_id = u)
               from crews c join cartels ca on ca.id = c.cartel_id where c.id = pr.crew_id),
    'storage', (select coalesce(jsonb_object_agg(commodity, qty), '{}'::jsonb) from storage where player_id = u),
    'storage_used', (select coalesce(sum(qty), 0) from storage where player_id = u),
    'prices', (select jsonb_object_agg(commodity, price) from street_prices),
    'grow_houses', (select coalesce(jsonb_agg(jsonb_build_object(
                      'id', g.id, 'commodity', g.commodity, 'level', g.level, 'running', g.running,
                      'started_at', g.started_at,
                      'rate', round(c.grow_rate * g.level * _grow_boost(pk, g.commodity), 1),
                      'cap', floor(c.grow_cap * g.level * _grow_boost(pk, g.commodity))::int,
                      'produced', least(floor(c.grow_cap * g.level * _grow_boost(pk, g.commodity))::int, g.banked + case when g.running
                          then floor(extract(epoch from now() - g.started_at) / 3600 * c.grow_rate * g.level * _grow_boost(pk, g.commodity))::int else 0 end),
                      'upgrade_cost', c.grow_price * g.level * 2) order by c.sort), '[]'::jsonb)
                    from grow_houses g join commodities c on c.code = g.commodity where g.player_id = u),
    'hustlers', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'commodity', commodity, 'count', count,
                      'units', units, 'cash_due', cash_due, 'returns_at', returns_at, 'back', returns_at <= now())
                      order by returns_at), '[]'::jsonb)
                 from hustlers where player_id = u and not collected),
    'inventory', (select coalesce(jsonb_agg(jsonb_build_object('item_id', i.item_id, 'qty', i.qty, 'name', d.name,
                      'category', d.category, 'att', d.att, 'def', d.def, 'capacity', d.capacity, 'price', d.price,
                      'combo_tag', d.combo_tag) order by d.sort), '[]'::jsonb)
                  from inventory i join item_defs d on d.id = i.item_id where i.player_id = u and i.qty > 0),
    'setups', (select coalesce(jsonb_object_agg(s, items), '{}'::jsonb) from (
                 select s.setup as s, coalesce(jsonb_agg(jsonb_build_object('item_id', s.item_id, 'qty', s.qty, 'name', d.name,
                        'category', d.category, 'att', d.att, 'def', d.def, 'combo_tag', d.combo_tag) order by d.sort), '[]'::jsonb) as items
                   from setup_items s join item_defs d on d.id = s.item_id where s.player_id = u and s.qty > 0 group by s.setup) x),
    'hoodlums', (select coalesce(jsonb_object_agg(code, qty), '{}'::jsonb) from player_hoodlums where player_id = u),
    'transport_capacity', floor((select coalesce(max(d.capacity), 0) from inventory i join item_defs d on d.id = i.item_id
                           where i.player_id = u and i.qty > 0 and d.category = 'transport') * (1 + _pk(pk, 'trucking')))::int,
    'listings', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'commodity', commodity, 'qty', qty,
                      'unit_price', unit_price, 'expires_at', expires_at, 'held', status = 'returned') order by created_at desc), '[]'::jsonb)
                 from listings where seller_id = u and status in ('open', 'returned')),
    'ribbons', _ribbons(u),
    'server_time', now()
  ) || jsonb_build_object(   -- a second object: jsonb_build_object takes at most 100 arguments
    'hospital_out_at', ceil(_cfg('hospital_release_pct') / 100.0 * pr.health_max)::int,
    'heat_next', pr.last_tick + make_interval(mins => _cfg('regen_minutes')::int),
    'unread_activity', (select count(*) from activity where player_id = u and not seen),
    'unread_dms', (select count(*) from chat_reads r where r.player_id = u
                     and exists (select 1 from messages m where m.channel = r.channel and m.created_at > r.read_at and m.sender_id <> u)),
    'storage_base', pr.storage_cap,
    'listing_max', floor(_cfg('listing_max') * (1 + _pk(pk, 'trucking')))::int,
    'perks', pk,
    'drop', jsonb_build_object('subscribed', _drop_active(pr), 'since', pr.drop_since, 'until', pr.drop_until,
              'crates', pr.drop_crates, 'max', _cfg('drop_max_crates')::int,
              'opened', (select count(*) from drop_opens where player_id = u),
              'last', (select jsonb_build_object('label', z.label, 'kind', z.kind, 'amount', o.amount, 'jackpot', z.jackpot, 'at', o.created_at)
                         from drop_opens o join drop_prizes z on z.code = o.prize where o.player_id = u order by o.id desc limit 1)),
    'free_refills', pr.free_refills, 'free_hustlers', pr.free_hustlers,
    'combos', (select jsonb_object_agg(s, jsonb_build_object('active', _active_combo(u, s), 'complete', to_jsonb(_setup_combos(u, s)),
                 'chosen', (select combo from setup_combos where player_id = u and setup = s)))
                 from unnest(array['offense', 'defense', 'jail']::setup_kind[]) s)
  );
end $$;

-- ---------------------------------------------------------------------------
-- Activity: the combo that hit you
-- ---------------------------------------------------------------------------
-- Thugs never read an activity feed, so don't write one for them. Notes the attacker's combo so you can counter it.
create or replace function _act_fight() returns trigger language plpgsql security definer set search_path = public as $$
declare a activity; held boolean := new.winner_id = new.defender_id; hosp boolean; bot boolean;
begin
  select health <= 19, is_bot into hosp, bot from profiles where id = new.defender_id;
  if bot then return null; end if;
  select * into a from activity
   where player_id = new.defender_id and kind = 'attacked' and actor_id = new.attacker_id
     and not seen and updated_at > now() - interval '1 hour'
   order by updated_at desc limit 1 for update;
  if a.id is null then
    insert into activity (player_id, kind, actor_id, data) values (new.defender_id, 'attacked', new.attacker_id,
      jsonb_build_object('n', 1, 'held', held::int,
                         'cash_won', case when held then new.cash_taken else 0 end,
                         'cash_lost', case when held then 0 else new.cash_taken end,
                         'hospital', coalesce(hosp, false), 'combo', new.attacker_combo));
  else
    update activity set updated_at = now(), data = jsonb_build_object(
        'n', coalesce((a.data->>'n')::int, 1) + 1,
        'held', coalesce((a.data->>'held')::int, 0) + held::int,
        'cash_won', coalesce((a.data->>'cash_won')::bigint, 0) + case when held then new.cash_taken else 0 end,
        'cash_lost', coalesce((a.data->>'cash_lost')::bigint, 0) + case when held then 0 else new.cash_taken end,
        'hospital', coalesce((a.data->>'hospital')::boolean, false) or coalesce(hosp, false),
        'combo', new.attacker_combo)
     where id = a.id;
  end if;
  return null;
end $$;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
do $$ declare f record; begin
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('attack', 'fight_preview', 'find_thugs', 'set_combo', 'combo_meta',
                                                         'get_fights', 'get_catalog', 'get_me') loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('_setup_combos', '_active_combo', '_combo_max', '_win_frac', '_power',
                                                         '_fight_setup', '_jail_check', '_cfg') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
end $$;
