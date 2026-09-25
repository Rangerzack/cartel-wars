-- Local-only demo world: 24 bot players, crews, a cartel, held blocks, listings, chat, fights.
-- Bots sign in as bot01@demo.local … bot24@demo.local / secret123 (dev-server.mjs only).
-- Run: npm run db:demo   (after db:reset)
\set ON_ERROR_STOP on
\set QUIET on

do $$
declare
  names text[] := array['Escobar','Lalo','Nacho','Tuco','Gus','Hector','Marco','Leonel','Fring','Chapo','Ochoa','Salazar',
                        'Vega','Pinto','Rojas','Duarte','Ibarra','Cruz','Mendez','Zamora','Ruiz','Ortiz','Lima','Reyes'];
  uid uuid; i int; crew_a uuid; crew_b uuid; crew_c uuid; cartel uuid; pid uuid;
  ids uuid[] := '{}';
begin
  -- players
  for i in 1..array_length(names, 1) loop
    uid := gen_random_uuid();
    insert into auth.users (id, email, raw_user_meta_data, password)
    values (uid, format('bot%s@demo.local', lpad(i::text, 2, '0')), jsonb_build_object('name', names[i]), 'secret123');
    ids := ids || uid;
    update profiles set
      cash = 5000 + (random() * 400000)::int, bank = (random() * 900000)::int, diamonds = (random() * 60)::int,
      immune_until = now() - interval '1 day', created_at = now() - (random() * 60 || ' days')::interval,
      last_seen = now() - (random() * 3 || ' days')::interval,
      actions_done = (random() * 3000)::int, fights_won = (random() * 400)::int, fights_lost = (random() * 300)::int,
      imports = (random() * 20000)::int, market_volume = (random() * 3000000)::int,
      stamina_max = 25 + 5 * (random() * 10)::int, health_max = 100 + 25 * (random() * 6)::int,
      heat = (random() * 90)::int,
      avatar = (array['🕶️','🐍','🦂','💀','🐺','🦅','🃏','🔥','🌵','🐊','🥷','👑'])[1 + (random() * 11)::int],
      bio = (array['Plata o plomo.','Producers welcome, snitches not.','Runs the docks.','Never lost a block.','Buying pills, paying street.',''])[1 + (random() * 5)::int],
      reputation = (random() * 80)::int
    where id = uid;
    update profiles set stamina = stamina_max, health = health_max where id = uid;
    -- gear: a weapon, protection and vehicle scaled by wealth
    insert into inventory (player_id, item_id, qty)
      select uid, id, 1 from item_defs where category = 'weapon' and price <= 20000 + (random() * 300000)::int order by price desc limit 2;
    insert into inventory (player_id, item_id, qty)
      select uid, id, 1 from item_defs where category = 'protection' and price <= 10000 + (random() * 200000)::int order by price desc limit 2;
    insert into inventory (player_id, item_id, qty)
      select uid, id, 1 from item_defs where category = 'transport' and price <= 5000 + (random() * 300000)::int order by price desc limit 1;
    insert into inventory (player_id, item_id, qty) select uid, id, 1 from item_defs where name = 'Shank';
    insert into setup_items (player_id, setup, item_id, qty) select uid, 'offense', item_id, 1 from inventory where player_id = uid and item_id in (select id from item_defs where category <> 'jail_weapon');
    insert into setup_items (player_id, setup, item_id, qty) select uid, 'defense', item_id, 1 from inventory where player_id = uid and item_id in (select id from item_defs where category <> 'jail_weapon');
    insert into setup_items (player_id, setup, item_id, qty) select uid, 'jail', item_id, 1 from inventory where player_id = uid and item_id in (select id from item_defs where category in ('jail_weapon','protection'));
    -- product + production
    update storage set qty = (random() * 400)::int where player_id = uid and commodity = 'herb';
    update storage set qty = (random() * 150)::int where player_id = uid and commodity = 'dust';
    update storage set qty = (random() * 40)::int where player_id = uid and commodity = 'pills';
    insert into grow_houses (player_id, commodity, level, running, started_at) values (uid, 'herb', 1 + (random() * 4)::int, true, now() - interval '2 hours');
    if random() < 0.5 then insert into grow_houses (player_id, commodity, level, running, started_at) values (uid, 'dust', 1 + (random() * 2)::int, true, now() - interval '1 hour'); end if;
    -- hoodlums
    insert into player_hoodlums (player_id, code, qty) values (uid, 'thug', (random() * 200)::int), (uid, 'spy', (random() * 5)::int),
      (uid, 'mercenary', (random() * 20)::int), (uid, 'enforcer', (random() * 20)::int);
  end loop;

  -- crews
  insert into crews (name, emblem, description, capo_id) values ('Los Pollos', '🐔', 'Chicken and more.', ids[1]) returning id into crew_a;
  insert into crews (name, emblem, description, capo_id) values ('Harbor Kings', '👑', 'We run the docks.', ids[7]) returning id into crew_b;
  insert into crews (name, emblem, description, capo_id) values ('Sinaloa Sur', '🌵', 'Recruiting. Producers welcome.', ids[13]) returning id into crew_c;
  update profiles set crew_id = crew_a where id = any(ids[1:6]);
  update profiles set crew_id = crew_b where id = any(ids[7:12]);
  update profiles set crew_id = crew_c where id = any(ids[13:18]);
  update crews set bank = (random() * 2000000)::int;
  insert into crew_applications (crew_id, player_id) values (crew_a, ids[19]), (crew_a, ids[20]);

  -- cartel
  insert into cartels (name, don_id, bank) values ('Juárez', ids[1], 1500000) returning id into cartel;
  update crews set cartel_id = cartel where id in (crew_a, crew_c);
  insert into cartel_invites (cartel_id, crew_id) values (cartel, crew_b);

  -- territory: crew A holds most of the Harbor row, crew B the Hilltop row, C scattered around the center
  update blocks b set owner_crew_id = crew_a, taken_at = now() - interval '3 days' from hoods h where h.id = b.hood_id and h.gy = 1 and h.gx <= 6 and b.slot <> 6;
  update blocks b set owner_crew_id = crew_b, taken_at = now() - interval '1 day' from hoods h where h.id = b.hood_id and h.gy = 9 and h.gx >= 4 and b.slot <> 1;
  update blocks b set owner_crew_id = crew_c, taken_at = now() - interval '5 hours' from hoods h where h.id = b.hood_id and h.gy between 4 and 6 and h.gx between 4 and 6 and b.slot in (2, 4);
  update blocks set bonus_at = now() + (random() * 24 || ' hours')::interval where owner_crew_id is not null;
  -- sieges in progress: A is hitting B's hilltop blocks, B is hitting A back
  insert into block_siege (block_id, crew_id, wins, updated_at)
    select id, crew_a, 5 + (random() * 40)::int, now() - (random() * 5 || ' hours')::interval from blocks b
     where owner_crew_id = crew_b and random() < 0.4;
  insert into block_siege (block_id, crew_id, wins, updated_at)
    select id, crew_b, 1 + (random() * 20)::int, now() - (random() * 5 || ' hours')::interval from blocks b
     where owner_crew_id = crew_a and random() < 0.25;
  insert into block_garrison (block_id, code, qty) select id, 'thug', 20 + (random() * 100)::int from blocks where owner_crew_id is not null;
  insert into block_garrison (block_id, code, qty) select id, 'enforcer', (random() * 10)::int from blocks where owner_crew_id is not null;
  perform _recompute_hood(id) from hoods;

  -- marketplace listings
  for i in 1..12 loop
    pid := ids[1 + (random() * 23)::int];
    -- note: random() in a select list gets correlated with `order by random()`, so pick the row first
    insert into listings (seller_id, commodity, qty, unit_price, expires_at)
    select pid, x.code, 25 * (1 + (random() * 8)::int), greatest(1, (x.price * (0.7 + random() * 0.3))::int), now() + (random() * 40 || ' hours')::interval
      from (select c.code, sp.price from commodities c join street_prices sp on sp.commodity = c.code order by random() limit 1) x;
  end loop;

  -- fights and turf log
  for i in 1..80 loop
    insert into fights (attacker_id, defender_id, attacker_dmg, defender_dmg, cash_taken, winner_id, created_at)
    select a, d, da, dd, (random() * 20000)::int, case when da > dd then a else d end, now() - (random() * 6 || ' days')::interval
      from (select ids[1 + (random() * 23)::int] a, ids[1 + (random() * 23)::int] d, (random() * 80)::int da, (random() * 30)::int dd) x where a <> d;
  end loop;
  insert into accolade_events (player_id, kind, amount, created_at)
    select case when f.winner_id = f.attacker_id then f.attacker_id else f.defender_id end,
           case when f.winner_id = f.attacker_id then 'fight_win' else 'defense' end, 1, f.created_at from fights f;
  insert into accolade_events (player_id, kind, amount, created_at)
    select ids[1 + (random() * 23)::int], k.kind, case k.kind when 'action' then 1 when 'import' then 8 + (random() * 60)::int when 'market' then 500 + (random() * 40000)::int else 1 end,
           now() - (random() * 13 || ' days')::interval
      from generate_series(1, 600), lateral (select (array['action','action','action','import','market','turf'])[1 + (random() * 5)::int] as kind) k;
  for i in 1..40 loop
    insert into territory_log (block_id, attacker_id, crew_id, defender_crew_id, success, attack, resistance, thugs, mercs,
                               lost_thugs, garrison_lost, siege_wins, created_at)
    select x.bid, x.pid, x.cid, x.owner, y.a > y.r, y.a, y.r, y.a / 10, 0, (y.r / 40), case when y.a > y.r then 3 else 0 end,
           case when x.owner is not null then 1 + (random() * 40)::int end, now() - (random() * 2 || ' days')::interval
      from (select b.id bid, b.owner_crew_id owner, p.id pid, p.crew_id cid from blocks b, profiles p
             where p.crew_id is not null and b.owner_crew_id is distinct from p.crew_id and b.owner_crew_id is not null
             order by random() limit 1) x,
           (select 510 + (random() * 900)::int a, 250 + (random() * 700)::int r) y;
  end loop;
  -- ledgers
  insert into bank_ledger (crew_id, player_id, kind, amount, balance, note, created_at)
    select c.id, case when k = 'bonus' then null else (select id from profiles where crew_id = c.id order by random() limit 1) end, k,
           case k when 'withdraw' then -(random() * 200000)::int when 'bonus' then 42666 else (random() * 150000)::int end,
           c.bank, case when k = 'bonus' then 'Harbor Row — Block A' else '' end, now() - (g * interval '37 minutes')
      from crews c cross join generate_series(1, 12) g cross join lateral (select (array['deposit','withdraw','bonus','bonus'])[1 + (random() * 3)::int] k) kk;
  insert into bank_ledger (cartel_id, player_id, kind, amount, balance, note, created_at)
    select cartel, null, 'bonus', 10667, 1500000, 'Harbor Row — Block ' || chr(64 + g), now() - (g * interval '1 hour') from generate_series(1, 5) g;
  update crews set co_capo_id = ids[2] where id = crew_a;
  update profiles set reputation = reputation + 150 where id = ids[1];   -- bot01 has to pick a path

  -- chat
  insert into messages (channel, sender_id, sender_name, body, created_at)
    select 'global', p.id, p.name, m.body, now() - (row_number() over () * interval '7 minutes')
      from (values ('anyone selling pills under 550?'), ('Harbor Kings are soft, take the port'), ('who keeps hitting Block C'),
                   ('lf crew, I run 3 grow houses'), ('street price on dust is crashing lol'), ('Juárez recruiting crews, dm Escobar'),
                   ('busted twice today, bribe is worth it'), ('anyone else get jail weapons confiscated?'), ('gg Lalo'), ('herb 40/u, 500 units, listing now')) m(body)
      cross join lateral (select * from profiles where m.body is not null order by random() limit 1) p;
  insert into messages (channel, sender_id, sender_name, body) select 'crew:' || crew_a, id, name, 'Station enforcers on Harbor Row before the weekend.' from profiles where id = ids[1];
  insert into messages (channel, sender_id, sender_name, body) select 'cartel:' || cartel, id, name, 'Cartel bank hit 1.5M. Hoods pay out at midnight.' from profiles where id = ids[1];
end $$;

\echo 'DEMO WORLD SEEDED — sign in as bot01@demo.local … bot24@demo.local / secret123'
