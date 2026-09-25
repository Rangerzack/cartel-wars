-- Producers and Traders.
-- Once a player has earned 100 reputation (lifetime, so spending rep on items doesn't undo it) they must
-- pick a path before running grow houses or sending hustlers again:
--   * Producer: builds, starts and upgrades grow houses. Can't send hustlers.
--   * Trader:   sends hustlers. Can't build, start or upgrade grow houses (their houses stop; anything
--               already grown can still be collected).
-- Both keep the Marketplace, which is where producers sell and traders buy.
-- Hustler trips already on the road still come back. Switching paths later costs diamonds.

alter table profiles add column if not exists rep_earned integer not null default 0;
alter table profiles add column if not exists path text check (path in ('producer', 'trader'));
alter table profiles add column if not exists path_chosen_at timestamptz;
update profiles set rep_earned = greatest(rep_earned, reputation);

-- Lifetime reputation only ever goes up with reputation gains.
create or replace function _track_rep_earned() returns trigger language plpgsql set search_path = public as $$
begin
  if new.reputation > old.reputation then new.rep_earned := new.rep_earned + (new.reputation - old.reputation); end if;
  return new;
end $$;
drop trigger if exists profiles_rep_earned on profiles;
create trigger profiles_rep_earned before update of reputation on profiles
  for each row execute function _track_rep_earned();

-- Fails unless the player may do something that needs `want` ('producer' | 'trader').
create or replace function _need_path(pr profiles, want text) returns void language plpgsql set search_path = public as $$
begin
  if pr.path is null then
    if pr.rep_earned >= _cfg('path_rep') then
      perform _fail(format('You have %s reputation — choose Producer or Trader on the Economy page first', _cfg('path_rep')));
    end if;
  elsif pr.path <> want then
    perform _fail(case want when 'producer' then 'Only Producers run grow houses — switch paths on the Economy page'
                            else 'Only Traders send hustlers — switch paths on the Economy page' end);
  end if;
end $$;

create or replace function choose_path(p text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; cost int := 0; g grow_houses;
begin
  perform _nn(p, 'path');
  pr := _tick(u);
  if p not in ('producer', 'trader') then perform _fail('Pick producer or trader'); end if;
  if pr.rep_earned < _cfg('path_rep') then perform _fail(format('Paths unlock at %s reputation', _cfg('path_rep'))); end if;
  if pr.path = p then perform _fail('You are already on that path'); end if;
  if pr.path is not null then
    cost := _cfg('path_switch_diamonds')::int;
    if pr.diamonds < cost then perform _fail(format('Switching costs %s diamonds', cost)); end if;
  end if;
  update profiles set path = p, path_chosen_at = now(), diamonds = diamonds - cost where id = u;
  if p = 'trader' then
    -- traders don't grow: freeze what's been produced and stop every house
    for g in select * from grow_houses where player_id = u and running for update loop
      g := _grow_settle(g);
      update grow_houses set banked = g.banked, running = false, started_at = null where id = g.id;
    end loop;
  end if;
  return jsonb_build_object('path', p, 'diamonds', cost);
end $$;

create or replace function grow_build(commodity text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; c commodities; owned int; dcost int := 0;
begin
  pr := _tick(u);
  perform _need_path(pr, 'producer');
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

create or replace function grow_toggle(house uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; g grow_houses;
begin
  pr := _tick(u);
  select * into g from grow_houses where id = house and player_id = u for update;
  if g.id is null then perform _fail('No such grow house'); end if;
  if not g.running then perform _need_path(pr, 'producer'); end if;   -- anyone may stop a house
  g := _grow_settle(g);
  g.running := not g.running;
  g.started_at := case when g.running then now() else null end;
  update grow_houses set banked = g.banked, running = g.running, started_at = g.started_at where id = g.id;
  return jsonb_build_object('running', g.running);
end $$;

create or replace function grow_upgrade(house uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; g grow_houses; c commodities; cost int;
begin
  pr := _tick(u);
  perform _need_path(pr, 'producer');
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

create or replace function hire_hustlers(commodity text, n integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; c commodities; have int; units int; cost int; price int; due bigint;
begin
  perform _nn(n, 'count');
  pr := _tick(u);
  perform _need_path(pr, 'trader');
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

do $$ declare f record; begin
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('choose_path') loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
