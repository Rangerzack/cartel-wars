-- Territory rebuilt, Cartel Wars style.
--  * The city is a 9x9 grid of hoods; each hood is a 2x3 grid of 6 blocks (properties).
--    Hoods toward the center are pricier, pay more and are harder to hit.
--  * Every block pays its owner a bonus once per cycle (24h): 80% to the crew bank, 20% to the cartel bank.
--    Each block shows a countdown to its next bonus.
--  * A turf attack needs at least 51 thugs (mercenaries optional on top).
--  * An empty block is claimed with one successful attack (plus the claim price).
--  * An owned block falls only after the attacking crew lands 50 successful attacks on it (counted across
--    the whole crew). Every successful hit also restarts the owner's bonus countdown.
--  * Every attack on a block is logged and readable per block.
-- The old 12-hood map is wiped: ownership, garrisons and logs are cleared.

delete from territory_log;
delete from block_garrison;
delete from blocks;
delete from hoods;

alter table hoods add column if not exists gx integer;
alter table hoods add column if not exists gy integer;
alter table blocks add column if not exists slot integer;
alter table blocks add column if not exists bonus_at timestamptz;     -- next bonus; null while unowned

alter table territory_log add column if not exists defender_crew_id uuid references crews(id) on delete set null;
alter table territory_log add column if not exists thugs        integer not null default 0;
alter table territory_log add column if not exists mercs        integer not null default 0;
alter table territory_log add column if not exists lost_thugs   integer not null default 0;
alter table territory_log add column if not exists lost_mercs   integer not null default 0;
alter table territory_log add column if not exists garrison_lost integer not null default 0;
alter table territory_log add column if not exists siege_wins   integer;           -- attacking crew's count after this hit
alter table territory_log add column if not exists captured     boolean not null default false;
create index if not exists territory_log_block_idx on territory_log(block_id, created_at desc);

create table if not exists block_siege (
  block_id   integer references blocks(id) on delete cascade,
  crew_id    uuid references crews(id) on delete cascade,
  wins       integer not null default 0,
  updated_at timestamptz not null default now(),
  primary key (block_id, crew_id)
);
alter table block_siege enable row level security;
revoke all on block_siege from anon, authenticated;

-- 9 districts (rows A–I) x 9 streets (columns 1–9). Ring 0 is the center hood, ring 4 the outer edge.
with d(gy, district) as (values (1, 'Harbor'), (2, 'Cannery'), (3, 'Bluffs'), (4, 'Railside'), (5, 'Medellín'),
                                (6, 'Iron'), (7, 'Boardwalk'), (8, 'Marina'), (9, 'Hilltop')),
     s(gx, street) as (values (1, 'Row'), (2, 'Flats'), (3, 'Park'), (4, 'Point'), (5, 'Square'),
                             (6, 'Court'), (7, 'Gardens'), (8, 'Terrace'), (9, 'Yards')),
     t(ring, price, income, res) as (values (0, 50000, 1000000, 1400), (1, 42000, 840000, 900), (2, 32000, 640000, 600),
                                           (3, 24000, 480000, 400), (4, 16000, 320000, 250))
insert into hoods (island, name, price, daily_income, base_resistance, gx, gy)
select d.district, d.district || ' ' || s.street, t.price, t.income, t.res, s.gx, d.gy
  from d cross join s join t on t.ring = greatest(abs(s.gx - 5), abs(d.gy - 5))
 order by d.gy, s.gx;

alter table hoods alter column gx set not null;
alter table hoods alter column gy set not null;
create unique index if not exists hoods_grid_idx on hoods(gx, gy);

insert into blocks (hood_id, name, slot)
select h.id, h.name || ' — Block ' || chr(64 + s), s from hoods h cross join generate_series(1, 6) s order by h.id, s;
alter table blocks alter column slot set not null;
create index if not exists blocks_bonus_idx on blocks(bonus_at) where owner_crew_id is not null;

-- Per-block bonus for one cycle.
create or replace function _block_bonus(daily_income integer) returns bigint language sql immutable set search_path = public as $$
  select floor(daily_income / 6.0 * _cfg('block_bonus_hours') / 24.0)::bigint $$;

-- World tick: expired listings, and block bonuses (replaces the old hood-level daily payout).
create or replace function _tick_world() returns void language plpgsql set search_path = public as $$
declare l record; b record; periods int; income bigint; cartel uuid; cut bigint;
        cycle interval := make_interval(hours => _cfg('block_bonus_hours')::int);
begin
  -- expired listings go back to storage; whatever doesn't fit waits in a 'returned' holding listing
  for l in select * from listings where status = 'open' and expires_at <= now() for update skip locked loop
    perform _return_product(l.seller_id, l.commodity, l.qty, l.id, 'expired');
  end loop;

  for b in select bl.id, bl.name, bl.owner_crew_id, bl.bonus_at, h.daily_income
             from blocks bl join hoods h on h.id = bl.hood_id
            where bl.owner_crew_id is not null and bl.bonus_at <= now()
            for update of bl skip locked loop
    periods := 1 + floor(extract(epoch from now() - b.bonus_at) / extract(epoch from cycle))::int;
    income := _block_bonus(b.daily_income) * periods;
    select cartel_id into cartel from crews where id = b.owner_crew_id;
    if cartel is null then
      update crews set bank = bank + income where id = b.owner_crew_id;
      perform _crew_ledger(b.owner_crew_id, null, 'bonus', income, b.name);
    else
      cut := (income * 0.2)::bigint;
      update crews set bank = bank + (income - cut) where id = b.owner_crew_id;
      update cartels set bank = bank + cut where id = cartel;
      perform _crew_ledger(b.owner_crew_id, null, 'bonus', income - cut, b.name);
      perform _cartel_ledger(cartel, null, 'bonus', cut, b.name);
    end if;
    update blocks set bonus_at = b.bonus_at + periods * cycle where id = b.id;
  end loop;
end $$;

create or replace function get_territory() returns jsonb
language sql security definer set search_path = public stable as $$
  with me as (select crew_id from profiles where id = auth.uid()),
  g as (select block_id, sum(qty) as n, jsonb_object_agg(code, qty) as garrison
          from block_garrison where qty > 0 group by block_id),
  s as (select block_id, max(wins) as top, max(wins) filter (where crew_id = (select crew_id from me)) as mine
          from block_siege group by block_id),
  bl as (select b.hood_id,
                count(*) filter (where b.owner_crew_id = (select crew_id from me)) as my_blocks,
                jsonb_agg(jsonb_build_object('id', b.id, 'slot', b.slot, 'name', b.name,
                  'owner', case when c.id is not null then jsonb_build_object('id', c.id, 'name', c.name, 'emblem', c.emblem) end,
                  'mine', b.owner_crew_id is not null and b.owner_crew_id = (select crew_id from me),
                  'garrisoned', g.n is not null,
                  'garrison_size', case when b.owner_crew_id = (select crew_id from me) then coalesce(g.n, 0) end,
                  'garrison', case when b.owner_crew_id = (select crew_id from me) then g.garrison end,
                  'bonus_at', b.bonus_at,
                  'my_wins', coalesce(s.mine, 0), 'top_wins', coalesce(s.top, 0)) order by b.slot) as blocks
           from blocks b left join crews c on c.id = b.owner_crew_id
           left join g on g.block_id = b.id left join s on s.block_id = b.id
          group by b.hood_id)
  select jsonb_build_object(
    'hoods', coalesce(jsonb_agg(jsonb_build_object('id', h.id, 'name', h.name, 'district', h.island, 'gx', h.gx, 'gy', h.gy,
               'price', h.price, 'claim_price', h.price / 6, 'daily_income', h.daily_income, 'block_bonus', _block_bonus(h.daily_income),
               'base_resistance', h.base_resistance, 'my_blocks', bl.my_blocks,
               'owner', (select jsonb_build_object('id', c.id, 'name', c.name, 'emblem', c.emblem) from crews c where c.id = h.owner_crew_id),
               'blocks', bl.blocks) order by h.gy, h.gx), '[]'::jsonb),
    'rules', jsonb_build_object('siege_wins', _cfg('siege_wins'), 'min_thugs', _cfg('siege_min_thugs'),
                                'bonus_hours', _cfg('block_bonus_hours'), 'stamina', 3))
  from hoods h join bl on bl.hood_id = h.id $$;

create or replace function _territory_log_json(l territory_log) returns jsonb language sql stable set search_path = public as $$
  select jsonb_build_object('id', l.id, 'block_id', l.block_id, 'block', b.name, 'hood', h.name, 'hood_id', h.id,
           'attacker', p.name, 'attacker_id', l.attacker_id, 'crew', c.name, 'crew_emblem', c.emblem,
           'defender_crew', dc.name, 'success', l.success, 'captured', l.captured, 'attack', l.attack, 'resistance', l.resistance,
           'thugs', l.thugs, 'mercs', l.mercs, 'lost_thugs', l.lost_thugs, 'lost_mercs', l.lost_mercs,
           'garrison_lost', l.garrison_lost, 'siege_wins', l.siege_wins, 'at', l.created_at)
    from blocks b join hoods h on h.id = b.hood_id
    left join profiles p on p.id = l.attacker_id left join crews c on c.id = l.crew_id left join crews dc on dc.id = l.defender_crew_id
   where b.id = l.block_id $$;

create or replace function get_territory_log(limit_n integer default 30) returns jsonb
language sql security definer set search_path = public stable as $$
  select coalesce(jsonb_agg(_territory_log_json(l) order by l.created_at desc, l.id desc), '[]'::jsonb)
  from (select * from territory_log order by created_at desc, id desc limit least(greatest(limit_n, 1), 100)) l $$;

create or replace function get_block(block integer) returns jsonb
language plpgsql security definer set search_path = public stable as $$
declare u uuid := _uid(); b blocks; h hoods; my_crew uuid; mine boolean;
begin
  select * into b from blocks where id = block;
  if b.id is null then perform _fail('No such block'); end if;
  select * into h from hoods where id = b.hood_id;
  select crew_id into my_crew from profiles where id = u;
  mine := b.owner_crew_id is not null and b.owner_crew_id = my_crew;
  return jsonb_build_object('id', b.id, 'name', b.name, 'slot', b.slot, 'hood_id', h.id, 'hood', h.name, 'district', h.island,
    'gx', h.gx, 'gy', h.gy, 'claim_price', h.price / 6, 'block_bonus', _block_bonus(h.daily_income),
    'base_resistance', h.base_resistance, 'bonus_at', b.bonus_at, 'taken_at', b.taken_at, 'mine', mine,
    'owner', (select jsonb_build_object('id', c.id, 'name', c.name, 'emblem', c.emblem) from crews c where c.id = b.owner_crew_id),
    'garrisoned', exists (select 1 from block_garrison where block_id = b.id and qty > 0),
    'garrison', case when mine then (select coalesce(jsonb_object_agg(code, qty), '{}'::jsonb) from block_garrison where block_id = b.id and qty > 0) end,
    'siege', (select coalesce(jsonb_agg(jsonb_build_object('crew_id', c.id, 'crew', c.name, 'emblem', c.emblem, 'wins', s.wins,
                'mine', c.id = my_crew, 'at', s.updated_at) order by s.wins desc, s.updated_at), '[]'::jsonb)
              from block_siege s join crews c on c.id = s.crew_id where s.block_id = b.id and s.wins > 0),
    'log', (select coalesce(jsonb_agg(_territory_log_json(l) order by l.created_at desc, l.id desc), '[]'::jsonb)
            from (select * from territory_log where block_id = b.id order by created_at desc, id desc limit 30) l));
end $$;

create or replace function withdraw_garrison(block integer, kind text, n integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; b blocks; c crews; have int;
begin
  perform _nn(n, 'quantity');
  pr := _tick(u);
  select * into b from blocks where id = block for update;
  select * into c from crews where id = pr.crew_id;
  if b.id is null or c.id is null or b.owner_crew_id is distinct from c.id or not _crew_boss(c, u) then
    perform _fail('Only your Capo or Co-Capo can withdraw a garrison');
  end if;
  select bg.qty into have from block_garrison bg where bg.block_id = block and bg.code = kind;
  if n <= 0 or coalesce(have, 0) < n then perform _fail('Not that many stationed'); end if;
  update block_garrison bg set qty = bg.qty - n where bg.block_id = block and bg.code = kind;
  insert into player_hoodlums as ph (player_id, code, qty) values (u, kind, n)
    on conflict (player_id, code) do update set qty = ph.qty + excluded.qty;
  return jsonb_build_object('ok', true);
end $$;

-- Attack a block with thugs (at least 51) and optional mercenaries.
create or replace function attack_block(block integer, thugs integer, mercs integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; b blocks; h hoods; have_t int; have_m int; atk numeric; res numeric;
        claim int := 0; success boolean; captured boolean := false; loss_frac numeric; lost_t int; lost_m int;
        g record; gloss numeric; glost int := 0; nwins int; defender crews; my_cartel uuid;
        need int := _cfg('siege_wins')::int; min_thugs int := _cfg('siege_min_thugs')::int;
        cycle interval := make_interval(hours => _cfg('block_bonus_hours')::int);
begin
  perform _nn(thugs, 'thugs'); perform _nn(mercs, 'mercenaries');
  pr := _tick(u);
  if pr.crew_id is null then perform _fail('Join a crew to fight for territory'); end if;
  if _jailed(pr) then perform _fail('You cannot run a turf war from jail'); end if;
  if _hospital(pr) then perform _fail('You are in the hospital'); end if;
  if mercs < 0 then perform _fail('Bad number of mercenaries'); end if;
  if thugs < min_thugs then perform _fail(format('A turf attack needs at least %s thugs', min_thugs)); end if;
  select * into b from blocks where id = block for update;
  if b.id is null then perform _fail('No such block'); end if;
  if b.owner_crew_id = pr.crew_id then perform _fail('Your crew already holds that block'); end if;
  select * into h from hoods where id = b.hood_id;
  if b.owner_crew_id is not null then
    select * into defender from crews where id = b.owner_crew_id;
    select cartel_id into my_cartel from crews where id = pr.crew_id;
    if my_cartel is not null and defender.cartel_id = my_cartel then perform _fail('That block belongs to a crew in your cartel'); end if;
  end if;
  select coalesce(qty,0) into have_t from player_hoodlums where player_id = u and code = 'thug';
  select coalesce(qty,0) into have_m from player_hoodlums where player_id = u and code = 'mercenary';
  if coalesce(have_t,0) < thugs or coalesce(have_m,0) < mercs then perform _fail('Not enough hoodlums'); end if;
  if b.owner_crew_id is null then
    claim := h.price / 6;
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
  for g in select * from block_garrison where block_id = block and qty > 0 loop
    glost := glost + floor(g.qty * gloss)::int;
    update block_garrison set qty = qty - floor(g.qty * gloss)::int where block_id = block and code = g.code;
  end loop;

  if success then
    if b.owner_crew_id is null then
      captured := true;                                   -- empty block: one win claims it
    else
      insert into block_siege as s (block_id, crew_id, wins) values (block, pr.crew_id, 1)
        on conflict (block_id, crew_id) do update set wins = s.wins + 1, updated_at = now()
        returning s.wins into nwins;
      if nwins >= need then
        captured := true;
      else
        update blocks set bonus_at = now() + cycle where id = block;   -- every hit restarts their bonus clock
      end if;
    end if;
  end if;

  if captured then
    glost := glost + coalesce((select sum(qty) from block_garrison where block_id = block), 0)::int;
    delete from block_garrison where block_id = block;
    delete from block_siege where block_id = block;
    update blocks set owner_crew_id = pr.crew_id, taken_at = now(), bonus_at = now() + cycle where id = block;
    if claim > 0 then update profiles set cash = cash - claim where id = u; end if;
    perform _recompute_hood(h.id);
    perform _event(u, 'turf');
    if defender.id is not null then
      insert into messages (channel, sender_id, sender_name, body)
      values ('crew:' || defender.id, u, pr.name, format('🏚 %s took %s from your crew.', (select name from crews where id = pr.crew_id), b.name));
    end if;
  end if;

  insert into territory_log (block_id, attacker_id, crew_id, defender_crew_id, success, captured, attack, resistance,
                             thugs, mercs, lost_thugs, lost_mercs, garrison_lost, siege_wins)
  values (block, u, pr.crew_id, b.owner_crew_id, success, captured, round(atk), round(res),
          thugs, mercs, lost_t, lost_m, glost, case when b.owner_crew_id is not null then coalesce(nwins, (select s.wins from block_siege s where s.block_id = block and s.crew_id = pr.crew_id), 0) end);
  return jsonb_build_object('success', success, 'captured', captured, 'attack', round(atk), 'resistance', round(res),
    'lost_thugs', lost_t, 'lost_mercs', lost_m, 'garrison_lost', glost,
    'claim_paid', case when captured then claim else 0 end,
    'wins', case when b.owner_crew_id is not null then case when captured then need else coalesce(nwins, (select s.wins from block_siege s where s.block_id = block and s.crew_id = pr.crew_id), 0) end end,
    'wins_needed', need,
    'bonus_reset', success and not captured and b.owner_crew_id is not null);
end $$;

do $$ declare f record; begin
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('get_block') loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
