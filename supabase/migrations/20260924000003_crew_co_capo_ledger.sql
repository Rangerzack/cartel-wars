-- Crews: a Co-Capo, and a ledger for crew and cartel banks.
--  * The Capo can name one Co-Capo. The Co-Capo can do what the Capo does inside the crew
--    (applications, kicks, bank withdrawals, crew profile, pulling garrisons) but can't kick the Capo,
--    name a Co-Capo, or act for the crew in its cartel. If the Capo leaves, the Co-Capo takes over.
--  * Every movement of a crew or cartel bank is logged: deposits, withdrawals, block bonuses,
--    crew-fight stakes. Crew members can read their crew's ledger; any member of a cartel crew can
--    read the cartel's.

alter table crews add column if not exists co_capo_id uuid references profiles(id) on delete set null;

create table if not exists bank_ledger (
  id         bigserial primary key,
  crew_id    uuid references crews(id) on delete cascade,
  cartel_id  uuid references cartels(id) on delete cascade,
  player_id  uuid references profiles(id) on delete set null,
  kind       text not null check (kind in ('deposit', 'withdraw', 'bonus', 'fight_won', 'fight_lost')),
  amount     bigint not null,            -- signed: + into the bank, - out of it
  balance    bigint not null,            -- bank balance after this entry
  note       text not null default '',
  created_at timestamptz not null default now(),
  check ((crew_id is null) <> (cartel_id is null))
);
create index if not exists bank_ledger_crew_idx   on bank_ledger(crew_id, created_at desc)   where crew_id is not null;
create index if not exists bank_ledger_cartel_idx on bank_ledger(cartel_id, created_at desc) where cartel_id is not null;
alter table bank_ledger enable row level security;
revoke all on bank_ledger from anon, authenticated;

-- Log a crew-bank movement (call after updating crews.bank).
create or replace function _crew_ledger(cid uuid, who uuid, kind text, amount bigint, note text default '')
returns void language sql set search_path = public as $$
  insert into bank_ledger (crew_id, player_id, kind, amount, balance, note)
  select cid, who, kind, amount, c.bank, coalesce(note, '') from crews c where c.id = cid $$;

create or replace function _cartel_ledger(caid uuid, who uuid, kind text, amount bigint, note text default '')
returns void language sql set search_path = public as $$
  insert into bank_ledger (cartel_id, player_id, kind, amount, balance, note)
  select caid, who, kind, amount, ca.bank, coalesce(note, '') from cartels ca where ca.id = caid $$;

-- Capo or Co-Capo.
create or replace function _crew_boss(c crews, u uuid) returns boolean language sql immutable set search_path = public as $$
  select c.id is not null and (c.capo_id = u or c.co_capo_id = u) $$;

-- The crew the caller runs (as Capo or Co-Capo), locked.
create or replace function _my_bossed_crew(u uuid) returns crews language plpgsql set search_path = public as $$
declare c crews;
begin
  select x.* into c from crews x join profiles p on p.crew_id = x.id where p.id = u for update of x;
  if not _crew_boss(c, u) then perform _fail('Only the Capo or Co-Capo can do that'); end if;
  return c;
end $$;

create or replace function crew_set_co_capo(pid uuid) returns jsonb   -- pid null clears the Co-Capo
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); c crews; nm text;
begin
  select * into c from crews where capo_id = u for update;
  if c.id is null then perform _fail('Only the Capo can name a Co-Capo'); end if;
  if pid is not null then
    if pid = u then perform _fail('You are already the Capo'); end if;
    select name into nm from profiles where id = pid and crew_id = c.id;
    if nm is null then perform _fail('Not in your crew'); end if;
  end if;
  update crews set co_capo_id = pid where id = c.id;
  insert into messages (channel, sender_id, sender_name, body)
  select 'crew:' || c.id, u, p.name,
         case when pid is null then '🎖 The crew no longer has a Co-Capo.' else format('🎖 %s is now Co-Capo.', nm) end
    from profiles p where p.id = u;
  return jsonb_build_object('co_capo_id', pid);
end $$;

create or replace function crew_update(emblem text, description text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); c crews;
begin
  c := _my_bossed_crew(u);
  update crews x set emblem = left(coalesce(nullif(crew_update.emblem, ''), x.emblem), 8),
                     description = left(coalesce(crew_update.description, ''), 500)
   where x.id = c.id;
  return jsonb_build_object('ok', true);
end $$;

create or replace function crew_decide(pid uuid, accept boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); c crews; n int;
begin
  c := _my_bossed_crew(u);
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

create or replace function _crew_remove(c crews, pid uuid) returns void language plpgsql set search_path = public as $$
declare successor uuid;
begin
  update profiles set crew_id = null where id = pid;
  if c.co_capo_id = pid then update crews set co_capo_id = null where id = c.id; end if;
  if c.capo_id = pid then
    -- the Co-Capo steps up; otherwise the longest-standing member
    select id into successor from profiles where crew_id = c.id
     order by (id = c.co_capo_id) desc, created_at limit 1;
    if successor is null then
      -- disband: blocks freed (and any sieges on them dropped), cartel membership dropped
      delete from block_siege where block_id in (select id from blocks where owner_crew_id = c.id);
      update blocks set owner_crew_id = null, taken_at = null, bonus_at = null where owner_crew_id = c.id;
      update hoods set owner_crew_id = null where owner_crew_id = c.id;
      if c.cartel_id is not null then perform _cartel_drop_crew(c.cartel_id, c.id); end if;
      delete from crews where id = c.id;
    else
      update crews set capo_id = successor, co_capo_id = case when co_capo_id = successor then null else co_capo_id end where id = c.id;
      if c.cartel_id is not null then update cartels set don_id = successor where id = c.cartel_id and don_id = pid; end if;
    end if;
  end if;
end $$;

create or replace function crew_kick(pid uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); c crews;
begin
  c := _my_bossed_crew(u);
  if pid = u then perform _fail('Use Leave instead'); end if;
  if pid = c.capo_id then perform _fail('The Co-Capo cannot kick the Capo'); end if;
  if not exists (select 1 from profiles where id = pid and crew_id = c.id) then perform _fail('Not in your crew'); end if;
  perform _crew_remove(c, pid);
  return jsonb_build_object('ok', true);
end $$;

create or replace function crew_bank(amount bigint) returns jsonb  -- positive deposits, negative withdraws (Capo / Co-Capo)
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
    perform _crew_ledger(c.id, u, 'deposit', amount);
  elsif amount < 0 then
    if not _crew_boss(c, u) then perform _fail('Only the Capo or Co-Capo can withdraw'); end if;
    if -amount > c.bank then perform _fail('Not enough in the crew bank'); end if;
    update profiles set cash = cash - amount where id = u;
    update crews set bank = bank + amount where id = c.id;
    perform _crew_ledger(c.id, u, 'withdraw', amount);
  end if;
  return jsonb_build_object('bank', c.bank + amount);
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
    perform _cartel_ledger(car.id, u, 'deposit', amount);
  elsif amount < 0 then
    if car.don_id is distinct from u then perform _fail('Only the Don can withdraw'); end if;
    if -amount > car.bank then perform _fail('Not enough in the cartel bank'); end if;
    update profiles set cash = cash - amount where id = u;
    update cartels set bank = bank + amount where id = car.id;
    perform _cartel_ledger(car.id, u, 'withdraw', amount);
  end if;
  return jsonb_build_object('bank', car.bank + amount);
end $$;

-- scope: 'crew' (your crew) or 'cartel' (your crew's cartel)
create or replace function get_bank_ledger(scope text, limit_n integer default 50) returns jsonb
language plpgsql security definer set search_path = public stable as $$
declare u uuid := _uid(); cid uuid; caid uuid;
begin
  select p.crew_id, c.cartel_id into cid, caid from profiles p left join crews c on c.id = p.crew_id where p.id = u;
  if scope = 'crew' then
    if cid is null then perform _fail('You are not in a crew'); end if;
  elsif scope = 'cartel' then
    if caid is null then perform _fail('Your crew is not in a cartel'); end if;
  else
    perform _fail('Bad ledger');
  end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('id', l.id, 'kind', l.kind, 'amount', l.amount, 'balance', l.balance,
            'note', l.note, 'at', l.created_at, 'player', p.name, 'player_id', l.player_id) order by l.created_at desc, l.id desc), '[]'::jsonb)
          from (select * from bank_ledger
                 where case when scope = 'crew' then crew_id = cid else cartel_id = caid end
                 order by created_at desc, id desc limit least(greatest(limit_n, 1), 200)) l
          left join profiles p on p.id = l.player_id);
end $$;

-- Crew fights now write the stake to both crews' ledgers.
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
    if taken > 0 then
      perform _crew_ledger(mine.id, u, 'fight_won', taken, 'Beat ' || theirs.name);
      perform _crew_ledger(theirs.id, u, 'fight_lost', -taken, 'Hit by ' || mine.name);
    end if;
  else
    taken := floor(mine.bank * _cfg('crew_fight_stake_pct') / 100.0);
    update crews set bank = bank - taken where id = mine.id;
    update crews set bank = bank + taken where id = theirs.id;
    update profiles set health = greatest(1, health - _rand_between(10, 25)) where crew_id = mine.id and health > 19 and immune_until <= now() and id <> u;
    update profiles set health = greatest(1, health - _rand_between(3, 8))   where crew_id = theirs.id and health > 19 and immune_until <= now() and id <> u;
    if taken > 0 then
      perform _crew_ledger(mine.id, u, 'fight_lost', -taken, 'Pushed back by ' || theirs.name);
      perform _crew_ledger(theirs.id, u, 'fight_won', taken, 'Held off ' || mine.name);
    end if;
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

create or replace function get_crew(cid uuid) returns jsonb
language plpgsql security definer set search_path = public stable as $$
declare u uuid := _uid(); c crews; boss boolean;
begin
  select * into c from crews where id = cid;
  if c.id is null then perform _fail('No such crew'); end if;
  boss := _crew_boss(c, u);
  return jsonb_build_object('id', c.id, 'name', c.name, 'emblem', c.emblem, 'description', c.description,
    'capo_id', c.capo_id, 'is_capo', c.capo_id = u, 'co_capo_id', c.co_capo_id, 'is_co_capo', c.co_capo_id = u,
    'is_boss', boss, 'created_at', c.created_at,
    'bank', case when exists (select 1 from profiles where id = u and crew_id = c.id) then c.bank end,
    'cartel', (select jsonb_build_object('id', id, 'name', name, 'don_id', don_id) from cartels where id = c.cartel_id),
    'members', (select coalesce(jsonb_agg(jsonb_build_object('id', p.id, 'name', p.name, 'avatar', p.avatar, 'fights_won', p.fights_won,
                  'actions', p.actions_done, 'is_capo', p.id = c.capo_id, 'is_co_capo', p.id = c.co_capo_id, 'last_seen', p.last_seen)
                  order by p.id = c.capo_id desc, p.id = c.co_capo_id desc, p.name), '[]'::jsonb)
                from profiles p where p.crew_id = c.id),
    'blocks', (select coalesce(jsonb_agg(jsonb_build_object('id', b.id, 'name', b.name, 'hood', h.name, 'hood_id', h.id, 'island', h.island,
                  'bonus_at', b.bonus_at) order by b.bonus_at nulls last), '[]'::jsonb)
               from blocks b join hoods h on h.id = b.hood_id where b.owner_crew_id = c.id),
    'applications', case when boss then
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

do $$ declare f record; begin
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('crew_set_co_capo', 'get_bank_ledger', 'buy_health') loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
