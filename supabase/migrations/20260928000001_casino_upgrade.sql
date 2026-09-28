-- Casino upgrade, reviewed with a pro's eye.
--
-- Craps
--  * Free odds behind the line, paid at true odds (no house edge): 3-4-5x behind Pass (3x on 4/10,
--    4x on 5/9, 5x on 6/8), and lay up to 6x behind Don't Pass.
--  * Place bets on every point number: 4/10 pay 9:5, 5/9 pay 7:5, 6/8 pay 7:6.
--  * Hardways: hard 4 and hard 10 pay 7:1, hard 6 and hard 8 pay 9:1. Lose on the easy way or a 7.
--  * Like a real table, place bets and hardways are OFF on the come-out roll, and a winning place or
--    hardway bet is paid and stays up. The point (the puck) is set by the dice, not by whether you
--    happen to have a line bet.
--  * The last 20 rolls are kept for the roll history strip.
--  * The dice are rolled in craps_roll(); the rules live in _craps_roll(player, d1, d2) so tests can
--    roll loaded dice.
--
-- Blackjack
--  * Split any two cards of the same value, up to four hands. Double after split is allowed.
--    Split aces get one card each and a 21 on a split hand is not a blackjack (pays 1:1).
--  * Hands live in blackjack_games.hands; player / wager are kept in step for older clients.

-- ---------------------------------------------------------------------------
-- Craps
-- ---------------------------------------------------------------------------
alter table craps_games add column if not exists history jsonb not null default '[]'::jsonb;

-- True-odds multiple allowed behind Pass on this point (3-4-5x).
create or replace function _craps_odds_mult(pt integer) returns integer language sql immutable set search_path = public as $$
  select case when pt in (4, 10) then 3 when pt in (5, 9) then 4 when pt in (6, 8) then 5 else 0 end $$;

create or replace function _craps_view(g craps_games) returns jsonb language plpgsql stable set search_path = public as $$
declare pass bigint := coalesce((g.bets->>'pass')::bigint, 0); dont bigint := coalesce((g.bets->>'dont')::bigint, 0);
begin
  return jsonb_build_object('point', g.point, 'bets', coalesce(g.bets, '{}'::jsonb), 'last', g.last,
    'history', coalesce(g.history, '[]'::jsonb),
    'odds_max', jsonb_build_object(
      'pass_odds', case when g.point is not null then pass * _craps_odds_mult(g.point) else 0 end,
      'dont_odds', case when g.point is not null then dont * 6 else 0 end));
end $$;

create or replace function craps_state() returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); g craps_games;
begin
  select * into g from craps_games where player_id = u;
  return _craps_view(g);
end $$;

create or replace function craps_bet(kind text, amount bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pr profiles; g craps_games; cur bigint; total bigint; line bigint; cap bigint;
begin
  perform _nn(amount, 'amount');
  if kind not in ('pass','dont','pass_odds','dont_odds','field','place4','place5','place6','place8','place9','place10',
                  'hard4','hard6','hard8','hard10','any7','anycraps') then perform _fail('Unknown bet'); end if;
  pr := _casino_player(amount);
  insert into craps_games (player_id) values (pr.id) on conflict do nothing;
  select * into g from craps_games where player_id = pr.id for update;
  cur := coalesce((g.bets->>kind)::bigint, 0);
  if kind in ('pass','dont') and g.point is not null then perform _fail('Line bets only before the point is set'); end if;
  if kind in ('pass_odds','dont_odds') then
    if g.point is null then perform _fail('Odds go behind the line once a point is set'); end if;
    line := coalesce((g.bets->>(case when kind = 'pass_odds' then 'pass' else 'dont' end))::bigint, 0);
    if line = 0 then perform _fail(case when kind = 'pass_odds' then 'Put a bet on the Pass Line first' else 'Put a bet on Don''t Pass first' end); end if;
    cap := case when kind = 'pass_odds' then line * _craps_odds_mult(g.point) else line * 6 end;
    if cur + amount > cap then
      perform _fail(format('Odds max is $%s (%sx your line bet)', cap, case when kind = 'pass_odds' then _craps_odds_mult(g.point) else 6 end));
    end if;
  else
    -- table max counts everything except odds (odds are capped by the line bet instead)
    total := (select coalesce(sum(value::bigint), 0) from jsonb_each_text(g.bets) where key not in ('pass_odds', 'dont_odds'));
    if total + amount > _casino_cfg('max_bet') then perform _fail(format('Table max is $%s in play', _casino_cfg('max_bet'))); end if;
  end if;
  update profiles set cash = cash - amount where id = pr.id;
  update craps_games set bets = g.bets || jsonb_build_object(kind, cur + amount), updated_at = now() where player_id = pr.id
    returning * into g;
  return _craps_view(g);
end $$;

-- One roll with the given dice. Settles every bet on the felt, moves the puck, logs history.
create or replace function _craps_roll(p uuid, d1 integer, d2 integer) returns jsonb
language plpgsql set search_path = public as $$
declare g craps_games; s int := d1 + d2; hard boolean := d1 = d2; pt int; newpoint int; nb jsonb := '{}'::jsonb;
        wagered bigint := 0; payout bigint := 0; log jsonb := '[]'::jsonb; k text; amt bigint; win bigint; keep boolean;
        n int; ev text; stays boolean;
begin
  select * into g from craps_games where player_id = p for update;
  if g.player_id is null or (select coalesce(sum(value::bigint), 0) from jsonb_each_text(g.bets)) = 0 then perform _fail('Place a bet first'); end if;
  pt := g.point; newpoint := pt;

  for k, amt in select key, value::bigint from jsonb_each_text(g.bets) loop
    if amt <= 0 then continue; end if;
    win := null; keep := false; stays := false;
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

    if keep then nb := nb || jsonb_build_object(k, amt); end if;
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

create or replace function craps_roll() returns jsonb
language plpgsql security definer set search_path = public as $$
declare pr profiles;
begin
  pr := _casino_player(null);
  return _craps_roll(pr.id, 1 + floor(random() * 6)::int, 1 + floor(random() * 6)::int);
end $$;

-- Take back everything that isn't a contract bet: Pass and Don't Pass stay once the point is on; odds,
-- place, hardway, field and prop bets can always come down.
create or replace function craps_clear() returns jsonb
language plpgsql security definer set search_path = public as $$
declare pr profiles; g craps_games; refund bigint := 0; k text; amt bigint; nb jsonb := '{}'::jsonb;
begin
  pr := _casino_player(null);
  select * into g from craps_games where player_id = pr.id for update;
  if g.player_id is null then return _craps_view(g); end if;
  for k, amt in select key, value::bigint from jsonb_each_text(g.bets) loop
    if g.point is not null and k in ('pass', 'dont') then nb := nb || jsonb_build_object(k, amt); else refund := refund + amt; end if;
  end loop;
  update profiles set cash = cash + refund where id = pr.id;
  update craps_games set bets = nb, updated_at = now() where player_id = pr.id returning * into g;
  return _craps_view(g);
end $$;

-- ---------------------------------------------------------------------------
-- Blackjack with splits
-- ---------------------------------------------------------------------------
alter table blackjack_games add column if not exists hands  jsonb;
alter table blackjack_games add column if not exists active integer not null default 0;
update blackjack_games
   set hands = jsonb_build_array(jsonb_build_object('cards', to_jsonb(player), 'bet', wager, 'doubled', false,
                                                    'split', false, 'aces', false, 'done', status = 'done')),
       active = 0
 where hands is null;

create or replace function _bj_cards(h jsonb) returns integer[] language sql immutable set search_path = public as $$
  select coalesce(array_agg(x::int order by o), '{}') from jsonb_array_elements_text(h->'cards') with ordinality t(x, o) $$;

-- Blackjack value of a card (2..11), for split checks.
create or replace function _bj_card_value(c integer) returns integer language sql immutable set search_path = public as $$
  select case when c / 4 = 12 then 11 when c / 4 >= 8 then 10 else c / 4 + 2 end $$;

create or replace function _bj_view(g blackjack_games, reveal boolean) returns jsonb language plpgsql stable set search_path = public as $$
declare dv record; hv record; h jsonb; i int := 0; out_hands jsonb := '[]'::jsonb; cards int[]; cur jsonb; cur_cards int[];
        total_bet bigint := 0; can_double boolean := false; can_split boolean := false; n int;
begin
  n := jsonb_array_length(g.hands);
  for h in select value from jsonb_array_elements(g.hands) loop
    cards := _bj_cards(h);
    select * into hv from _bj_value(cards);
    total_bet := total_bet + (h->>'bet')::bigint;
    out_hands := out_hands || jsonb_build_object(
      'cards', (select coalesce(jsonb_agg(_card_text(c)), '[]'::jsonb) from unnest(cards) c),
      'total', hv.total, 'soft', hv.soft, 'bet', (h->>'bet')::bigint,
      'doubled', coalesce((h->>'doubled')::boolean, false), 'split', coalesce((h->>'split')::boolean, false),
      'done', coalesce((h->>'done')::boolean, false) or g.status = 'done',
      'active', g.status = 'playing' and i = g.active,
      'result', g.result->'hands'->i);
    i := i + 1;
  end loop;
  cur := g.hands->least(g.active, n - 1);
  cur_cards := _bj_cards(cur);
  select * into hv from _bj_value(cur_cards);
  if g.status = 'playing' and array_length(cur_cards, 1) = 2 and not coalesce((cur->>'aces')::boolean, false) then
    can_double := true;
    can_split := n < 4 and _bj_card_value(cur_cards[1]) = _bj_card_value(cur_cards[2]);
  end if;
  select * into dv from _bj_value(case when reveal then g.dealer else g.dealer[1:1] end);
  return jsonb_build_object('status', g.status, 'wager', total_bet,
    'hands', out_hands, 'active', g.active,
    -- the hand being played (older clients read these)
    'player', (select coalesce(jsonb_agg(_card_text(c)), '[]'::jsonb) from unnest(cur_cards) c),
    'player_total', hv.total, 'player_soft', hv.soft,
    'dealer', (select jsonb_agg(_card_text(c)) from unnest(case when reveal then g.dealer else g.dealer[1:1] end) c),
    'dealer_total', dv.total, 'dealer_hidden', not reveal,
    'can_double', can_double, 'can_split', can_split,
    'result', g.result);
end $$;

create or replace function blackjack_state() returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); g blackjack_games;
begin
  select * into g from blackjack_games where player_id = u;
  if g.player_id is null then return jsonb_build_object('status', 'none'); end if;
  return _bj_view(g, g.status = 'done');
end $$;

-- Dealer plays out (unless every hand busted), each hand settles, one ledger line for the round.
create or replace function _bj_finish(g blackjack_games) returns jsonb language plpgsql set search_path = public as $$
declare pv record; dv record; h jsonb; cards int[]; live boolean := false; single boolean; bet bigint;
        total_bet bigint := 0; total_pay bigint := 0; pay bigint; outcome text; results jsonb := '[]'::jsonb;
begin
  single := jsonb_array_length(g.hands) = 1 and not coalesce((g.hands->0->>'split')::boolean, false);
  for h in select value from jsonb_array_elements(g.hands) loop
    select * into pv from _bj_value(_bj_cards(h));
    if pv.total <= 21 then live := true; end if;
  end loop;
  if live then
    loop
      select * into dv from _bj_value(g.dealer);
      exit when dv.total >= 17;
      g.dealer := g.dealer || g.shoe[1]; g.shoe := g.shoe[2:];
    end loop;
  end if;
  select * into dv from _bj_value(g.dealer);

  for h in select value from jsonb_array_elements(g.hands) loop
    cards := _bj_cards(h); bet := (h->>'bet')::bigint;
    select * into pv from _bj_value(cards);
    if pv.total > 21 then outcome := 'bust'; pay := 0;
    elsif single and array_length(cards, 1) = 2 and pv.total = 21 and not (array_length(g.dealer, 1) = 2 and dv.total = 21) then outcome := 'blackjack'; pay := bet * 5 / 2;
    elsif array_length(g.dealer, 1) = 2 and dv.total = 21 and not (single and array_length(cards, 1) = 2 and pv.total = 21) then outcome := 'lose'; pay := 0;
    elsif dv.total > 21 then outcome := 'dealer_bust'; pay := bet * 2;
    elsif pv.total > dv.total then outcome := 'win'; pay := bet * 2;
    elsif pv.total = dv.total then outcome := 'push'; pay := bet;
    else outcome := 'lose'; pay := 0; end if;
    total_bet := total_bet + bet; total_pay := total_pay + pay;
    results := results || jsonb_build_object('outcome', outcome, 'payout', pay, 'net', pay - bet);
  end loop;

  g.status := 'done';
  g.hands := (select jsonb_agg(x || '{"done": true}'::jsonb order by o) from jsonb_array_elements(g.hands) with ordinality t(x, o));
  g.result := jsonb_build_object('outcome', case when jsonb_array_length(results) = 1 then results->0->>'outcome' else 'split' end,
                                 'payout', total_pay, 'net', total_pay - total_bet, 'hands', results);
  update blackjack_games set shoe = g.shoe, dealer = g.dealer, hands = g.hands, status = g.status, result = g.result,
         wager = total_bet, updated_at = now() where player_id = g.player_id;
  perform _casino_settle(g.player_id, 'blackjack', total_bet, total_pay, jsonb_build_object('outcome', g.result->>'outcome',
    'hands', (select jsonb_agg((select jsonb_agg(_card_text(c)) from unnest(_bj_cards(x)) c)) from jsonb_array_elements(g.hands) x),
    'dealer', (select jsonb_agg(_card_text(c)) from unnest(g.dealer) c)));
  return _bj_view(g, true);
end $$;

-- Move to the next hand that still needs playing; a hand dealt 21 stands itself. Finishes the round when none are left.
create or replace function _bj_next(g blackjack_games) returns jsonb language plpgsql set search_path = public as $$
declare n int := jsonb_array_length(g.hands); pv record;
begin
  loop
    if g.active >= n then return _bj_finish(g); end if;
    if not coalesce((g.hands->g.active->>'done')::boolean, false) then
      select * into pv from _bj_value(_bj_cards(g.hands->g.active));
      exit when pv.total < 21;
      g.hands := jsonb_set(g.hands, array[g.active::text, 'done'], 'true');
    end if;
    g.active := g.active + 1;
  end loop;
  update blackjack_games set hands = g.hands, active = g.active, shoe = g.shoe,
         player = _bj_cards(g.hands->0), updated_at = now() where player_id = g.player_id;
  return _bj_view(g, false);
end $$;

create or replace function blackjack_deal(wager bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pr profiles; g blackjack_games; shoe integer[]; pv record; dv record;
begin
  perform _nn(wager, 'wager');
  pr := _casino_player(wager);
  select * into g from blackjack_games where player_id = pr.id for update;
  if g.status = 'playing' then perform _fail('Finish the hand in front of you first'); end if;
  update profiles set cash = cash - wager where id = pr.id;
  shoe := _deck() || _deck() || _deck() || _deck() || _deck() || _deck();
  g.player_id := pr.id; g.shoe := shoe[5:]; g.player := array[shoe[1], shoe[3]]; g.dealer := array[shoe[2], shoe[4]];
  g.wager := wager; g.status := 'playing'; g.result := null; g.updated_at := now(); g.active := 0;
  g.hands := jsonb_build_array(jsonb_build_object('cards', to_jsonb(g.player), 'bet', wager, 'doubled', false,
                                                  'split', false, 'aces', false, 'done', false));
  insert into blackjack_games (player_id, shoe, player, dealer, wager, status, result, updated_at, hands, active)
  values (g.player_id, g.shoe, g.player, g.dealer, g.wager, g.status, g.result, g.updated_at, g.hands, 0)
    on conflict (player_id) do update set shoe = excluded.shoe, player = excluded.player, dealer = excluded.dealer,
      wager = excluded.wager, status = excluded.status, result = null, hands = excluded.hands, active = 0, updated_at = now();
  select * into pv from _bj_value(g.player);
  select * into dv from _bj_value(g.dealer);
  if pv.total = 21 or dv.total = 21 then return _bj_finish(g); end if;   -- naturals settle immediately (the dealer peeks)
  return _bj_view(g, false);
end $$;

create or replace function blackjack_action(action text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pr profiles; g blackjack_games; h jsonb; cards int[]; bet bigint; pv record; a jsonb; b jsonb; aces boolean;
begin
  pr := _casino_player(null);
  select * into g from blackjack_games where player_id = pr.id for update;
  if g.player_id is null or g.status <> 'playing' then perform _fail('No hand in play — deal first'); end if;
  h := g.hands->g.active; cards := _bj_cards(h); bet := (h->>'bet')::bigint;

  if action = 'hit' then
    if coalesce((h->>'aces')::boolean, false) then perform _fail('Split aces get one card each'); end if;
    cards := cards || g.shoe[1]; g.shoe := g.shoe[2:];
    select * into pv from _bj_value(cards);
    g.hands := jsonb_set(g.hands, array[g.active::text], h || jsonb_build_object('cards', to_jsonb(cards), 'done', pv.total >= 21));
  elsif action = 'stand' then
    g.hands := jsonb_set(g.hands, array[g.active::text, 'done'], 'true');
  elsif action = 'double' then
    if array_length(cards, 1) <> 2 then perform _fail('You can only double on your first two cards'); end if;
    if coalesce((h->>'aces')::boolean, false) then perform _fail('Split aces get one card each'); end if;
    if pr.cash < bet then perform _fail('Not enough cash to double'); end if;
    update profiles set cash = cash - bet where id = pr.id;
    cards := cards || g.shoe[1]; g.shoe := g.shoe[2:];
    g.hands := jsonb_set(g.hands, array[g.active::text], h || jsonb_build_object('cards', to_jsonb(cards), 'bet', bet * 2, 'doubled', true, 'done', true));
  elsif action = 'split' then
    if array_length(cards, 1) <> 2 or _bj_card_value(cards[1]) <> _bj_card_value(cards[2]) then perform _fail('You can only split a pair'); end if;
    if coalesce((h->>'aces')::boolean, false) then perform _fail('Split aces can''t be split again'); end if;
    if jsonb_array_length(g.hands) >= 4 then perform _fail('Four hands is the limit'); end if;
    if pr.cash < bet then perform _fail('Not enough cash to split'); end if;
    update profiles set cash = cash - bet where id = pr.id;
    aces := _bj_card_value(cards[1]) = 11;
    a := jsonb_build_object('cards', jsonb_build_array(cards[1], g.shoe[1]), 'bet', bet, 'doubled', false, 'split', true, 'aces', aces, 'done', aces);
    b := jsonb_build_object('cards', jsonb_build_array(cards[2], g.shoe[2]), 'bet', bet, 'doubled', false, 'split', true, 'aces', aces, 'done', aces);
    g.shoe := g.shoe[3:];
    g.hands := (select jsonb_agg(x order by o) from (
                  select x, o::numeric as o from jsonb_array_elements(g.hands) with ordinality t(x, o) where o <> g.active + 1
                  union all select a, g.active + 1
                  union all select b, g.active + 1.5) s);
  else
    perform _fail('Unknown action');
  end if;
  return _bj_next(g);
end $$;

-- Grants: _craps_roll and the _bj_* helpers stay private; the RPCs keep their grants from create or replace.
do $$ declare f record; begin
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('_craps_roll', '_craps_view', '_craps_odds_mult', '_bj_cards', '_bj_card_value', '_bj_next') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
end $$;
