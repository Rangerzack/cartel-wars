-- Round 3: the game day, daily cash, head-to-head fights with +1 edges, and rare finds on actions.
--
--  * Game day: rolls over at 00:00 UTC (5pm Pacific), the same clock the weekly boards use.
--  * Refills: the three full product refills come back at the rollover. They used to come back 24 hours
--    after the first one, so a refill at 6pm locked you out until 6pm the next day.
--  * Daily cash: at the rollover every player account gets daily_cash as cash on hand, online or not.
--    Cash on hand can be taken in fights until it's banked, so an account nobody logs into piles up and
--    becomes worth hitting. The thugs are left out (they have their own refilling stash). A pg_cron job
--    pays everyone at 00:00; _tick pays anything it missed, so a skipped cron run just pays late.
--  * Fights are head-to-head. Both sides score the same way:
--        60 × your attack / (your attack + their defense) + a 0–6 roll + your edges (the two capped at 10)
--        + a 0–10 combo roll if your setup has a weapon/protection combo
--    Higher score wins; a tie goes to the defender. Edges (+1 each): the defender always; whoever has more
--    cash on hand; whoever has more heat. The winner's hit lands in full, the loser's at counter_pct (35%).
--    Before this, only the attacker got the situational roll and the defender's hit-back counted 35% toward
--    who won, so attackers won everything short of being out-geared about 5 to 1 and a defender +1 could
--    never matter. Thugs fight at bot_min_strength (half) of their gear at Thug 1, rising to full at
--    Thug 200, so new players can still farm the first forty or so.
--  * fight_preview(target) gives exact odds (every roll enumerated) and lists the edges.
--  * find_thugs(): every thug with its stash and your odds, so hunters can find the fat, beatable ones.
--  * Rare finds: four drop-only items, each the best of its kind, found only on actions. Each action names
--    the item it can turn up; the chance is stamina_cost / drop_stamina (1 in 500 on a 12-stamina job), so
--    spamming the cheapest job isn't a shortcut. They can't be bought or sold.

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
    when 'daily_cash'         then 50000  -- cash on hand every player account gets at 00:00 UTC
    when 'counter_pct'        then 35     -- the losing side's hit lands at this % of its score
    when 'bot_min_strength'   then 0.5    -- Thug 1 fights at this share of its gear, rising to 1.0 at Thug 200
    when 'drop_stamina'       then 6000   -- rare-find chance per action = stamina_cost / this (12 stamina → 1 in 500)
    else 0 end $$;

-- ---------------------------------------------------------------------------
-- Game clock
-- ---------------------------------------------------------------------------
create or replace function _game_day() returns date language sql stable set search_path = public as $$
  select (now() at time zone 'utc')::date $$;

create or replace function _day_start() returns timestamptz language sql stable set search_path = public as $$
  select (_game_day())::timestamp at time zone 'utc' $$;

-- The last game day this account was paid for. New accounts start on the day they sign up (first pay at the
-- next rollover); existing accounts are marked paid for today, so the first payout is tonight's rollover.
alter table profiles add column if not exists daily_day date not null default ((now() at time zone 'utc')::date);

-- Daily cash shows in the activity feed; unseen days fold into one line.
create or replace function _act_daily_cash(p uuid, paid bigint, days integer) returns void
language plpgsql set search_path = public as $$
declare aid bigint;
begin
  select id into aid from activity where player_id = p and kind = 'daily_cash' and not seen
   order by updated_at desc limit 1 for update;
  if aid is null then
    insert into activity (player_id, kind, data) values (p, 'daily_cash', jsonb_build_object('cash', paid, 'days', days));
  else
    update activity set updated_at = now(), data = jsonb_build_object(
        'cash', coalesce((data->>'cash')::bigint, 0) + paid,
        'days', coalesce((data->>'days')::int, 0) + days)
     where id = aid;
  end if;
end $$;

-- Player tick: lazy regen on three clocks (stamina, health, heat); thugs refill their stash; the game-day
-- rollover brings refills back and pays daily cash.
create or replace function _tick(p uuid) returns profiles language plpgsql set search_path = public as $$
declare pr profiles; ticks int; sticks int; hticks int; cap bigint; today date := _game_day(); days int; paid bigint;
        step  interval := make_interval(mins => _cfg('regen_minutes')::int);
        sstep interval := make_interval(mins => _cfg('stamina_regen_minutes')::int);
        hstep interval := make_interval(mins => _cfg('health_regen_minutes')::int);
begin
  select * into pr from profiles where id = p for update;
  if pr.id is null then raise exception 'No such player'; end if;
  ticks := floor(extract(epoch from now() - pr.last_tick) / extract(epoch from step))::int;
  if ticks > 0 then
    pr.heat      := greatest(0, pr.heat - ticks);
    pr.last_tick := pr.last_tick + ticks * step;
  end if;
  sticks := floor(extract(epoch from now() - pr.stamina_tick) / extract(epoch from sstep))::int;
  if sticks > 0 then
    pr.stamina      := least(pr.stamina_max, pr.stamina + _cfg('stamina_regen_amount')::int * sticks);
    pr.stamina_tick := pr.stamina_tick + sticks * sstep;
    -- NPC thugs: the stash tops back up over an hour (cash won off failed attackers is kept)
    if pr.is_bot and pr.bot_level is not null then
      cap := _bot_cash_cap(pr.bot_level);
      if pr.cash < cap then
        pr.cash := least(cap, pr.cash + ceil(cap * sticks * _cfg('stamina_regen_minutes') / 60.0)::bigint);
      end if;
    end if;
  end if;
  hticks := floor(extract(epoch from now() - pr.health_tick) / extract(epoch from hstep))::int;
  if hticks > 0 then
    pr.health      := greatest(pr.health, least(pr.health_max, pr.health + _cfg('health_regen_amount')::int * hticks));
    pr.health_tick := pr.health_tick + hticks * hstep;
  end if;
  pr.in_hospital := _hospital_state(pr.in_hospital, pr.health, pr.health_max);
  if pr.jail_until is not null and pr.jail_until <= now() then pr.jail_until := null; end if;
  -- game-day rollover (00:00 UTC): product refills come back ...
  if pr.refills_used > 0 and pr.refills_reset_at < _day_start() then
    pr.refills_used := 0;
  end if;
  -- ... and daily cash lands on hand, one payment per day missed (thugs have their own stash)
  if not pr.is_bot and pr.daily_day < today then
    days := today - pr.daily_day;
    paid := days * _cfg('daily_cash')::bigint;
    pr.cash := pr.cash + paid;
    pr.daily_day := today;
    perform _act_daily_cash(p, paid, days);
  end if;
  if pr.health_bought > 0 and pr.health_bought_at <= now() - interval '24 hours' then
    pr.health_bought := 0; pr.health_bought_at := null;
  end if;
  update profiles set stamina = pr.stamina, health = pr.health, heat = pr.heat, last_tick = pr.last_tick,
         stamina_tick = pr.stamina_tick, health_tick = pr.health_tick, in_hospital = pr.in_hospital,
         jail_until = pr.jail_until, refills_used = pr.refills_used,
         health_bought = pr.health_bought, health_bought_at = pr.health_bought_at, cash = pr.cash,
         daily_day = pr.daily_day
   where id = p;
  return pr;
end $$;

-- Pays every account at the rollover, whether or not anyone touches it. Rows locked mid-action are skipped;
-- that action's own tick pays them.
create or replace function _daily_sweep() returns integer language plpgsql set search_path = public as $$
declare r record; n int := 0;
begin
  for r in select id from profiles where not is_bot and daily_day < _game_day() for update skip locked loop
    perform _tick(r.id);
    n := n + 1;
  end loop;
  return n;
end $$;

-- ---------------------------------------------------------------------------
-- Fights
-- ---------------------------------------------------------------------------
-- Thugs fight at part strength: bot_min_strength at Thug 1, full at Thug 200. Players always at full.
create or replace function _bot_strength(pr profiles) returns numeric language sql stable set search_path = public as $$
  select case when pr.is_bot and pr.bot_level is not null
              then _cfg('bot_min_strength') + (1 - _cfg('bot_min_strength')) * (greatest(1, least(200, pr.bot_level)) - 1) / 199.0
              else 1 end $$;

-- The +1 edges. `edges` lists who holds each one, from the attacker's side ('you' / 'them').
create or replace function _fight_edges(me profiles, them profiles, out edge_a integer, out edge_d integer, out edges jsonb)
language plpgsql stable set search_path = public as $$
begin
  edge_a := 0; edge_d := 1;
  edges := jsonb_build_array(jsonb_build_object('k', 'defender', 'side', 'them'));
  if me.cash > them.cash then edge_a := edge_a + 1; edges := edges || jsonb_build_object('k', 'cash', 'side', 'you');
  elsif them.cash > me.cash then edge_d := edge_d + 1; edges := edges || jsonb_build_object('k', 'cash', 'side', 'them');
  end if;
  if me.heat > them.heat then edge_a := edge_a + 1; edges := edges || jsonb_build_object('k', 'heat', 'side', 'you');
  elsif them.heat > me.heat then edge_d := edge_d + 1; edges := edges || jsonb_build_object('k', 'heat', 'side', 'them');
  end if;
end $$;

-- Everything about a fight that isn't a dice roll: setups, effective power, base scores and edges.
create or replace function _fight_setup(me profiles, them profiles,
    out sa setup_kind, out sd setup_kind,
    out a_att numeric, out a_def numeric, out a_combo boolean,
    out d_att numeric, out d_def numeric, out d_combo boolean,
    out base_a numeric, out base_d numeric,
    out edge_a integer, out edge_d integer, out edges jsonb)
language plpgsql stable set search_path = public as $$
declare pa record; pd record; f numeric := _bot_strength(them); e record;
begin
  sa := case when _jailed(me) then 'jail' else 'offense' end;
  sd := case when _jailed(them) then 'jail' else 'defense' end;
  select * into pa from _power(me.id, sa);
  select * into pd from _power(them.id, sd);
  a_att := pa.att; a_def := pa.def; a_combo := pa.combo;
  d_att := pd.att * f; d_def := pd.def * f; d_combo := pd.combo;
  base_a := 60.0 * a_att / (a_att + d_def);
  base_d := 60.0 * d_att / (d_att + a_def);
  select * into e from _fight_edges(me, them);
  edge_a := e.edge_a; edge_d := e.edge_d; edges := e.edges;
end $$;

create or replace function attack(target uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); me profiles; them profiles; fs record;
        roll_a int; roll_d int; s_a numeric; s_d numeric; dmg_a int; dmg_d int; taken bigint := 0; win boolean; pct numeric;
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
  if them.immune_until > now() then perform _fail('That player has new-player immunity'); end if;
  if me.immune_until > now() then me.immune_until := now(); end if;   -- attacking forfeits your own immunity
  -- the same wallet can only be shaken down so often: after 3 hits on a target in an hour the cash dries up
  select count(*) into recent from fights where attacker_id = u and defender_id = target and created_at > now() - interval '1 hour';

  select * into fs from _fight_setup(me, them);
  roll_a := _rand_between(0, 6); roll_d := _rand_between(0, 6);
  s_a := fs.base_a + least(10, roll_a + fs.edge_a) + case when fs.a_combo then _rand_between(0, 10) else 0 end;
  s_d := fs.base_d + least(10, roll_d + fs.edge_d) + case when fs.d_combo then _rand_between(0, 10) else 0 end;
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

  insert into fights (attacker_id, defender_id, attacker_dmg, defender_dmg, cash_taken, winner_id)
  values (u, target, dmg_a, dmg_d, taken, case when win then u else target end) returning * into f;
  if win then perform _event(u, 'fight_win'); else perform _event(target, 'defense'); end if;
  perform _award_milestones(u);
  return jsonb_build_object('won', win, 'damage_dealt', dmg_a, 'damage_taken', dmg_d, 'cash', taken, 'dry', recent >= 3,
                            'their_health', them.health, 'my_health', me.health,
                            'hospitalized_them', them.health <= 19, 'hospitalized_me', me.health <= 19,
                            'busted', _jailed(me) and fs.sa <> 'jail',
                            'my_att', round(fs.a_att)::int, 'my_def', round(fs.a_def)::int,
                            'their_att', round(fs.d_att)::int, 'their_def', round(fs.d_def)::int,
                            'my_score', round(s_a, 1), 'their_score', round(s_d, 1),
                            'my_roll', roll_a, 'their_roll', roll_d, 'edges', fs.edges);
end $$;

-- Fight preview: exact odds from every combination of rolls, what it costs, and the edges on each side.
-- Keep in step with attack().
create or replace function fight_preview(target uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); me profiles; them profiles; fs record; recent int; heat_after int; red int := _cfg('heat_red')::int;
        counter numeric := _cfg('counter_pct') / 100.0; wins bigint; n bigint; dmin int; dmax int;
begin
  perform _nn(target, 'target');
  if target = u then perform _fail('You cannot attack yourself'); end if;
  if not exists (select 1 from profiles where id = target) then perform _fail('No such player'); end if;
  -- tick both (heat and cash feed the edges), locking in id order like attack()
  if u < target then me := _tick(u); them := _tick(target); else them := _tick(target); me := _tick(u); end if;
  select * into fs from _fight_setup(me, them);
  select count(*) filter (where x.sa > x.sd), count(*),
         min(least(80, round(case when x.sa > x.sd then counter * x.sd else x.sd end))::int),
         max(least(80, round(case when x.sa > x.sd then counter * x.sd else x.sd end))::int)
    into wins, n, dmin, dmax
    from (select fs.base_a + least(10, ra + fs.edge_a) + ca as sa, fs.base_d + least(10, rd + fs.edge_d) + cd as sd
            from generate_series(0, 6) ra, generate_series(0, 6) rd,
                 generate_series(0, case when fs.a_combo then 10 else 0 end) ca,
                 generate_series(0, case when fs.d_combo then 10 else 0 end) cd) x;
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
    'combo_you', fs.a_combo, 'combo_them', fs.d_combo,
    'my_att', round(fs.a_att)::int, 'my_def', round(fs.a_def)::int,
    'their_att', round(fs.d_att)::int, 'their_def', round(fs.d_def)::int);
end $$;

-- Every thug with its stash (as it stands now, refills included) and your odds against it. Odds here count
-- every roll but take combo rolls at their average, so they can be a point or two off the fight preview.
create or replace function find_thugs() returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); me profiles; t profiles; po record; pd record; e record; f numeric; a_att numeric; a_def numeric;
        d_att numeric; d_def numeric; ba numeric; bd numeric; ca numeric; cd numeric; wins int; cap bigint; stash bigint;
        sticks int; hits jsonb; out jsonb := '[]'::jsonb;
begin
  me := _tick(u);
  select * into po from _power(u, case when _jailed(me) then 'jail'::setup_kind else 'offense'::setup_kind end);
  a_att := po.att; a_def := po.def; ca := case when po.combo then 5 else 0 end;
  select coalesce(jsonb_object_agg(defender_id, n), '{}'::jsonb) into hits
    from (select defender_id, count(*) n from fights where attacker_id = u and created_at > now() - interval '1 hour' group by 1) h;
  for t in select * from profiles where is_bot and bot_level is not null order by bot_level loop
    -- the stash refills lazily; show what it would be if you hit it now
    cap := _bot_cash_cap(t.bot_level);
    sticks := floor(extract(epoch from now() - t.stamina_tick) / 60 / _cfg('stamina_regen_minutes'))::int;
    stash := case when t.cash >= cap then t.cash
                  else least(cap, t.cash + ceil(cap * greatest(0, sticks) * _cfg('stamina_regen_minutes') / 60.0)::bigint) end;
    t.cash := stash;
    f := _bot_strength(t);
    select * into pd from _power(t.id, case when _jailed(t) then 'jail'::setup_kind else 'defense'::setup_kind end);
    d_att := pd.att * f; d_def := pd.def * f; cd := case when pd.combo then 5 else 0 end;
    ba := 60.0 * a_att / (a_att + d_def) + ca;
    bd := 60.0 * d_att / (d_att + a_def) + cd;
    select * into e from _fight_edges(me, t);
    select count(*) filter (where ba + least(10, ra + e.edge_a) > bd + least(10, rd + e.edge_d)) into wins
      from generate_series(0, 6) ra, generate_series(0, 6) rd;
    out := out || jsonb_build_object('id', t.id, 'name', t.name, 'avatar', t.avatar, 'level', t.bot_level,
      'stash', stash, 'health', t.health, 'health_max', t.health_max, 'hospital', _hospital(t),
      'win_pct', round(100.0 * wins / 49)::int, 'hits', coalesce((hits->>t.id::text)::int, 0),
      'dry', coalesce((hits->>t.id::text)::int, 0) >= 3);
  end loop;
  return out;
end $$;

-- ---------------------------------------------------------------------------
-- Rare finds
-- ---------------------------------------------------------------------------
alter table item_defs   add column if not exists drop_only boolean not null default false;
alter table action_defs add column if not exists drop_item integer references item_defs(id);

create table if not exists rare_finds (
  id         bigserial primary key,
  player_id  uuid not null references profiles(id) on delete cascade,
  item_id    integer not null references item_defs(id),
  action_id  integer references action_defs(id) on delete set null,
  created_at timestamptz not null default now()
);
create index if not exists rare_finds_recent_idx on rare_finds(created_at desc);
alter table rare_finds enable row level security;
revoke all on rare_finds from anon, authenticated;

-- The best item of each kind. Nothing in the shop or the reputation list beats them.
insert into item_defs (name, category, att, def, capacity, price, rep_price, combo_tag, sort, drop_only)
select v.name, v.category::item_category, v.att, v.def, v.capacity, 0, 0, v.combo_tag, v.sort, true
  from (values ('TOW Missile',   'weapon',      185,   0,   0, 'heavy', 26),   -- Minigun 150
               ('Zip Gun',       'jail_weapon',  60,   0,   0, 'shiv',  37),   -- Prison Tattoo Needle 45
               ('EOD Bomb Suit', 'protection',    0, 115,   0, 'heavy', 50),   -- Bulletproof Plate 90
               ('MRAP',          'transport',    15,  40, 400, null,    67))   -- Armored Limousine 12/30
       v(name, category, att, def, capacity, combo_tag, sort)
 where not exists (select 1 from item_defs d where d.name = v.name);

-- Which job turns up which find: guns and hits → TOW Missile; muscle and protection → EOD Bomb Suit;
-- anything on wheels, boats or planes → MRAP; the jail hustles → Zip Gun.
update action_defs set drop_item = (select id from item_defs where name = 'TOW Missile')
 where name in ('Shake Down a Shop Owner', 'Rob a Bodega', 'Run Guns to the Docks', 'Kidnap a Banker', 'Assassinate a Snitch',
                'Raid a Federal Evidence Lockup', 'Take Down a Rival Don', 'Settle a Dispute for the Don', 'Host the Cartel Summit');
update action_defs set drop_item = (select id from item_defs where name = 'EOD Bomb Suit')
 where name in ('Sling on the Corner', 'Lookout for the Block', 'Collect Protection Money', 'Fence Stolen Goods', 'Intimidate a Witness',
                'Torch a Rival Stash House', 'Rob an Armored Car', 'Hit a Rival''s Grow Op', 'Launder Cash Through a Casino',
                'Pay for a Neighborhood Funeral', 'Bankroll a Crew Member''s Bail');
update action_defs set drop_item = (select id from item_defs where name = 'MRAP')
 where name in ('Run a Package', 'Jack a Car Stereo', 'Move Product Across Town', 'Hijack a Delivery Van', 'Bribe a Customs Agent',
                'Smuggle a Shipment Through the Port', 'Take Over a Chop Shop', 'Hijack a Cartel Plane', 'Escort the Shipment Personally');
update action_defs set drop_item = (select id from item_defs where name = 'Zip Gun') where is_jail;

-- Roll for a find. `r` is the random draw (tests pass 0 to force one). Returns the item, or null.
create or replace function _rare_roll(p uuid, a action_defs, r double precision) returns jsonb
language plpgsql set search_path = public as $$
declare d item_defs;
begin
  if a.drop_item is null or a.effect = 'go_to_jail' or r >= a.stamina_cost / _cfg('drop_stamina') then return null; end if;
  select * into d from item_defs where id = a.drop_item;
  insert into inventory (player_id, item_id, qty) values (p, d.id, 1)
    on conflict (player_id, item_id) do update set qty = inventory.qty + 1;
  insert into rare_finds (player_id, item_id, action_id) values (p, d.id, a.id);
  return jsonb_build_object('id', d.id, 'name', d.name, 'category', d.category, 'att', d.att, 'def', d.def,
                            'owned', (select qty from inventory where player_id = p and item_id = d.id));
end $$;

create or replace function do_action(action_id integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; a action_defs; pay int; busted boolean := false; crew_n int; was_jailed boolean; found jsonb;
begin
  perform _nn(action_id, 'action');
  pr := _tick(u);
  was_jailed := _jailed(pr);
  select * into a from action_defs where id = action_id;
  if a.id is null then perform _fail('Unknown action'); end if;
  if _hospital(pr) then perform _fail('You are in the hospital'); end if;
  if _jailed(pr) and not a.is_jail then perform _fail('You are in jail — only jail actions are available'); end if;
  if not _jailed(pr) and a.is_jail then perform _fail('Jail actions can only be done in jail'); end if;
  if pr.stamina < a.stamina_cost then perform _fail('Not enough stamina'); end if;
  if pr.cash < a.cash_cost then perform _fail('Not enough cash'); end if;
  if a.requires_item is not null and not exists (select 1 from inventory where player_id = u and item_id = a.requires_item and qty > 0) then
    perform _fail('Requires ' || (select name from item_defs where id = a.requires_item));
  end if;
  if a.min_crew > 0 then
    select count(*) into crew_n from profiles where crew_id = pr.crew_id and pr.crew_id is not null;
    if coalesce(crew_n, 0) < a.min_crew then perform _fail(format('Requires a crew of at least %s', a.min_crew)); end if;
  end if;

  pr.stamina := pr.stamina - a.stamina_cost;
  pr.cash := pr.cash - a.cash_cost;
  pr.actions_done := pr.actions_done + 1;

  if a.effect = 'go_to_jail' then
    pr.jail_until := now() + make_interval(mins => _cfg('jail_minutes')::int);
    pay := 0; busted := true;
  else
    pay := _rand_between(a.pay_min, a.pay_max);
    pr.cash := pr.cash + pay;
    pr.reputation := pr.reputation + a.pay_rep;
    pr.heat := least(pr.heat_max, pr.heat + a.heat_gain);
    pr := _bust_roll(pr);
    busted := _jailed(pr) and not was_jailed;
    found := _rare_roll(u, a, random());
  end if;

  update profiles set stamina = pr.stamina, cash = pr.cash, heat = pr.heat, jail_until = pr.jail_until,
         actions_done = pr.actions_done, reputation = pr.reputation where id = u;
  perform _event(u, 'action');
  perform _award_milestones(u);
  return jsonb_build_object('pay', pay, 'rep', a.pay_rep, 'busted', busted, 'heat', pr.heat, 'stamina', pr.stamina, 'cash', pr.cash,
                            'found', found);
end $$;

-- Latest finds across the city, for the Actions page.
create or replace function recent_finds(limit_n integer default 8) returns jsonb
language sql security definer set search_path = public stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('player_id', f.player_id, 'player', p.name, 'item', d.name, 'item_id', d.id,
           'action', a.name, 'at', f.created_at) order by f.created_at desc), '[]'::jsonb)
    from (select * from rare_finds order by created_at desc limit greatest(1, least(coalesce(limit_n, 8), 50))) f
    join profiles p on p.id = f.player_id join item_defs d on d.id = f.item_id
    left join action_defs a on a.id = f.action_id $$;

-- Finds can't be bought or sold.
create or replace function buy_item(item integer, n integer default 1) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; d item_defs; cost bigint;
begin
  perform _nn(n, 'quantity');
  pr := _tick(u);
  select * into d from item_defs where id = item;
  if d.id is null or n <= 0 then perform _fail('Bad item'); end if;
  if d.drop_only then perform _fail(format('%s can only be found on actions', d.name)); end if;
  if d.rep_price > 0 then
    cost := d.rep_price::bigint * n;
    if pr.reputation < cost then perform _fail(format('Needs %s reputation', cost)); end if;
    update profiles set reputation = reputation - cost where id = u;
  else
    cost := d.price::bigint * n;
    if pr.cash < cost then perform _fail(format('Costs $%s', cost)); end if;
    update profiles set cash = cash - cost where id = u;
  end if;
  insert into inventory (player_id, item_id, qty) values (u, item, n)
    on conflict (player_id, item_id) do update set qty = inventory.qty + excluded.qty;
  return jsonb_build_object('cost', cost);
end $$;

create or replace function sell_item(item integer, n integer default 1) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); have int; used int; d item_defs; refund bigint;
begin
  perform _nn(n, 'quantity');
  perform _tick(u);
  select * into d from item_defs where id = item;
  select qty into have from inventory where player_id = u and item_id = item;
  select coalesce(max(qty), 0) into used from setup_items where player_id = u and item_id = item;
  if d.id is null or n <= 0 or coalesce(have, 0) - used < n then perform _fail('Not enough unequipped units to sell'); end if;
  if d.rep_price > 0 then perform _fail('Rare items cannot be sold'); end if;
  if d.drop_only then perform _fail('Rare finds cannot be sold'); end if;
  refund := (d.price / 2)::bigint * n;
  update inventory set qty = qty - n where player_id = u and item_id = item;
  update profiles set cash = cash + refund where id = u;
  return jsonb_build_object('refund', refund);
end $$;

-- Catalog: the new tunables for the client.
create or replace function get_catalog() returns jsonb
language sql security definer set search_path = public stable as $$
  select jsonb_build_object(
    'actions', (select jsonb_agg(to_jsonb(a) order by a.sort) from action_defs a),
    'items', (select jsonb_agg(to_jsonb(i) order by i.sort) from item_defs i),
    'commodities', (select jsonb_agg(to_jsonb(c) order by c.sort) from commodities c),
    'hoodlums', (select jsonb_agg(to_jsonb(h)) from hoodlum_defs h),
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
      'bot_min_strength', _cfg('bot_min_strength'))
  ) $$;

-- ---------------------------------------------------------------------------
-- Grants and schedule
-- ---------------------------------------------------------------------------
do $$ declare f record; begin
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('find_thugs', 'recent_finds', 'fight_preview', 'attack', 'do_action',
                                                         'buy_item', 'sell_item', 'get_catalog') loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('_game_day', '_day_start', '_act_daily_cash', '_tick', '_daily_sweep',
                                                         '_bot_strength', '_fight_edges', '_fight_setup', '_rare_roll', '_cfg') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
end $$;

-- Pay at 00:00 UTC with pg_cron where it's available (the hosted project). Local test databases don't have
-- pg_cron; tests call _daily_sweep() directly, and _tick pays late if a run is ever missed.
do $$
begin
  if exists (select 1 from pg_available_extensions where name = 'pg_cron') then
    begin
      create extension if not exists pg_cron;
      perform cron.schedule('daily-rollover', '0 0 * * *', 'select public._daily_sweep()');
    exception when others then
      raise notice 'pg_cron not usable here (%) — _daily_sweep() is not scheduled', sqlerrm;
    end;
  end if;
end $$;
