-- Thugs get the daily cash too.
-- At the 00:00 UTC rollover every thug gets daily_cash on hand like a player (no activity line — thugs don't
-- read one). It lands on top of the stash; the hourly refill only tops a thug back up to its stash cap, so the
-- extra sits there until hunters take it (5–10% a win). A thug nobody can beat keeps stacking it.

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
  -- ... and daily cash lands on hand, one payment per day missed. Thugs get it too, on top of their stash
  -- (the hourly refill only tops up to the stash cap, so the extra sits there until someone takes it).
  if pr.daily_day < today then
    days := today - pr.daily_day;
    paid := days * _cfg('daily_cash')::bigint;
    pr.cash := pr.cash + paid;
    pr.daily_day := today;
    if not pr.is_bot then perform _act_daily_cash(p, paid, days); end if;   -- thugs don't read a feed
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

-- Pays every account — players and thugs — at the rollover, whether or not anyone touches it. Rows locked
-- mid-action are skipped; that action's own tick pays them.
create or replace function _daily_sweep() returns integer language plpgsql set search_path = public as $$
declare r record; n int := 0;
begin
  for r in select id from profiles where daily_day < _game_day() for update skip locked loop
    perform _tick(r.id);
    n := n + 1;
  end loop;
  return n;
end $$;

-- The thug list counts daily cash that hasn't been swept in yet, so the stash shown is what a hit would see.
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
                  else least(cap, t.cash + ceil(cap * greatest(0, sticks) * _cfg('stamina_regen_minutes') / 60.0)::bigint) end
             + greatest(0, _game_day() - t.daily_day) * _cfg('daily_cash')::bigint;   -- daily cash not yet swept in
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
