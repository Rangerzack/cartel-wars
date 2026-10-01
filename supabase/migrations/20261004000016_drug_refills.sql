-- Drug refills (Zack, 2026-10-01).
--
-- Herb, dust and pills refill stamina only now; health comes from the Hospital (cash) or diamonds. Each drug fills
-- your stamina all the way 3 times a game day, counted per drug, so 9 full refills a day if you hold all three; Daily
-- Drop subscribers get 5 of each. Past those, a refill of that drug restores half your stamina bar (50% of max, up to
-- full) instead of the old shrinking ½, ¼, ⅛ … of what's missing. The counts come back at 00:00 UTC like the rest.
--
-- profiles.drug_refills holds today's counts with the game day they belong to ({"day": "2026-10-01", "herb": 2}), so a
-- new day reads as zero without _tick having to reset it. refills_used still counts every drug refill (the rollover
-- and older clients read it). Diamond and free (Daily Drop) refills are unchanged: always full, never counted.

alter table profiles add column if not exists drug_refills jsonb not null default '{}'::jsonb;

-- ---------------------------------------------------------------------------
-- Tunables: refill_full is now per drug; refill_sub_extra and refill_late_share are new
-- ---------------------------------------------------------------------------
create or replace function _cfg(key text) returns numeric language sql immutable set search_path = public as $$
  select case key
    when 'regen_minutes'      then 10     -- heat cools 1 point every 10 min
    -- Regen boost (10x): stamina +2 every minute (was every 10), health +10 every minute (was +5 every 5).
    -- To go back: stamina_regen_minutes 10, health_regen_minutes 5, health_regen_amount 5.
    when 'stamina_regen_minutes' then 1
    when 'stamina_regen_amount'  then 2
    when 'health_regen_minutes' then 1
    when 'health_regen_amount'  then 10
    when 'hospital_release_pct' then 20   -- knocked out at 19 health or less; back out at this % of max health
    when 'heat_yellow'        then 40     -- at base max heat; each heat upgrade moves both lines up by its amount
    when 'heat_red'           then 75
    -- Jail has no timer: you're inside until you post bail (bail_base, less the Law Office). bail_per_minute stays at 0
    -- only so pages from before the change still show the right bail.
    when 'jail_diamonds'      then 50     -- turn yourself in: straight to jail, no stamina or cash
    when 'bail_base'          then 8000
    when 'bail_per_minute'    then 0
    when 'bribe_per_heat'     then 40
    when 'heat_base'          then 100    -- everyone's max heat before upgrades
    when 'heat_upgrade_diamonds' then 30  -- a heat upgrade: +heat_upgrade_amount max heat, and the yellow/red lines move up
    when 'heat_upgrade_amount' then 50    --   with it (red at heat_red + the extra). Flat price, no cap.
    when 'hospital_per_point' then 40     -- base $ per health point
    when 'health_price_scale' then 100    -- price per point grows by 1x for every 100 points bought in 24h
    when 'refill_diamonds'    then 6
    when 'refill_full'        then 3      -- full stamina refills per drug (herb, dust, pills) a game day
    when 'refill_sub_extra'   then 2      -- Daily Drop subscribers get this many more of each
    when 'refill_late_share'  then 0.5    -- past those, a drug refill restores this share of max stamina
    when 'hustler_price'      then 400    -- per hustler, for players who haven't picked a path (Traders pay a cut instead)
    when 'hustler_hours'      then 4
    when 'trader_cut_pct'     then 10     -- Traders: their hustlers keep this % of the take, nothing up front
    when 'trader_markup_pct'  then 10     -- ... and Traders sell this % over street
    when 'listing_min'        then 25
    when 'listing_max'        then 1000
    when 'listing_max_pct'    then 150    -- listings and buy orders can be priced up to this % of street
    when 'market_fee_pct'     then 5      -- the seller pays this % of every Marketplace sale
    when 'order_max'          then 10000  -- most units one buy order can ask for
    when 'orders_open_max'    then 5      -- open buy orders a player can have at once
    when 'price_noise_pct'    then 15     -- street price wiggles at most this % either side of base ...
    when 'price_step_pct'     then 4      -- ... moving at most this much every 10 minutes ...
    when 'price_revert_pct'   then 10     -- ... and drifting this share of the way back to base each step
    when 'price_pressure_max_pct' then 60 -- hustler dumping can take at most this % off street
    when 'price_recover_hours' then 4     -- dumping pressure fades by half this often
    when 'crew_max'           then 12
    when 'immunity_hours'     then 0      -- new-player immunity removed
    when 'starter_cash'       then 10000
    when 'starter_diamonds'   then 25
    when 'extra_grow_diamonds' then 20
    when 'crew_fight_stamina' then 5
    when 'crew_fight_cooldown_min' then 60
    when 'crew_fight_stake_pct' then 5
    when 'path_rep'           then 100    -- lifetime reputation at which a player must pick Producer or Trader ...
    when 'path_grow_level'    then 5      -- ... or to take a grow house past this level
    when 'path_switch_diamonds' then 50   -- cost to switch paths afterwards
    when 'siege_wins'         then 50     -- successful hits a crew needs to take an owned block
    when 'siege_min_thugs'    then 51     -- thugs needed to launch a turf attack
    when 'block_bonus_hours'  then 24     -- each block pays its bonus on this cycle
    when 'block_bonus_pct'    then 75     -- ... this % of its sixth of the hood's daily income (was 100)
    when 'daily_cash'         then 50000  -- cash on hand every player account gets at 00:00 UTC
    when 'counter_pct'        then 35     -- the losing side's hit lands at this % of its score
    when 'bot_min_strength'   then 0.5    -- Thug 1 fights at this share of its gear, rising to 1.0 at Thug 200
    when 'drop_stamina'       then 6000   -- rare-find chance per action = stamina_cost / this (12 stamina → 1 in 500)
    when 'drop_max_crates'    then 7      -- Daily Drop: unopened crates stack up to this many
    when 'drop_price_cents'   then 299    -- Daily Drop: $2.99 a month once it's paid
    when 'drop_free'          then 1      -- Daily Drop: 1 = free to subscribe for now
    when 'combo_counter'      then 10     -- a combo that counters the other side's rolls 0–this
    when 'combo_neutral'      then 5      -- ... one that neither counters nor is countered rolls 0–this (countered: nothing)
    when 'base_slots'         then 6      -- setup slots everyone starts with
    when 'max_slots'          then 130    -- the most setup slots anyone can have (the original game's cap)
    -- Slots: the k-th past the base costs base + 1 more diamond every `every` slots, and step x k cash
    -- (1💎 for slots 7–10, 2💎 for 11–14 … 31💎 for 127–130; $20k for the 7th … $2.48M for the 130th — 💎1,984 + $155M in all)
    when 'slot_diamonds_base' then 1
    when 'slot_diamonds_every' then 4
    when 'slot_cash_step'     then 20000
    when 'boost_diamonds'     then 50     -- a boost: +boost_amount attack (Offense) or defense (Defense) for boost_hours
    when 'boost_amount'       then 50
    when 'boost_hours'        then 24
    else 0 end $$;

-- ---------------------------------------------------------------------------
-- Today's drug refills and how many full ones a player gets
-- ---------------------------------------------------------------------------
create or replace function _drug_refills_today(pr profiles) returns jsonb
language sql stable set search_path = public as $$
  select case when pr.drug_refills->>'day' = _game_day()::text then pr.drug_refills - 'day' else '{}'::jsonb end $$;

create or replace function _refill_full_n(pr profiles) returns int
language sql stable set search_path = public as $$
  select (_cfg('refill_full') + case when _drop_active(pr) then _cfg('refill_sub_extra') else 0 end)::int $$;

-- ---------------------------------------------------------------------------
-- refill: drugs for stamina only, full per drug, then half the bar
-- ---------------------------------------------------------------------------
create or replace function refill(kind text, method text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; c commodities; units int; missing int; gain int; have int;
        today jsonb; used int := 0; full_n int := 0;
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
  elsif method = 'free' then
    -- a Daily Drop credit: a full stamina refill that doesn't count toward the three a day
    if kind <> 'stamina' then perform _fail('Free refills are for stamina'); end if;
    if pr.free_refills <= 0 then perform _fail('No free refills left'); end if;
    update profiles set free_refills = free_refills - 1 where id = u;
    gain := missing;
  else
    select * into c from commodities where code = method;
    if c.code is null then perform _fail('Bad refill'); end if;
    -- drugs are for stamina; health comes from the Hospital or diamonds
    if kind <> 'stamina' then perform _fail('Drugs refill stamina. Health comes from the Hospital or diamonds.'); end if;
    units := ceil(c.refill_stamina * (1 - _pk(_perks(u), 'pharmacy')))::int;
    select qty into have from storage where player_id = u and commodity = method;
    if coalesce(have, 0) < units then perform _fail(format('Needs %s %s', units, c.name)); end if;
    update storage set qty = qty - units where player_id = u and commodity = method;
    -- each drug fills you up 3 times a game day (5 on the Daily Drop); after that it restores half your stamina bar
    today := _drug_refills_today(pr);
    used := coalesce((today->>method)::int, 0);
    full_n := _refill_full_n(pr);
    gain := case when used < full_n then missing else least(missing, ceil(pr.stamina_max * _cfg('refill_late_share'))::int) end;
    update profiles set drug_refills = today || jsonb_build_object(method, used + 1, 'day', _game_day()::text),
           refills_used = refills_used + 1,
           refills_reset_at = case when pr.refills_used = 0 then now() else refills_reset_at end where id = u;
  end if;
  if kind = 'stamina' then update profiles set stamina = stamina + gain where id = u;
  else update profiles set health = health + gain where id = u; end if;
  -- for a drug: how many full refills of it are left today, and how many it gets a day
  return jsonb_build_object('gain', gain, 'units', units, 'full_left', case when units is not null then greatest(0, full_n - used - 1) end,
                            'full', case when units is not null then full_n end);
end $$;

-- ---------------------------------------------------------------------------
-- get_me: 'refills' (full per drug, today's counts, the late share, the subscriber count) in place of 'refill_share'
-- ---------------------------------------------------------------------------
create or replace function get_me() returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; po record; pd record; pj record; pk jsonb;
begin
  perform _refresh_prices();
  perform _tick_world();
  pr := _tick(u);
  update profiles set last_seen = now() where id = u;
  select * into po from _power(u, 'offense');
  select * into pd from _power(u, 'defense');
  select * into pj from _power(u, 'jail');
  pk := _perks(u);
  return jsonb_build_object(
    'id', pr.id, 'name', pr.name, 'created_at', pr.created_at, 'avatar', pr.avatar, 'bio', pr.bio, 'reputation', pr.reputation,
    'cash', pr.cash, 'bank', pr.bank, 'diamonds', pr.diamonds,
    'stamina', pr.stamina, 'stamina_max', pr.stamina_max,
    'health', pr.health, 'health_max', pr.health_max,
    'heat', pr.heat, 'heat_max', pr.heat_max,
    'heat_level', _heat_level(pr),
    'jailed', _jailed(pr), 'jail_until', case when isfinite(pr.jail_until) then pr.jail_until end,   -- null: until bail
    'hospital', _hospital(pr),
    'health_next', pr.health_tick + make_interval(mins => _cfg('health_regen_minutes')::int),
    'health_bought', pr.health_bought,
    'rep_earned', pr.rep_earned, 'path', pr.path,
    'path_required', _path_due(pr) is not null,
    'immune_until', pr.immune_until, 'immune', pr.immune_until > now(),
    'inventory_slots', pr.inventory_slots, 'storage_cap', floor(pr.storage_cap * (1 + _pk(pk, 'warehouse')))::int,
    'refills_used', pr.refills_used,
    'actions_done', pr.actions_done, 'fights_won', pr.fights_won, 'fights_lost', pr.fights_lost,
    'market_volume', pr.market_volume, 'imports', pr.imports,
    'next_tick', pr.stamina_tick + make_interval(mins => _cfg('stamina_regen_minutes')::int),   -- next stamina regen
    'power', jsonb_build_object('offense', to_jsonb(po), 'defense', to_jsonb(pd), 'jail', to_jsonb(pj)),
    'crew', (select jsonb_build_object('id', c.id, 'name', c.name, 'emblem', c.emblem, 'capo_id', c.capo_id,
                                       'is_capo', c.capo_id = u, 'co_capo_id', c.co_capo_id, 'is_co_capo', c.co_capo_id = u,
                                       'cartel_id', c.cartel_id,
                                       'members', (select count(*) from profiles where crew_id = c.id),
                                       'applications', case when _crew_boss(c, u) then (select count(*) from crew_applications where crew_id = c.id) else 0 end,
                                       'invites', case when c.capo_id = u and c.cartel_id is null then (select count(*) from cartel_invites where crew_id = c.id) else 0 end)
             from crews c where c.id = pr.crew_id),
    'cartel', (select jsonb_build_object('id', ca.id, 'name', ca.name, 'don_id', ca.don_id, 'is_don', ca.don_id = u)
               from crews c join cartels ca on ca.id = c.cartel_id where c.id = pr.crew_id),
    'storage', (select coalesce(jsonb_object_agg(commodity, qty), '{}'::jsonb) from storage where player_id = u),
    'storage_used', (select coalesce(sum(qty), 0) from storage where player_id = u),
    'prices', (select jsonb_object_agg(commodity, price) from street_prices),
    'grow_houses', (select coalesce(jsonb_agg(jsonb_build_object(
                      'id', g.id, 'commodity', g.commodity, 'level', g.level, 'running', g.running,
                      'started_at', g.started_at,
                      'rate', round(c.grow_rate * g.level * _grow_boost(pk, g.commodity), 1),
                      'cap', floor(c.grow_cap * g.level * _grow_boost(pk, g.commodity))::int,
                      'produced', least(floor(c.grow_cap * g.level * _grow_boost(pk, g.commodity))::int, g.banked + case when g.running
                          then floor(extract(epoch from now() - g.started_at) / 3600 * c.grow_rate * g.level * _grow_boost(pk, g.commodity))::int else 0 end),
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
    'transport_capacity', _haul(u),
    'listings', (select coalesce(jsonb_agg(jsonb_build_object('id', id, 'commodity', commodity, 'qty', qty,
                      'unit_price', unit_price, 'expires_at', expires_at, 'held', status = 'returned') order by created_at desc), '[]'::jsonb)
                 from listings where seller_id = u and status in ('open', 'returned')),
    'ribbons', _ribbons(u),
    'server_time', now()
  ) || jsonb_build_object(   -- a second object: jsonb_build_object takes at most 100 arguments
    'hospital_out_at', ceil(_cfg('hospital_release_pct') / 100.0 * pr.health_max)::int,
    'heat_next', pr.last_tick + make_interval(mins => _cfg('regen_minutes')::int),
    'unread_activity', (select count(*) from activity where player_id = u and not seen),
    'unread_dms', (select count(*) from chat_reads r where r.player_id = u
                     and exists (select 1 from messages m where m.channel = r.channel and m.created_at > r.read_at and m.sender_id <> u and not m.deleted)
                     and not _blocked_pair(u, _dm_other(r.channel, u))),   -- that conversation is out of the list
    'storage_base', pr.storage_cap,
    'listing_max', floor(_cfg('listing_max') * (1 + _pk(pk, 'trucking')))::int,
    'perks', pk,
    'drop', jsonb_build_object('subscribed', _drop_active(pr), 'since', pr.drop_since, 'until', pr.drop_until,
              'drop_paid', pr.drop_until is not null,   -- only the store webhook sets drop_until
              'crates', pr.drop_crates, 'max', _cfg('drop_max_crates')::int,
              'opened', (select count(*) from drop_opens where player_id = u),
              'last', (select jsonb_build_object('label', z.label, 'kind', z.kind, 'amount', o.amount, 'jackpot', z.jackpot, 'at', o.created_at)
                         from drop_opens o join drop_prizes z on z.code = o.prize where o.player_id = u order by o.id desc limit 1)),
    'free_refills', pr.free_refills, 'free_hustlers', pr.free_hustlers,
    'combos', (select jsonb_object_agg(s, jsonb_build_object('active', _active_combo(u, s), 'complete', to_jsonb(_setup_combos(u, s)),
                 'chosen', (select combo from setup_combos where player_id = u and setup = s)))
                 from unnest(array['offense', 'defense', 'jail']::setup_kind[]) s),
    'slot_cost', (select jsonb_build_object('diamonds', c.diamonds, 'cash', c.cash) from _slot_cost(pr.inventory_slots) c),
    'boost', jsonb_build_object('side', pr.boost_side, 'until', pr.boost_until, 'active', _boost_active(pr),
               'amount', _cfg('boost_amount')::int)
  ) || jsonb_build_object(
    -- the market: street details (for previewing a hustle), my open buy orders; and today's drug refills
    'street', _street_json(),
    'orders', (select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'commodity', o.commodity, 'qty', o.qty, 'filled', o.filled,
                    'unit_price', o.unit_price, 'expires_at', o.expires_at) order by o.created_at desc), '[]'::jsonb)
               from buy_orders o where o.buyer_id = u and o.status = 'open'),
    -- drug refills: full ones per drug today (3, or 5 on the Daily Drop), how many of each are used, and what one
    -- restores after that (a share of max stamina)
    'refills', jsonb_build_object('full', _refill_full_n(pr), 'used', _drug_refills_today(pr), 'late_share', _cfg('refill_late_share'),
                                  'sub_full', (_cfg('refill_full') + _cfg('refill_sub_extra'))::int),
    'path_due', _path_due(pr),  -- why a path is required: 'rep' or 'grow'
    'heat_yellow', _heat_yellow(pr), 'heat_red', _heat_red(pr),  -- this player's lines (heat upgrades move them up)
    -- moderation: admins see the queue size; a reset (or placeholder) name asks for a new one
    'is_admin', pr.is_admin, 'rename_pending', pr.rename_pending,
    'name_required', pr.rename_pending or pr.name like 'player\_%',
    'reports_open', case when pr.is_admin then (select count(distinct target_id) from profile_reports where status = 'open') else 0 end,
    -- players I've blocked: the client drops their realtime chat lines
    'blocked', (select coalesce(jsonb_agg(blocked_id), '[]'::jsonb) from blocked_players where blocker_id = u),
    -- muted: the client shows the end of the mute in place of the chat and forum composers
    'muted_until', case when pr.muted_until > now() then pr.muted_until end
  );
end $$;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
do $$ declare f record; begin
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('refill', 'get_me') loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('_cfg', '_drug_refills_today', '_refill_full_n') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
end $$;
