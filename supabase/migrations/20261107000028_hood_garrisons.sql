-- The hood, done the city's way (Zack, 2026-11-07): a hood block is held by a garrison of thugs and enforcers, not by
-- a defender with attack stats, and you take it with your own thugs and mercenaries — the same math as a city block.
--
--  · seasons.home_defenders now holds the TROOP VALUE of each garrison in dollars: $50k, $150k, $500k, $1M, $2.5M,
--    $5M for blocks 1–6 and $10M for the boss. A garrison is derived from it: the resistance that much mercenary muscle
--    would bring (value × 60 att / $4,000), half of it thugs (10 def) and half enforcers (60 def).
--  · home_blocks and home_hoods keep each player's garrison counts; every attack wears them down. A win clears the block.
--  · home_attack(slot, thugs, mercs) and home_boss(thugs, mercs): attack = (thugs × 10 + mercs × 60) × 0.9–1.1;
--    at least a quarter of the resistance to get a fight; attacker losses = min(1, res / atk) / 2 of the force sent,
--    garrison losses = min(1, atk / res) / 2; atk > res takes the block; 3 stamina, as a turf war. No gear, no
--    health, no hospital: it is muscle against muscle. The old home_attack(slot) and home_boss() refuse, with the reason.
--  · The campaign is reordered: the city's basics first (Work, Get Armed, Bank It, Grow, First Blood, Move Product),
--    then Hire Muscle, then the hood — a new player starts with $10,000 and block 1 wants $50k of troops. The hood
--    lives on the Territory page now, so Territory never locks.
--  · Income stays as it was ($1,500 to $14,000 a day by level, +50% with the boss).
-- Bodies of _home_ensure, _home_json, home_state, _unlocked, _season_me from 20261030000022 / 20261106000025.

-- --------------------------------------------------------------------------------------------------------------------
-- Garrisons
-- --------------------------------------------------------------------------------------------------------------------
alter table home_blocks add column if not exists thugs int not null default 0;
alter table home_blocks add column if not exists enforcers int not null default 0;
alter table home_hoods add column if not exists boss_thugs int not null default 0;
alter table home_hoods add column if not exists boss_enforcers int not null default 0;
alter table seasons alter column home_defenders set default array[50000, 150000, 500000, 1000000, 2500000, 5000000, 10000000];

-- The garrison worth a troop value: the resistance that value in mercenaries would bring, half thugs, half enforcers.
create or replace function _home_garrison(value bigint, out thugs int, out enforcers int, out resistance int)
language sql immutable as $$
  select ceil(value * 60.0 / 4000 / 2 / 10)::int, ceil(value * 60.0 / 4000 / 2 / 60)::int,
         ceil(value * 60.0 / 4000 / 2 / 10)::int * 10 + ceil(value * 60.0 / 4000 / 2 / 60)::int * 60 $$;

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
    when 'fight_stamina'  then 3         -- a turf war's price
    when 'min_force'      then 0.25      -- bring at least this share of the resistance to get a fight
    else 0 end $$;

-- A player's hood for the season, made on first sight, every block and the boss garrisoned from the season's values.
create or replace function _home_ensure(p uuid, s seasons) returns void language plpgsql set search_path = public as $$
declare g record;
begin
  if s.id is null then return; end if;
  select * into g from _home_garrison(s.home_defenders[7]);
  insert into home_hoods (player_id, season_id, boss_thugs, boss_enforcers) values (p, s.id, g.thugs, g.enforcers) on conflict do nothing;
  insert into home_blocks (player_id, season_id, slot, business, thugs, enforcers)
    select p, s.id, i, s.home_businesses[i], (_home_garrison(s.home_defenders[i])).thugs, (_home_garrison(s.home_defenders[i])).enforcers
      from generate_series(1, 6) i on conflict do nothing;
end $$;

-- Season 1 was drawn under the old numbers: the troop values go in, and every hood already made is garrisoned.
update seasons set home_defenders = array[50000, 150000, 500000, 1000000, 2500000, 5000000, 10000000]
 where cancelled_at is null and ends_at > now() and home_defenders[1] < 1000;
update home_blocks b set thugs = (_home_garrison(s.home_defenders[b.slot])).thugs, enforcers = (_home_garrison(s.home_defenders[b.slot])).enforcers
  from seasons s
 where s.id = b.season_id and b.cleared_at is null and b.thugs = 0 and b.enforcers = 0;
update home_hoods h set boss_thugs = (_home_garrison(s.home_defenders[7])).thugs, boss_enforcers = (_home_garrison(s.home_defenders[7])).enforcers
  from seasons s
 where s.id = h.season_id and h.boss_cleared_at is null and h.boss_thugs = 0 and h.boss_enforcers = 0;

-- --------------------------------------------------------------------------------------------------------------------
-- The hood as the screen sees it
-- --------------------------------------------------------------------------------------------------------------------
create or replace function _home_json(p uuid) returns jsonb language plpgsql stable set search_path = public as $$
declare s seasons := _season(); h home_hoods; boss boolean; nxt int; res int; nt int; ne int;
        my_t int; my_m int;
begin
  if s.id is null then return null; end if;
  select * into h from home_hoods where player_id = p and season_id = s.id;
  if h.player_id is null then return null; end if;
  boss := h.boss_cleared_at is not null;
  select min(slot) into nxt from home_blocks where player_id = p and season_id = s.id and cleared_at is null;
  if nxt is not null then select b.thugs, b.enforcers into nt, ne from home_blocks b where b.player_id = p and b.season_id = s.id and b.slot = nxt;
  elsif not boss then nt := h.boss_thugs; ne := h.boss_enforcers; end if;
  res := nt * 10 + ne * 60;
  select coalesce(sum(qty) filter (where code = 'thug'), 0), coalesce(sum(qty) filter (where code = 'mercenary'), 0)
    into my_t, my_m from player_hoodlums where player_id = p;
  return jsonb_build_object(
    'season', jsonb_build_object('id', s.id, 'name', s.name, 'starts_at', s.starts_at, 'ends_at', s.ends_at),
    'opened', h.opened_at is not null,
    'boss', jsonb_build_object('cleared', boss, 'cleared_at', h.boss_cleared_at, 'value', s.home_defenders[7],
                               'thugs', h.boss_thugs, 'enforcers', h.boss_enforcers, 'resistance', h.boss_thugs * 10 + h.boss_enforcers * 60,
                               'ready', nxt is null and not boss),
    'cleared', (select count(*) from home_blocks where player_id = p and season_id = s.id and cleared_at is not null),
    'next_slot', nxt,
    'next', case when nt is not null then jsonb_build_object(
              'slot', coalesce(nxt, 7), 'thugs', nt, 'enforcers', ne, 'resistance', res,
              'min_force', ceil(res * _home_cfg('min_force'))::int,
              'my_thugs', my_t, 'my_mercs', my_m, 'my_attack', my_t * 10 + my_m * 60,
              'stamina', _home_cfg('fight_stamina')::int) end,
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
                 'value', s.home_defenders[b.slot], 'thugs', b.thugs, 'enforcers', b.enforcers, 'resistance', b.thugs * 10 + b.enforcers * 60,
                 'perk_value', case when b.cleared_at is not null then round(dd.base + (dd.ceiling - dd.base) * (b.level - 1) / 4.0, 4) end
               ) order by b.slot)
               from home_blocks b join business_defs dd on dd.code = b.business where b.player_id = p and b.season_id = s.id),
    'perks', _home_perks(p),
    'cfg', jsonb_build_object('cap_hours', _home_cfg('cap_hours')::int, 'boss_bonus', _home_cfg('boss_bonus'),
                              'stamina', _home_cfg('fight_stamina')::int, 'min_force', _home_cfg('min_force'))
  );
end $$;

-- --------------------------------------------------------------------------------------------------------------------
-- The fight: your thugs and mercs against the garrison, the city's math
-- --------------------------------------------------------------------------------------------------------------------
create or replace function _home_fight(u uuid, slot int, thugs int, mercs int) returns jsonb
language plpgsql set search_path = public as $$
declare s seasons := _season(); pr profiles; h home_hoods; b home_blocks; nxt int; have_t int; have_m int;
        gt int; ge int; atk numeric; res numeric; success boolean; loss_frac numeric; lost_t int; lost_m int;
        gloss numeric; glost_t int; glost_e int;
begin
  if s.id is null then perform _fail('No season is running'); end if;
  perform _nn(thugs, 'thugs'); perform _nn(mercs, 'mercenaries');
  if thugs < 0 or mercs < 0 then perform _fail('Bad force'); end if;
  if thugs + mercs = 0 then perform _fail('Send some muscle'); end if;
  perform _home_ensure(u, s);
  pr := _tick(u);
  if _hospital(pr) then perform _fail('You are in the hospital'); end if;
  if _jailed(pr) then perform _fail('Not from a cell'); end if;
  select * into h from home_hoods where player_id = u and season_id = s.id for update;
  select min(x.slot) into nxt from home_blocks x where x.player_id = u and x.season_id = s.id and x.cleared_at is null;
  if slot between 1 and 6 then
    if nxt is null or slot < nxt then perform _fail('That block is already yours'); end if;
    if slot > nxt then perform _fail(format('Take block %s first', nxt)); end if;
    select * into b from home_blocks x where x.player_id = u and x.season_id = s.id and x.slot = _home_fight.slot for update;
    gt := b.thugs; ge := b.enforcers;
  elsif slot = 7 then
    if nxt is not null then perform _fail('Take all six blocks first'); end if;
    if h.boss_cleared_at is not null then perform _fail('The hood is already yours'); end if;
    gt := h.boss_thugs; ge := h.boss_enforcers;
  else
    perform _fail('No such block');
  end if;
  select coalesce(qty, 0) into have_t from player_hoodlums where player_id = u and code = 'thug';
  select coalesce(qty, 0) into have_m from player_hoodlums where player_id = u and code = 'mercenary';
  if coalesce(have_t, 0) < thugs or coalesce(have_m, 0) < mercs then perform _fail('Not enough hoodlums'); end if;
  if pr.stamina < _home_cfg('fight_stamina') then perform _fail(format('A fight for a block takes %s stamina', _home_cfg('fight_stamina')::int)); end if;

  atk := (thugs * 10 + mercs * 60) * (0.9 + random() * 0.2);
  res := gt * 10 + ge * 60;
  if atk < res * _home_cfg('min_force') then
    perform _fail(format('That force would be laughed off the block — bring at least a quarter of the resistance (~%s)', ceil(res * _home_cfg('min_force'))));
  end if;
  success := atk > res;
  update profiles set stamina = stamina - _home_cfg('fight_stamina')::int where id = u;

  -- attacker losses: proportional to how hard the resistance was, up to half the force sent
  loss_frac := least(1, res / greatest(atk, 1)) * 0.5;
  lost_t := floor(thugs * loss_frac); lost_m := floor(mercs * loss_frac);
  update player_hoodlums set qty = qty - lost_t where player_id = u and code = 'thug';
  update player_hoodlums set qty = qty - lost_m where player_id = u and code = 'mercenary';

  -- garrison losses the same way (rounded down); a win wipes what's left
  gloss := least(1, atk / greatest(res, 1)) * 0.5;
  glost_t := case when success then gt else floor(gt * gloss) end;
  glost_e := case when success then ge else floor(ge * gloss) end;
  if slot = 7 then
    update home_hoods set boss_thugs = boss_thugs - glost_t, boss_enforcers = boss_enforcers - glost_e,
                          boss_cleared_at = case when success then now() else boss_cleared_at end
     where player_id = u and season_id = s.id;
  else
    update home_blocks set thugs = home_blocks.thugs - glost_t, enforcers = home_blocks.enforcers - glost_e,
                           cleared_at = case when success then now() else cleared_at end,
                           collected_at = case when success then now() else collected_at end
     where player_id = u and season_id = s.id and home_blocks.slot = _home_fight.slot;
  end if;
  return jsonb_build_object('won', success, 'slot', slot, 'boss', slot = 7,
                            'attack', round(atk), 'resistance', round(res), 'thugs', thugs, 'mercs', mercs,
                            'lost_thugs', lost_t, 'lost_mercs', lost_m, 'garrison_lost', glost_t + glost_e,
                            'garrison_left', (gt - glost_t) * 10 + (ge - glost_e) * 60,
                            'stamina', pr.stamina - _home_cfg('fight_stamina')::int,
                            'hood', _home_json(u));
end $$;

create or replace function home_attack(slot int, thugs int, mercs int default 0) returns jsonb
language plpgsql security definer set search_path = public as $$
begin
  perform _nn(slot, 'block');
  if slot not between 1 and 6 then perform _fail('No such block'); end if;
  return _home_fight(_uid(), slot, thugs, mercs);
end $$;

create or replace function home_boss(thugs int, mercs int default 0) returns jsonb
language plpgsql security definer set search_path = public as $$
begin return _home_fight(_uid(), 7, thugs, mercs); end $$;

-- the old shapes stay callable (an old client) and say what changed
create or replace function home_attack(slot int) returns jsonb
language plpgsql security definer set search_path = public as $$
begin perform _fail('Blocks fall to muscle now: send thugs and mercs'); return null; end $$;
create or replace function home_boss() returns jsonb
language plpgsql security definer set search_path = public as $$
begin perform _fail('The boss falls to muscle now: send thugs and mercs'); return null; end $$;

-- --------------------------------------------------------------------------------------------------------------------
-- The campaign, reordered: the city first, then the hood
-- --------------------------------------------------------------------------------------------------------------------
insert into mission_defs (key, seq, title, intro, done, label, objective, qty, reward_cash, reward_diamonds, unlocks, link) values
  ('six_blocks',    1, 'Six Blocks',
     'Boss. The city got reset. Everybody''s back to nothing — except we''ve still got six blocks on the edge of town. Somebody''s squatting on every one of them, with muscle.',
     'Every block''s got a crew sitting on it. We''ll need our own before we take one. First, the basics.',
     'Look at your six blocks', 'hood_open', 1, 500, 0, '{}', '/territory?focus=hood'),
  ('work',          2, 'Work',
     'Fights don''t pay the bills. There''s work on the street — small jobs. Watch your heat.',
     'Small jobs, steady money. Lay low and the heat comes down.',
     'Complete 3 actions', 'actions', 3, 1500, 0, '{actions}', '/actions'),
  ('get_armed',     3, 'Get Armed',
     'Nobody respects a boss with empty hands. Get something sharper than your fists — the shop''s open.',
     'Better. Now you look like trouble.',
     'Attack power 28 or more', 'attack', 28, 2000, 0, '{items}', '/items?tab=shop&cat=weapon'),
  ('bank_it',       4, 'Bank It',
     'Cash on hand is cash somebody can take. Put it in the bank.',
     'Can''t be robbed of what you don''t carry.',
     'Deposit any amount', 'bank', 1, 0, 10, '{services,casino}', '/services?focus=bank'),
  ('grow',          5, 'Grow',
     'Street money''s small. Product is where the real money is. Build a grow house.',
     'It grows while you sleep. Come back and collect.',
     'Own a grow house', 'grow', 1, 3000, 0, '{economy}', '/economy'),
  ('first_blood',   6, 'First Blood',
     'Time to fight somebody who fights back — there are thugs on every corner.',
     'Now you''ve got a record. Keep it clean.',
     'Win a fight', 'fight_win', 1, 3000, 0, '{fight}', '/fight?tab=thugs'),
  ('move_product',  7, 'Move Product',
     'Product on a shelf is worth nothing. Send hustlers out or list it on the market.',
     'Now it''s a business.',
     'Send hustlers or list product', 'moved', 1, 4000, 0, '{}', '/economy?tab=hustlers'),
  ('hire_muscle',   8, 'Hire Muscle',
     'Blocks don''t fall to fists. Thugs take them, mercs break them. Services sells both — hire a crew of thugs.',
     'That''s a crew. The {biz1} on block one is held by about fifty grand of muscle. Bring more than that.',
     'Own 30 thugs', 'hoodlums', 30, 5000, 0, '{}', '/services?focus=hoodlums'),
  ('block_one',     9, 'Block One',
     'Block one. Send more muscle than they''ve got sitting on it, and don''t send it all — you lose some either way.',
     'That''s one block working for us. Five to go.',
     'Clear block 1', 'home_clear', 1, 10000, 0, '{}', '/territory?focus=hood'),
  ('open_for_business', 10, 'Open for Business',
     'The {biz1} on block one still runs, and the till fills by the hour. Go empty it.',
     'Every day it pays. Don''t forget it, and don''t let it sit.',
     'Collect from a block', 'home_collect', 1, 2000, 0, '{}', '/territory?focus=hood'),
  ('build_it_up',  11, 'Build It Up',
     'The {biz1} could pull twice the money with some work. Spend some.',
     'Spend money to make money. You''re learning.',
     'Upgrade a block to level 2', 'home_upgrade', 2, 2500, 0, '{}', '/territory?focus=hood'),
  ('block_two',    12, 'Block Two',
     'Block two''s held by three times the muscle. Build the force, then take it.',
     'Two down. The others heard about it.',
     'Clear block 2', 'home_clear', 2, 15000, 0, '{}', '/territory?focus=hood'),
  ('blocks_three_four', 13, 'Blocks Three and Four',
     'Two more. Half a million of muscle on three, a million on four. Mercs hit six times harder than thugs — buy accordingly.',
     'Four blocks. Half a hood and the whole street knows your name.',
     'Clear block 4', 'home_clear', 4, 25000, 0, '{}', '/territory?focus=hood'),
  ('blocks_five_six', 14, 'Blocks Five and Six',
     'The last two are held by real armies. This is where the money you banked goes to work.',
     'Six blocks. All ours. But the guy who ran this hood before the reset wants it back.',
     'Clear block 6', 'home_clear', 6, 50000, 0, '{}', '/territory?focus=hood'),
  ('the_boss',     15, 'The Boss Falls', 'He''s at the top of the hood with ten million in muscle around him. End it.',
     'The hood''s yours, boss. Now the city''s noticed.',
     'Beat the hood boss', 'home_boss', 1, 100000, 50, '{crew}', '/territory?focus=hood'),
  ('into_the_city', 16, 'Into the City',
     'Six blocks is a start. The city''s 486. Nobody takes that alone — find a crew or start one and hit a block.',
     'That''s how it starts. Fifty wins takes a block. Go take the city.',
     'Crew, 5 hoodlums, 1 block hit', 'city', 3, 25000, 25, '{}', '/crew')
on conflict (key) do update set seq = excluded.seq, title = excluded.title, intro = excluded.intro, done = excluded.done,
  label = excluded.label, objective = excluded.objective, qty = excluded.qty, reward_cash = excluded.reward_cash,
  reward_diamonds = excluded.reward_diamonds, unlocks = excluded.unlocks, link = excluded.link;

-- The gate: Territory is where the hood lives, so it never locks. Body from 20261106000025; only the lists changed.
create or replace function _unlocked(p uuid) returns jsonb language plpgsql stable set search_path = public as $$
declare s seasons := _season(); always text[] := array['home', 'hood', 'territory', 'profile', 'store', 'chat', 'forum', 'activity', 'accolades', 'missions'];
        gated text[] := array['items', 'actions', 'services', 'casino', 'economy', 'fight', 'crew'];
        cur text;
begin
  if s.id is null then return to_jsonb(always || gated); end if;
  if exists (select 1 from home_hoods h join seasons x on x.id = h.season_id
              where h.player_id = p and x.id <> s.id and x.starts_at < s.starts_at) then
    return to_jsonb(always || gated);
  end if;
  select d.key into cur from _mission_defs(s.id) d
   where not d.pass_only and not exists (select 1 from missions m where m.player_id = p and m.season_id = s.id and m.key = d.key and m.claimed_at is not null)
   order by d.seq limit 1;
  return to_jsonb(always || coalesce((select array_agg(distinct x) from mission_defs d cross join unnest(d.unlocks) x
                                       where d.key = cur
                                          or exists (select 1 from missions m where m.player_id = p and m.season_id = s.id and m.key = d.key and m.claimed_at is not null)), '{}'::text[]));
end $$;


-- 'thugs' as an objective word: Hire Muscle counts thugs alone, not every hoodlum. Body from 20261030000022 plus one line.
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
    when 'thugs'        then v := (select coalesce(sum(qty), 0) from player_hoodlums where player_id = p and code = 'thug');
    when 'turf'         then v := pr.turf_attacks;
    -- the finale: a crew, five hoodlums, one city block hit; three ticks on the card
    when 'city'         then v := (pr.crew_id is not null)::int
                               + ((select coalesce(sum(qty), 0) from player_hoodlums where player_id = p) >= 5)::int
                               + (pr.turf_attacks >= 1)::int;
    else v := 0;
  end case;
  return coalesce(v, 0);
end $$;
update mission_defs set objective = 'thugs' where key = 'hire_muscle';

-- season_start's default troop values. Body from 20261106000026; only the default changed.
create or replace function season_start(nm text, from_at timestamptz default now(), months int default 3,
                                        defenders int[] default array[50000, 150000, 500000, 1000000, 2500000, 5000000, 10000000]) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); s seasons; draw text[];
begin
  if not _is_admin(u) then perform _fail('Admins only'); end if;
  if nullif(trim(nm), '') is null then perform _fail('Name the season'); end if;
  if array_length(defenders, 1) <> 7 then perform _fail('Seven defender numbers: six blocks and the boss'); end if;
  if months < 1 then perform _fail('A season is at least a month'); end if;
  if exists (select 1 from seasons x where x.cancelled_at is null and x.starts_at < from_at + make_interval(months => months) and x.ends_at > from_at) then
    perform _fail('That overlaps a season'); end if;
  select array_agg(code) into draw from (select code from business_defs order by random() limit 6) x;
  insert into seasons (name, starts_at, ends_at, home_businesses, home_defenders)
    values (trim(nm), from_at, from_at + make_interval(months => months), draw, defenders) returning * into s;
  return to_jsonb(s);
end $$;

-- --------------------------------------------------------------------------------------------------------------------
-- Grants
-- --------------------------------------------------------------------------------------------------------------------
do $$ declare f record; begin
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('_home_garrison', '_home_cfg', '_home_ensure', '_home_json', '_home_fight', '_unlocked', '_mission_progress') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('home_attack', 'home_boss', 'season_start') loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
