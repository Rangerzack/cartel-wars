-- Daily Drop: a subscription that leaves one crate a day.
--  * It will cost $2.99/month; it is free for now (_cfg drop_free = 1). subscribe_drop() starts it open-ended.
--    When the paid plan goes live, the payment webhook calls _drop_subscribe(player, paid_through) instead
--    and drop_free goes to 0.
--  * One crate per game day (00:00 UTC) while subscribed. Unopened crates stack up to drop_max_crates (7);
--    a day that lands on a full stack is lost. Subscribing leaves today's crate straight away (once per day,
--    so dropping and re-subscribing doesn't farm crates). Crates already earned can be opened after cancelling.
--  * Each crate rolls one prize off drop_prizes, weighted out of 1,000. The same table drives the odds the
--    game shows.
--  * Product goes straight into storage even past the cap. A crate never shrinks; you just can't add more
--    product until you're back under the cap.
--  * "2 free refills" are stamina refill credits (a full refill each, like the diamond one, and they don't
--    count toward the 3 product refills a day). "100 hustlers" are hustler credits: each one waives the
--    hire fee for one hustler. Thugs land in your crew straight away.

-- ---------------------------------------------------------------------------
-- Schema
-- ---------------------------------------------------------------------------
alter table profiles add column if not exists drop_since    timestamptz;   -- subscribed since (null = not subscribed)
alter table profiles add column if not exists drop_until    timestamptz;   -- paid through (null = open-ended, the free plan)
alter table profiles add column if not exists drop_day      date;          -- last game day a crate was left
alter table profiles add column if not exists drop_crates   integer not null default 0 check (drop_crates >= 0);
alter table profiles add column if not exists free_refills  integer not null default 0 check (free_refills >= 0);
alter table profiles add column if not exists free_hustlers integer not null default 0 check (free_hustlers >= 0);

create table if not exists drop_prizes (
  code    text primary key,
  label   text not null,
  kind    text not null check (kind in ('herb', 'dust', 'pills', 'diamonds', 'cash', 'refills', 'thugs', 'hustlers')),
  amount  bigint not null check (amount > 0),
  weight  integer not null check (weight > 0),   -- out of the table's total (1,000)
  jackpot boolean not null default false,
  sort    integer not null
);
alter table drop_prizes enable row level security;
revoke all on drop_prizes from anon, authenticated;

insert into drop_prizes (code, label, kind, amount, weight, jackpot, sort) values
  ('herb_1000',    '1,000 Herb',      'herb',        1000, 100, false,  1),
  ('dust_700',     '700 Dust',        'dust',         700, 100, false,  2),
  ('pills_250',    '250 Pills',       'pills',        250, 100, false,  3),
  ('dia_5',        '5 Diamonds',      'diamonds',       5, 200, false,  4),
  ('dia_10',       '10 Diamonds',     'diamonds',      10, 100, false,  5),
  ('refills_2',    '2 Free Refills',  'refills',        2, 100, false,  6),
  ('cash_100k',    '$100,000',        'cash',      100000, 100, false,  7),
  ('thugs_1000',   '1,000 Thugs',     'thugs',       1000,  50, false,  8),
  ('hustlers_100', '100 Hustlers',    'hustlers',     100,  50, false,  9),
  ('dia_25',       '25 Diamonds',     'diamonds',      25,  70, true,  10),
  ('cash_1m',      '$1,000,000',      'cash',     1000000,  30, true,  11)
on conflict (code) do update set label = excluded.label, kind = excluded.kind, amount = excluded.amount,
                                 weight = excluded.weight, jackpot = excluded.jackpot, sort = excluded.sort;

create table if not exists drop_opens (
  id         bigserial primary key,
  player_id  uuid not null references profiles(id) on delete cascade,
  prize      text not null references drop_prizes(code),
  amount     bigint not null,
  created_at timestamptz not null default now()
);
create index if not exists drop_opens_player_idx on drop_opens(player_id, id desc);
alter table drop_opens enable row level security;
revoke all on drop_opens from anon, authenticated;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create or replace function _drop_active(pr profiles) returns boolean
language sql stable set search_path = public as $$
  select pr.drop_since is not null and (pr.drop_until is null or pr.drop_until > now()) $$;

-- Start (or extend) a subscription. `until` is the paid-through time; null is open-ended (the free plan).
-- Leaves today's crate if today's hasn't been left yet.
create or replace function _drop_subscribe(p uuid, until timestamptz) returns profiles
language plpgsql set search_path = public as $$
declare pr profiles; today date := _game_day();
begin
  pr := _tick(p);
  if pr.is_bot then perform _fail('Thugs don''t subscribe'); end if;
  update profiles
     set drop_since  = case when _drop_active(pr) then pr.drop_since else now() end,
         drop_until  = until,
         drop_crates = case when pr.drop_day is null or pr.drop_day < today
                            then least(_cfg('drop_max_crates')::int, pr.drop_crates + 1) else pr.drop_crates end,
         drop_day    = today
   where id = p
   returning * into pr;
  return pr;
end $$;

-- Open one crate. `r` is the draw, 0 .. total weight - 1 (open_crate passes a random one; tests pick the prize).
create or replace function _drop_open(p uuid, r integer) returns jsonb
language plpgsql set search_path = public as $$
declare z drop_prizes; acc int := 0; left_n int;
begin
  for z in select * from drop_prizes order by sort loop
    acc := acc + z.weight;
    exit when r < acc;
  end loop;
  case z.kind
    when 'herb', 'dust', 'pills' then
      insert into storage as st (player_id, commodity, qty) values (p, z.kind, z.amount::int)
        on conflict (player_id, commodity) do update set qty = st.qty + excluded.qty;
    when 'diamonds' then update profiles set diamonds = diamonds + z.amount::int where id = p;
    when 'cash'     then update profiles set cash = cash + z.amount where id = p;
    when 'refills'  then update profiles set free_refills = free_refills + z.amount::int where id = p;
    when 'hustlers' then update profiles set free_hustlers = free_hustlers + z.amount::int where id = p;
    when 'thugs'    then
      insert into player_hoodlums as ph (player_id, code, qty) values (p, 'thug', z.amount::int)
        on conflict (player_id, code) do update set qty = ph.qty + excluded.qty;
  end case;
  update profiles set drop_crates = drop_crates - 1 where id = p returning drop_crates into left_n;
  insert into drop_opens (player_id, prize, amount) values (p, z.code, z.amount);
  return jsonb_build_object('code', z.code, 'label', z.label, 'kind', z.kind, 'amount', z.amount,
                            'jackpot', z.jackpot, 'crates', left_n);
end $$;

-- ---------------------------------------------------------------------------
-- Player RPCs
-- ---------------------------------------------------------------------------
create or replace function subscribe_drop() returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles;
begin
  pr := _tick(u);
  if _drop_active(pr) then perform _fail('You''re already subscribed'); end if;
  -- The paid plan hooks in here: once drop_free is 0, subscriptions only start from the payment webhook.
  if _cfg('drop_free') = 0 then perform _fail('Subscribe through the store'); end if;
  pr := _drop_subscribe(u, null);
  return jsonb_build_object('crates', pr.drop_crates, 'since', pr.drop_since);
end $$;

-- Cancel. Crates already left stay yours to open. (A paid plan will run to its paid-through date instead.)
create or replace function unsubscribe_drop() returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles;
begin
  pr := _tick(u);
  if not _drop_active(pr) then perform _fail('You''re not subscribed'); end if;
  update profiles set drop_since = null, drop_until = null where id = u;
  return jsonb_build_object('crates', pr.drop_crates);
end $$;

create or replace function open_crate() returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles;
begin
  pr := _tick(u);
  if pr.drop_crates <= 0 then
    perform _fail(case when _drop_active(pr) then 'No crate yet — the next one lands at 00:00 UTC'
                       else 'Subscribe to the Daily Drop to get crates' end);
  end if;
  return _drop_open(u, floor(random() * (select sum(weight) from drop_prizes))::int);
end $$;

-- The city's latest jackpots, for the Daily Drop card.
create or replace function recent_drops(limit_n integer default 5) returns jsonb
language sql security definer set search_path = public stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('player_id', o.player_id, 'player', p.name, 'label', z.label, 'kind', z.kind,
           'amount', o.amount, 'at', o.created_at) order by o.id desc), '[]'::jsonb)
    from (select o.* from drop_opens o join drop_prizes z on z.code = o.prize and z.jackpot
           order by o.id desc limit greatest(1, least(coalesce(limit_n, 5), 20))) o
    join profiles p on p.id = o.player_id join drop_prizes z on z.code = o.prize $$;

-- ---------------------------------------------------------------------------
-- Credits: free stamina refills and free hustlers
-- ---------------------------------------------------------------------------
create or replace function refill(kind text, method text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; c commodities; units int; missing int; gain int; have int;
begin
  perform _nn(kind, 'refill kind'); perform _nn(method, 'refill method');
  pr := _tick(u);
  if kind not in ('stamina','health') then perform _fail('Bad refill'); end if;
  missing := case when kind = 'stamina' then pr.stamina_max - pr.stamina else pr.health_max - pr.health end;
  if missing <= 0 then perform _fail('Already full'); end if;
  if method = 'diamonds' then
    if pr.diamonds < _cfg('refill_diamonds') then perform _fail('Not enough diamonds'); end if;
    update profiles set diamonds = diamonds - _cfg('refill_diamonds')::int where id = u;
    gain := missing;
  elsif method = 'free' then
    -- a Daily Drop credit: a full stamina refill that doesn't count toward the three a day
    if kind <> 'stamina' then perform _fail('Free refills are for stamina'); end if;
    if pr.free_refills <= 0 then perform _fail('No free refills left'); end if;
    update profiles set free_refills = free_refills - 1 where id = u;
    gain := missing;
  else
    select * into c from commodities where code = method;
    if c.code is null then perform _fail('Bad refill'); end if;
    units := case when kind = 'stamina' then c.refill_stamina else c.refill_health end;
    units := ceil(units * (1 - _pk(_perks(u), 'pharmacy')))::int;
    select qty into have from storage where player_id = u and commodity = method;
    if coalesce(have, 0) < units then perform _fail(format('Needs %s %s', units, c.name)); end if;
    update storage set qty = qty - units where player_id = u and commodity = method;
    gain := case when pr.refills_used >= 3 then ceil(missing / 2.0) else missing end;
    update profiles set refills_used = refills_used + 1,
           refills_reset_at = case when pr.refills_used = 0 then now() else refills_reset_at end where id = u;
  end if;
  if kind = 'stamina' then update profiles set stamina = stamina + gain where id = u;
  else update profiles set health = health + gain where id = u; end if;
  return jsonb_build_object('gain', gain, 'units', units);
end $$;

-- Hustler credits waive the hire fee, one hustler each. They still need product to carry.
create or replace function hire_hustlers(commodity text, n integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; c commodities; have int; units int; cost int; price int; due bigint; pk jsonb := _perks(u);
        comped int;
begin
  perform _nn(n, 'count');
  pr := _tick(u);
  perform _need_path(pr, 'trader');
  perform _refresh_prices();
  select * into c from commodities where code = hire_hustlers.commodity;
  if c.code is null or n <= 0 or n > 100 then perform _fail('Hire between 1 and 100 hustlers'); end if;
  units := floor(c.hustler_units * n * (1 + _pk(pk, 'strip_club')))::int;
  comped := least(n, pr.free_hustlers);
  cost := _cfg('hustler_price')::int * (n - comped);
  select qty into have from storage where player_id = u and storage.commodity = c.code;
  if coalesce(have, 0) < units then perform _fail(format('Needs %s %s in storage', units, c.name)); end if;
  if pr.cash < cost then perform _fail(format('Hiring costs $%s', cost)); end if;
  select sp.price into price from street_prices sp where sp.commodity = c.code;
  due := floor(units::numeric * price * (1 + _pk(pk, 'dispensary')))::bigint;
  update storage set qty = qty - units where player_id = u and storage.commodity = c.code;
  update profiles set cash = cash - cost, free_hustlers = free_hustlers - comped where id = u;
  insert into hustlers (player_id, commodity, count, units, cash_due, returns_at)
  values (u, c.code, n, units, due, now() + make_interval(secs => _cfg('hustler_hours') * 3600 * (1 - _pk(pk, 'night_club'))));
  return jsonb_build_object('units', units, 'cash_due', due, 'cost', cost, 'free', comped);
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
    when 'daily_cash'         then 50000  -- cash on hand every player account gets at 00:00 UTC
    when 'counter_pct'        then 35     -- the losing side's hit lands at this % of its score
    when 'bot_min_strength'   then 0.5    -- Thug 1 fights at this share of its gear, rising to 1.0 at Thug 200
    when 'drop_stamina'       then 6000   -- rare-find chance per action = stamina_cost / this (12 stamina → 1 in 500)
    when 'drop_max_crates'    then 7      -- Daily Drop: unopened crates stack up to this many
    when 'drop_price_cents'   then 299    -- Daily Drop: $2.99 a month once it's paid
    when 'drop_free'          then 1      -- Daily Drop: 1 = free to subscribe for now
    else 0 end $$;

-- ---------------------------------------------------------------------------
-- Tick: the crate lands at the 00:00 UTC rollover
-- ---------------------------------------------------------------------------
-- Player tick: lazy regen on three clocks (stamina, health, heat); thugs refill their stash; the game-day
-- rollover brings refills back, pays daily cash and leaves Daily Drop crates.
create or replace function _tick(p uuid) returns profiles language plpgsql set search_path = public as $$
declare pr profiles; ticks int; sticks int; hticks int; cap bigint; today date := _game_day(); days int; paid bigint; thru date;
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
  -- ... and daily cash lands on hand, one payment per day missed. Thugs get it too, on top of their stash
  -- (the hourly refill only tops up to the stash cap, so the extra sits there until someone takes it).
  if pr.daily_day < today then
    days := today - pr.daily_day;
    paid := days * _cfg('daily_cash')::bigint;
    pr.cash := pr.cash + paid;
    pr.daily_day := today;
    if not pr.is_bot then perform _act_daily_cash(p, paid, days); end if;   -- thugs don't read a feed
  end if;
  -- ... and the Daily Drop leaves a crate for each day subscribed, stacking up to drop_max_crates
  if pr.drop_since is not null then
    thru := case when pr.drop_until is null then today
                 else least(today, ((pr.drop_until - interval '1 microsecond') at time zone 'utc')::date) end;
    if pr.drop_day is null or pr.drop_day < thru then
      pr.drop_crates := least(_cfg('drop_max_crates')::int, pr.drop_crates + (thru - coalesce(pr.drop_day, thru - 1)));
      pr.drop_day := thru;
    end if;
  end if;
  if pr.health_bought > 0 and pr.health_bought_at <= now() - interval '24 hours' then
    pr.health_bought := 0; pr.health_bought_at := null;
  end if;
  update profiles set stamina = pr.stamina, health = pr.health, heat = pr.heat, last_tick = pr.last_tick,
         stamina_tick = pr.stamina_tick, health_tick = pr.health_tick, in_hospital = pr.in_hospital,
         jail_until = pr.jail_until, refills_used = pr.refills_used,
         health_bought = pr.health_bought, health_bought_at = pr.health_bought_at, cash = pr.cash,
         daily_day = pr.daily_day, drop_crates = pr.drop_crates, drop_day = pr.drop_day
   where id = p;
  return pr;
end $$;

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
      'drop_max_crates', _cfg('drop_max_crates'), 'drop_price_cents', _cfg('drop_price_cents'), 'drop_free', _cfg('drop_free'))
  ) $$;

-- get_me: the Daily Drop (subscription, crates, last prize) and the free refill / hustler credits.
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
    'free_refills', pr.free_refills, 'free_hustlers', pr.free_hustlers
  );
end $$;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
do $$ declare f record; begin
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('subscribe_drop', 'unsubscribe_drop', 'open_crate', 'recent_drops',
                                                         'refill', 'hire_hustlers', 'get_catalog', 'get_me') loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('_drop_active', '_drop_subscribe', '_drop_open', '_tick', '_cfg') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
end $$;
