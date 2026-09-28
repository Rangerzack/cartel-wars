-- Craps: Come and Don't Come, with odds.
--  * Come (only once a point is on) plays like a fresh Pass Line bet: 7 or 11 on the next roll wins 1:1,
--    2/3/12 loses, and any other number moves the bet onto that number (come4 … come10). A come point
--    wins 1:1 when its number rolls again before a 7.
--  * Don't Come is the mirror: 2/3 win, 7/11 lose, 12 pushes, any other number moves the bet behind that
--    number (dcome4 … dcome10), which then wins on a 7 before the number.
--  * Odds: up to 3-4-5x behind a come point at true odds (comeN_odds). As on a real table they're OFF on
--    the come-out roll — a 7 or the number on the come-out settles the flat bet and hands the odds back.
--    Lay odds up to 6x behind a don't come point (dcomeN_odds), always working.
--  * Come and don't come flats are contract bets (they stay until they win or lose); all odds can come down.

create or replace function _craps_view(g craps_games) returns jsonb language plpgsql stable set search_path = public as $$
declare pass bigint := coalesce((g.bets->>'pass')::bigint, 0); dont bigint := coalesce((g.bets->>'dont')::bigint, 0);
        come_max jsonb := '{}'::jsonb; dcome_max jsonb := '{}'::jsonb; k text; v bigint; n int;
begin
  for k, v in select key, value::bigint from jsonb_each_text(coalesce(g.bets, '{}'::jsonb)) loop
    if k ~ '^come[0-9]+$' then n := substring(k from 5)::int; come_max := come_max || jsonb_build_object(n::text, v * _craps_odds_mult(n));
    elsif k ~ '^dcome[0-9]+$' then n := substring(k from 6)::int; dcome_max := dcome_max || jsonb_build_object(n::text, v * 6);
    end if;
  end loop;
  return jsonb_build_object('point', g.point, 'bets', coalesce(g.bets, '{}'::jsonb), 'last', g.last,
    'history', coalesce(g.history, '[]'::jsonb),
    'odds_max', jsonb_build_object(
      'pass_odds', case when g.point is not null then pass * _craps_odds_mult(g.point) else 0 end,
      'dont_odds', case when g.point is not null then dont * 6 else 0 end,
      'come', come_max, 'dcome', dcome_max));
end $$;

create or replace function craps_bet(kind text, amount bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pr profiles; g craps_games; cur bigint; total bigint; line bigint; cap bigint; n int;
begin
  perform _nn(amount, 'amount');
  if not (kind in ('pass','dont','pass_odds','dont_odds','come','dcome','field','place4','place5','place6','place8','place9','place10',
                   'hard4','hard6','hard8','hard10','any7','anycraps')
          or kind ~ '^d?come(4|5|6|8|9|10)_odds$') then perform _fail('Unknown bet'); end if;
  pr := _casino_player(amount);
  insert into craps_games (player_id) values (pr.id) on conflict do nothing;
  select * into g from craps_games where player_id = pr.id for update;
  cur := coalesce((g.bets->>kind)::bigint, 0);
  if kind in ('pass','dont') and g.point is not null then perform _fail('Line bets only before the point is set'); end if;
  if kind in ('come','dcome') and g.point is null then perform _fail('Come bets go down once a point is set — use the Pass Line on the come-out'); end if;

  if kind like '%\_odds' then
    if kind in ('pass_odds', 'dont_odds') then
      if g.point is null then perform _fail('Odds go behind the line once a point is set'); end if;
      line := coalesce((g.bets->>(case when kind = 'pass_odds' then 'pass' else 'dont' end))::bigint, 0);
      if line = 0 then perform _fail(case when kind = 'pass_odds' then 'Put a bet on the Pass Line first' else 'Put a bet on Don''t Pass first' end); end if;
      cap := case when kind = 'pass_odds' then line * _craps_odds_mult(g.point) else line * 6 end;
    else
      n := substring(kind from '([0-9]+)_odds$')::int;
      line := coalesce((g.bets->>(replace(kind, '_odds', '')))::bigint, 0);
      if line = 0 then perform _fail(case when kind like 'dcome%' then format('No Don''t Come bet on the %s', n) else format('No Come bet on the %s', n) end); end if;
      cap := case when kind like 'dcome%' then line * 6 else line * _craps_odds_mult(n) end;
    end if;
    if cur + amount > cap then
      perform _fail(format('Odds max is $%s (%sx your bet)', cap, cap / line));
    end if;
  else
    -- table max counts everything except odds (odds are capped by their flat bet instead)
    total := (select coalesce(sum(value::bigint), 0) from jsonb_each_text(g.bets) where key not like '%\_odds');
    if total + amount > _casino_cfg('max_bet') then perform _fail(format('Table max is $%s in play', _casino_cfg('max_bet'))); end if;
  end if;
  update profiles set cash = cash - amount where id = pr.id;
  update craps_games set bets = g.bets || jsonb_build_object(kind, cur + amount), updated_at = now() where player_id = pr.id
    returning * into g;
  return _craps_view(g);
end $$;

-- One roll with the given dice. Settles every bet on the felt, moves come bets, moves the puck, logs history.
create or replace function _craps_roll(p uuid, d1 integer, d2 integer) returns jsonb
language plpgsql set search_path = public as $$
declare g craps_games; s int := d1 + d2; hard boolean := d1 = d2; pt int; newpoint int; nb jsonb := '{}'::jsonb;
        wagered bigint := 0; payout bigint := 0; log jsonb := '[]'::jsonb; k text; amt bigint; win bigint; keep boolean;
        n int; ev text; stays boolean; move_to text;
begin
  select * into g from craps_games where player_id = p for update;
  if g.player_id is null or (select coalesce(sum(value::bigint), 0) from jsonb_each_text(g.bets)) = 0 then perform _fail('Place a bet first'); end if;
  pt := g.point; newpoint := pt;

  for k, amt in select key, value::bigint from jsonb_each_text(g.bets) loop
    if amt <= 0 then continue; end if;
    win := null; keep := false; stays := false; move_to := null;
    case
      when k = 'pass' then
        if pt is null then
          if s in (7, 11) then win := amt * 2; elsif s in (2, 3, 12) then win := 0; else keep := true; end if;
        else
          if s = pt then win := amt * 2; elsif s = 7 then win := 0; else keep := true; end if;
        end if;
      when k = 'dont' then
        if pt is null then
          if s in (2, 3) then win := amt * 2; elsif s in (7, 11) then win := 0; elsif s = 12 then win := amt; else keep := true; end if;
        else
          if s = 7 then win := amt * 2; elsif s = pt then win := 0; else keep := true; end if;
        end if;
      when k = 'pass_odds' then        -- true odds: 2:1 on 4/10, 3:2 on 5/9, 6:5 on 6/8
        if pt is null then win := amt;  -- can't happen, but never eat a bet
        elsif s = pt then win := amt + case when pt in (4, 10) then amt * 2 when pt in (5, 9) then amt * 3 / 2 else amt * 6 / 5 end;
        elsif s = 7 then win := 0; else keep := true; end if;
      when k = 'dont_odds' then        -- lay: 1:2 on 4/10, 2:3 on 5/9, 5:6 on 6/8
        if pt is null then win := amt;
        elsif s = 7 then win := amt + case when pt in (4, 10) then amt / 2 when pt in (5, 9) then amt * 2 / 3 else amt * 5 / 6 end;
        elsif s = pt then win := 0; else keep := true; end if;
      when k = 'come' then             -- a new come bet: this roll is its come-out
        if s in (7, 11) then win := amt * 2; elsif s in (2, 3, 12) then win := 0; else move_to := 'come' || s; end if;
      when k = 'dcome' then
        if s in (2, 3) then win := amt * 2; elsif s in (7, 11) then win := 0; elsif s = 12 then win := amt; else move_to := 'dcome' || s; end if;
      when k ~ '^come[0-9]+$' then
        n := substring(k from 5)::int;
        if s = n then win := amt * 2; elsif s = 7 then win := 0; else keep := true; end if;
      when k ~ '^come[0-9]+_odds$' then  -- true odds, off on the come-out (returned if it settles then)
        n := substring(k from '^come([0-9]+)_odds$')::int;
        if s = n or s = 7 then
          if pt is null then win := amt;
          elsif s = n then win := amt + case when n in (4, 10) then amt * 2 when n in (5, 9) then amt * 3 / 2 else amt * 6 / 5 end;
          else win := 0; end if;
        else keep := true; end if;
      when k ~ '^dcome[0-9]+$' then
        n := substring(k from 6)::int;
        if s = 7 then win := amt * 2; elsif s = n then win := 0; else keep := true; end if;
      when k ~ '^dcome[0-9]+_odds$' then -- lay odds, always working
        n := substring(k from '^dcome([0-9]+)_odds$')::int;
        if s = 7 then win := amt + case when n in (4, 10) then amt / 2 when n in (5, 9) then amt * 2 / 3 else amt * 5 / 6 end;
        elsif s = n then win := 0; else keep := true; end if;
      when k = 'field' then
        win := case when s in (3, 4, 9, 10, 11) then amt * 2 when s = 2 then amt * 3 when s = 12 then amt * 4 else 0 end;
      when k like 'place%' then
        n := substring(k from 6)::int;
        if pt is null then keep := true;                             -- off on the come-out
        elsif s = n then keep := true; stays := true;               -- paid, and the bet stays up
          win := case when n in (4, 10) then amt * 9 / 5 when n in (5, 9) then amt * 7 / 5 else amt * 7 / 6 end;
        elsif s = 7 then win := 0; else keep := true; end if;
      when k like 'hard%' then
        n := substring(k from 5)::int;
        if pt is null then keep := true;                             -- off on the come-out
        elsif s = n and hard then keep := true; stays := true;
          win := case when n in (4, 10) then amt * 7 else amt * 9 end;
        elsif s = n or s = 7 then win := 0; else keep := true; end if;
      when k = 'any7' then win := case when s = 7 then amt * 5 else 0 end;
      when k = 'anycraps' then win := case when s in (2, 3, 12) then amt * 8 else 0 end;
      else keep := true;
    end case;

    if move_to is not null then
      -- add, don't overwrite: another bet may already sit on that number
      nb := nb || jsonb_build_object(move_to, coalesce((nb->>move_to)::bigint, 0) + amt);
      log := log || jsonb_build_object('bet', k, 'amount', amt, 'result', 'moves', 'to', s);
      continue;
    end if;
    if keep then nb := nb || jsonb_build_object(k, coalesce((nb->>k)::bigint, 0) + amt); end if;
    if stays then
      payout := payout + win;                                          -- winnings only; the bet is still on the felt
      log := log || jsonb_build_object('bet', k, 'amount', amt, 'result', 'win', 'win', win, 'stays', true);
    elsif keep then
      log := log || jsonb_build_object('bet', k, 'amount', amt, 'result', case when pt is null and (k like 'place%' or k like 'hard%') then 'off' else 'stays' end);
    else
      wagered := wagered + amt; payout := payout + win;
      log := log || jsonb_build_object('bet', k, 'amount', amt, 'result', case when win > amt then 'win' when win = amt then 'push' else 'lose' end, 'win', win);
    end if;
  end loop;

  -- the puck follows the dice
  if pt is null then
    if s in (4, 5, 6, 8, 9, 10) then newpoint := s; ev := 'point';
    elsif s in (7, 11) then ev := 'natural'; else ev := 'craps'; end if;
  elsif s = pt then newpoint := null; ev := 'hit';
  elsif s = 7 then newpoint := null; ev := 'seven_out';
  else ev := 'roll'; end if;

  update craps_games set point = newpoint, bets = nb,
         last = jsonb_build_object('dice', jsonb_build_array(d1, d2), 'sum', s, 'log', log, 'event', ev),
         history = (select coalesce(jsonb_agg(x), '[]'::jsonb) from (
                      select x from jsonb_array_elements(jsonb_build_array(jsonb_build_object('dice', jsonb_build_array(d1, d2), 'sum', s, 'event', ev))
                                                         || coalesce(g.history, '[]'::jsonb)) with ordinality t(x, o)
                       order by o limit 20) h),
         updated_at = now()
   where player_id = p;
  if wagered > 0 or payout > 0 then
    perform _casino_settle(p, 'craps', wagered, payout, jsonb_build_object('dice', jsonb_build_array(d1, d2), 'log', log));
  end if;
  return _craps_view((select c from craps_games c where c.player_id = p))
      || jsonb_build_object('dice', jsonb_build_array(d1, d2), 'sum', s, 'event', ev, 'log', log,
                            'wager', wagered, 'payout', payout, 'net', payout - wagered);
end $$;

-- Take back everything that isn't a contract bet. Contract: Pass / Don't Pass once the point is on, and
-- every Come / Don't Come flat (in the box or on a number). All odds, place, hardway, field and props come down.
create or replace function craps_clear() returns jsonb
language plpgsql security definer set search_path = public as $$
declare pr profiles; g craps_games; refund bigint := 0; k text; amt bigint; nb jsonb := '{}'::jsonb;
begin
  pr := _casino_player(null);
  select * into g from craps_games where player_id = pr.id for update;
  if g.player_id is null then return _craps_view(g); end if;
  for k, amt in select key, value::bigint from jsonb_each_text(g.bets) loop
    if (g.point is not null and k in ('pass', 'dont')) or k ~ '^d?come([0-9]+)?$' then nb := nb || jsonb_build_object(k, amt);
    else refund := refund + amt; end if;
  end loop;
  update profiles set cash = cash + refund where id = pr.id;
  update craps_games set bets = nb, updated_at = now() where player_id = pr.id returning * into g;
  return _craps_view(g);
end $$;
