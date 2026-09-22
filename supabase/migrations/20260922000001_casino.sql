-- Cartel Wars — Casino: slots, roulette, craps, blackjack (vs the house) and live No-Limit Hold'em.
-- Everything is server-side: RNG, dealing, hand evaluation, pots. Clients only call RPCs.

set check_function_bodies = on;

-- ---------------------------------------------------------------------------
-- Schema
-- ---------------------------------------------------------------------------
create table casino_bets (
  id         bigserial primary key,
  player_id  uuid not null references profiles(id) on delete cascade,
  game       text not null,                -- slots | roulette | craps | blackjack | poker
  wager      bigint not null,
  payout     bigint not null,              -- gross amount returned to the player (0 = lost)
  detail     jsonb,
  created_at timestamptz not null default now()
);
create index casino_bets_player_idx on casino_bets(player_id, created_at desc);

create table blackjack_games (
  player_id  uuid primary key references profiles(id) on delete cascade,
  shoe       integer[] not null,
  player     integer[] not null,
  dealer     integer[] not null,
  wager      bigint not null,
  status     text not null,                -- playing | done
  result     jsonb,
  updated_at timestamptz not null default now()
);

create table craps_games (
  player_id  uuid primary key references profiles(id) on delete cascade,
  point      integer,
  bets       jsonb not null default '{}'::jsonb,   -- {pass, dont, field, place6, place8, any7, anycraps}
  last       jsonb,
  updated_at timestamptz not null default now()
);

create table poker_tables (
  id          serial primary key,
  name        text not null,
  small_blind bigint not null,
  big_blind   bigint not null,
  min_buyin   bigint not null,
  max_buyin   bigint not null,
  seats       integer not null default 6
);

create table poker_seats (
  table_id   integer not null references poker_tables(id) on delete cascade,
  seat       integer not null,
  player_id  uuid not null references profiles(id) on delete cascade unique,   -- one table at a time
  stack      bigint not null default 0,
  sitting_out boolean not null default false,
  missed     integer not null default 0,        -- consecutive timeouts
  joined_at  timestamptz not null default now(),
  primary key (table_id, seat)
);

create table poker_hands (
  id           bigserial primary key,
  table_id     integer not null references poker_tables(id) on delete cascade,
  hand_no      integer not null,
  stage        text not null,                     -- preflop | flop | turn | river | done
  deck         integer[] not null,
  board        integer[] not null default '{}',
  pot          bigint not null default 0,         -- chips collected from finished streets
  dealer_seat  integer not null,
  to_act       integer,                           -- seat, null when hand is over
  current_bet  bigint not null default 0,
  min_raise    bigint not null default 0,
  deadline     timestamptz,
  result       jsonb,
  created_at   timestamptz not null default now(),
  finished_at  timestamptz
);
create unique index poker_hands_live_idx on poker_hands(table_id) where finished_at is null;
create index poker_hands_table_idx on poker_hands(table_id, id desc);

create table poker_hand_players (
  hand_id    bigint not null references poker_hands(id) on delete cascade,
  seat       integer not null,
  player_id  uuid not null references profiles(id) on delete cascade,
  hole       integer[] not null,
  street_bet bigint not null default 0,
  total_bet  bigint not null default 0,
  folded     boolean not null default false,
  all_in     boolean not null default false,
  acted      boolean not null default false,
  shown      boolean not null default false,
  primary key (hand_id, seat)
);

-- lock down like everything else
do $$
declare t text;
begin
  for t in select unnest(array['casino_bets','blackjack_games','craps_games','poker_tables','poker_seats','poker_hands','poker_hand_players']) loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $$;

-- table chat channels: 'table:<id>'
alter table messages drop constraint messages_channel_check;
alter table messages add constraint messages_channel_check
  check (channel ~ '^(global|crew:[0-9a-f-]{36}|cartel:[0-9a-f-]{36}|dm:[0-9a-f-]{36}:[0-9a-f-]{36}|table:[0-9]+)$');

-- ---------------------------------------------------------------------------
-- Seed: tables (two per stake)
-- ---------------------------------------------------------------------------
insert into poker_tables (name, small_blind, big_blind, min_buyin, max_buyin) values
  ('Back Room · 1k/2k',      1000,   2000,   80000,    400000),
  ('Back Room · 1k/2k #2',   1000,   2000,   80000,    400000),
  ('Boardwalk · 5k/10k',     5000,   10000,  400000,   2000000),
  ('Boardwalk · 5k/10k #2',  5000,   10000,  400000,   2000000),
  ('Penthouse · 25k/50k',    25000,  50000,  2000000,  10000000),
  ('Penthouse · 25k/50k #2', 25000,  50000,  2000000,  10000000),
  ('The Vault · 250k/500k',  250000, 500000, 20000000, 100000000);

-- ---------------------------------------------------------------------------
-- Shared helpers
-- ---------------------------------------------------------------------------
create or replace function _casino_cfg(key text) returns numeric language sql immutable as $$
  select case key
    when 'min_bet'        then 100
    when 'max_bet'        then 500000
    when 'big_win'        then 10000     -- wins above this add heat
    when 'big_win_heat'   then 2
    when 'poker_clock_s'  then 30
    when 'poker_pause_s'  then 6         -- show the result before the next hand
    when 'poker_rake_pct' then 5
    when 'poker_rake_cap_bb' then 3
    when 'poker_max_missed' then 3
    else 0 end $$;

-- Player must be able to gamble: not in jail, not in hospital, enough cash. Locks the profile row.
create or replace function _casino_player(wager bigint) returns profiles language plpgsql as $$
declare u uuid := _uid(); pr profiles;
begin
  pr := _tick(u);
  if _jailed(pr) then perform _fail('No gambling from a cell'); end if;
  if _hospital(pr) then perform _fail('You are in the hospital'); end if;
  if wager is not null then
    if wager < _casino_cfg('min_bet') or wager > _casino_cfg('max_bet') then
      perform _fail(format('Bets are $%s to $%s', _casino_cfg('min_bet'), _casino_cfg('max_bet'))); end if;
    if pr.cash < wager then perform _fail('Not enough cash on hand'); end if;
  end if;
  return pr;
end $$;

-- Settle a house bet: wager already taken; payout is gross return. Logs, heat, accolade.
create or replace function _casino_settle(p uuid, game text, wager bigint, payout bigint, detail jsonb) returns void language plpgsql as $$
begin
  if payout > 0 then update profiles set cash = cash + payout where id = p; end if;
  if payout - wager >= _casino_cfg('big_win') then
    update profiles set heat = least(heat_max, heat + _casino_cfg('big_win_heat')::int) where id = p;
  end if;
  insert into casino_bets (player_id, game, wager, payout, detail) values (p, game, wager, payout, detail);
  perform _event(p, 'gambler', payout - wager);
end $$;

-- A fresh shuffled deck: cards 0..51, rank = c/4 (0=2 … 12=A), suit = c%4 (♠♥♦♣)
create or replace function _deck() returns integer[] language sql volatile as $$
  select array_agg(c order by random()) from generate_series(0, 51) c $$;

create or replace function _card_text(c integer) returns text language sql immutable as $$
  select (array['2','3','4','5','6','7','8','9','T','J','Q','K','A'])[c / 4 + 1] || (array['s','h','d','c'])[c % 4 + 1] $$;

-- ---------------------------------------------------------------------------
-- Slots: 3 reels, weighted symbols, ~96.6% RTP
-- ---------------------------------------------------------------------------
create or replace function _slot_symbol() returns text language plpgsql volatile as $$
declare syms text[] := array['cherry','lemon','bell','bar','diamond','seven']; ws int[] := array[7,10,8,6,4,2];
        r numeric := random() * 37; acc numeric := 0; i int;
begin
  for i in 1..6 loop
    acc := acc + ws[i];
    if r < acc then return syms[i]; end if;
  end loop;
  return 'seven';
end $$;

create or replace function slots_spin(wager bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pr profiles; reels text[]; mult numeric := 0; cherries int; payout bigint;
begin
  perform _nn(wager, 'wager');
  pr := _casino_player(wager);
  update profiles set cash = cash - wager where id = pr.id;
  reels := array[_slot_symbol(), _slot_symbol(), _slot_symbol()];
  if reels[1] = reels[2] and reels[2] = reels[3] then
    mult := case reels[1] when 'seven' then 100 when 'diamond' then 40 when 'bar' then 20 when 'bell' then 12 when 'lemon' then 6 else 4 end;
  else
    cherries := (select count(*) from unnest(reels) r where r = 'cherry');
    mult := case cherries when 1 then 1 when 2 then 2 else 0 end;
  end if;
  payout := (wager * mult)::bigint;
  perform _casino_settle(pr.id, 'slots', wager, payout, jsonb_build_object('reels', to_jsonb(reels), 'mult', mult));
  return jsonb_build_object('reels', to_jsonb(reels), 'mult', mult, 'payout', payout, 'net', payout - wager);
end $$;

-- ---------------------------------------------------------------------------
-- Roulette (European, single zero). bets: [{"type": "straight"|"red"|"black"|"odd"|"even"|"low"|"high"|"dozen"|"column", "value": n, "amount": n}]
-- ---------------------------------------------------------------------------
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
    if t not in ('straight','red','black','odd','even','low','high','dozen','column') then perform _fail('Unknown bet type ' || coalesce(t, '?')); end if;
    payout := payout + win;
    results := results || jsonb_build_object('type', t, 'value', v, 'amount', amt, 'win', win);
  end loop;
  perform _casino_settle(pr.id, 'roulette', total, payout, jsonb_build_object('number', n, 'bets', results));
  return jsonb_build_object('number', n, 'color', case when n = 0 then 'green' when red then 'red' else 'black' end,
                            'bets', results, 'wager', total, 'payout', payout, 'net', payout - total);
end $$;

-- ---------------------------------------------------------------------------
-- Craps: pass / don't pass / field / place 6 / place 8 / any 7 / any craps
-- ---------------------------------------------------------------------------
create or replace function craps_state() returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); g craps_games;
begin
  select * into g from craps_games where player_id = u;
  return jsonb_build_object('point', g.point, 'bets', coalesce(g.bets, '{}'::jsonb), 'last', g.last);
end $$;

create or replace function craps_bet(kind text, amount bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pr profiles; g craps_games; cur bigint; total bigint;
begin
  perform _nn(amount, 'amount');
  if kind not in ('pass','dont','field','place6','place8','any7','anycraps') then perform _fail('Unknown bet'); end if;
  pr := _casino_player(amount);
  insert into craps_games (player_id) values (pr.id) on conflict do nothing;
  select * into g from craps_games where player_id = pr.id for update;
  if kind in ('pass','dont') and g.point is not null then perform _fail('Line bets only before the point is set'); end if;
  cur := coalesce((g.bets->>kind)::bigint, 0);
  total := (select coalesce(sum(value::bigint), 0) from jsonb_each_text(g.bets));
  if total + amount > _casino_cfg('max_bet') then perform _fail(format('Table max is $%s in play', _casino_cfg('max_bet'))); end if;
  update profiles set cash = cash - amount where id = pr.id;
  update craps_games set bets = g.bets || jsonb_build_object(kind, cur + amount), updated_at = now() where player_id = pr.id;
  return craps_state();
end $$;

create or replace function craps_roll() returns jsonb
language plpgsql security definer set search_path = public as $$
declare pr profiles; g craps_games; d1 int; d2 int; s int; b jsonb; nb jsonb := '{}'::jsonb; wagered bigint := 0; payout bigint := 0;
        log jsonb := '[]'::jsonb; k text; amt bigint; win bigint; keep boolean; newpoint int;
begin
  pr := _casino_player(null);
  select * into g from craps_games where player_id = pr.id for update;
  if g.player_id is null or (select coalesce(sum(value::bigint), 0) from jsonb_each_text(g.bets)) = 0 then perform _fail('Place a bet first'); end if;
  d1 := 1 + floor(random() * 6)::int; d2 := 1 + floor(random() * 6)::int; s := d1 + d2;
  b := g.bets; newpoint := g.point;

  for k, amt in select key, value::bigint from jsonb_each_text(b) loop
    if amt <= 0 then continue; end if;
    win := null; keep := false;
    case k
      when 'pass' then
        if g.point is null then
          if s in (7, 11) then win := amt * 2; elsif s in (2, 3, 12) then win := 0; else keep := true; newpoint := s; end if;
        else
          if s = g.point then win := amt * 2; elsif s = 7 then win := 0; else keep := true; end if;
        end if;
      when 'dont' then
        if g.point is null then
          if s in (2, 3) then win := amt * 2; elsif s in (7, 11) then win := 0; elsif s = 12 then win := amt; else keep := true; newpoint := s; end if;
        else
          if s = 7 then win := amt * 2; elsif s = g.point then win := 0; else keep := true; end if;
        end if;
      when 'field' then
        win := case when s in (3,4,9,10,11) then amt * 2 when s = 2 then amt * 3 when s = 12 then amt * 4 else 0 end;
      when 'place6' then
        if s = 6 then win := amt + amt * 7 / 6; elsif s = 7 then win := 0; else keep := true; end if;
      when 'place8' then
        if s = 8 then win := amt + amt * 7 / 6; elsif s = 7 then win := 0; else keep := true; end if;
      when 'any7' then win := case when s = 7 then amt * 5 else 0 end;
      when 'anycraps' then win := case when s in (2, 3, 12) then amt * 8 else 0 end;
      else keep := true;
    end case;
    if keep then
      nb := nb || jsonb_build_object(k, amt);
      log := log || jsonb_build_object('bet', k, 'amount', amt, 'result', 'stays');
    else
      wagered := wagered + amt; payout := payout + win;
      log := log || jsonb_build_object('bet', k, 'amount', amt, 'result', case when win > amt then 'win' when win = amt then 'push' else 'lose' end, 'win', win);
    end if;
  end loop;
  -- point resolves (hit or seven-out) → back to come-out
  if g.point is not null and (s = 7 or s = g.point) then newpoint := null; end if;

  update craps_games set point = newpoint, bets = nb, last = jsonb_build_object('dice', jsonb_build_array(d1, d2), 'sum', s, 'log', log), updated_at = now()
   where player_id = pr.id;
  if wagered > 0 then
    perform _casino_settle(pr.id, 'craps', wagered, payout, jsonb_build_object('dice', jsonb_build_array(d1, d2), 'log', log));
  end if;
  return jsonb_build_object('dice', jsonb_build_array(d1, d2), 'sum', s, 'point', newpoint, 'bets', nb, 'log', log,
                            'wager', wagered, 'payout', payout, 'net', payout - wagered);
end $$;

create or replace function craps_clear() returns jsonb   -- take back bets that are still on the felt (not allowed once a point is set for line bets)
language plpgsql security definer set search_path = public as $$
declare pr profiles; g craps_games; refund bigint := 0; k text; amt bigint; nb jsonb := '{}'::jsonb;
begin
  pr := _casino_player(null);
  select * into g from craps_games where player_id = pr.id for update;
  if g.player_id is null then return craps_state(); end if;
  for k, amt in select key, value::bigint from jsonb_each_text(g.bets) loop
    if g.point is not null and k in ('pass', 'dont') then nb := nb || jsonb_build_object(k, amt); else refund := refund + amt; end if;
  end loop;
  update profiles set cash = cash + refund where id = pr.id;
  update craps_games set bets = nb, updated_at = now() where player_id = pr.id;
  return craps_state();
end $$;

-- ---------------------------------------------------------------------------
-- Blackjack: 6-deck shoe per hand, dealer stands on soft 17, blackjack pays 3:2, double on any two cards.
-- ---------------------------------------------------------------------------
create or replace function _bj_value(cards integer[], out total int, out soft boolean) language plpgsql immutable as $$
declare c int; r int; aces int := 0;
begin
  total := 0;
  foreach c in array cards loop
    r := c / 4 + 2;                       -- 2..14
    if r = 14 then aces := aces + 1; total := total + 11;
    elsif r >= 10 then total := total + 10;
    else total := total + r; end if;
  end loop;
  while total > 21 and aces > 0 loop total := total - 10; aces := aces - 1; end loop;
  soft := aces > 0;
end $$;

create or replace function _bj_view(g blackjack_games, reveal boolean) returns jsonb language plpgsql stable as $$
declare pv record; dv record;
begin
  select * into pv from _bj_value(g.player);
  select * into dv from _bj_value(case when reveal then g.dealer else g.dealer[1:1] end);
  return jsonb_build_object('status', g.status, 'wager', g.wager,
    'player', (select jsonb_agg(_card_text(c)) from unnest(g.player) c), 'player_total', pv.total, 'player_soft', pv.soft,
    'dealer', (select jsonb_agg(_card_text(c)) from unnest(case when reveal then g.dealer else g.dealer[1:1] end) c),
    'dealer_total', dv.total, 'dealer_hidden', not reveal,
    'can_double', g.status = 'playing' and array_length(g.player, 1) = 2,
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

create or replace function _bj_finish(g blackjack_games) returns jsonb language plpgsql as $$
declare pv record; dv record; payout bigint; outcome text;
begin
  select * into pv from _bj_value(g.player);
  -- dealer plays (stands on all 17s) unless the player already busted
  if pv.total <= 21 then
    loop
      select * into dv from _bj_value(g.dealer);
      exit when dv.total >= 17;
      g.dealer := g.dealer || g.shoe[1]; g.shoe := g.shoe[2:];
    end loop;
  end if;
  select * into dv from _bj_value(g.dealer);
  if pv.total > 21 then outcome := 'bust'; payout := 0;
  elsif array_length(g.player, 1) = 2 and pv.total = 21 and not (array_length(g.dealer, 1) = 2 and dv.total = 21) then outcome := 'blackjack'; payout := g.wager * 5 / 2;
  elsif dv.total > 21 then outcome := 'dealer_bust'; payout := g.wager * 2;
  elsif pv.total > dv.total then outcome := 'win'; payout := g.wager * 2;
  elsif pv.total = dv.total then outcome := 'push'; payout := g.wager;
  else outcome := 'lose'; payout := 0; end if;
  g.status := 'done';
  g.result := jsonb_build_object('outcome', outcome, 'payout', payout, 'net', payout - g.wager);
  update blackjack_games set shoe = g.shoe, dealer = g.dealer, status = g.status, result = g.result, updated_at = now() where player_id = g.player_id;
  perform _casino_settle(g.player_id, 'blackjack', g.wager, payout, jsonb_build_object('outcome', outcome,
    'player', (select jsonb_agg(_card_text(c)) from unnest(g.player) c), 'dealer', (select jsonb_agg(_card_text(c)) from unnest(g.dealer) c)));
  return _bj_view(g, true);
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
  g.wager := wager; g.status := 'playing'; g.result := null; g.updated_at := now();
  insert into blackjack_games (player_id, shoe, player, dealer, wager, status, result, updated_at)
  values (g.player_id, g.shoe, g.player, g.dealer, g.wager, g.status, g.result, g.updated_at)
    on conflict (player_id) do update set shoe = excluded.shoe, player = excluded.player, dealer = excluded.dealer,
      wager = excluded.wager, status = excluded.status, result = null, updated_at = now();
  select * into pv from _bj_value(g.player);
  select * into dv from _bj_value(g.dealer);
  if pv.total = 21 or dv.total = 21 then return _bj_finish(g); end if;   -- naturals settle immediately
  return _bj_view(g, false);
end $$;

create or replace function blackjack_action(action text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pr profiles; g blackjack_games; pv record;
begin
  pr := _casino_player(null);
  select * into g from blackjack_games where player_id = pr.id for update;
  if g.player_id is null or g.status <> 'playing' then perform _fail('No hand in play — deal first'); end if;
  if action = 'hit' then
    g.player := g.player || g.shoe[1]; g.shoe := g.shoe[2:];
    select * into pv from _bj_value(g.player);
    update blackjack_games set player = g.player, shoe = g.shoe, updated_at = now() where player_id = pr.id;
    if pv.total >= 21 then return _bj_finish(g); end if;
    return _bj_view(g, false);
  elsif action = 'double' then
    if array_length(g.player, 1) <> 2 then perform _fail('You can only double on your first two cards'); end if;
    if pr.cash < g.wager then perform _fail('Not enough cash to double'); end if;
    update profiles set cash = cash - g.wager where id = pr.id;
    g.wager := g.wager * 2;
    g.player := g.player || g.shoe[1]; g.shoe := g.shoe[2:];
    update blackjack_games set player = g.player, shoe = g.shoe, wager = g.wager, updated_at = now() where player_id = pr.id;
    return _bj_finish(g);
  elsif action = 'stand' then
    return _bj_finish(g);
  end if;
  perform _fail('Unknown action');
  return null;
end $$;

-- ---------------------------------------------------------------------------
-- Poker: 7-card hand evaluator. Score = category * 15^5 + kickers (base 15), higher wins.
-- Categories: 8 straight flush, 7 quads, 6 full house, 5 flush, 4 straight, 3 trips, 2 two pair, 1 pair, 0 high card
-- ---------------------------------------------------------------------------
create or replace function _straight_high(ranks integer[]) returns integer language plpgsql immutable as $$
declare present boolean[] := array_fill(false, array[15]); r int; run int := 0; hi int;
begin
  foreach r in array ranks loop present[r] := true; end loop;
  if present[14] then present[1] := true; end if;   -- wheel
  for hi in reverse 14..5 loop
    if present[hi] and present[hi-1] and present[hi-2] and present[hi-3] and present[hi-4] then return hi; end if;
  end loop;
  return null;
end $$;

create or replace function _eval7(cards integer[]) returns bigint language plpgsql immutable as $$
declare cnt integer[] := array_fill(0, array[15]); suitcnt integer[] := array_fill(0, array[4]); c int; r int; s int;
        flush_suit int := null; ranks integer[] := '{}'; fr integer[] := '{}'; sh int; quad int := 0; trips int[] := '{}'; pairs int[] := '{}';
        kick int[]; score bigint; i int; k int[];
begin
  foreach c in array cards loop
    r := c / 4 + 2; s := c % 4 + 1;
    cnt[r] := cnt[r] + 1; suitcnt[s] := suitcnt[s] + 1; ranks := ranks || r;
  end loop;
  for s in 1..4 loop if suitcnt[s] >= 5 then flush_suit := s; end if; end loop;
  if flush_suit is not null then
    foreach c in array cards loop if c % 4 + 1 = flush_suit then fr := fr || (c / 4 + 2); end if; end loop;
    sh := _straight_high(fr);
    if sh is not null then return 8 * 759375 + sh * 50625; end if;
  end if;
  for r in reverse 14..2 loop
    if cnt[r] = 4 then quad := r;
    elsif cnt[r] = 3 then trips := trips || r;
    elsif cnt[r] = 2 then pairs := pairs || r; end if;
  end loop;
  -- distinct ranks descending, for kickers
  k := '{}'; for r in reverse 14..2 loop if cnt[r] > 0 then k := k || r; end if; end loop;
  if quad > 0 then
    kick := (select array_agg(x order by x desc) from unnest(k) x where x <> quad);
    return 7 * 759375 + quad * 50625 + kick[1] * 3375;
  end if;
  if array_length(trips, 1) >= 1 and (array_length(trips, 1) >= 2 or array_length(pairs, 1) >= 1) then
    return 6 * 759375 + trips[1] * 50625 + (case when array_length(trips, 1) >= 2 then trips[2] else pairs[1] end) * 3375;
  end if;
  if flush_suit is not null then
    kick := (select array_agg(x order by x desc) from unnest(fr) x);
    return 5 * 759375 + kick[1] * 50625 + kick[2] * 3375 + kick[3] * 225 + kick[4] * 15 + kick[5];
  end if;
  sh := _straight_high(ranks);
  if sh is not null then return 4 * 759375 + sh * 50625; end if;
  if array_length(trips, 1) >= 1 then
    kick := (select array_agg(x order by x desc) from unnest(k) x where x <> trips[1]);
    return 3 * 759375 + trips[1] * 50625 + kick[1] * 3375 + kick[2] * 225;
  end if;
  if array_length(pairs, 1) >= 2 then
    kick := (select array_agg(x order by x desc) from unnest(k) x where x <> pairs[1] and x <> pairs[2]);
    return 2 * 759375 + pairs[1] * 50625 + pairs[2] * 3375 + kick[1] * 225;
  end if;
  if array_length(pairs, 1) = 1 then
    kick := (select array_agg(x order by x desc) from unnest(k) x where x <> pairs[1]);
    return 1 * 759375 + pairs[1] * 50625 + kick[1] * 3375 + kick[2] * 225 + kick[3] * 15;
  end if;
  return k[1] * 50625 + k[2] * 3375 + k[3] * 225 + k[4] * 15 + k[5];
end $$;

create or replace function _hand_name(score bigint) returns text language sql immutable as $$
  select (array['High card','Pair','Two pair','Three of a kind','Straight','Flush','Full house','Four of a kind','Straight flush'])[score / 759375 + 1] $$;

-- ---------------------------------------------------------------------------
-- Poker: table mechanics
-- ---------------------------------------------------------------------------
create or replace function poker_lobby() returns jsonb
language sql security definer set search_path = public stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', t.id, 'name', t.name, 'small_blind', t.small_blind, 'big_blind', t.big_blind,
           'min_buyin', t.min_buyin, 'max_buyin', t.max_buyin, 'seats', t.seats,
           'seated', (select count(*) from poker_seats s where s.table_id = t.id),
           'players', (select coalesce(jsonb_agg(p.name), '[]'::jsonb) from poker_seats s join profiles p on p.id = s.player_id where s.table_id = t.id),
           'mine', exists (select 1 from poker_seats s where s.table_id = t.id and s.player_id = auth.uid())) order by t.big_blind, t.id), '[]'::jsonb)
  from poker_tables t $$;

-- Seat order helpers
create or replace function _next_seat(tid integer, after_seat integer, hand bigint default null) returns integer language plpgsql stable as $$
declare n int; s int; i int;
begin
  select seats into n from poker_tables where id = tid;
  for i in 1..n loop
    s := (after_seat + i) % n;
    if hand is null then
      if exists (select 1 from poker_seats where table_id = tid and seat = s and not sitting_out and stack > 0) then return s; end if;
    else
      if exists (select 1 from poker_hand_players where hand_id = hand and seat = s and not folded and not all_in) then return s; end if;
    end if;
  end loop;
  return null;
end $$;

create or replace function _poker_start_hand(tid integer) returns void language plpgsql as $$
declare t poker_tables; last poker_hands; dealer int; sb int; bb int; d integer[]; h poker_hands; s record; i int := 1; n int;
        first int; hp poker_hand_players; sb_amt bigint; bb_amt bigint;
begin
  select * into t from poker_tables where id = tid;
  select count(*) into n from poker_seats where table_id = tid and not sitting_out and stack > 0;
  if n < 2 then return; end if;
  select * into last from poker_hands where table_id = tid order by id desc limit 1;
  dealer := _next_seat(tid, coalesce(last.dealer_seat, -1));
  if n = 2 then sb := dealer; else sb := _next_seat(tid, dealer); end if;
  bb := _next_seat(tid, sb);
  d := _deck();
  insert into poker_hands (table_id, hand_no, stage, deck, dealer_seat, current_bet, min_raise, deadline)
  values (tid, coalesce(last.hand_no, 0) + 1, 'preflop', d, dealer, t.big_blind, t.big_blind, now() + make_interval(secs => _casino_cfg('poker_clock_s')))
  returning * into h;
  for s in select * from poker_seats where table_id = tid and not sitting_out and stack > 0 order by seat loop
    insert into poker_hand_players (hand_id, seat, player_id, hole) values (h.id, s.seat, s.player_id, array[d[i], d[i+1]]);
    i := i + 2;
  end loop;
  update poker_hands set deck = d[i:] where id = h.id;
  -- blinds (all-in if short)
  select least(stack, t.small_blind) into sb_amt from poker_seats where table_id = tid and seat = sb;
  select least(stack, t.big_blind) into bb_amt from poker_seats where table_id = tid and seat = bb;
  update poker_seats set stack = stack - sb_amt where table_id = tid and seat = sb;
  update poker_seats set stack = stack - bb_amt where table_id = tid and seat = bb;
  update poker_hand_players set street_bet = sb_amt, total_bet = sb_amt, all_in = (select stack = 0 from poker_seats where table_id = tid and seat = sb) where hand_id = h.id and seat = sb;
  update poker_hand_players set street_bet = bb_amt, total_bet = bb_amt, all_in = (select stack = 0 from poker_seats where table_id = tid and seat = bb) where hand_id = h.id and seat = bb;
  first := _next_seat(tid, bb, h.id);
  update poker_hands set to_act = first, current_bet = greatest(sb_amt, bb_amt) where id = h.id;
  if first is null then perform _poker_advance(h.id); end if;
end $$;

-- Award pots at the end of a hand (fold-out or showdown) with side pots and rake.
create or replace function _poker_showdown(hid bigint, fold_out boolean) returns void language plpgsql as $$
declare h poker_hands; t poker_tables; levels bigint[]; lvl bigint; prev bigint := 0; portion bigint; contrib bigint; p record; best bigint;
        winners int[]; share bigint; remainder bigint; results jsonb := '{}'::jsonb; rake bigint := 0; total bigint; won jsonb := '{}'::jsonb;
        scores jsonb := '{}'::jsonb; w int; k text; nxt int; rake_taken bigint := 0;
begin
  select * into h from poker_hands where id = hid for update;
  select * into t from poker_tables where id = h.table_id;
  -- move street bets into the pot
  update poker_hands set pot = pot + (select coalesce(sum(street_bet), 0) from poker_hand_players where hand_id = hid) where id = hid returning * into h;
  update poker_hand_players set street_bet = 0 where hand_id = hid;
  -- run out the board if we got here with players all-in
  while not fold_out and coalesce(array_length(h.board, 1), 0) < 5 loop
    h.board := h.board || h.deck[1]; h.deck := h.deck[2:];
  end loop;
  total := h.pot;
  if not fold_out or coalesce(array_length(h.board, 1), 0) >= 3 then
    rake := least(total * _casino_cfg('poker_rake_pct')::bigint / 100, t.big_blind * _casino_cfg('poker_rake_cap_bb')::bigint);
  end if;
  rake_taken := rake;
  -- hand scores for everyone still in
  if not fold_out then
    for p in select * from poker_hand_players where hand_id = hid and not folded loop
      scores := scores || jsonb_build_object(p.seat::text, _eval7(h.board || p.hole));
    end loop;
    update poker_hand_players set shown = true where hand_id = hid and not folded;
  end if;
  -- side pots by contribution level
  levels := (select array_agg(distinct total_bet order by total_bet) from poker_hand_players where hand_id = hid and total_bet > 0);
  -- (the rake is taken from the first pot)
  foreach lvl in array coalesce(levels, '{}'::bigint[]) loop
    portion := 0;
    for p in select * from poker_hand_players where hand_id = hid loop
      portion := portion + greatest(0, least(p.total_bet, lvl) - prev);
    end loop;
    if rake > 0 then portion := portion - rake; rake := 0; end if;
    if portion > 0 then
      if fold_out then
        winners := (select array_agg(seat) from poker_hand_players where hand_id = hid and not folded);
      else
        best := (select max((scores->>seat::text)::bigint) from poker_hand_players where hand_id = hid and not folded and total_bet >= lvl);
        winners := (select array_agg(seat order by seat) from poker_hand_players where hand_id = hid and not folded and total_bet >= lvl and (scores->>seat::text)::bigint = best);
      end if;
      if winners is null then   -- nobody eligible at this level (dead money from a folded over-bettor): best live hand takes it
        best := (select max((scores->>seat::text)::bigint) from poker_hand_players where hand_id = hid and not folded);
        winners := (select array_agg(seat order by seat) from poker_hand_players where hand_id = hid and not folded and coalesce((scores->>seat::text)::bigint, 0) = coalesce(best, 0));
      end if;
      share := portion / array_length(winners, 1); remainder := portion - share * array_length(winners, 1);
      -- odd chips go to the first winner after the dealer
      nxt := h.dealer_seat;
      foreach w in array winners loop
        won := won || jsonb_build_object(w::text, coalesce((won->>w::text)::bigint, 0) + share);
      end loop;
      if remainder > 0 then
        for k in select seat::text from poker_hand_players where hand_id = hid and seat = any(winners) order by (seat - h.dealer_seat - 1 + t.seats) % t.seats limit 1 loop
          won := won || jsonb_build_object(k, (won->>k)::bigint + remainder);
        end loop;
      end if;
    end if;
    prev := lvl;
  end loop;
  -- pay
  for k in select key from jsonb_each(won) loop
    update poker_seats set stack = stack + (won->>k)::bigint where table_id = h.table_id and seat = k::int;
  end loop;
  -- log each player's net for accolades / history
  for p in select hp.*, s.stack from poker_hand_players hp join poker_seats s on s.table_id = h.table_id and s.seat = hp.seat where hp.hand_id = hid loop
    insert into casino_bets (player_id, game, wager, payout, detail)
    values (p.player_id, 'poker', p.total_bet, coalesce((won->>p.seat::text)::bigint, 0), jsonb_build_object('hand', hid, 'table', h.table_id));
    perform _event(p.player_id, 'gambler', coalesce((won->>p.seat::text)::bigint, 0) - p.total_bet);
  end loop;
  update poker_hands set stage = 'done', to_act = null, deadline = null, board = h.board, deck = h.deck, finished_at = now(),
         result = jsonb_build_object('won', won, 'scores', scores, 'fold_out', fold_out, 'rake', rake_taken,
           'hands', (select jsonb_object_agg(seat::text, _hand_name((scores->>seat::text)::bigint)) from poker_hand_players where hand_id = hid and scores ? seat::text))
   where id = hid;
  -- busted players sit out
  update poker_seats set sitting_out = true where table_id = h.table_id and stack = 0;
end $$;

-- After an action: find the next player, or finish the street / the hand.
create or replace function _poker_advance(hid bigint) returns void language plpgsql as $$
declare h poker_hands; live int; can_act int; nxt int; p record; s int;
begin
  select * into h from poker_hands where id = hid for update;
  select count(*) into live from poker_hand_players where hand_id = hid and not folded;
  if live <= 1 then perform _poker_showdown(hid, true); return; end if;
  -- someone still owes action this street? (walk clockwise from the last actor)
  nxt := null;
  s := coalesce(h.to_act, h.dealer_seat);
  for p in select hp.* from poker_hand_players hp where hp.hand_id = hid and not hp.folded and not hp.all_in
             order by ((hp.seat - s - 1 + 100) % 100) loop
    if not p.acted or p.street_bet < h.current_bet then nxt := p.seat; exit; end if;
  end loop;
  if nxt is not null then
    update poker_hands set to_act = nxt, deadline = now() + make_interval(secs => _casino_cfg('poker_clock_s')) where id = hid;
    return;
  end if;
  -- street finished
  select count(*) into can_act from poker_hand_players where hand_id = hid and not folded and not all_in;
  if h.stage = 'river' or can_act <= 1 then perform _poker_showdown(hid, false); return; end if;
  update poker_hands set pot = pot + (select coalesce(sum(street_bet), 0) from poker_hand_players where hand_id = hid) where id = hid;
  update poker_hand_players set street_bet = 0, acted = false where hand_id = hid;
  if h.stage = 'preflop' then
    update poker_hands set stage = 'flop', board = array[deck[1], deck[2], deck[3]], deck = deck[4:] where id = hid;
  elsif h.stage = 'flop' then
    update poker_hands set stage = 'turn', board = board || deck[1], deck = deck[2:] where id = hid;
  else
    update poker_hands set stage = 'river', board = board || deck[1], deck = deck[2:] where id = hid;
  end if;
  nxt := _next_seat(h.table_id, h.dealer_seat, hid);
  update poker_hands set current_bet = 0, min_raise = (select big_blind from poker_tables where id = h.table_id), to_act = nxt,
         deadline = now() + make_interval(secs => _casino_cfg('poker_clock_s')) where id = hid;
end $$;

-- Drive the table forward: time out slow players, start the next hand. Called by clients on every poll.
create or replace function _poker_tick(tid integer) returns void language plpgsql as $$
declare h poker_hands; p poker_hand_players; s poker_seats;
begin
  select * into h from poker_hands where table_id = tid and finished_at is null for update skip locked;
  if h.id is not null and h.deadline is not null and h.deadline < now() then
    select * into p from poker_hand_players where hand_id = h.id and seat = h.to_act;
    update poker_seats set missed = missed + 1 where table_id = tid and seat = h.to_act returning * into s;
    if p.street_bet >= h.current_bet then
      update poker_hand_players set acted = true where hand_id = h.id and seat = h.to_act;              -- auto-check
    else
      update poker_hand_players set folded = true, acted = true where hand_id = h.id and seat = h.to_act; -- auto-fold
    end if;
    if s.missed >= _casino_cfg('poker_max_missed') then
      update poker_seats set sitting_out = true where table_id = tid and seat = h.to_act;               -- sit them out; stack is safe
    end if;
    perform _poker_advance(h.id);
  end if;
  if not exists (select 1 from poker_hands where table_id = tid and finished_at is null) then
    if not exists (select 1 from poker_hands where table_id = tid and finished_at > now() - make_interval(secs => _casino_cfg('poker_pause_s'))) then
      perform _poker_start_hand(tid);
    end if;
  end if;
end $$;

create or replace function poker_join(tid integer, seat_no integer, buyin bigint) returns jsonb
language plpgsql security definer set search_path = public as $$
declare pr profiles; t poker_tables; cur poker_seats;
begin
  perform _nn(buyin, 'buy-in'); perform _nn(seat_no, 'seat');
  pr := _casino_player(null);
  select * into t from poker_tables where id = tid;
  if t.id is null then perform _fail('No such table'); end if;
  select * into cur from poker_seats where player_id = pr.id;
  if cur.player_id is not null then
    if cur.table_id <> tid then perform _fail('You are already seated at another table'); end if;
    -- rebuy / top up
    if buyin <= 0 or cur.stack + buyin > t.max_buyin then perform _fail(format('Stack can''t exceed $%s', t.max_buyin)); end if;
    if pr.cash < buyin then perform _fail('Not enough cash'); end if;
    update profiles set cash = cash - buyin where id = pr.id;
    update poker_seats set stack = stack + buyin, sitting_out = false, missed = 0 where player_id = pr.id;
    perform _poker_tick(tid);
    return poker_state(tid);
  end if;
  if seat_no < 0 or seat_no >= t.seats then perform _fail('Bad seat'); end if;
  if exists (select 1 from poker_seats where table_id = tid and seat = seat_no) then perform _fail('That seat is taken'); end if;
  if buyin < t.min_buyin or buyin > t.max_buyin then perform _fail(format('Buy in for $%s to $%s', t.min_buyin, t.max_buyin)); end if;
  if pr.cash < buyin then perform _fail('Not enough cash on hand — withdraw from the bank first'); end if;
  update profiles set cash = cash - buyin where id = pr.id;
  insert into poker_seats (table_id, seat, player_id, stack) values (tid, seat_no, pr.id, buyin);
  perform _poker_tick(tid);
  return poker_state(tid);
end $$;

create or replace function poker_leave() returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); s poker_seats; h poker_hands;
begin
  select * into s from poker_seats where player_id = u for update;
  if s.player_id is null then perform _fail('You are not at a table'); end if;
  select * into h from poker_hands where table_id = s.table_id and finished_at is null for update;
  if h.id is not null and exists (select 1 from poker_hand_players where hand_id = h.id and seat = s.seat and not folded) then
    update poker_hand_players set folded = true, acted = true where hand_id = h.id and seat = s.seat;
    if h.to_act = s.seat or (select count(*) from poker_hand_players where hand_id = h.id and not folded) <= 1 then
      perform _poker_advance(h.id);
    end if;
  end if;
  update profiles set cash = cash + s.stack where id = u;
  delete from poker_seats where player_id = u;
  return jsonb_build_object('cashed_out', s.stack);
end $$;

create or replace function poker_sit_in() returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); s poker_seats;
begin
  update poker_seats set sitting_out = false, missed = 0 where player_id = u returning * into s;
  if s.player_id is null then perform _fail('You are not at a table'); end if;
  if s.stack = 0 then perform _fail('Rebuy first'); end if;
  perform _poker_tick(s.table_id);
  return poker_state(s.table_id);
end $$;

-- action: fold | check | call | bet | raise (amount = total you want your street bet to be)
create or replace function poker_act(action text, amount bigint default null) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); s poker_seats; h poker_hands; p poker_hand_players; t poker_tables; to_call bigint; put bigint; new_bet bigint;
begin
  select * into s from poker_seats where player_id = u;
  if s.player_id is null then perform _fail('You are not at a table'); end if;
  perform _poker_tick(s.table_id);
  select * into h from poker_hands where table_id = s.table_id and finished_at is null for update;
  if h.id is null or h.to_act is distinct from s.seat then perform _fail('It is not your turn'); end if;
  select * into p from poker_hand_players where hand_id = h.id and seat = s.seat for update;
  select * into t from poker_tables where id = s.table_id;
  to_call := h.current_bet - p.street_bet;
  if action = 'fold' then
    update poker_hand_players set folded = true, acted = true where hand_id = h.id and seat = s.seat;
  elsif action = 'check' then
    if to_call > 0 then perform _fail(format('You need to call $%s or fold', to_call)); end if;
    update poker_hand_players set acted = true where hand_id = h.id and seat = s.seat;
  elsif action = 'call' then
    if to_call <= 0 then perform _fail('Nothing to call — check instead'); end if;
    put := least(to_call, s.stack);
    update poker_seats set stack = stack - put where player_id = u;
    update poker_hand_players set street_bet = street_bet + put, total_bet = total_bet + put, acted = true, all_in = (s.stack - put = 0) where hand_id = h.id and seat = s.seat;
  elsif action in ('bet', 'raise') then
    perform _nn(amount, 'amount');
    new_bet := amount;
    if new_bet <= h.current_bet then perform _fail('A raise must be more than the current bet'); end if;
    put := new_bet - p.street_bet;
    if put > s.stack then perform _fail(format('You only have $%s behind', s.stack)); end if;
    if new_bet < h.current_bet + h.min_raise and put < s.stack then
      perform _fail(format('Minimum raise is to $%s', h.current_bet + h.min_raise)); end if;
    update poker_seats set stack = stack - put where player_id = u;
    update poker_hand_players set street_bet = new_bet, total_bet = total_bet + put, acted = true, all_in = (s.stack - put = 0) where hand_id = h.id and seat = s.seat;
    -- a full raise reopens the action for everyone else
    if new_bet >= h.current_bet + h.min_raise then
      update poker_hand_players set acted = false where hand_id = h.id and seat <> s.seat and not folded and not all_in;
      update poker_hands set min_raise = new_bet - h.current_bet where id = h.id;
    end if;
    update poker_hands set current_bet = new_bet where id = h.id;
  else
    perform _fail('Unknown action');
  end if;
  update poker_seats set missed = 0 where player_id = u;
  perform _poker_advance(h.id);
  return poker_state(s.table_id);
end $$;

create or replace function poker_state(tid integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); t poker_tables; h poker_hands; me poker_seats; my poker_hand_players; showdown boolean; last poker_hands;
begin
  select * into t from poker_tables where id = tid;
  if t.id is null then perform _fail('No such table'); end if;
  perform _poker_tick(tid);
  select * into h from poker_hands where table_id = tid and finished_at is null;
  if h.id is null then
    select * into last from poker_hands where table_id = tid and finished_at > now() - interval '2 minutes' order by id desc limit 1;
    h := last;   -- show the finished hand (with result) until the next one starts
  end if;
  select * into me from poker_seats where table_id = tid and player_id = u;
  if h.id is not null then select * into my from poker_hand_players where hand_id = h.id and seat = me.seat and player_id = u; end if;
  showdown := h.id is not null and h.finished_at is not null and not coalesce((h.result->>'fold_out')::boolean, true);
  return jsonb_build_object(
    'table', jsonb_build_object('id', t.id, 'name', t.name, 'small_blind', t.small_blind, 'big_blind', t.big_blind, 'min_buyin', t.min_buyin, 'max_buyin', t.max_buyin, 'seats', t.seats),
    'me', case when me.player_id is null then null else jsonb_build_object('seat', me.seat, 'stack', me.stack, 'sitting_out', me.sitting_out) end,
    'hand', case when h.id is null then null else jsonb_build_object(
      'id', h.id, 'no', h.hand_no, 'stage', h.stage, 'finished', h.finished_at is not null,
      'board', (select coalesce(jsonb_agg(_card_text(c) order by ord), '[]'::jsonb) from unnest(h.board) with ordinality as x(c, ord)),
      'pot', h.pot + (select coalesce(sum(street_bet), 0) from poker_hand_players where hand_id = h.id),
      'dealer', h.dealer_seat, 'to_act', h.to_act, 'current_bet', h.current_bet, 'min_raise', h.min_raise, 'deadline', h.deadline,
      'result', h.result,
      'my', case when my.hand_id is null then null else jsonb_build_object(
          'hole', (select jsonb_agg(_card_text(c) order by ord) from unnest(my.hole) with ordinality as x(c, ord)),
          'folded', my.folded, 'all_in', my.all_in, 'street_bet', my.street_bet, 'total_bet', my.total_bet,
          'to_call', greatest(0, least(h.current_bet - my.street_bet, me.stack)),
          'min_raise_to', h.current_bet + h.min_raise,
          'my_turn', h.to_act = me.seat and h.finished_at is null) end) end,
    'seats', (select coalesce(jsonb_agg(jsonb_build_object('seat', s.seat, 'name', p.name, 'avatar', p.avatar, 'stack', s.stack,
                'sitting_out', s.sitting_out, 'is_me', s.player_id = u, 'player_id', s.player_id,
                'in_hand', hp.hand_id is not null, 'folded', hp.folded, 'all_in', hp.all_in, 'street_bet', hp.street_bet,
                'hole', case when hp.hand_id is not null and (s.player_id = u or (showdown and hp.shown))
                        then (select jsonb_agg(_card_text(c) order by ord) from unnest(hp.hole) with ordinality as x(c, ord)) end,
                'hand_name', case when showdown and hp.shown then h.result->'hands'->>s.seat::text end,
                'won', case when h.finished_at is not null then (h.result->'won'->>s.seat::text)::bigint end) order by s.seat), '[]'::jsonb)
              from poker_seats s join profiles p on p.id = s.player_id
              left join poker_hand_players hp on hp.hand_id = h.id and hp.seat = s.seat and hp.player_id = s.player_id
              where s.table_id = tid),
    'server_time', now());
end $$;

-- Table chat: anyone seated at the table
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
  if channel ~ '^table:[0-9]+$' then
    return exists (select 1 from poker_seats where player_id = u and table_id = split_part(channel, ':', 2)::int);
  end if;
  if channel ~ '^dm:[0-9a-f-]{36}:[0-9a-f-]{36}$' then
    declare a uuid := split_part(channel, ':', 2)::uuid; b uuid := split_part(channel, ':', 3)::uuid;
    begin
      return a < b and (a = u or b = u);
    exception when others then return false;
    end;
  end if;
  return false;
end $$;

-- Casino history for the player
create or replace function casino_history(limit_n integer default 30) returns jsonb
language sql security definer set search_path = public stable as $$
  select jsonb_build_object(
    'net', (select coalesce(sum(payout - wager), 0) from casino_bets where player_id = auth.uid()),
    'recent', (select coalesce(jsonb_agg(jsonb_build_object('game', game, 'wager', wager, 'payout', payout, 'net', payout - wager, 'at', created_at) order by created_at desc), '[]'::jsonb)
               from (select * from casino_bets where player_id = auth.uid() order by created_at desc limit limit_n) b)) $$;

-- ---------------------------------------------------------------------------
-- Grants (default privileges revoke execute; grant the public RPCs)
-- ---------------------------------------------------------------------------
do $$
declare f record;
begin
  for f in select p.oid::regprocedure as sig, p.proname from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and p.proname in ('slots_spin','roulette_spin','craps_state','craps_bet','craps_roll','craps_clear',
              'blackjack_state','blackjack_deal','blackjack_action','poker_lobby','poker_join','poker_leave','poker_sit_in','poker_act','poker_state','casino_history') loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
  for f in select p.oid::regprocedure as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
            where n.nspname = 'public' and (p.proconfig is null or not p.proconfig::text like '%search_path%') loop
    execute format('alter function %s set search_path = public', f.sig);
  end loop;
end $$;
