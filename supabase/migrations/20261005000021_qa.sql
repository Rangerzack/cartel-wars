-- Phase 6 QA fixes. Nothing here changes how the game plays; each one closes a gap the QA sweeps found.
--
-- 1. Private helpers callable by anyone. 20260921000002_functions revoked EXECUTE from public, anon and authenticated
--    on every function that existed then, and set "alter default privileges in schema public revoke execute on
--    functions from public". Postgres ignores that last part for PUBLIC (the PUBLIC grant on functions is a global
--    default, and a per-schema default can only add to it), so every helper added since (32 of them: the casino,
--    poker, forum, crew ledgers, hospital) was callable through /rest/v1/rpc by anyone, signed in or not. None of them
--    is security definer, so a direct call runs as the caller and row security stops it from reading or changing
--    anything; this is defense in depth, not a hole that was open. From now on scripts/grants-test.sql fails the build
--    when a helper is callable.
-- 2. Lists that took any length: casino_history, get_fights and find_players passed limit_n straight to LIMIT, so one
--    call could ask for every row. Capped at 100 like get_messages and find_fighters. find_players also matched a
--    typed % or _ as a wildcard ("%" listed every player, thugs included); they now match themselves.
-- 3. Roulette took a straight bet on 99, or a dozen 4, and kept the stake (it can never win). An impossible bet is now
--    refused before any money moves, like an unknown bet type (which was checked after the stake was taken; the
--    transaction undid it, but it now fails first).
-- 4. Not enough money said "Invalid amount" (a double tap, or a second tab, hits it). It now says what's short.
-- Bodies are the current ones (20260921000002_functions, 20260922000001_casino, 20261004000012_store,
-- 20261004000013_deletion_history, 20261004000014_find_players); only the marked lines are new.

-- 1 -------------------------------------------------------------------------------------------------------------------
do $$ declare f record; begin
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname like '\_%' loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
end $$;

-- 2 -------------------------------------------------------------------------------------------------------------------
create or replace function casino_history(limit_n integer default 30) returns jsonb
language sql security definer set search_path = public stable as $$
  select jsonb_build_object(
    'net', (select coalesce(sum(payout - wager), 0) from casino_bets where player_id = auth.uid()),
    'recent', (select coalesce(jsonb_agg(jsonb_build_object('game', game, 'wager', wager, 'payout', payout, 'net', payout - wager, 'at', created_at) order by created_at desc), '[]'::jsonb)
               from (select * from casino_bets where player_id = auth.uid() order by created_at desc
                     limit greatest(1, least(coalesce(limit_n, 30), 100))) b)) $$;   -- new: capped

create or replace function get_fights(limit_n integer default 30) returns jsonb
language sql security definer set search_path = public stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'attacker', coalesce(a.name, 'Deleted player'), 'attacker_id', f.attacker_id,
           'defender', coalesce(d.name, 'Deleted player'), 'defender_id', f.defender_id, 'attacker_dmg', f.attacker_dmg, 'defender_dmg', f.defender_dmg,
           'cash', f.cash_taken, 'won', coalesce(f.winner_id = auth.uid(), false), 'i_attacked', coalesce(f.attacker_id = auth.uid(), false),
           'at', f.created_at,
           'attacker_combo', f.attacker_combo, 'defender_combo', f.defender_combo,
           'attacker_combo_bonus', f.attacker_combo_bonus, 'defender_combo_bonus', f.defender_combo_bonus)
           order by f.id desc), '[]'::jsonb)
  from (select * from fights where attacker_id = auth.uid() or defender_id = auth.uid()
        order by id desc limit greatest(1, least(coalesce(limit_n, 30), 100))) f   -- new: capped
  left join profiles a on a.id = f.attacker_id left join profiles d on d.id = f.defender_id $$;

create or replace function find_players(q text default '', limit_n integer default 40) returns jsonb
language sql security definer set search_path = public stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'avatar', p.avatar,
           'crew', (select jsonb_build_object('name', c.name, 'emblem', c.emblem) from crews c where c.id = p.crew_id),
           'fights', p.fights_won + p.fights_lost, 'fights_won', p.fights_won,
           'hospital', p.in_hospital or p.health <= 19, 'jailed', p.jail_until is not null and p.jail_until > now(),
           'immune', p.immune_until > now(), 'last_seen', p.last_seen)), '[]'::jsonb)
  from (select * from profiles where id <> auth.uid()
          -- new: % _ and \ in what was typed match themselves
          and (coalesce(q, '') = '' or name ilike '%' || replace(replace(replace(q, '\', '\\'), '%', '\%'), '_', '\_') || '%')
          and (coalesce(q, '') <> '' or not is_bot)
        order by last_seen desc limit greatest(1, least(coalesce(limit_n, 40), 100))) p $$;   -- new: capped

-- 3 -------------------------------------------------------------------------------------------------------------------
create or replace function roulette_spin(bets jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pr profiles; b jsonb; total bigint := 0; n int; red boolean; payout bigint := 0; win bigint; results jsonb := '[]'::jsonb;
        t text; v int; amt bigint;
begin
  if bets is null or jsonb_typeof(bets) <> 'array' or jsonb_array_length(bets) = 0 then perform _fail('Place a bet first'); end if;
  if jsonb_array_length(bets) > 20 then perform _fail('Too many bets at once'); end if;
  for b in select * from jsonb_array_elements(bets) loop
    amt := (b->>'amount')::bigint;
    if amt is null or amt < _casino_cfg('min_bet') then perform _fail(format('Each bet is at least $%s', _casino_cfg('min_bet'))); end if;
    -- new: the bet has to be one the table takes, checked before the stake comes off
    t := b->>'type'; v := (b->>'value')::int;
    if t is null or t not in ('straight','red','black','odd','even','low','high','dozen','column') then perform _fail('Unknown bet type ' || coalesce(t, '?')); end if;
    if t = 'straight' and (v is null or v not between 0 and 36) then perform _fail('A number bet is on 0 to 36'); end if;
    if t in ('dozen','column') and (v is null or v not between 1 and 3) then perform _fail(format('Pick a %s from 1 to 3', t)); end if;
    total := total + amt;
  end loop;
  if total > _casino_cfg('max_bet') then perform _fail(format('Table max is $%s per spin', _casino_cfg('max_bet'))); end if;
  pr := _casino_player(total);
  update profiles set cash = cash - total where id = pr.id;

  n := floor(random() * 37)::int;
  red := n in (1,3,5,7,9,12,14,16,18,19,21,23,25,27,30,32,34,36);
  for b in select * from jsonb_array_elements(bets) loop
    t := b->>'type'; v := (b->>'value')::int; amt := (b->>'amount')::bigint;
    win := case
      when t = 'straight' and v between 0 and 36 and n = v then amt * 36
      when t = 'red'    and n <> 0 and red      then amt * 2
      when t = 'black'  and n <> 0 and not red  then amt * 2
      when t = 'odd'    and n <> 0 and n % 2 = 1 then amt * 2
      when t = 'even'   and n <> 0 and n % 2 = 0 then amt * 2
      when t = 'low'    and n between 1 and 18  then amt * 2
      when t = 'high'   and n between 19 and 36 then amt * 2
      when t = 'dozen'  and v between 1 and 3 and n <> 0 and (n - 1) / 12 + 1 = v then amt * 3
      when t = 'column' and v between 1 and 3 and n <> 0 and (n - 1) % 3 + 1 = v then amt * 3
      else 0 end;
    payout := payout + win;
    results := results || jsonb_build_object('type', t, 'value', v, 'amount', amt, 'win', win);
  end loop;
  perform _casino_settle(pr.id, 'roulette', total, payout, jsonb_build_object('number', n, 'bets', results));
  return jsonb_build_object('number', n, 'color', case when n = 0 then 'green' when red then 'red' else 'black' end,
                            'bets', results, 'wager', total, 'payout', payout, 'net', payout - total);
end $$;

-- 4 -------------------------------------------------------------------------------------------------------------------
create or replace function bank_deposit(amount bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles;
begin
  perform _nn(amount, 'amount');
  pr := _tick(u);
  if amount <= 0 then perform _fail('Invalid amount'); end if;
  if amount > pr.cash then perform _fail(format('You have $%s on hand', pr.cash)); end if;   -- new
  update profiles set cash = cash - amount, bank = bank + amount where id = u;
  return jsonb_build_object('bank', pr.bank + amount);
end $$;

create or replace function bank_withdraw(amount bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles;
begin
  perform _nn(amount, 'amount');
  pr := _tick(u);
  if amount <= 0 then perform _fail('Invalid amount'); end if;
  if amount > pr.bank then perform _fail(format('You have $%s in the bank', pr.bank)); end if;   -- new
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
  if amount <= 0 then perform _fail('Invalid amount'); end if;
  if amount > pr.cash then perform _fail(format('You have $%s on hand', pr.cash)); end if;   -- new
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
  if n <= 0 then perform _fail('Invalid amount'); end if;
  if n > pr.diamonds then perform _fail(format('You have %s diamonds', pr.diamonds)); end if;   -- new
  if n > pr.diamonds - pr.diamonds_bought_unspent then perform _fail('You can only send diamonds you earned in the game'); end if;
  if not exists (select 1 from profiles where id = target) then perform _fail('No such player'); end if;
  update profiles set diamonds = diamonds - n, diamonds_bought_unspent = diamonds_bought_unspent + n where id = u;
  update profiles set diamonds = diamonds + n where id = target;
  return jsonb_build_object('sent', n);
end $$;

-- `create or replace` keeps each function's grants; the loop covers nothing new but says what's callable
do $$ declare f record; begin
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('casino_history','get_fights','find_players','roulette_spin',
             'bank_deposit','bank_withdraw','send_cash','send_diamonds') loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
