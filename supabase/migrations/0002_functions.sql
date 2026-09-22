-- Cartel Wars — game logic (RPCs)
-- Every function runs as SECURITY DEFINER and validates auth.uid() itself.

set check_function_bodies = on;

-- ---------------------------------------------------------------------------
-- Helpers
-- ---------------------------------------------------------------------------
create or replace function _uid() returns uuid language plpgsql stable as $$
declare u uuid := auth.uid();
begin
  if u is null then raise exception 'Not signed in'; end if;
  return u;
end $$;

create or replace function _fail(msg text) returns void language plpgsql as $$
begin raise exception '%', msg using errcode = 'P0001'; end $$;

-- Reject NULL arguments up front so `null <= 0` style guards can't be skipped.
create or replace function _nn(v anyelement, what text) returns void language plpgsql immutable as $$
begin if v is null then raise exception 'Missing %', what using errcode = 'P0001'; end if; end $$;

create or replace function _rand_between(lo integer, hi integer) returns integer
language sql volatile as $$ select lo + floor(random() * (hi - lo + 1))::integer $$;

-- Tunables -----------------------------------------------------------------
create or replace function _cfg(key text) returns numeric language sql immutable as $$
  select case key
    when 'regen_minutes'      then 10     -- every 10 min: +2 stamina, +2 health, -1 heat
    when 'heat_yellow'        then 40
    when 'heat_red'           then 75
    when 'jail_minutes'       then 120
    when 'bail_base'          then 2000
    when 'bail_per_minute'    then 50
    when 'bribe_per_heat'     then 40
    when 'hospital_per_point' then 40
    when 'refill_diamonds'    then 6
    when 'hustler_price'      then 400
    when 'hustler_hours'      then 4
    when 'listing_min'        then 25
    when 'listing_max'        then 1000
    when 'crew_max'           then 12
    when 'immunity_hours'     then 48
    when 'starter_cash'       then 10000
    when 'starter_diamonds'   then 25
    when 'extra_grow_diamonds' then 20
    when 'crew_fight_stamina' then 5
    when 'crew_fight_cooldown_min' then 60
    when 'crew_fight_stake_pct' then 5
    else 0 end $$;

-- Street prices random-walk whenever read, at most every 10 minutes.
create or replace function _refresh_prices() returns void language plpgsql as $$
begin
  update street_prices sp
     set price = greatest((c.base_price * 0.65)::int,
                 least((c.base_price * 1.35)::int,
                       round(sp.price * (1 + (random() - 0.5) * 0.12))::int)),
         updated_at = now()
    from commodities c
   where c.code = sp.commodity and sp.updated_at < now() - interval '10 minutes';
end $$;

-- Put product back in a player's storage, respecting the cap. Overflow stays on the listing row
-- (status 'returned') so the player can reclaim it once they have room.
create or replace function _return_product(p uuid, com text, n integer, listing uuid, final listing_status) returns integer
language plpgsql as $$
declare cap int; used int; fit int;
begin
  select storage_cap into cap from profiles where id = p for update;
  select coalesce(sum(qty), 0) into used from storage where player_id = p;
  fit := greatest(0, least(n, cap - used));
  if fit > 0 then
    insert into storage as st (player_id, commodity, qty) values (p, com, fit)
      on conflict (player_id, commodity) do update set qty = st.qty + excluded.qty;
  end if;
  if fit = n then update listings set status = final, qty = 0 where id = listing;
  else update listings set status = 'returned', qty = n - fit where id = listing; end if;
  return fit;
end $$;

-- World tick: expire listings, pay hoods. Cheap; called from get_me.
create or replace function _tick_world() returns void language plpgsql as $$
declare l record; h record; periods int; income bigint; cartel uuid;
begin
  -- expired listings go back to storage; whatever doesn't fit waits in a 'returned' holding listing
  for l in select * from listings where status = 'open' and expires_at <= now() for update skip locked loop
    perform _return_product(l.seller_id, l.commodity, l.qty, l.id, 'expired');
  end loop;

  for h in select * from hoods where last_payout_at + interval '24 hours' <= now() for update skip locked loop
    periods := floor(extract(epoch from now() - h.last_payout_at) / 86400)::int;
    if h.owner_crew_id is not null then
      income := h.daily_income::bigint * periods;
      select cartel_id into cartel from crews where id = h.owner_crew_id;
      if cartel is null then
        update crews set bank = bank + income where id = h.owner_crew_id;
      else
        update crews set bank = bank + (income * 0.8)::bigint where id = h.owner_crew_id;
        update cartels set bank = bank + (income * 0.2)::bigint where id = cartel;
      end if;
    end if;
    update hoods set last_payout_at = last_payout_at + (periods * interval '24 hours') where id = h.id;
  end loop;
end $$;

-- Player tick: lazy regen. Locks the row; returns the fresh profile.
create or replace function _tick(p uuid) returns profiles language plpgsql as $$
declare pr profiles; ticks int; step interval := make_interval(mins => _cfg('regen_minutes')::int);
begin
  select * into pr from profiles where id = p for update;
  if pr.id is null then raise exception 'No such player'; end if;
  ticks := floor(extract(epoch from now() - pr.last_tick) / extract(epoch from step))::int;
  if ticks > 0 then
    pr.stamina   := least(pr.stamina_max, pr.stamina + 2 * ticks);
    pr.health    := least(pr.health_max,  pr.health  + 2 * ticks);
    pr.heat      := greatest(0, pr.heat - ticks);
    pr.last_tick := pr.last_tick + ticks * step;
  end if;
  if pr.jail_until is not null and pr.jail_until <= now() then pr.jail_until := null; end if;
  if pr.refills_used > 0 and pr.refills_reset_at <= now() - interval '24 hours' then
    pr.refills_used := 0;
  end if;
  update profiles set stamina = pr.stamina, health = pr.health, heat = pr.heat, last_tick = pr.last_tick,
         jail_until = pr.jail_until, refills_used = pr.refills_used
   where id = p;
  return pr;
end $$;

create or replace function _jailed(pr profiles) returns boolean language sql stable as $$
  select pr.jail_until is not null and pr.jail_until > now() $$;

create or replace function _hospital(pr profiles) returns boolean language sql stable as $$
  select pr.health <= 19 $$;

-- Attack / defense from a setup. Barehands baseline 20/20. Best single transport counts.
create or replace function _power(p uuid, s setup_kind, out att int, out def int, out combo boolean)
language plpgsql stable as $$
begin
  select 20 + coalesce(sum(case when d.category <> 'transport' then d.att * si.qty end), 0)
            + coalesce(max(case when d.category = 'transport' then d.att end), 0),
         20 + coalesce(sum(case when d.category <> 'transport' then d.def * si.qty end), 0)
            + coalesce(max(case when d.category = 'transport' then d.def end), 0),
         exists (select 1 from setup_items a join item_defs da on da.id = a.item_id
                 join setup_items b on b.player_id = a.player_id and b.setup = a.setup
                 join item_defs db on db.id = b.item_id
                 where a.player_id = p and a.setup = s and a.qty > 0 and b.qty > 0
                   and da.category in ('weapon','jail_weapon') and db.category = 'protection'
                   and da.combo_tag is not null and da.combo_tag = db.combo_tag)
    into att, def, combo
    from setup_items si join item_defs d on d.id = si.item_id
   where si.player_id = p and si.setup = s and si.qty > 0;
  att := coalesce(att, 20); def := coalesce(def, 20); combo := coalesce(combo, false);
end $$;

create or replace function _bust_roll(pr profiles) returns profiles language plpgsql as $$
begin
  if _jailed(pr) then return pr; end if;
  if pr.heat >= _cfg('heat_red') and random() < (pr.heat - _cfg('heat_red') + 1) / 40.0 then
    pr.jail_until := now() + make_interval(mins => _cfg('jail_minutes')::int);
    pr.heat := _cfg('heat_yellow')::int;
  end if;
  return pr;
end $$;

create or replace function _award_milestones(p uuid) returns void language plpgsql as $$
declare pr profiles; m record;
begin
  select * into pr from profiles where id = p;
  for m in select * from (values ('actions_50',50,5),('actions_100',100,10),('actions_500',500,25),
                                ('actions_1000',1000,50),('actions_5000',5000,100)) v(key, n, reward) loop
    if pr.actions_done >= m.n and not exists (select 1 from milestones where player_id = p and key = m.key) then
      insert into milestones (player_id, key) values (p, m.key);
      update profiles set diamonds = diamonds + m.reward where id = p;
    end if;
  end loop;
  for m in select * from (values ('wins_10',10,5),('wins_100',100,20),('wins_1000',1000,75)) v(key, n, reward) loop
    if pr.fights_won >= m.n and not exists (select 1 from milestones where player_id = p and key = m.key) then
      insert into milestones (player_id, key) values (p, m.key);
      update profiles set diamonds = diamonds + m.reward where id = p;
    end if;
  end loop;
end $$;

create or replace function _event(p uuid, kind text, amount bigint default 1) returns void language sql as $$
  insert into accolade_events (player_id, kind, amount) values (p, kind, amount) $$;

-- Ribbons a player wears this week = their top-3 finishes last week.
create or replace function _ribbons(p uuid) returns jsonb language sql stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('kind', kind, 'rank', rank) order by rank, kind), '[]'::jsonb)
  from (
    select kind, rank() over (partition by kind order by total desc) as rank, player_id
      from (select kind, player_id, sum(amount) as total from accolade_events
             where created_at >= date_trunc('week', now() at time zone 'utc') at time zone 'utc' - interval '7 days' and created_at < date_trunc('week', now() at time zone 'utc') at time zone 'utc'
             group by kind, player_id) t
  ) r where r.player_id = p and r.rank <= 3 $$;

-- ---------------------------------------------------------------------------
-- Registration
-- ---------------------------------------------------------------------------
create or replace function _create_profile(uid uuid, wanted text) returns profiles
language plpgsql security definer set search_path = public as $$
declare nm text; pr profiles;
begin
  nm := nullif(trim(coalesce(wanted, '')), '');
  if nm is null or char_length(nm) < 3 or char_length(nm) > 20 or exists (select 1 from profiles where lower(name) = lower(nm)) then
    nm := 'player_' || substr(replace(uid::text, '-', ''), 1, 8);
  end if;
  insert into profiles (id, name, cash, diamonds, immune_until)
  values (uid, nm, _cfg('starter_cash')::bigint, _cfg('starter_diamonds')::int,
          now() + make_interval(hours => _cfg('immunity_hours')::int))
  returning * into pr;
  insert into storage (player_id, commodity, qty) select uid, code, 0 from commodities;
  return pr;
end $$;

create or replace function handle_new_user() returns trigger
language plpgsql security definer set search_path = public as $$
begin
  perform _create_profile(new.id, new.raw_user_meta_data ->> 'name');
  return new;
end $$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created after insert on auth.users
  for each row execute function handle_new_user();

-- Client-callable fallback (idempotent). Also lets a new player pick a name.
create or replace function ensure_profile(wanted text default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles;
begin
  select * into pr from profiles where id = u;
  if pr.id is null then
    pr := _create_profile(u, wanted);
  elsif wanted is not null and pr.name like 'player\_%' and char_length(trim(wanted)) between 3 and 20
        and not exists (select 1 from profiles where lower(name) = lower(trim(wanted))) then
    update profiles set name = trim(wanted) where id = u;
  end if;
  return get_me();
end $$;

-- ---------------------------------------------------------------------------
-- Read: full private state
-- ---------------------------------------------------------------------------
create or replace function get_me() returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; po record; pd record; pj record;
begin
  perform _refresh_prices();
  perform _tick_world();
  pr := _tick(u);
  update profiles set last_seen = now() where id = u;
  select * into po from _power(u, 'offense');
  select * into pd from _power(u, 'defense');
  select * into pj from _power(u, 'jail');
  return jsonb_build_object(
    'id', pr.id, 'name', pr.name, 'created_at', pr.created_at,
    'cash', pr.cash, 'bank', pr.bank, 'diamonds', pr.diamonds,
    'stamina', pr.stamina, 'stamina_max', pr.stamina_max,
    'health', pr.health, 'health_max', pr.health_max,
    'heat', pr.heat, 'heat_max', pr.heat_max,
    'heat_level', case when pr.heat >= _cfg('heat_red') then 'red' when pr.heat >= _cfg('heat_yellow') then 'yellow' else 'green' end,
    'jailed', _jailed(pr), 'jail_until', pr.jail_until,
    'hospital', _hospital(pr),
    'immune_until', pr.immune_until, 'immune', pr.immune_until > now(),
    'inventory_slots', pr.inventory_slots, 'storage_cap', pr.storage_cap,
    'refills_used', pr.refills_used,
    'actions_done', pr.actions_done, 'fights_won', pr.fights_won, 'fights_lost', pr.fights_lost,
    'market_volume', pr.market_volume, 'imports', pr.imports,
    'next_tick', pr.last_tick + make_interval(mins => _cfg('regen_minutes')::int),
    'power', jsonb_build_object('offense', to_jsonb(po), 'defense', to_jsonb(pd), 'jail', to_jsonb(pj)),
    'crew', (select jsonb_build_object('id', c.id, 'name', c.name, 'emblem', c.emblem, 'capo_id', c.capo_id,
                                       'is_capo', c.capo_id = u, 'cartel_id', c.cartel_id,
                                       'members', (select count(*) from profiles where crew_id = c.id))
             from crews c where c.id = pr.crew_id),
    'cartel', (select jsonb_build_object('id', ca.id, 'name', ca.name, 'don_id', ca.don_id, 'is_don', ca.don_id = u)
               from crews c join cartels ca on ca.id = c.cartel_id where c.id = pr.crew_id),
    'storage', (select coalesce(jsonb_object_agg(commodity, qty), '{}'::jsonb) from storage where player_id = u),
    'storage_used', (select coalesce(sum(qty), 0) from storage where player_id = u),
    'prices', (select jsonb_object_agg(commodity, price) from street_prices),
    'grow_houses', (select coalesce(jsonb_agg(jsonb_build_object(
                      'id', g.id, 'commodity', g.commodity, 'level', g.level, 'running', g.running,
                      'started_at', g.started_at,
                      'rate', c.grow_rate * g.level, 'cap', c.grow_cap * g.level,
                      'produced', least(c.grow_cap * g.level, g.banked + case when g.running
                          then floor(extract(epoch from now() - g.started_at) / 3600 * c.grow_rate * g.level)::int else 0 end),
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
    'transport_capacity', (select coalesce(max(d.capacity), 0) from inventory i join item_defs d on d.id = i.item_id
                           where i.player_id = u and i.qty > 0 and d.category = 'transport'),
    'listings', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'commodity', commodity, 'qty', qty,
                      'unit_price', unit_price, 'expires_at', expires_at, 'held', status = 'returned') order by created_at desc), '[]'::jsonb)
                 from listings where seller_id = u and status in ('open', 'returned')),
    'ribbons', _ribbons(u),
    'server_time', now()
  );
end $$;

-- ---------------------------------------------------------------------------
-- Catalogs (public)
-- ---------------------------------------------------------------------------
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
      'extra_grow_diamonds', _cfg('extra_grow_diamonds'), 'heat_yellow', _cfg('heat_yellow'), 'heat_red', _cfg('heat_red'))
  ) $$;

-- ---------------------------------------------------------------------------
-- Actions
-- ---------------------------------------------------------------------------
create or replace function do_action(action_id integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; a action_defs; pay int; busted boolean := false; crew_n int; was_jailed boolean;
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
    pr.heat := least(pr.heat_max, pr.heat + a.heat_gain);
    pr := _bust_roll(pr);
    busted := _jailed(pr) and not was_jailed;
  end if;

  update profiles set stamina = pr.stamina, cash = pr.cash, heat = pr.heat, jail_until = pr.jail_until,
         actions_done = pr.actions_done where id = u;
  perform _event(u, 'action');
  perform _award_milestones(u);
  return jsonb_build_object('pay', pay, 'busted', busted, 'heat', pr.heat, 'stamina', pr.stamina, 'cash', pr.cash);
end $$;

-- ---------------------------------------------------------------------------
-- Fighting
-- ---------------------------------------------------------------------------
create or replace function attack(target uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); me profiles; them profiles; pa record; pd record;
        base int; sit int; bonus int; dmg_a int; dmg_d int; taken bigint := 0; win boolean; pct numeric;
        sa setup_kind; sd setup_kind; f fights; recent int;
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

  sa := case when _jailed(me) then 'jail' else 'offense' end;
  sd := case when _jailed(them) then 'jail' else 'defense' end;
  select * into pa from _power(u, sa);
  select * into pd from _power(target, sd);

  base  := round(60.0 * pa.att / (pa.att + pd.def));
  sit   := _rand_between(0, 6)
           + case when me.health::numeric / me.health_max > them.health::numeric / them.health_max then 2 else 0 end
           + case when me.heat < them.heat then 1 else 0 end
           + case when me.stamina > them.stamina then 1 else 0 end;
  bonus := case when pa.combo then _rand_between(0, 10) else 0 end - case when pd.combo then _rand_between(0, 10) else 0 end;
  dmg_a := greatest(0, least(80, base + least(10, sit) + bonus));
  dmg_d := greatest(0, round(0.35 * (60.0 * pd.att / (pd.att + pa.def) + _rand_between(0, 10))));

  win := dmg_a > dmg_d;
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
                            'busted', _jailed(me) and sa <> 'jail', 'my_att', pa.att, 'their_def', pd.def);
end $$;

create or replace function get_fights(limit_n integer default 30) returns jsonb
language sql security definer set search_path = public stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'attacker', a.name, 'attacker_id', f.attacker_id,
           'defender', d.name, 'defender_id', f.defender_id, 'attacker_dmg', f.attacker_dmg, 'defender_dmg', f.defender_dmg,
           'cash', f.cash_taken, 'won', f.winner_id = auth.uid(), 'i_attacked', f.attacker_id = auth.uid(), 'at', f.created_at)
           order by f.created_at desc), '[]'::jsonb)
  from (select * from fights where attacker_id = auth.uid() or defender_id = auth.uid()
        order by created_at desc limit limit_n) f
  join profiles a on a.id = f.attacker_id join profiles d on d.id = f.defender_id $$;

-- Public profile for other players
create or replace function get_player(pid uuid) returns jsonb
language plpgsql security definer set search_path = public stable as $$
declare pr profiles;
begin
  perform _uid();
  select * into pr from profiles where id = pid;
  if pr.id is null then perform _fail('No such player'); end if;
  return jsonb_build_object('id', pr.id, 'name', pr.name, 'created_at', pr.created_at,
    'fights', pr.fights_won + pr.fights_lost, 'fights_won', pr.fights_won, 'actions', pr.actions_done,
    'health', pr.health, 'health_max', pr.health_max,
    'heat_level', case when pr.heat >= _cfg('heat_red') then 'red' when pr.heat >= _cfg('heat_yellow') then 'yellow' else 'green' end,
    'jailed', _jailed(pr), 'hospital', _hospital(pr), 'immune', pr.immune_until > now(),
    'last_seen', pr.last_seen, 'ribbons', _ribbons(pr.id),
    'crew', (select jsonb_build_object('id', c.id, 'name', c.name, 'emblem', c.emblem) from crews c where c.id = pr.crew_id),
    'cartel', (select jsonb_build_object('id', ca.id, 'name', ca.name) from crews c join cartels ca on ca.id = c.cartel_id where c.id = pr.crew_id));
end $$;

create or replace function find_players(q text default '', limit_n integer default 40) returns jsonb
language sql security definer set search_path = public stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name,
           'crew', (select jsonb_build_object('name', c.name, 'emblem', c.emblem) from crews c where c.id = p.crew_id),
           'fights', p.fights_won + p.fights_lost, 'fights_won', p.fights_won,
           'hospital', p.health <= 19, 'jailed', p.jail_until is not null and p.jail_until > now(),
           'immune', p.immune_until > now(), 'last_seen', p.last_seen)), '[]'::jsonb)
  from (select * from profiles where id <> auth.uid() and (q = '' or name ilike '%' || q || '%')
        order by last_seen desc limit limit_n) p $$;

create or replace function top_users() returns jsonb
language sql security definer set search_path = public stable as $$
  select jsonb_build_object(
    'fighters', (select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'value', fights_won)) from (select * from profiles order by fights_won desc limit 20) x),
    'hustlers', (select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'value', actions_done)) from (select * from profiles order by actions_done desc limit 20) x),
    'traders',  (select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'value', market_volume)) from (select * from profiles order by market_volume desc limit 20) x),
    'crews',    (select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'emblem', c.emblem, 'value', (select count(*) from blocks where owner_crew_id = c.id)))
                 from (select * from crews order by (select count(*) from blocks where owner_crew_id = crews.id) desc, created_at limit 20) c)) $$;

-- ---------------------------------------------------------------------------
-- Services: hospital, police, refills, upgrades, bank
-- ---------------------------------------------------------------------------
create or replace function hospital_checkout() returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; cost int;
begin
  pr := _tick(u);
  if not _hospital(pr) then perform _fail('You are not in the hospital'); end if;
  cost := (20 - pr.health) * _cfg('hospital_per_point')::int;
  if pr.cash < cost then perform _fail(format('Checkout costs $%s', cost)); end if;
  update profiles set cash = cash - cost, health = 20 where id = u;
  return jsonb_build_object('cost', cost);
end $$;

create or replace function bribe_police(points integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; n int; cost int;
begin
  perform _nn(points, 'amount');
  pr := _tick(u);
  n := least(points, pr.heat);
  if n <= 0 then perform _fail('No heat to bribe away'); end if;
  cost := n * _cfg('bribe_per_heat')::int;
  if pr.cash < cost then perform _fail(format('That bribe costs $%s', cost)); end if;
  update profiles set cash = cash - cost, heat = heat - n where id = u;
  return jsonb_build_object('cost', cost, 'heat', pr.heat - n);
end $$;

create or replace function bail_out() returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; mins int; cost int;
begin
  pr := _tick(u);
  if not _jailed(pr) then perform _fail('You are not in jail'); end if;
  mins := ceil(extract(epoch from pr.jail_until - now()) / 60)::int;
  cost := _cfg('bail_base')::int + mins * _cfg('bail_per_minute')::int;
  if pr.cash < cost then perform _fail(format('Bail costs $%s', cost)); end if;
  update profiles set cash = cash - cost, jail_until = null where id = u;
  return jsonb_build_object('cost', cost);
end $$;

-- kind: stamina | health ; method: diamonds | herb | dust | pills
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
  else
    select * into c from commodities where code = method;
    if c.code is null then perform _fail('Bad refill'); end if;
    units := case when kind = 'stamina' then c.refill_stamina else c.refill_health end;
    select qty into have from storage where player_id = u and commodity = method;
    if coalesce(have, 0) < units then perform _fail(format('Needs %s %s', units, c.name)); end if;
    update storage set qty = qty - units where player_id = u and commodity = method;
    gain := case when pr.refills_used >= 3 then ceil(missing / 2.0) else missing end;
    update profiles set refills_used = refills_used + 1,
           refills_reset_at = case when pr.refills_used = 0 then now() else refills_reset_at end where id = u;
  end if;
  if kind = 'stamina' then update profiles set stamina = stamina + gain where id = u;
  else update profiles set health = health + gain where id = u; end if;
  return jsonb_build_object('gain', gain);
end $$;

-- kind: stamina (+5 / 10💎, max 150) | health (+25 / 10💎, max 500) | slots (+1 / 15💎)
create or replace function upgrade_stat(kind text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; cost int;
begin
  perform _nn(kind, 'upgrade');
  pr := _tick(u);
  cost := case kind when 'stamina' then 10 when 'health' then 10 when 'slots' then 15 else null end;
  if cost is null then perform _fail('Bad upgrade'); end if;
  if pr.diamonds < cost then perform _fail(format('Costs %s diamonds', cost)); end if;
  if kind = 'stamina' then
    if pr.stamina_max >= 150 then perform _fail('Stamina is maxed'); end if;
    update profiles set stamina_max = least(150, stamina_max + 5), stamina = stamina + 5 where id = u;
  elsif kind = 'health' then
    if pr.health_max >= 500 then perform _fail('Health is maxed'); end if;
    update profiles set health_max = least(500, health_max + 25), health = health + 25 where id = u;
  else
    update profiles set inventory_slots = inventory_slots + 1 where id = u;
  end if;
  update profiles set diamonds = diamonds - cost where id = u;
  return jsonb_build_object('cost', cost);
end $$;

create or replace function bank_deposit(amount bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles;
begin
  perform _nn(amount, 'amount');
  pr := _tick(u);
  if amount <= 0 or amount > pr.cash then perform _fail('Invalid amount'); end if;
  update profiles set cash = cash - amount, bank = bank + amount where id = u;
  return jsonb_build_object('bank', pr.bank + amount);
end $$;

create or replace function bank_withdraw(amount bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles;
begin
  perform _nn(amount, 'amount');
  pr := _tick(u);
  if amount <= 0 or amount > pr.bank then perform _fail('Invalid amount'); end if;
  update profiles set cash = cash + amount, bank = bank - amount where id = u;
  return jsonb_build_object('bank', pr.bank - amount);
end $$;

create or replace function send_cash(target uuid, amount bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles;
begin
  perform _nn(amount, 'amount');
  pr := _tick(u);
  if target = u then perform _fail('Cannot send to yourself'); end if;
  if amount <= 0 or amount > pr.cash then perform _fail('Invalid amount'); end if;
  if not exists (select 1 from profiles where id = target) then perform _fail('No such player'); end if;
  update profiles set cash = cash - amount where id = u;
  update profiles set cash = cash + amount where id = target;
  return jsonb_build_object('sent', amount);
end $$;

create or replace function send_diamonds(target uuid, n integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles;
begin
  perform _nn(n, 'amount');
  pr := _tick(u);
  if target = u then perform _fail('Cannot send to yourself'); end if;
  if n <= 0 or n > pr.diamonds then perform _fail('Invalid amount'); end if;
  if not exists (select 1 from profiles where id = target) then perform _fail('No such player'); end if;
  update profiles set diamonds = diamonds - n where id = u;
  update profiles set diamonds = diamonds + n where id = target;
  return jsonb_build_object('sent', n);
end $$;

-- ---------------------------------------------------------------------------
-- Items & setups
-- ---------------------------------------------------------------------------
create or replace function buy_item(item integer, n integer default 1) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; d item_defs; cost bigint;
begin
  perform _nn(n, 'quantity');
  pr := _tick(u);
  select * into d from item_defs where id = item;
  if d.id is null or n <= 0 then perform _fail('Bad item'); end if;
  cost := d.price::bigint * n;
  if pr.cash < cost then perform _fail(format('Costs $%s', cost)); end if;
  update profiles set cash = cash - cost where id = u;
  insert into inventory (player_id, item_id, qty) values (u, item, n)
    on conflict (player_id, item_id) do update set qty = inventory.qty + excluded.qty;
  return jsonb_build_object('cost', cost);
end $$;

-- Sell back at 50%. Cannot sell units that are equipped in any setup.
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
  refund := (d.price / 2)::bigint * n;
  update inventory set qty = qty - n where player_id = u and item_id = item;
  update profiles set cash = cash + refund where id = u;
  return jsonb_build_object('refund', refund);
end $$;

create or replace function equip(s setup_kind, item integer, n integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; d item_defs; have int; slots_used int; cur int;
begin
  perform _nn(n, 'quantity');
  pr := _tick(u);
  select * into d from item_defs where id = item;
  if d.id is null then perform _fail('Bad item'); end if;
  if d.category = 'weapon' and s = 'jail' then perform _fail('Regular weapons are confiscated in jail'); end if;
  if d.category = 'jail_weapon' and s <> 'jail' then perform _fail('Jail weapons only work in the jail setup'); end if;
  select qty into have from inventory where player_id = u and item_id = item;
  select coalesce(qty, 0) into cur from setup_items where player_id = u and setup = s and item_id = item;
  cur := coalesce(cur, 0);
  if n < 0 or n > coalesce(have, 0) then perform _fail('You do not own that many'); end if;
  select coalesce(sum(qty), 0) into slots_used from setup_items where player_id = u and setup = s and item_id <> item;
  if slots_used + n > pr.inventory_slots then perform _fail(format('Only %s slots in this setup', pr.inventory_slots)); end if;
  insert into setup_items (player_id, setup, item_id, qty) values (u, s, item, n)
    on conflict (player_id, setup, item_id) do update set qty = excluded.qty;
  delete from setup_items where player_id = u and qty = 0;
  return jsonb_build_object('setup', s, 'item', item, 'qty', n);
end $$;

-- ---------------------------------------------------------------------------
-- Production
-- ---------------------------------------------------------------------------
create or replace function grow_build(commodity text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; c commodities; owned int; dcost int := 0;
begin
  pr := _tick(u);
  select * into c from commodities where code = grow_build.commodity;
  if c.code is null then perform _fail('Bad commodity'); end if;
  if exists (select 1 from grow_houses where player_id = u and grow_houses.commodity = c.code) then perform _fail('You already run that grow house'); end if;
  select count(*) into owned from grow_houses where player_id = u;
  if owned > 0 then dcost := _cfg('extra_grow_diamonds')::int; end if;
  if pr.cash < c.grow_price then perform _fail(format('Costs $%s', c.grow_price)); end if;
  if pr.diamonds < dcost then perform _fail(format('Extra grow houses cost %s diamonds', dcost)); end if;
  update profiles set cash = cash - c.grow_price, diamonds = diamonds - dcost where id = u;
  insert into grow_houses (player_id, commodity, running, started_at) values (u, c.code, true, now());
  return jsonb_build_object('cost', c.grow_price, 'diamonds', dcost);
end $$;

-- Freezes produced units into `banked`, so start/stop/upgrade don't lose progress.
create or replace function _grow_settle(g grow_houses) returns grow_houses language plpgsql as $$
declare c commodities; rate numeric; units int; cap int;
begin
  select * into c from commodities where code = g.commodity;
  if g.running then
    rate := c.grow_rate * g.level;                       -- units per hour
    cap := c.grow_cap * g.level;
    units := floor(extract(epoch from now() - g.started_at) / 3600 * rate)::int;
    if g.banked + units >= cap then
      g.banked := cap; g.started_at := now();            -- capped: progress beyond the cap is lost anyway
    else
      g.banked := g.banked + units;
      g.started_at := g.started_at + make_interval(secs => units / rate * 3600);   -- keep the fractional unit
    end if;
  end if;
  return g;
end $$;

create or replace function grow_toggle(house uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); g grow_houses;
begin
  perform _tick(u);
  select * into g from grow_houses where id = house and player_id = u for update;
  if g.id is null then perform _fail('No such grow house'); end if;
  g := _grow_settle(g);
  g.running := not g.running;
  g.started_at := case when g.running then now() else null end;
  update grow_houses set banked = g.banked, running = g.running, started_at = g.started_at where id = g.id;
  return jsonb_build_object('running', g.running);
end $$;

create or replace function grow_collect(house uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; g grow_houses; used int; room int; take int;
begin
  pr := _tick(u);
  select * into g from grow_houses where id = house and player_id = u for update;
  if g.id is null then perform _fail('No such grow house'); end if;
  g := _grow_settle(g);
  select coalesce(sum(qty), 0) into used from storage where player_id = u;
  room := pr.storage_cap - used;
  take := least(g.banked, greatest(room, 0));
  if take <= 0 then perform _fail(case when g.banked = 0 then 'Nothing to collect yet' else 'Storage is full' end); end if;
  update storage set qty = qty + take where player_id = u and commodity = g.commodity;
  update grow_houses set banked = g.banked - take, started_at = g.started_at where id = g.id;
  return jsonb_build_object('collected', take, 'left', g.banked - take);
end $$;

create or replace function grow_upgrade(house uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; g grow_houses; c commodities; cost int;
begin
  pr := _tick(u);
  select * into g from grow_houses where id = house and player_id = u for update;
  if g.id is null then perform _fail('No such grow house'); end if;
  select * into c from commodities where code = g.commodity;
  cost := c.grow_price * g.level * 2;
  if pr.cash < cost then perform _fail(format('Upgrade costs $%s', cost)); end if;
  g := _grow_settle(g);
  update profiles set cash = cash - cost where id = u;
  update grow_houses set level = level + 1, banked = g.banked, started_at = g.started_at where id = g.id;
  return jsonb_build_object('cost', cost, 'level', g.level + 1);
end $$;

create or replace function grow_abandon(house uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid();
begin
  delete from grow_houses where id = house and player_id = u;
  if not found then perform _fail('No such grow house'); end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function storage_upgrade() returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; cost int;
begin
  pr := _tick(u);
  cost := pr.storage_cap * 20;
  if pr.cash < cost then perform _fail(format('Storage upgrade costs $%s', cost)); end if;
  update profiles set cash = cash - cost, storage_cap = storage_cap + 250 where id = u;
  return jsonb_build_object('cost', cost, 'storage_cap', pr.storage_cap + 250);
end $$;

-- ---------------------------------------------------------------------------
-- Hustlers
-- ---------------------------------------------------------------------------
create or replace function hire_hustlers(commodity text, n integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; c commodities; have int; units int; cost int; price int; due bigint;
begin
  perform _nn(n, 'count');
  pr := _tick(u);
  perform _refresh_prices();
  select * into c from commodities where code = hire_hustlers.commodity;
  if c.code is null or n <= 0 or n > 100 then perform _fail('Hire between 1 and 100 hustlers'); end if;
  units := c.hustler_units * n;
  cost := _cfg('hustler_price')::int * n;
  select qty into have from storage where player_id = u and storage.commodity = c.code;
  if coalesce(have, 0) < units then perform _fail(format('Needs %s %s in storage', units, c.name)); end if;
  if pr.cash < cost then perform _fail(format('Hiring costs $%s', cost)); end if;
  select sp.price into price from street_prices sp where sp.commodity = c.code;
  due := units::bigint * price;
  update storage set qty = qty - units where player_id = u and storage.commodity = c.code;
  update profiles set cash = cash - cost where id = u;
  insert into hustlers (player_id, commodity, count, units, cash_due, returns_at)
  values (u, c.code, n, units, due, now() + make_interval(hours => _cfg('hustler_hours')::int));
  return jsonb_build_object('units', units, 'cash_due', due, 'cost', cost);
end $$;

create or replace function collect_hustlers() returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); total bigint; units bigint;
begin
  perform _tick(u);
  select coalesce(sum(cash_due), 0), coalesce(sum(hustlers.units), 0) into total, units
    from hustlers where player_id = u and not collected and returns_at <= now();
  if total = 0 then perform _fail('No hustlers are back yet'); end if;
  update hustlers set collected = true where player_id = u and not collected and returns_at <= now();
  update profiles set cash = cash + total, imports = imports + units where id = u;
  perform _event(u, 'import', units);
  return jsonb_build_object('cash', total, 'units', units);
end $$;

-- ---------------------------------------------------------------------------
-- Marketplace
-- ---------------------------------------------------------------------------
create or replace function get_market(commodity text default null) returns jsonb
language sql security definer set search_path = public stable as $$
  select jsonb_build_object(
    'prices', (select jsonb_object_agg(sp.commodity, sp.price) from street_prices sp),
    'listings', (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'commodity', l.commodity, 'qty', l.qty,
                   'unit_price', l.unit_price, 'seller', p.name, 'seller_id', l.seller_id, 'mine', l.seller_id = auth.uid(),
                   'expires_at', l.expires_at) order by l.unit_price, l.created_at), '[]'::jsonb)
                 from listings l join profiles p on p.id = l.seller_id
                 where l.status = 'open' and l.expires_at > now() and (get_market.commodity is null or l.commodity = get_market.commodity))) $$;

create or replace function list_product(commodity text, n integer, unit_price integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; have int; street int; cap int; l listings;
begin
  perform _nn(n, 'quantity'); perform _nn(unit_price, 'price');
  pr := _tick(u);
  perform _refresh_prices();
  if n < _cfg('listing_min') or n > _cfg('listing_max') then
    perform _fail(format('List between %s and %s units', _cfg('listing_min'), _cfg('listing_max'))); end if;
  select price into street from street_prices where street_prices.commodity = list_product.commodity;
  if street is null then perform _fail('Bad commodity'); end if;
  if unit_price <= 0 or unit_price > street then perform _fail(format('Street price is $%s — you cannot list above it', street)); end if;
  select coalesce(max(d.capacity), 0) into cap from inventory i join item_defs d on d.id = i.item_id
   where i.player_id = u and i.qty > 0 and d.category = 'transport';
  if cap < n then perform _fail(format('Your transport carries %s units — buy a bigger vehicle', cap)); end if;
  select qty into have from storage where player_id = u and storage.commodity = list_product.commodity;
  if coalesce(have, 0) < n then perform _fail('Not enough in storage'); end if;
  update storage set qty = qty - n where player_id = u and storage.commodity = list_product.commodity;
  insert into listings (seller_id, commodity, qty, unit_price) values (u, commodity, n, unit_price) returning * into l;
  return jsonb_build_object('id', l.id);
end $$;

create or replace function cancel_listing(listing uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); l listings; fit int;
begin
  perform _tick(u);
  select * into l from listings where id = listing and seller_id = u and status in ('open', 'returned') for update;
  if l.id is null then perform _fail('No such listing'); end if;
  fit := _return_product(u, l.commodity, l.qty, l.id, 'cancelled');
  return jsonb_build_object('returned', fit, 'held', l.qty - fit);
end $$;

create or replace function buy_listing(listing uuid, n integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; l listings; used int; cost bigint;
begin
  perform _nn(n, 'quantity');
  pr := _tick(u);
  select * into l from listings where id = listing and status = 'open' and expires_at > now() for update;
  if l.id is null then perform _fail('That listing is gone'); end if;
  if l.seller_id = u then perform _fail('That is your own listing'); end if;
  if n <= 0 or n > l.qty then perform _fail('Invalid quantity'); end if;
  cost := l.unit_price::bigint * n;
  if pr.cash < cost then perform _fail(format('Costs $%s', cost)); end if;
  select coalesce(sum(qty), 0) into used from storage where player_id = u;
  if used + n > pr.storage_cap then perform _fail('Not enough storage room'); end if;
  update profiles set cash = cash - cost, market_volume = market_volume + cost where id = u;
  update profiles set cash = cash + cost, market_volume = market_volume + cost where id = l.seller_id;
  perform _event(u, 'market', cost); perform _event(l.seller_id, 'market', cost);
  update storage set qty = qty + n where player_id = u and commodity = l.commodity;
  if n = l.qty then update listings set status = 'sold' where id = l.id;
  else update listings set qty = qty - n where id = l.id; end if;
  return jsonb_build_object('cost', cost, 'units', n);
end $$;

-- ---------------------------------------------------------------------------
-- Crews
-- ---------------------------------------------------------------------------
create or replace function crew_create(nm text, emblem text default '🏴', description text default '') returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; c crews;
begin
  pr := _tick(u);
  if pr.crew_id is not null then perform _fail('Leave your crew first'); end if;
  if char_length(trim(nm)) not between 3 and 24 then perform _fail('Crew name must be 3–24 characters'); end if;
  if exists (select 1 from crews where lower(name) = lower(trim(nm))) then perform _fail('That crew name is taken'); end if;
  insert into crews (name, emblem, description, capo_id)
  values (trim(nm), left(coalesce(nullif(emblem, ''), '🏴'), 8), left(coalesce(description, ''), 500), u) returning * into c;
  update profiles set crew_id = c.id where id = u;
  return jsonb_build_object('id', c.id);
end $$;

create or replace function crew_update(emblem text, description text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid();
begin
  update crews c set emblem = left(coalesce(nullif(crew_update.emblem, ''), c.emblem), 8),
                     description = left(coalesce(crew_update.description, ''), 500)
   where c.capo_id = u;
  if not found then perform _fail('Only the Capo can do that'); end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function list_crews(q text default '') returns jsonb
language sql security definer set search_path = public stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'emblem', c.emblem, 'description', c.description,
           'members', (select count(*) from profiles where crew_id = c.id),
           'blocks', (select count(*) from blocks where owner_crew_id = c.id),
           'cartel', (select name from cartels where id = c.cartel_id)) order by c.created_at), '[]'::jsonb)
  from crews c where q = '' or c.name ilike '%' || q || '%' $$;

-- Crew power: sum of every member's setup (jail setup while jailed). Hospitalized members sit out.
create or replace function _crew_power(cid uuid, offense boolean) returns integer language plpgsql stable as $$
declare total int := 0; m profiles; pw record;
begin
  for m in select * from profiles where crew_id = cid loop
    if _hospital(m) then continue; end if;
    select * into pw from _power(m.id, case when _jailed(m) then 'jail'::setup_kind when offense then 'offense' else 'defense' end);
    total := total + case when offense then pw.att else pw.def end;
  end loop;
  return total;
end $$;

create or replace function get_crew(cid uuid) returns jsonb
language plpgsql security definer set search_path = public stable as $$
declare u uuid := _uid(); c crews;
begin
  select * into c from crews where id = cid;
  if c.id is null then perform _fail('No such crew'); end if;
  return jsonb_build_object('id', c.id, 'name', c.name, 'emblem', c.emblem, 'description', c.description,
    'capo_id', c.capo_id, 'is_capo', c.capo_id = u, 'created_at', c.created_at,
    'bank', case when exists (select 1 from profiles where id = u and crew_id = c.id) then c.bank end,
    'cartel', (select jsonb_build_object('id', id, 'name', name, 'don_id', don_id) from cartels where id = c.cartel_id),
    'members', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'fights_won', p.fights_won,
                  'actions', p.actions_done, 'is_capo', p.id = c.capo_id, 'last_seen', p.last_seen) order by p.id = c.capo_id desc, p.name), '[]'::jsonb)
                from profiles p where p.crew_id = c.id),
    'blocks', (select coalesce(jsonb_agg(jsonb_build_object('id', b.id, 'name', b.name, 'hood', h.name, 'island', h.island)), '[]'::jsonb)
               from blocks b join hoods h on h.id = b.hood_id where b.owner_crew_id = c.id),
    'applications', case when c.capo_id = u then
       (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'at', a.created_at)), '[]'::jsonb)
        from crew_applications a join profiles p on p.id = a.player_id where a.crew_id = c.id) end,
    'applied', exists (select 1 from crew_applications where crew_id = c.id and player_id = u),
    'invites', case when c.capo_id = u then
       (select coalesce(jsonb_agg(jsonb_build_object('id', ca.id, 'name', ca.name)), '[]'::jsonb)
        from cartel_invites i join cartels ca on ca.id = i.cartel_id where i.crew_id = c.id) end,
    'power', jsonb_build_object('att', _crew_power(c.id, true), 'def', _crew_power(c.id, false)),
    'fights', (select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'attacker', a.name, 'attacker_id', a.id, 'defender', d.name, 'defender_id', d.id,
                  'won', f.won, 'attack', f.attack_power, 'defense', f.defense_power, 'cash', f.cash_taken, 'at', f.created_at,
                  'we_attacked', f.attacker_crew = c.id) order by f.created_at desc), '[]'::jsonb)
               from (select * from crew_fights where attacker_crew = c.id or defender_crew = c.id order by created_at desc limit 10) f
               join crews a on a.id = f.attacker_crew join crews d on d.id = f.defender_crew),
    'next_fight_at', (select max(created_at) + make_interval(mins => _cfg('crew_fight_cooldown_min')::int) from crew_fights
                      where defender_crew = c.id and attacker_crew = (select crew_id from profiles where id = u)));
end $$;

create or replace function crew_apply(cid uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles;
begin
  pr := _tick(u);
  if pr.crew_id is not null then perform _fail('You are already in a crew'); end if;
  if not exists (select 1 from crews where id = cid) then perform _fail('No such crew'); end if;
  insert into crew_applications (crew_id, player_id) values (cid, u) on conflict do nothing;
  return jsonb_build_object('ok', true);
end $$;

create or replace function crew_withdraw(cid uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  delete from crew_applications where crew_id = cid and player_id = _uid();
  return jsonb_build_object('ok', true);
end $$;

create or replace function crew_decide(pid uuid, accept boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); c crews; n int;
begin
  select * into c from crews where capo_id = u for update;
  if c.id is null then perform _fail('Only the Capo can do that'); end if;
  if not exists (select 1 from crew_applications where crew_id = c.id and player_id = pid) then perform _fail('No such application'); end if;
  delete from crew_applications where crew_id = c.id and player_id = pid;
  if accept then
    select count(*) into n from profiles where crew_id = c.id;
    if n >= _cfg('crew_max') then perform _fail('Crew is full'); end if;
    update profiles set crew_id = c.id where id = pid and crew_id is null;
    if not found then perform _fail('That player already joined another crew'); end if;
    delete from crew_applications where player_id = pid;
  end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function _crew_remove(c crews, pid uuid) returns void language plpgsql as $$
declare successor uuid;
begin
  update profiles set crew_id = null where id = pid;
  if c.capo_id = pid then
    select id into successor from profiles where crew_id = c.id order by created_at limit 1;
    if successor is null then
      -- disband: blocks freed, cartel membership dropped
      update blocks set owner_crew_id = null, taken_at = null where owner_crew_id = c.id;
      update hoods set owner_crew_id = null where owner_crew_id = c.id;
      if c.cartel_id is not null then perform _cartel_drop_crew(c.cartel_id, c.id); end if;
      delete from crews where id = c.id;
    else
      update crews set capo_id = successor where id = c.id;
      if c.cartel_id is not null then update cartels set don_id = successor where id = c.cartel_id and don_id = pid; end if;
    end if;
  end if;
end $$;

create or replace function crew_kick(pid uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); c crews;
begin
  select * into c from crews where capo_id = u;
  if c.id is null then perform _fail('Only the Capo can do that'); end if;
  if pid = u then perform _fail('Use Leave instead'); end if;
  if not exists (select 1 from profiles where id = pid and crew_id = c.id) then perform _fail('Not in your crew'); end if;
  perform _crew_remove(c, pid);
  return jsonb_build_object('ok', true);
end $$;

create or replace function crew_leave() returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); c crews;
begin
  select x.* into c from crews x join profiles p on p.crew_id = x.id where p.id = u;
  if c.id is null then perform _fail('You are not in a crew'); end if;
  perform _crew_remove(c, u);
  return jsonb_build_object('ok', true);
end $$;

create or replace function crew_bank(amount bigint) returns jsonb  -- positive deposits, negative withdraws (Capo)
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; c crews;
begin
  perform _nn(amount, 'amount');
  pr := _tick(u);
  select * into c from crews where id = pr.crew_id for update;
  if c.id is null then perform _fail('You are not in a crew'); end if;
  if amount > 0 then
    if amount > pr.cash then perform _fail('Not enough cash'); end if;
    update profiles set cash = cash - amount where id = u;
    update crews set bank = bank + amount where id = c.id;
  elsif amount < 0 then
    if c.capo_id is distinct from u then perform _fail('Only the Capo can withdraw'); end if;
    if -amount > c.bank then perform _fail('Not enough in the crew bank'); end if;
    update profiles set cash = cash - amount where id = u;
    update crews set bank = bank + amount where id = c.id;
  end if;
  return jsonb_build_object('bank', c.bank + amount);
end $$;

create or replace function crew_fight(target uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; mine crews; theirs crews; atk numeric; def numeric; won boolean; taken bigint := 0;
        last_at timestamptz; cd int := _cfg('crew_fight_cooldown_min')::int; f crew_fights; was_jailed boolean;
begin
  pr := _tick(u);
  was_jailed := _jailed(pr);
  if pr.crew_id is null then perform _fail('You are not in a crew'); end if;
  if _hospital(pr) then perform _fail('You are in the hospital'); end if;
  if pr.stamina < _cfg('crew_fight_stamina') then perform _fail(format('Crew fights cost %s stamina', _cfg('crew_fight_stamina'))); end if;
  if _jailed(pr) then perform _fail('You cannot run a crew fight from jail'); end if;
  if not exists (select 1 from crews where id = target) then perform _fail('No such crew'); end if;
  -- lock both crews in id order to avoid deadlocks between opposing attacks
  if pr.crew_id < target then
    select * into mine from crews where id = pr.crew_id for update; select * into theirs from crews where id = target for update;
  else
    select * into theirs from crews where id = target for update; select * into mine from crews where id = pr.crew_id for update;
  end if;
  if theirs.id = mine.id then perform _fail('That is your own crew'); end if;
  if mine.cartel_id is not null and mine.cartel_id = theirs.cartel_id then perform _fail('You cannot fight a crew in your own cartel'); end if;
  select max(created_at) into last_at from crew_fights where attacker_crew = mine.id and defender_crew = theirs.id;
  if last_at is not null and last_at > now() - make_interval(mins => cd) then
    perform _fail(format('Your crew already hit them recently — try again in %s min', ceil(extract(epoch from last_at + make_interval(mins => cd) - now()) / 60)));
  end if;

  atk := _crew_power(mine.id, true)  * (0.85 + random() * 0.3);
  def := _crew_power(theirs.id, false) * (0.85 + random() * 0.3);
  won := atk > def;
  if won then
    taken := floor(theirs.bank * _cfg('crew_fight_stake_pct') / 100.0);
    update crews set bank = bank - taken where id = theirs.id;
    update crews set bank = bank + taken where id = mine.id;
    update profiles set health = greatest(1, health - _rand_between(10, 25)) where crew_id = theirs.id and health > 19 and immune_until <= now() and id <> u;
    update profiles set health = greatest(1, health - _rand_between(3, 8))   where crew_id = mine.id and health > 19 and immune_until <= now() and id <> u;
  else
    taken := floor(mine.bank * _cfg('crew_fight_stake_pct') / 100.0);
    update crews set bank = bank - taken where id = mine.id;
    update crews set bank = bank + taken where id = theirs.id;
    update profiles set health = greatest(1, health - _rand_between(10, 25)) where crew_id = mine.id and health > 19 and immune_until <= now() and id <> u;
    update profiles set health = greatest(1, health - _rand_between(3, 8))   where crew_id = theirs.id and health > 19 and immune_until <= now() and id <> u;
  end if;
  pr.stamina := pr.stamina - _cfg('crew_fight_stamina')::int;
  pr.heat := least(pr.heat_max, pr.heat + 3);
  pr.health := greatest(1, pr.health - case when won then _rand_between(3, 8) else _rand_between(10, 25) end);
  pr := _bust_roll(pr);
  update profiles set stamina = pr.stamina, heat = pr.heat, jail_until = pr.jail_until, health = pr.health where id = u;
  insert into crew_fights (attacker_crew, defender_crew, started_by, attack_power, defense_power, won, cash_taken)
  values (mine.id, theirs.id, u, round(atk), round(def), won, taken) returning * into f;
  insert into messages (channel, sender_id, sender_name, body)
  values ('crew:' || theirs.id, u, pr.name, format('⚔️ %s %s your crew (%s vs %s)%s', mine.name, case when won then 'hit' else 'was pushed back by' end,
          round(atk), round(def), case when won then format(' — $%s taken from the crew bank', taken) else '' end));
  return jsonb_build_object('won', won, 'attack', round(atk), 'defense', round(def), 'cash', taken, 'busted', _jailed(pr) and not was_jailed);
end $$;

-- ---------------------------------------------------------------------------
-- Cartels
-- ---------------------------------------------------------------------------
create or replace function _cartel_drop_crew(cartel uuid, crew uuid) returns void language plpgsql as $$
declare ca cartels; next_capo uuid;
begin
  update crews set cartel_id = null where id = crew;
  select * into ca from cartels where id = cartel;
  if ca.id is null then return; end if;
  if not exists (select 1 from crews where cartel_id = cartel) then
    delete from cartels where id = cartel;
  elsif ca.don_id in (select capo_id from crews where id = crew) or ca.don_id is null then
    select capo_id into next_capo from crews where cartel_id = cartel order by created_at limit 1;
    update cartels set don_id = next_capo where id = cartel;
  end if;
end $$;

create or replace function cartel_create(nm text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); c crews; ca cartels;
begin
  select * into c from crews where capo_id = u for update;
  if c.id is null then perform _fail('Only a Capo can found a cartel'); end if;
  if c.cartel_id is not null then perform _fail('Your crew is already in a cartel'); end if;
  if char_length(trim(nm)) not between 3 and 24 then perform _fail('Cartel name must be 3–24 characters'); end if;
  if exists (select 1 from cartels where lower(name) = lower(trim(nm))) then perform _fail('That cartel name is taken'); end if;
  insert into cartels (name, don_id) values (trim(nm), u) returning * into ca;
  update crews set cartel_id = ca.id where id = c.id;
  return jsonb_build_object('id', ca.id);
end $$;

create or replace function list_cartels() returns jsonb
language sql security definer set search_path = public stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', ca.id, 'name', ca.name, 'don', (select name from profiles where id = ca.don_id),
           'crews', (select count(*) from crews where cartel_id = ca.id),
           'blocks', (select count(*) from blocks b join crews c on c.id = b.owner_crew_id where c.cartel_id = ca.id)) order by ca.created_at), '[]'::jsonb)
  from cartels ca $$;

create or replace function get_cartel(cid uuid) returns jsonb
language plpgsql security definer set search_path = public stable as $$
declare u uuid := _uid(); ca cartels; member boolean;
begin
  select * into ca from cartels where id = cid;
  if ca.id is null then perform _fail('No such cartel'); end if;
  member := exists (select 1 from profiles p join crews c on c.id = p.crew_id where p.id = u and c.cartel_id = ca.id);
  return jsonb_build_object('id', ca.id, 'name', ca.name, 'don_id', ca.don_id, 'is_don', ca.don_id = u,
    'don', (select name from profiles where id = ca.don_id), 'created_at', ca.created_at,
    'bank', case when member then ca.bank end, 'member', member,
    'crews', (select coalesce(jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'emblem', c.emblem, 'capo_id', c.capo_id,
                'capo', (select name from profiles where id = c.capo_id),
                'members', (select count(*) from profiles where crew_id = c.id),
                'blocks', (select count(*) from blocks where owner_crew_id = c.id)) order by c.created_at), '[]'::jsonb)
              from crews c where c.cartel_id = ca.id));
end $$;

create or replace function cartel_invite(crew uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); ca cartels;
begin
  select * into ca from cartels where don_id = u;
  if ca.id is null then perform _fail('Only the Don can invite crews'); end if;
  if not exists (select 1 from crews where id = crew and cartel_id is null) then perform _fail('That crew is unavailable'); end if;
  insert into cartel_invites (cartel_id, crew_id) values (ca.id, crew) on conflict do nothing;
  return jsonb_build_object('ok', true);
end $$;

create or replace function cartel_accept(cartel uuid, accept boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); c crews;
begin
  select * into c from crews where capo_id = u;
  if c.id is null then perform _fail('Only a Capo can answer cartel invites'); end if;
  if not exists (select 1 from cartel_invites where cartel_id = cartel and crew_id = c.id) then perform _fail('No such invite'); end if;
  delete from cartel_invites where cartel_id = cartel and crew_id = c.id;
  if accept then
    if c.cartel_id is not null then perform _fail('Your crew is already in a cartel'); end if;
    update crews set cartel_id = cartel where id = c.id;
    delete from cartel_invites where crew_id = c.id;
  end if;
  return jsonb_build_object('ok', true);
end $$;

create or replace function cartel_leave() returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); c crews;
begin
  select * into c from crews where capo_id = u;
  if c.id is null or c.cartel_id is null then perform _fail('Your crew is not in a cartel'); end if;
  perform _cartel_drop_crew(c.cartel_id, c.id);
  return jsonb_build_object('ok', true);
end $$;

create or replace function cartel_bank(amount bigint) returns jsonb  -- positive deposits, negative withdraws (Don)
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; car cartels;
begin
  perform _nn(amount, 'amount');
  pr := _tick(u);
  select x.* into car from cartels x join crews c on c.cartel_id = x.id where c.id = pr.crew_id for update of x;
  if car.id is null then perform _fail('You are not in a cartel'); end if;
  if amount > 0 then
    if amount > pr.cash then perform _fail('Not enough cash'); end if;
    update profiles set cash = cash - amount where id = u;
    update cartels set bank = bank + amount where id = car.id;
  elsif amount < 0 then
    if car.don_id is distinct from u then perform _fail('Only the Don can withdraw'); end if;
    if -amount > car.bank then perform _fail('Not enough in the cartel bank'); end if;
    update profiles set cash = cash - amount where id = u;
    update cartels set bank = bank + amount where id = car.id;
  end if;
  return jsonb_build_object('bank', car.bank + amount);
end $$;

-- ---------------------------------------------------------------------------
-- Territory
-- ---------------------------------------------------------------------------
create or replace function get_territory() returns jsonb
language sql security definer set search_path = public stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('island', island, 'hoods', hoods) order by first_id), '[]'::jsonb)
  from (
    select h.island, min(h.id) as first_id, jsonb_agg(jsonb_build_object('id', h.id, 'name', h.name, 'price', h.price, 'daily_income', h.daily_income,
             'base_resistance', h.base_resistance,
             'owner', (select jsonb_build_object('id', c.id, 'name', c.name, 'emblem', c.emblem) from crews c where c.id = h.owner_crew_id),
             'blocks', (select jsonb_agg(jsonb_build_object('id', b.id, 'name', b.name,
                          'owner', (select jsonb_build_object('id', c.id, 'name', c.name, 'emblem', c.emblem) from crews c where c.id = b.owner_crew_id),
                          'mine', b.owner_crew_id is not null and b.owner_crew_id = (select crew_id from profiles where id = auth.uid()),
                          'garrisoned', exists (select 1 from block_garrison where block_id = b.id and qty > 0),
                          'garrison_size', case when b.owner_crew_id = (select crew_id from profiles where id = auth.uid())
                                           then (select coalesce(sum(qty), 0) from block_garrison where block_id = b.id) end,
                          'garrison', case when b.owner_crew_id = (select crew_id from profiles where id = auth.uid())
                                      then (select jsonb_object_agg(code, qty) from block_garrison where block_id = b.id and qty > 0) end,
                          'claim_price', h.price / (select count(*) from blocks where hood_id = h.id)) order by b.id)
                        from blocks b where b.hood_id = h.id)) order by h.id) as hoods
    from hoods h group by h.island) x $$;

create or replace function _hoodlum_price(kind text, owned integer, n integer) returns bigint
language sql stable as $$
  select (select base_price from hoodlum_defs d where d.code = kind)::bigint * n
         * (1 + (owned + n / 2.0) / 2000.0) $$;

create or replace function buy_hoodlums(kind text, n integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; owned int; cost bigint;
begin
  perform _nn(n, 'quantity');
  pr := _tick(u);
  if n < 1 or n > 1000 then perform _fail('Buy between 1 and 1000 per transaction'); end if;
  if not exists (select 1 from hoodlum_defs d where d.code = kind) then perform _fail('Bad hoodlum'); end if;
  select coalesce(ph.qty, 0) into owned from player_hoodlums ph where ph.player_id = u and ph.code = kind;
  cost := _hoodlum_price(kind, coalesce(owned, 0), n);
  if pr.cash < cost then perform _fail(format('Costs $%s', cost)); end if;
  update profiles set cash = cash - cost where id = u;
  insert into player_hoodlums as ph (player_id, code, qty) values (u, kind, n)
    on conflict (player_id, code) do update set qty = ph.qty + excluded.qty;
  return jsonb_build_object('cost', cost);
end $$;

create or replace function station_hoodlums(block integer, kind text, n integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; b blocks; have int;
begin
  perform _nn(n, 'quantity');
  pr := _tick(u);
  select * into b from blocks where id = block for update;
  if b.id is null or pr.crew_id is null or b.owner_crew_id is distinct from pr.crew_id then perform _fail('Your crew does not hold that block'); end if;
  select ph.qty into have from player_hoodlums ph where ph.player_id = u and ph.code = kind;
  if n <= 0 or coalesce(have, 0) < n then perform _fail('Not enough hoodlums'); end if;
  update player_hoodlums ph set qty = ph.qty - n where ph.player_id = u and ph.code = kind;
  insert into block_garrison as bg (block_id, code, qty) values (block, kind, n)
    on conflict (block_id, code) do update set qty = bg.qty + excluded.qty;
  return jsonb_build_object('ok', true);
end $$;

create or replace function withdraw_garrison(block integer, kind text, n integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; b blocks; c crews; have int;
begin
  perform _nn(n, 'quantity');
  pr := _tick(u);
  select * into b from blocks where id = block for update;
  select * into c from crews where id = pr.crew_id;
  if b.id is null or c.id is null or b.owner_crew_id is distinct from c.id or c.capo_id is distinct from u then perform _fail('Only your Capo can withdraw a garrison'); end if;
  select bg.qty into have from block_garrison bg where bg.block_id = block and bg.code = kind;
  if n <= 0 or coalesce(have, 0) < n then perform _fail('Not that many stationed'); end if;
  update block_garrison bg set qty = bg.qty - n where bg.block_id = block and bg.code = kind;
  insert into player_hoodlums as ph (player_id, code, qty) values (u, kind, n)
    on conflict (player_id, code) do update set qty = ph.qty + excluded.qty;
  return jsonb_build_object('ok', true);
end $$;

-- Spend one spy to see a block's garrison.
create or replace function spy_block(block integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); have int; g jsonb; b blocks; h hoods;
begin
  perform _tick(u);
  select * into b from blocks where id = block; select * into h from hoods where id = b.hood_id;
  if b.id is null then perform _fail('No such block'); end if;
  select qty into have from player_hoodlums where player_id = u and code = 'spy';
  if coalesce(have, 0) < 1 then perform _fail('You need a Spy'); end if;
  update player_hoodlums set qty = qty - 1 where player_id = u and code = 'spy';
  select coalesce(jsonb_object_agg(code, qty), '{}'::jsonb) into g from block_garrison where block_id = block and qty > 0;
  return jsonb_build_object('garrison', g, 'resistance',
    h.base_resistance + coalesce((select sum(bg.qty * d.def) from block_garrison bg join hoodlum_defs d on d.code = bg.code where bg.block_id = block), 0));
end $$;

create or replace function _recompute_hood(hid integer) returns void language plpgsql as $$
declare total int; best record;
begin
  select count(*) into total from blocks where hood_id = hid;
  select owner_crew_id, count(*) as n into best from blocks where hood_id = hid and owner_crew_id is not null
   group by owner_crew_id order by n desc limit 1;
  if best.owner_crew_id is not null and best.n * 2 > total then
    update hoods set owner_crew_id = best.owner_crew_id,
           last_payout_at = case when owner_crew_id is distinct from best.owner_crew_id then now() else last_payout_at end
     where id = hid;
  else
    update hoods set owner_crew_id = null, last_payout_at = now() where id = hid;
  end if;
end $$;

-- Attack a block with thugs and mercenaries. Unowned blocks also cost cash to claim.
create or replace function attack_block(block integer, thugs integer, mercs integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; b blocks; h hoods; have_t int; have_m int; atk numeric; res numeric;
        claim int := 0; success boolean; loss_frac numeric; lost_t int; lost_m int; g record; gloss numeric; nblocks int;
begin
  perform _nn(thugs, 'thugs'); perform _nn(mercs, 'mercenaries');
  pr := _tick(u);
  if pr.crew_id is null then perform _fail('Join a crew to fight for territory'); end if;
  if _jailed(pr) then perform _fail('You cannot run a turf war from jail'); end if;
  if thugs < 0 or mercs < 0 or thugs + mercs = 0 then perform _fail('Send at least one hoodlum'); end if;
  select * into b from blocks where id = block for update;
  if b.id is null then perform _fail('No such block'); end if;
  if b.owner_crew_id = pr.crew_id then perform _fail('Your crew already holds that block'); end if;
  select * into h from hoods where id = b.hood_id;
  select coalesce(qty,0) into have_t from player_hoodlums where player_id = u and code = 'thug';
  select coalesce(qty,0) into have_m from player_hoodlums where player_id = u and code = 'mercenary';
  if coalesce(have_t,0) < thugs or coalesce(have_m,0) < mercs then perform _fail('Not enough hoodlums'); end if;
  if b.owner_crew_id is null then
    select count(*) into nblocks from blocks where hood_id = h.id;
    claim := h.price / nblocks;
    if pr.cash < claim then perform _fail(format('Claiming a block here costs $%s', claim)); end if;
  end if;

  if pr.stamina < 3 then perform _fail('A turf war takes 3 stamina'); end if;
  atk := (thugs * 10 + mercs * 60) * (0.9 + random() * 0.2);
  res := h.base_resistance + coalesce((select sum(bg.qty * d.def) from block_garrison bg join hoodlum_defs d on d.code = bg.code where bg.block_id = block), 0);
  if atk < res * 0.25 then perform _fail(format('That force would be laughed off the block — bring at least a quarter of the resistance (~%s)', round(res * 0.25))); end if;
  success := atk > res;
  update profiles set stamina = stamina - 3 where id = u;

  -- attacker losses: proportional to how hard the resistance was, up to 50%
  loss_frac := least(1, res / greatest(atk, 1)) * 0.5;
  lost_t := floor(thugs * loss_frac); lost_m := floor(mercs * loss_frac);
  update player_hoodlums set qty = qty - lost_t where player_id = u and code = 'thug';
  update player_hoodlums set qty = qty - lost_m where player_id = u and code = 'mercenary';

  -- garrison losses (rounded down — a token raid doesn't chip away at a big garrison)
  gloss := least(1, atk / greatest(res, 1)) * 0.5;
  for g in select * from block_garrison where block_id = block loop
    update block_garrison set qty = qty - floor(g.qty * gloss)::int where block_id = block and code = g.code;
  end loop;

  if success then
    delete from block_garrison where block_id = block;
    update blocks set owner_crew_id = pr.crew_id, taken_at = now() where id = block;
    if claim > 0 then update profiles set cash = cash - claim where id = u; end if;
    perform _recompute_hood(h.id);
    perform _event(u, 'turf');
  end if;
  insert into territory_log (block_id, attacker_id, crew_id, success, attack, resistance)
  values (block, u, pr.crew_id, success, round(atk), round(res));
  return jsonb_build_object('success', success, 'attack', round(atk), 'resistance', round(res),
    'lost_thugs', lost_t, 'lost_mercs', lost_m, 'claim_paid', case when success then claim else 0 end);
end $$;

create or replace function get_territory_log(limit_n integer default 30) returns jsonb
language sql security definer set search_path = public stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'block', b.name, 'hood', h.name, 'attacker', p.name,
           'crew', c.name, 'success', l.success, 'attack', l.attack, 'resistance', l.resistance, 'at', l.created_at) order by l.created_at desc), '[]'::jsonb)
  from (select * from territory_log order by created_at desc limit limit_n) l
  join blocks b on b.id = l.block_id join hoods h on h.id = b.hood_id
  left join profiles p on p.id = l.attacker_id left join crews c on c.id = l.crew_id $$;

-- ---------------------------------------------------------------------------
-- Accolades
-- ---------------------------------------------------------------------------
create or replace function _accolade_board(from_ts timestamptz, to_ts timestamptz) returns jsonb language sql stable as $$
  select coalesce(jsonb_object_agg(kind, rows), '{}'::jsonb) from (
    select kind, jsonb_agg(jsonb_build_object('id', player_id, 'name', name, 'value', total) order by total desc) as rows
    from (
      select e.kind, e.player_id, p.name, sum(e.amount) as total,
             row_number() over (partition by e.kind order by sum(e.amount) desc) as rn
        from accolade_events e join profiles p on p.id = e.player_id
       where e.created_at >= from_ts and e.created_at < to_ts
       group by e.kind, e.player_id, p.name
    ) t where rn <= 10 group by kind
  ) b $$;

create or replace function get_accolades() returns jsonb
language sql security definer set search_path = public stable as $$
  select jsonb_build_object(
    'week_start', date_trunc('week', now() at time zone 'utc') at time zone 'utc',
    'week_end', date_trunc('week', now() at time zone 'utc') at time zone 'utc' + interval '7 days',
    'this_week', _accolade_board(date_trunc('week', now() at time zone 'utc') at time zone 'utc', date_trunc('week', now() at time zone 'utc') at time zone 'utc' + interval '7 days'),
    'last_week', _accolade_board(date_trunc('week', now() at time zone 'utc') at time zone 'utc' - interval '7 days', date_trunc('week', now() at time zone 'utc') at time zone 'utc'),
    'mine', _ribbons(auth.uid())) $$;

-- ---------------------------------------------------------------------------
-- Chat
-- ---------------------------------------------------------------------------
create or replace function _can_use_channel(u uuid, channel text) returns boolean language plpgsql stable as $$
declare pr profiles; cartel uuid;
begin
  if channel = 'global' then return true; end if;
  select * into pr from profiles where id = u;
  if channel like 'crew:%' then return pr.crew_id is not null and channel = 'crew:' || pr.crew_id::text; end if;
  if channel like 'cartel:%' then
    select cartel_id into cartel from crews where id = pr.crew_id;
    return cartel is not null and channel = 'cartel:' || cartel::text;
  end if;
  if channel ~ '^dm:[0-9a-f-]{36}:[0-9a-f-]{36}$' then
    declare a uuid := split_part(channel, ':', 2)::uuid; b uuid := split_part(channel, ':', 3)::uuid;
    begin
      return a < b and (a = u or b = u);   -- canonical order, involves the caller, never a self-DM
    exception when others then return false;
    end;
  end if;
  return false;
end $$;

-- Used by the realtime RLS policy on messages (runs as the caller, so it must be definer).
create or replace function can_use_channel(channel text) returns boolean
language sql security definer set search_path = public stable as $$
  select _can_use_channel(auth.uid(), channel) $$;

drop policy if exists messages_read on messages;
create policy messages_read on messages for select to authenticated using (can_use_channel(channel));

create or replace function dm_channel(other uuid) returns text language plpgsql stable as $$
begin
  if other is null or other = auth.uid() then raise exception 'Bad conversation' using errcode = 'P0001'; end if;
  return 'dm:' || least(auth.uid(), other)::text || ':' || greatest(auth.uid(), other)::text;
end $$;

create or replace function send_message(channel text, body text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); nm text; m messages;
begin
  if channel is null or not _can_use_channel(u, channel) then perform _fail('You cannot post there'); end if;
  if char_length(trim(coalesce(body, ''))) = 0 then perform _fail('Say something first'); end if;
  select name into nm from profiles where id = u;
  insert into messages (channel, sender_id, sender_name, body) values (channel, u, nm, left(trim(body), 500)) returning * into m;
  return jsonb_build_object('id', m.id);
end $$;

create or replace function get_messages(channel text, limit_n integer default 50) returns jsonb
language plpgsql security definer set search_path = public stable as $$
declare u uuid := _uid();
begin
  if not _can_use_channel(u, channel) then perform _fail('You cannot read that channel'); end if;
  return (select coalesce(jsonb_agg(to_jsonb(m) order by m.created_at), '[]'::jsonb)
          from (select id, sender_id, sender_name, body, created_at from messages where messages.channel = get_messages.channel
                order by created_at desc limit limit_n) m);
end $$;

create or replace function get_conversations() returns jsonb
language sql security definer set search_path = public stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('channel', x.channel, 'other_id', x.other_id,
           'other', (select name from profiles where id = x.other_id), 'last', x.body, 'at', x.created_at) order by x.created_at desc), '[]'::jsonb)
  from (select distinct on (channel) channel, body, created_at,
               (case when split_part(channel, ':', 2)::uuid = auth.uid() then split_part(channel, ':', 3) else split_part(channel, ':', 2) end)::uuid as other_id
          from messages where channel like 'dm:%' and position(auth.uid()::text in channel) > 0
         order by channel, created_at desc) x $$;

-- ---------------------------------------------------------------------------
-- Account deletion: run leadership succession / disband before the profile goes away
-- ---------------------------------------------------------------------------
create or replace function _before_profile_delete() returns trigger language plpgsql security definer set search_path = public as $$
declare c crews;
begin
  if old.crew_id is not null then
    select * into c from crews where id = old.crew_id for update;
    if c.id is not null then perform _crew_remove(c, old.id); end if;
  end if;
  return old;
end $$;
drop trigger if exists profiles_before_delete on profiles;
create trigger profiles_before_delete before delete on profiles for each row execute function _before_profile_delete();

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
-- Supabase grants EXECUTE on new public functions to anon/authenticated by default; turn that off so
-- anything added in a later migration is private until explicitly granted.
alter default privileges in schema public revoke execute on functions from anon, authenticated, public;

do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if f.proname not like '\_%' and f.proname <> 'handle_new_user' then
      execute format('grant execute on function %s to authenticated', f.sig);
    end if;
  end loop;
end $$;
