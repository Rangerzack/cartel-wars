-- Season 1: the Personal Hood and the Marcus campaign (sprint day 1, 2026-10-30).
--
-- A season is three months. When one starts, six of the nineteen businesses are drawn at random, the same six for every
-- player, and every player gets a Personal Hood: six private blocks off the map, each holding one of those businesses
-- and each held by defenders until the player takes it back. A cleared block pays cash by level and gives the player
-- its business's perk; with all six cleared the hood's old owner shows up as a boss. Beside the hood runs a campaign of
-- missions narrated by Marcus, the player's right-hand man: each mission is one row of data (a line, an objective, a
-- reward, what it unlocks), evaluated from state the game already keeps, so wording and tuning are updates, not
-- releases. The campaign gates the city: tabs open as missions are claimed.
--
-- Everything seasonal is keyed by season_id. Starting the next season is a new row and a new draw; the old season's
-- rows stay as history. Nothing here changes the shape of profiles. With no season row the game plays exactly as
-- before: get_me reports no season, no hood, no mission, and every tab open.
--
-- The design is in the sprint doc; the numbers (defenders, income, prices) are proposals to tune on staging.

-- ---------------------------------------------------------------------------------------------------------------------
-- Tables
-- ---------------------------------------------------------------------------------------------------------------------
create table if not exists seasons (
  id              serial primary key,
  name            text not null,
  starts_at       timestamptz not null,
  ends_at         timestamptz not null,
  home_businesses text[] not null,      -- six business_defs codes, slot order
  home_defenders  int[] not null,       -- seven numbers: blocks 1-6 and the boss (att = def)
  created_at      timestamptz not null default now(),
  check (array_length(home_businesses, 1) = 6 and array_length(home_defenders, 1) = 7 and ends_at > starts_at)
);
alter table seasons enable row level security;

create table if not exists home_hoods (
  player_id       uuid not null references profiles(id) on delete cascade,
  season_id       int not null references seasons(id) on delete cascade,
  opened_at       timestamptz,          -- first look at the hood screen (mission 1)
  boss_cleared_at timestamptz,
  collects        int not null default 0,
  created_at      timestamptz not null default now(),
  primary key (player_id, season_id)
);
alter table home_hoods enable row level security;

create table if not exists home_blocks (
  player_id    uuid not null references profiles(id) on delete cascade,
  season_id    int not null references seasons(id) on delete cascade,
  slot         int not null check (slot between 1 and 6),
  business     text not null references business_defs(code),
  cleared_at   timestamptz,
  level        int not null default 1 check (level between 1 and 5),
  collected_at timestamptz,             -- income accrues from here once cleared
  primary key (player_id, season_id, slot)
);
alter table home_blocks enable row level security;

create table if not exists mission_defs (
  key             text primary key,
  season_id       int references seasons(id) on delete cascade,   -- null: every season
  seq             int not null,
  title           text not null,
  intro           text not null,        -- Marcus before; {biz1}..{biz6} are the season's businesses
  done            text not null,        -- Marcus after
  label           text not null,        -- the objective in the player's words ("Clear block 2")
  objective       text not null,        -- what _mission_progress counts (see it)
  qty             int not null default 1,
  reward_cash     bigint not null default 0,
  reward_diamonds int not null default 0,
  unlocks         text[] not null default '{}',   -- tab codes this mission opens when claimed
  link            text not null default '/',      -- where the card's button goes
  pass_only       boolean not null default false,
  unique (season_id, seq)
);
alter table mission_defs enable row level security;

create table if not exists missions (
  player_id    uuid not null references profiles(id) on delete cascade,
  season_id    int not null references seasons(id) on delete cascade,
  key          text not null references mission_defs(key) on delete cascade,
  completed_at timestamptz,             -- first time the objective was seen met
  claimed_at   timestamptz,
  primary key (player_id, season_id, key)
);
alter table missions enable row level security;

-- ---------------------------------------------------------------------------------------------------------------------
-- Numbers (proposals; a season row carries its own defenders)
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function _home_cfg(key text) returns numeric language sql immutable as $$
  select case key
    when 'income_1'       then 1500      -- per block per day, by level
    when 'income_2'       then 3000
    when 'income_3'       then 5500
    when 'income_4'       then 9000
    when 'income_5'       then 14000
    when 'upgrade_2'      then 5000      -- price of reaching that level
    when 'upgrade_3'      then 15000
    when 'upgrade_4'      then 40000
    when 'upgrade_5'      then 100000
    when 'cap_hours'      then 48        -- income stops piling up after this
    when 'boss_bonus'     then 0.5       -- +50% income with the boss beaten
    when 'fight_stamina'  then 2
    when 'loss_dmg_min'   then 10        -- a lost fight costs health: min + defender / 5, up to max
    when 'loss_dmg_max'   then 25
    when 'health_floor'   then 20        -- never below this from your own hood (20 is out of the hospital)
    else 0 end $$;

create or replace function _home_income(level int, boss boolean) returns bigint language sql immutable as $$
  select floor(_home_cfg('income_' || greatest(1, least(5, level))) * (1 + case when boss then _home_cfg('boss_bonus') else 0 end))::bigint $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- The season
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function _season() returns seasons language sql stable set search_path = public as $$
  select s from seasons s where s.starts_at <= now() and s.ends_at > now() order by s.starts_at desc limit 1 $$;

-- Admin: open a season. Draws the six businesses; the defenders default to the sprint proposal.
create or replace function season_start(nm text, from_at timestamptz default now(), months int default 3,
                                        defenders int[] default array[12, 22, 32, 45, 60, 75, 95]) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); s seasons; draw text[];
begin
  if not _is_admin(u) then perform _fail('Admins only'); end if;
  if nullif(trim(nm), '') is null then perform _fail('Name the season'); end if;
  if array_length(defenders, 1) <> 7 then perform _fail('Seven defender numbers: six blocks and the boss'); end if;
  if months < 1 then perform _fail('A season is at least a month'); end if;
  if exists (select 1 from seasons x where x.starts_at < from_at + make_interval(months => months) and x.ends_at > from_at) then
    perform _fail('That overlaps a season'); end if;
  select array_agg(code) into draw from (select code from business_defs order by random() limit 6) x;
  insert into seasons (name, starts_at, ends_at, home_businesses, home_defenders)
    values (trim(nm), from_at, from_at + make_interval(months => months), draw, defenders) returning * into s;
  return to_jsonb(s);
end $$;

-- A player's hood for the season, made on first sight (new signups and existing players alike).
create or replace function _home_ensure(p uuid, s seasons) returns void language plpgsql set search_path = public as $$
begin
  if s.id is null then return; end if;
  insert into home_hoods (player_id, season_id) values (p, s.id) on conflict do nothing;
  insert into home_blocks (player_id, season_id, slot, business)
    select p, s.id, i, s.home_businesses[i] from generate_series(1, 6) i on conflict do nothing;
end $$;

create or replace function _home_boss(p uuid, sid int) returns boolean language sql stable set search_path = public as $$
  select coalesce((select boss_cleared_at is not null from home_hoods where player_id = p and season_id = sid), false) $$;

-- Cash waiting on a cleared block: its daily income, by the hour, capped.
create or replace function _home_ready(b home_blocks, boss boolean) returns bigint language sql stable as $$
  select case when b.cleared_at is null then 0 else
    floor(_home_income(b.level, boss) * least(_home_cfg('cap_hours'), extract(epoch from now() - b.collected_at) / 3600) / 24)::bigint end $$;

-- The perk each cleared block gives: the business's base at level 1 up to its ceiling at level 5.
create or replace function _home_perks(p uuid) returns jsonb language sql stable set search_path = public as $$
  select coalesce(jsonb_object_agg(d.code, round(d.base + (d.ceiling - d.base) * (b.level - 1) / 4.0, 4)), '{}'::jsonb)
    from home_blocks b join business_defs d on d.code = b.business
   where b.player_id = p and b.cleared_at is not null and b.season_id = (select id from _season()) $$;

-- Crew perks and hood perks: the larger of the two per business, never the sum.
create or replace function _perks(p uuid) returns jsonb language sql stable set search_path = public as $$
  select coalesce(jsonb_object_agg(code, greatest(cv, hv)), '{}'::jsonb) from (
    select coalesce(c.key, h.key) as code, coalesce(c.value::numeric, 0) as cv, coalesce(h.value::numeric, 0) as hv
      from jsonb_each_text(coalesce((select _crew_perks(crew_id) from profiles where id = p and crew_id is not null), '{}'::jsonb)) c
      full join jsonb_each_text(_home_perks(p)) h on h.key = c.key) x $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- The hood: look, fight, collect, upgrade
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function _home_json(p uuid) returns jsonb language plpgsql stable set search_path = public as $$
declare s seasons := _season(); h home_hoods; boss boolean; nxt int; d int; po record; ba numeric; bd numeric; code text;
begin
  if s.id is null then return null; end if;
  select * into h from home_hoods where player_id = p and season_id = s.id;
  if h.player_id is null then return null; end if;
  boss := h.boss_cleared_at is not null;
  select min(slot) into nxt from home_blocks where player_id = p and season_id = s.id and cleared_at is null;
  select * into po from _power(p, 'offense');
  code := _active_combo(p, 'offense');
  d := case when nxt is not null then s.home_defenders[nxt] when not boss then s.home_defenders[7] end;
  if d is not null then
    ba := 60.0 * po.att / (po.att + d); bd := 60.0 * d / (d + po.def);
  end if;
  return jsonb_build_object(
    'season', jsonb_build_object('id', s.id, 'name', s.name, 'starts_at', s.starts_at, 'ends_at', s.ends_at),
    'opened', h.opened_at is not null,
    'boss', jsonb_build_object('cleared', boss, 'cleared_at', h.boss_cleared_at, 'defender', s.home_defenders[7],
                               'ready', nxt is null and not boss),
    'cleared', (select count(*) from home_blocks where player_id = p and season_id = s.id and cleared_at is not null),
    'next_slot', nxt,
    'next', case when d is not null then jsonb_build_object('defender', d, 'win_pct', round(100 * _win_frac(ba, bd, 0, 0, _combo_max(code, null), 0))::int,
                                                             'my_att', po.att, 'my_def', po.def, 'stamina', _home_cfg('fight_stamina')::int) end,
    'ready_cash', (select coalesce(sum(_home_ready(b, boss)), 0) from home_blocks b where b.player_id = p and b.season_id = s.id),
    'income_day', (select coalesce(sum(_home_income(b.level, boss)), 0) from home_blocks b where b.player_id = p and b.season_id = s.id and b.cleared_at is not null),
    'collects', h.collects,
    'blocks', (select jsonb_agg(jsonb_build_object(
                 'slot', b.slot, 'business', b.business, 'name', dd.name, 'icon', dd.icon, 'perk', dd.perk, 'category', dd.category,
                 'cleared', b.cleared_at is not null, 'cleared_at', b.cleared_at, 'level', b.level,
                 'income_day', case when b.cleared_at is not null then _home_income(b.level, boss) end,
                 'ready', _home_ready(b, boss),
                 'cap_at', case when b.cleared_at is not null then b.collected_at + make_interval(hours => _home_cfg('cap_hours')::int) end,
                 'upgrade_cost', case when b.cleared_at is not null and b.level < 5 then _home_cfg('upgrade_' || (b.level + 1))::bigint end,
                 'defender', s.home_defenders[b.slot],
                 'perk_value', case when b.cleared_at is not null then round(dd.base + (dd.ceiling - dd.base) * (b.level - 1) / 4.0, 4) end
               ) order by b.slot)
               from home_blocks b join business_defs dd on dd.code = b.business where b.player_id = p and b.season_id = s.id),
    'perks', _home_perks(p),
    'cfg', jsonb_build_object('cap_hours', _home_cfg('cap_hours')::int, 'boss_bonus', _home_cfg('boss_bonus'))
  );
end $$;

-- The hood screen. Looking at it is mission 1.
create or replace function home_state() returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); s seasons := _season();
begin
  if s.id is null then perform _fail('No season is running'); end if;
  perform _home_ensure(u, s);
  update home_hoods set opened_at = now() where player_id = u and season_id = s.id and opened_at is null;
  return _home_json(u);
end $$;

-- One fight against the defenders of a block (1-6) or the boss (7). Your offense setup against a defender whose attack
-- and defense are both the season's number for that slot: the same scores, rolls and combo bonus as a player fight,
-- no edges (there is no setup on the other side), no heat, no cash, no fight row.
create or replace function _home_fight(u uuid, slot int) returns jsonb
language plpgsql set search_path = public as $$
declare s seasons := _season(); pr profiles; h home_hoods; nxt int; d int; po record; code text;
        ba numeric; bd numeric; roll_a int; roll_d int; ca int; s_a numeric; s_d numeric; win boolean; dmg int := 0;
begin
  if s.id is null then perform _fail('No season is running'); end if;
  perform _home_ensure(u, s);
  pr := _tick(u);
  select * into h from home_hoods where player_id = u and season_id = s.id;
  if _hospital(pr) then perform _fail('You are in the hospital'); end if;
  if _jailed(pr) then perform _fail('Not from a cell'); end if;
  if pr.stamina < _home_cfg('fight_stamina') then perform _fail(format('You need %s stamina to fight', _home_cfg('fight_stamina')::int)); end if;
  select min(b.slot) into nxt from home_blocks b where b.player_id = u and b.season_id = s.id and b.cleared_at is null;
  if slot between 1 and 6 then
    if nxt is null or slot < nxt then perform _fail('That block is already yours'); end if;
    if slot > nxt then perform _fail(format('Take block %s first', nxt)); end if;
  elsif slot = 7 then
    if nxt is not null then perform _fail('Take all six blocks first'); end if;
    if h.boss_cleared_at is not null then perform _fail('The hood is already yours'); end if;
  else
    perform _fail('No such block');
  end if;
  d := s.home_defenders[slot];
  select * into po from _power(u, 'offense');
  code := _active_combo(u, 'offense');
  ba := 60.0 * po.att / (po.att + d); bd := 60.0 * d / (d + po.def);
  roll_a := _rand_between(0, 6); roll_d := _rand_between(0, 6);
  ca := _rand_between(0, _combo_max(code, null));
  s_a := ba + roll_a + ca; s_d := bd + roll_d;
  win := s_a > s_d;                                   -- a tie goes to the defenders, as in any fight
  pr.stamina := pr.stamina - _home_cfg('fight_stamina')::int;
  if win then
    if slot = 7 then update home_hoods set boss_cleared_at = now() where player_id = u and season_id = s.id;
    else update home_blocks set cleared_at = now(), collected_at = now() where player_id = u and season_id = s.id and home_blocks.slot = _home_fight.slot; end if;
  else
    dmg := least(_home_cfg('loss_dmg_max'), _home_cfg('loss_dmg_min') + d / 5.0)::int;
    pr.health := greatest(least(pr.health, _home_cfg('health_floor')::int), pr.health - dmg);
    dmg := greatest(0, (select health from profiles where id = u) - pr.health);
  end if;
  update profiles set stamina = pr.stamina, health = pr.health where id = u;
  return jsonb_build_object('won', win, 'slot', slot, 'boss', slot = 7, 'defender', d,
                            'my_att', po.att, 'my_def', po.def, 'my_score', round(s_a, 1), 'their_score', round(s_d, 1),
                            'my_roll', roll_a, 'their_roll', roll_d, 'my_combo', code, 'my_combo_bonus', ca,
                            'damage_taken', dmg, 'my_health', pr.health, 'stamina', pr.stamina,
                            'hood', _home_json(u));
end $$;

create or replace function home_attack(slot int) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform _nn(slot, 'block');
  if slot not between 1 and 6 then perform _fail('No such block'); end if;
  return _home_fight(_uid(), slot);
end $$;

create or replace function home_boss() returns jsonb
language plpgsql security definer set search_path = public as $$
begin return _home_fight(_uid(), 7); end $$;

-- Collect one block's cash, or every block's (slot null).
create or replace function home_collect(slot int default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); s seasons := _season(); boss boolean; got bigint := 0; b home_blocks; n int := 0;
begin
  if s.id is null then perform _fail('No season is running'); end if;
  perform _home_ensure(u, s);
  perform _tick(u);
  boss := _home_boss(u, s.id);
  for b in select * from home_blocks where player_id = u and season_id = s.id and cleared_at is not null
             and (home_collect.slot is null or home_blocks.slot = home_collect.slot) order by home_blocks.slot for update loop
    if _home_ready(b, boss) > 0 then
      got := got + _home_ready(b, boss); n := n + 1;
      update home_blocks set collected_at = now() where player_id = u and season_id = s.id and home_blocks.slot = b.slot;
    end if;
  end loop;
  if slot is not null and not exists (select 1 from home_blocks where player_id = u and season_id = s.id and home_blocks.slot = home_collect.slot and cleared_at is not null) then
    perform _fail('That block isn''t yours yet'); end if;
  if got = 0 then perform _fail('Nothing to collect yet'); end if;
  update profiles set cash = cash + got where id = u;
  update home_hoods set collects = collects + 1 where player_id = u and season_id = s.id;
  return jsonb_build_object('collected', got, 'blocks', n, 'hood', _home_json(u));
end $$;

create or replace function home_upgrade(slot int) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); s seasons := _season(); pr profiles; b home_blocks; price bigint;
begin
  perform _nn(slot, 'block');
  if s.id is null then perform _fail('No season is running'); end if;
  perform _home_ensure(u, s);
  pr := _tick(u);
  select * into b from home_blocks where player_id = u and season_id = s.id and home_blocks.slot = home_upgrade.slot for update;
  if b.player_id is null then perform _fail('No such block'); end if;
  if b.cleared_at is null then perform _fail('Take the block first'); end if;
  if b.level >= 5 then perform _fail('That business is at its top level'); end if;
  price := _home_cfg('upgrade_' || (b.level + 1))::bigint;
  if pr.cash < price then perform _fail(format('Costs $%s cash on hand', price)); end if;
  -- cash waiting at the old level is paid out first, so an upgrade never shrinks it
  update profiles set cash = cash - price + _home_ready(b, _home_boss(u, s.id)) where id = u;
  update home_blocks set level = level + 1, collected_at = now() where player_id = u and season_id = s.id and home_blocks.slot = home_upgrade.slot;
  return jsonb_build_object('level', b.level + 1, 'cost', price, 'hood', _home_json(u));
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- The campaign
-- ---------------------------------------------------------------------------------------------------------------------
-- What a player has done toward an objective, from state the game already keeps. New kinds are a line here.
create or replace function _mission_progress(p uuid, objective text) returns int
language plpgsql stable set search_path = public as $$
declare sid int := (select id from _season()); pr profiles; po record; v int;
begin
  select * into pr from profiles where id = p;
  case objective
    when 'hood_open'    then v := (select (opened_at is not null)::int from home_hoods where player_id = p and season_id = sid);
    when 'home_clear'   then v := (select count(*) from home_blocks where player_id = p and season_id = sid and cleared_at is not null);
    when 'home_collect' then v := (select collects from home_hoods where player_id = p and season_id = sid);
    when 'home_upgrade' then v := (select max(level) from home_blocks where player_id = p and season_id = sid and cleared_at is not null);
    when 'home_boss'    then v := _home_boss(p, sid)::int;
    when 'attack'       then select att into v from _power(p, 'offense');
    when 'actions'      then v := pr.actions_done;
    when 'bank'         then v := (pr.bank > 0)::int;
    when 'grow'         then v := (select count(*) from grow_houses where player_id = p);
    when 'fight_win'    then v := pr.fights_won;
    when 'moved'        then v := (pr.imports > 0 or pr.market_volume > 0 or exists (select 1 from hustlers where player_id = p))::int;
    when 'crew'         then v := (pr.crew_id is not null)::int;
    when 'hoodlums'     then v := (select coalesce(sum(qty), 0) from player_hoodlums where player_id = p);
    when 'turf'         then v := pr.turf_attacks;
    -- the finale: a crew, five hoodlums, one city block hit; three ticks on the card
    when 'city'         then v := (pr.crew_id is not null)::int
                               + ((select coalesce(sum(qty), 0) from player_hoodlums where player_id = p) >= 5)::int
                               + (pr.turf_attacks >= 1)::int;
    else v := 0;
  end case;
  return coalesce(v, 0);
end $$;

-- The three parts of a composite objective, for the card's ticks.
create or replace function _mission_parts(p uuid, objective text) returns jsonb
language sql stable set search_path = public as $$
  select case objective when 'city' then jsonb_build_array(
      jsonb_build_object('label', 'Join or found a crew', 'done', _mission_progress(p, 'crew') >= 1),
      jsonb_build_object('label', 'Own 5 hoodlums', 'done', _mission_progress(p, 'hoodlums') >= 5),
      jsonb_build_object('label', 'Attack a city block', 'done', _mission_progress(p, 'turf') >= 1))
    else null end $$;

-- Marcus names the season's businesses: {biz1} is the one on block 1.
create or replace function _mission_text(t text, s seasons) returns text language sql stable set search_path = public as $$
  select replace(replace(replace(replace(replace(replace(t,
           '{biz1}', coalesce((select name from business_defs where code = s.home_businesses[1]), '')),
           '{biz2}', coalesce((select name from business_defs where code = s.home_businesses[2]), '')),
           '{biz3}', coalesce((select name from business_defs where code = s.home_businesses[3]), '')),
           '{biz4}', coalesce((select name from business_defs where code = s.home_businesses[4]), '')),
           '{biz5}', coalesce((select name from business_defs where code = s.home_businesses[5]), '')),
           '{biz6}', coalesce((select name from business_defs where code = s.home_businesses[6]), '')) $$;

-- The campaign for this season, in order: the season's own missions, else the ones for every season.
create or replace function _mission_defs(sid int) returns setof mission_defs language sql stable set search_path = public as $$
  select * from mission_defs d where d.season_id = sid
  union all
  select * from mission_defs d where d.season_id is null and not exists (select 1 from mission_defs x where x.season_id = sid)
  order by seq $$;

-- One mission as the card shows it.
create or replace function _mission_json(p uuid, d mission_defs, s seasons, n int) returns jsonb
language plpgsql stable set search_path = public as $$
declare m missions; prog int;
begin
  select * into m from missions where player_id = p and season_id = s.id and key = d.key;
  prog := least(d.qty, _mission_progress(p, d.objective));
  return jsonb_build_object('key', d.key, 'seq', d.seq, 'n', n, 'title', d.title,
    'intro', _mission_text(d.intro, s), 'done', _mission_text(d.done, s), 'label', d.label,
    'progress', prog, 'qty', d.qty, 'complete', prog >= d.qty or m.completed_at is not null,
    'claimed', m.claimed_at is not null, 'claimed_at', m.claimed_at,
    'reward_cash', d.reward_cash, 'reward_diamonds', d.reward_diamonds, 'unlocks', to_jsonb(d.unlocks), 'link', d.link,
    'parts', _mission_parts(p, d.objective), 'pass_only', d.pass_only);
end $$;

-- The current mission: the first unclaimed one on the free track. Null when the campaign is done or no season runs.
create or replace function _mission_card(p uuid) returns jsonb
language plpgsql set search_path = public as $$
declare s seasons := _season(); d mission_defs; n int := 0; total int;
begin
  if s.id is null then return null; end if;
  select count(*) into total from _mission_defs(s.id) where not pass_only;
  for d in select * from _mission_defs(s.id) where not pass_only loop
    n := n + 1;
    if not exists (select 1 from missions where player_id = p and season_id = s.id and key = d.key and claimed_at is not null) then
      -- the first look at a met objective is remembered, so a state that later changes (cash withdrawn) can't unfinish it
      if _mission_progress(p, d.objective) >= d.qty then
        insert into missions (player_id, season_id, key, completed_at) values (p, s.id, d.key, now())
          on conflict (player_id, season_id, key) do update set completed_at = coalesce(missions.completed_at, now());
      end if;
      return _mission_json(p, d, s, n) || jsonb_build_object('total', total);
    end if;
  end loop;
  return jsonb_build_object('finished', true, 'total', total);
end $$;

-- Tabs the campaign has opened: always-open ones plus what claimed missions unlock. No season: everything.
create or replace function _unlocked(p uuid) returns jsonb language plpgsql stable set search_path = public as $$
declare s seasons := _season(); always text[] := array['home', 'hood', 'profile', 'store', 'chat', 'forum', 'activity', 'accolades', 'missions'];
        gated text[] := array['items', 'actions', 'services', 'casino', 'economy', 'fight', 'crew', 'territory'];
begin
  if s.id is null then return to_jsonb(always || gated); end if;
  return to_jsonb(always || coalesce((select array_agg(distinct x) from missions m join mission_defs d on d.key = m.key
                                        cross join unnest(d.unlocks) x
                                       where m.player_id = p and m.season_id = s.id and m.claimed_at is not null), '{}'::text[]));
end $$;

create or replace function missions_state() returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); s seasons := _season(); d mission_defs; n int := 0; lst jsonb := '[]'::jsonb;
begin
  if s.id is null then return jsonb_build_object('season', null, 'missions', lst); end if;
  perform _home_ensure(u, s);
  for d in select * from _mission_defs(s.id) where not pass_only loop
    n := n + 1;
    lst := lst || _mission_json(u, d, s, n);
  end loop;
  return jsonb_build_object('season', jsonb_build_object('id', s.id, 'name', s.name, 'ends_at', s.ends_at),
                            'missions', lst, 'current', _mission_card(u), 'unlocked', _unlocked(u));
end $$;

-- Take the reward. Only the current mission, only once it's met; paying twice is refused.
create or replace function mission_claim(key text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); s seasons := _season(); d mission_defs; cur jsonb; m missions;
begin
  perform _nn(key, 'mission');
  if s.id is null then perform _fail('No season is running'); end if;
  perform _home_ensure(u, s);
  perform _tick(u);
  select * into d from _mission_defs(s.id) x where x.key = mission_claim.key;
  if d.key is null then perform _fail('No such mission'); end if;
  cur := _mission_card(u);
  if cur->>'key' is distinct from d.key then perform _fail('That isn''t the mission you''re on'); end if;
  if not (cur->>'complete')::boolean then perform _fail('Not done yet'); end if;
  select * into m from missions where player_id = u and season_id = s.id and missions.key = d.key for update;
  if m.claimed_at is not null then perform _fail('Already claimed'); end if;
  update missions set claimed_at = now() where player_id = u and season_id = s.id and missions.key = d.key;
  update profiles set cash = cash + d.reward_cash, diamonds = diamonds + d.reward_diamonds where id = u;
  return jsonb_build_object('claimed', d.key, 'reward_cash', d.reward_cash, 'reward_diamonds', d.reward_diamonds,
                            'unlocks', to_jsonb(d.unlocks), 'next', _mission_card(u), 'unlocked', _unlocked(u));
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- Season 1's missions (season_id null: the campaign every season runs until one gets its own)
-- ---------------------------------------------------------------------------------------------------------------------
insert into mission_defs (key, seq, title, intro, done, label, objective, qty, reward_cash, reward_diamonds, unlocks, link) values
  ('six_blocks',    1, 'Six Blocks',
     'Boss. The city got reset. Everybody''s back to nothing — except we''ve still got six blocks on the edge of town. Somebody''s squatting on every one of them.',
     'First block''s held by a couple of kids with bats. Go introduce yourself.',
     'Open Your Hood', 'hood_open', 1, 500, 0, '{}', '/hood'),
  ('block_one',     2, 'Block One', 'Nothing fancy. Just win.', 'That''s one block working for us. Five to go.',
     'Clear block 1', 'home_clear', 1, 1000, 0, '{}', '/hood'),
  ('get_armed',     3, 'Get Armed',
     'Block two''s a different story. Get something sharper than your fists — the shop''s open.',
     'Better. Now you look like trouble.',
     'Attack power 28 or more', 'attack', 28, 2000, 0, '{items}', '/items?tab=shop&cat=weapon'),
  ('open_for_business', 4, 'Open for Business',
     'The {biz1} on block one still runs. The till''s full. Go empty it.',
     'Every day it pays. Don''t forget it, and don''t let it sit.',
     'Collect from a block', 'home_collect', 1, 500, 0, '{}', '/hood'),
  ('work',          5, 'Work',
     'Fights don''t pay the bills. There''s work on the street — small jobs. Watch your heat.',
     'Small jobs, steady money. Lay low and the heat comes down.',
     'Complete 3 actions', 'actions', 3, 1500, 0, '{actions}', '/actions'),
  ('bank_it',       6, 'Bank It',
     'Cash on hand is cash somebody can take. Put it in the bank.',
     'Can''t be robbed of what you don''t carry.',
     'Deposit any amount', 'bank', 1, 0, 10, '{services,casino}', '/services?focus=bank'),
  ('block_two',     7, 'Block Two', 'You''re armed, you''re funded. Take it.', 'Two down. The others heard about it.',
     'Clear block 2', 'home_clear', 2, 2000, 0, '{}', '/hood'),
  ('build_it_up',   8, 'Build It Up',
     'The {biz2} could pull twice the money with some work. Spend some.',
     'Spend money to make money. You''re learning.',
     'Upgrade a block to level 2', 'home_upgrade', 2, 2500, 0, '{}', '/hood'),
  ('grow',          9, 'Grow',
     'Street money''s small. Product is where the real money is. Build a grow house.',
     'It grows while you sleep. Come back and collect.',
     'Own a grow house', 'grow', 1, 3000, 0, '{economy}', '/economy'),
  ('blocks_three_four', 10, 'Blocks Three and Four',
     'Two more. They''ve got better gear than the last ones. So should you.',
     'Four blocks. Half a hood and the whole street knows your name.',
     'Clear block 4', 'home_clear', 4, 4000, 0, '{}', '/hood'),
  ('first_blood',  11, 'First Blood',
     'You''ve been fighting squatters. Time to fight somebody who fights back — there are thugs on every corner.',
     'Now you''ve got a record. Keep it clean.',
     'Win a fight', 'fight_win', 1, 3000, 0, '{fight}', '/fight?tab=thugs'),
  ('move_product', 12, 'Move Product',
     'Product on a shelf is worth nothing. Send hustlers out or list it on the market.',
     'Now it''s a business.',
     'Send hustlers or list product', 'moved', 1, 4000, 0, '{}', '/economy?tab=hustlers'),
  ('blocks_five_six', 13, 'Blocks Five and Six',
     'The last two are held by somebody with real muscle. Gear up both ways — what you wear matters as much as what you swing.',
     'Six blocks. All ours. But the guy who ran this hood before the reset wants it back.',
     'Clear block 6', 'home_clear', 6, 6000, 0, '{}', '/hood'),
  ('the_boss',     14, 'The Boss Falls', 'He''s at the top of the hood. End it.',
     'The hood''s yours, boss. Now the city''s noticed.',
     'Beat the hood boss', 'home_boss', 1, 10000, 25, '{crew,territory}', '/hood'),
  ('into_the_city', 15, 'Into the City',
     'Six blocks is a start. The city''s 486. Nobody takes that alone — find a crew or start one, hire muscle, and hit a block.',
     'That''s how it starts. Fifty wins takes a block. Go take the city.',
     'Crew, 5 hoodlums, 1 block hit', 'city', 3, 15000, 50, '{}', '/crew')
on conflict (key) do update set seq = excluded.seq, title = excluded.title, intro = excluded.intro, done = excluded.done,
  label = excluded.label, objective = excluded.objective, qty = excluded.qty, reward_cash = excluded.reward_cash,
  reward_diamonds = excluded.reward_diamonds, unlocks = excluded.unlocks, link = excluded.link;

-- ---------------------------------------------------------------------------------------------------------------------
-- get_me: the season, the hood in brief, the current mission and the open tabs (null / everything without a season)
-- ---------------------------------------------------------------------------------------------------------------------
create or replace function _season_me(u uuid) returns jsonb language plpgsql set search_path = public as $$
declare s seasons := _season(); hj jsonb;
begin
  if s.id is null then return jsonb_build_object('season', null, 'home', null, 'mission', null, 'unlocked', _unlocked(u)); end if;
  perform _home_ensure(u, s);
  hj := _home_json(u);
  return jsonb_build_object(
    'season', jsonb_build_object('id', s.id, 'name', s.name, 'starts_at', s.starts_at, 'ends_at', s.ends_at, 'businesses', to_jsonb(s.home_businesses)),
    'home', jsonb_build_object('cleared', hj->'cleared', 'boss', hj->'boss'->'cleared', 'boss_ready', hj->'boss'->'ready',
                               'ready_cash', hj->'ready_cash', 'income_day', hj->'income_day', 'next', hj->'next', 'opened', hj->'opened'),
    'mission', _mission_card(u),
    'unlocked', _unlocked(u));
end $$;

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
    'heat_level', _heat_level(pr),
    'jailed', _jailed(pr), 'jail_until', case when isfinite(pr.jail_until) then pr.jail_until end,   -- null: until bail
    'hospital', _hospital(pr),
    'health_next', pr.health_tick + make_interval(mins => _cfg('health_regen_minutes')::int),
    'health_bought', pr.health_bought,
    'rep_earned', pr.rep_earned, 'path', pr.path,
    'path_required', _path_due(pr) is not null,
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
    'transport_capacity', _haul(u),
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
                     and exists (select 1 from messages m where m.channel = r.channel and m.created_at > r.read_at and m.sender_id <> u and not m.deleted)
                     and not _blocked_pair(u, _dm_other(r.channel, u))),   -- that conversation is out of the list
    'storage_base', pr.storage_cap,
    'listing_max', floor(_cfg('listing_max') * (1 + _pk(pk, 'trucking')))::int,
    'perks', pk,
    'drop', jsonb_build_object('subscribed', _drop_active(pr), 'since', pr.drop_since, 'until', pr.drop_until,
              'drop_paid', pr.drop_until is not null,   -- only the store webhook sets drop_until
              'crates', pr.drop_crates, 'max', _cfg('drop_max_crates')::int,
              'opened', (select count(*) from drop_opens where player_id = u),
              'last', (select jsonb_build_object('label', z.label, 'kind', z.kind, 'amount', o.amount, 'jackpot', z.jackpot, 'at', o.created_at)
                         from drop_opens o join drop_prizes z on z.code = o.prize where o.player_id = u order by o.id desc limit 1)),
    'free_refills', pr.free_refills, 'free_hustlers', pr.free_hustlers,
    'combos', (select jsonb_object_agg(s, jsonb_build_object('active', _active_combo(u, s), 'complete', to_jsonb(_setup_combos(u, s)),
                 'chosen', (select combo from setup_combos where player_id = u and setup = s)))
                 from unnest(array['offense', 'defense', 'jail']::setup_kind[]) s),
    'slot_cost', (select jsonb_build_object('diamonds', c.diamonds, 'cash', c.cash) from _slot_cost(pr.inventory_slots) c),
    'boost', jsonb_build_object('side', pr.boost_side, 'until', pr.boost_until, 'active', _boost_active(pr),
               'amount', _cfg('boost_amount')::int)
  ) || jsonb_build_object(
    -- the market: street details (for previewing a hustle), my open buy orders; and today's drug refills
    'street', _street_json(),
    'orders', (select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'commodity', o.commodity, 'qty', o.qty, 'filled', o.filled,
                    'unit_price', o.unit_price, 'expires_at', o.expires_at) order by o.created_at desc), '[]'::jsonb)
               from buy_orders o where o.buyer_id = u and o.status = 'open'),
    -- drug refills: full ones per drug today (3, or 5 on the Daily Drop), how many of each are used, and what one
    -- restores after that (a share of max stamina)
    'refills', jsonb_build_object('full', _refill_full_n(pr), 'used', _drug_refills_today(pr), 'late_share', _cfg('refill_late_share'),
                                  'sub_full', (_cfg('refill_full') + _cfg('refill_sub_extra'))::int),
    'path_due', _path_due(pr),  -- why a path is required: 'rep' or 'grow'
    'heat_yellow', _heat_yellow(pr), 'heat_red', _heat_red(pr),  -- this player's lines (heat upgrades move them up)
    -- milestone progress the profile row doesn't already carry: turf attacks made and cash wagered at the casino
    'turf_attacks', pr.turf_attacks, 'casino_wagered', pr.casino_wagered,
    -- moderation: admins see the queue size; a reset (or placeholder) name asks for a new one
    'is_admin', pr.is_admin, 'rename_pending', pr.rename_pending,
    'name_required', pr.rename_pending or pr.name like 'player\_%',
    'reports_open', case when pr.is_admin then (select count(distinct target_id) from profile_reports where status = 'open') else 0 end,
    -- players I've blocked: the client drops their realtime chat lines
    'blocked', (select coalesce(jsonb_agg(blocked_id), '[]'::jsonb) from blocked_players where blocker_id = u),
    -- muted: the client shows the end of the mute in place of the chat and forum composers
    'muted_until', case when pr.muted_until > now() then pr.muted_until end
  ) || _season_me(u);   -- Season 1: season, home, mission, unlocked
end $$;

-- ---------------------------------------------------------------------------------------------------------------------
-- Grants: the RPCs to players, the helpers to nobody (Postgres gives new functions to PUBLIC by default)
-- ---------------------------------------------------------------------------------------------------------------------
do $$ declare f record; begin
  for f in select p.oid::regprocedure::text as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and (p.proname like '\_%' or p.proname in ('season_start', 'home_state', 'home_attack', 'home_boss',
             'home_collect', 'home_upgrade', 'missions_state', 'mission_claim', 'get_me')) loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname not like '\_%' then execute format('grant execute on function %s to authenticated', f.sig); end if;
  end loop;
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and (p.proconfig is null or not p.proconfig::text like '%search_path%') loop
    execute format('alter function %s set search_path = public', f.sig);
  end loop;
end $$;
