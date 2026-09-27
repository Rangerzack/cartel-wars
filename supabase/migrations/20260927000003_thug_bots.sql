-- 200 NPC punching bags: "Thug 1" … "Thug 200".
--  * They never act. They sit in the city, show up in player search / the Fight list, and can be attacked.
--  * Strength climbs with the number: Thug 1 is bare-handed, Thug 200 carries 3 Miniguns, 3 Bulletproof
--    Plates and an Armored SUV, and has 200 health.
--  * Each carries a cash stash that grows with the number ($2k for Thug 1 up to $500k for Thug 200) and
--    tops back up over an hour, so they're worth hunting. The usual 5–10% per win and the 3-hits-an-hour
--    dry wallet rule still apply.
--  * They heal like players (lazy regen on _tick) and count on leaderboards like anyone else.
--  * Their accounts can't sign in (no password, banned). To remove them all:
--      delete from auth.users where email like 'thug-%@bots.cartelwars.invalid';

alter table profiles add column if not exists is_bot    boolean not null default false;
alter table profiles add column if not exists bot_level integer;

-- Cash a thug of this level carries when topped up.
create or replace function _bot_cash_cap(lvl integer) returns bigint language sql immutable set search_path = public as $$
  select (2000 + 498000 * power((greatest(1, least(200, lvl)) - 1) / 199.0, 2))::bigint $$;

-- Accounts. The signup trigger (handle_new_user) creates each profile from raw_user_meta_data.name.
do $$
declare full_auth boolean := exists (select 1 from information_schema.columns
                                      where table_schema = 'auth' and table_name = 'users' and column_name = 'instance_id');
begin
  if full_auth then
    -- hosted Supabase: fill the token columns with '' (NULLs there break the Auth admin API)
    insert into auth.users (instance_id, id, aud, role, email, encrypted_password, raw_app_meta_data, raw_user_meta_data,
                            is_super_admin, created_at, updated_at, confirmation_token, recovery_token,
                            email_change_token_new, email_change, banned_until)
    select '00000000-0000-0000-0000-000000000000', gen_random_uuid(), 'authenticated', 'authenticated',
           'thug-' || i || '@bots.cartelwars.invalid', '',
           '{"provider": "email", "providers": ["email"], "bot": true}'::jsonb,
           jsonb_build_object('name', 'Thug ' || i),
           false, now(), now(), '', '', '', '', '2999-12-31'::timestamptz
      from generate_series(1, 200) i
     where not exists (select 1 from profiles where lower(name) = lower('Thug ' || i))
       and not exists (select 1 from auth.users where email = 'thug-' || i || '@bots.cartelwars.invalid');
  else
    -- local auth stub
    insert into auth.users (id, email, raw_user_meta_data)
    select gen_random_uuid(), 'thug-' || i || '@bots.cartelwars.invalid', jsonb_build_object('name', 'Thug ' || i)
      from generate_series(1, 200) i
     where not exists (select 1 from profiles where lower(name) = lower('Thug ' || i))
       and not exists (select 1 from auth.users where email = 'thug-' || i || '@bots.cartelwars.invalid');
  end if;
end $$;

update profiles p set is_bot = true, bot_level = substring(p.name from '^Thug ([0-9]+)$')::int
  from auth.users u
 where u.id = p.id and u.email like 'thug-%@bots.cartelwars.invalid' and p.name ~ '^Thug [0-9]+$';

-- Stats, stash and gear, scaled by level.
do $$
declare b record; s numeric; k int; wq int; pq int; w int; pr int; t int; hmax int;
begin
  for b in select id, bot_level from profiles where is_bot and bot_level is not null loop
    s := (b.bot_level - 1) / 199.0;             -- 0 for Thug 1, 1 for Thug 200
    k := ceil(s * 6)::int;                       -- weapons + protection in the setup (0..6)
    wq := ceil(k / 2.0)::int; pq := k - wq;
    select id into w  from item_defs where category = 'weapon'     and rep_price = 0 order by price offset floor(s * 12)::int limit 1;
    select id into pr from item_defs where category = 'protection' and rep_price = 0 order by price offset floor(s * 8)::int  limit 1;
    t := null;
    if s >= 0.1 then
      select id into t from item_defs where category = 'transport' and rep_price = 0 order by att + def, price offset floor(s * 5)::int limit 1;
    end if;
    hmax := 100 + floor(100 * s)::int;

    delete from setup_items where player_id = b.id;
    delete from inventory where player_id = b.id;
    if wq > 0 then
      insert into inventory (player_id, item_id, qty) values (b.id, w, wq);
      insert into setup_items (player_id, setup, item_id, qty) values (b.id, 'offense', w, wq), (b.id, 'defense', w, wq);
    end if;
    if pq > 0 then
      insert into inventory (player_id, item_id, qty) values (b.id, pr, pq);
      insert into setup_items (player_id, setup, item_id, qty) values (b.id, 'offense', pr, pq), (b.id, 'defense', pr, pq);
    end if;
    if t is not null then
      insert into inventory (player_id, item_id, qty) values (b.id, t, 1);
      insert into setup_items (player_id, setup, item_id, qty) values (b.id, 'offense', t, 1), (b.id, 'defense', t, 1);
    end if;

    update profiles set
      avatar = '💪',
      bio = 'NPC street muscle. The higher the number, the harder they hit back — and the fatter the stash.',
      health_max = hmax, health = hmax, stamina = stamina_max, heat = 0,
      cash = _bot_cash_cap(b.bot_level), bank = 0, diamonds = 0,
      inventory_slots = greatest(6, k + (t is not null)::int),
      -- real players who were on recently list first; thugs list in order after them
      last_seen = now() - interval '1 day' - make_interval(secs => b.bot_level)
    where id = b.id;
  end loop;
end $$;

-- Player tick: lazy regen on three clocks (stamina, health, heat); thugs also refill their stash.
create or replace function _tick(p uuid) returns profiles language plpgsql set search_path = public as $$
declare pr profiles; ticks int; sticks int; hticks int; cap bigint;
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
  if pr.refills_used > 0 and pr.refills_reset_at <= now() - interval '24 hours' then
    pr.refills_used := 0;
  end if;
  if pr.health_bought > 0 and pr.health_bought_at <= now() - interval '24 hours' then
    pr.health_bought := 0; pr.health_bought_at := null;
  end if;
  update profiles set stamina = pr.stamina, health = pr.health, heat = pr.heat, last_tick = pr.last_tick,
         stamina_tick = pr.stamina_tick, health_tick = pr.health_tick, in_hospital = pr.in_hospital,
         jail_until = pr.jail_until, refills_used = pr.refills_used,
         health_bought = pr.health_bought, health_bought_at = pr.health_bought_at, cash = pr.cash
   where id = p;
  return pr;
end $$;

-- Thugs never read an activity feed, so don't write one for them.
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
                         'hospital', coalesce(hosp, false)));
  else
    update activity set updated_at = now(), data = jsonb_build_object(
        'n', coalesce((a.data->>'n')::int, 1) + 1,
        'held', coalesce((a.data->>'held')::int, 0) + held::int,
        'cash_won', coalesce((a.data->>'cash_won')::bigint, 0) + case when held then new.cash_taken else 0 end,
        'cash_lost', coalesce((a.data->>'cash_lost')::bigint, 0) + case when held then 0 else new.cash_taken end,
        'hospital', coalesce((a.data->>'hospital')::boolean, false) or coalesce(hosp, false))
     where id = a.id;
  end if;
  return null;
end $$;
