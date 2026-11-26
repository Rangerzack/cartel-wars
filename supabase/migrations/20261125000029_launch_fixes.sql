-- Launch fixes (docs/LAUNCH.md), Zack's calls of 2026-11-25.
--
-- 1. Fights cost no stamina. attack() checked for 2 stamina and never took them; now it doesn't check either, and
--    fight_preview quotes 0. (Crew fights, turf wars and Personal Hood fights keep their own stamina costs.)
-- 2. Sandbox purchases (TestFlight and App Review, which Apple doesn't charge for) credit only accounts marked
--    iap_tester, and admins. Anyone else's is recorded in iap_grants and ignored. admin_set_iap_tester(player, enabled)
--    marks an account; mark the App Review demo account before submitting.
-- 3. The Daily Drop is paused until 1.1. Nobody can subscribe, and the free subscriptions running now stop (their rows
--    are kept in drop_pause_backup so 1.1 can put them back). Unopened crates and free credits stay and still open.
--    Resume: delete from app_text where key = 'drop_paused'; then restore drop_since from drop_pause_backup.
-- 4. Store product ids move off the old bundle id to io.github.rangerzack.thugempire.* (the bundle id is now io.github.rangerzack.thugempire). No purchase has ever been
--    made (iap_grants was empty), so nothing refers to the old ids.
--
-- Rollback: re-run attack() from 20261002000001_combos_jail.sql, fight_preview() from 20261004000003_heat_upgrade.sql, iap_apply() from
-- 20261004000012_store.sql and subscribe_drop() from 20261001000001_daily_drop.sql; unpause as above.

alter table profiles add column if not exists iap_tester boolean not null default false;

create or replace function attack(target uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); me profiles; them profiles; fs record;
        roll_a int; roll_d int; ca int; cd int; s_a numeric; s_d numeric; dmg_a int; dmg_d int; taken bigint := 0; win boolean; pct numeric;
        counter numeric := _cfg('counter_pct') / 100.0; f fights; recent int;
begin
  perform _nn(target, 'target');
  if target = u then perform _fail('You cannot attack yourself'); end if;
  if not exists (select 1 from profiles where id = target) then perform _fail('No such player'); end if;
  -- lock in id order to avoid deadlocks
  if u < target then me := _tick(u); them := _tick(target); else them := _tick(target); me := _tick(u); end if;

  if _hospital(me) then perform _fail('You are in the hospital'); end if;
  if _hospital(them) then perform _fail('That player is in the hospital'); end if;
  -- fights cost no stamina (Zack, 2026-11-25): no stamina check, nothing taken
  perform _jail_check(me, them);
  if them.immune_until > now() then perform _fail('That player has new-player immunity'); end if;
  if me.immune_until > now() then me.immune_until := now(); end if;   -- attacking forfeits your own immunity
  -- the same wallet can only be shaken down so often: after 3 hits on a target in an hour the cash dries up
  select count(*) into recent from fights where attacker_id = u and defender_id = target and created_at > now() - interval '1 hour';

  select * into fs from _fight_setup(me, them);
  roll_a := _rand_between(0, 6); roll_d := _rand_between(0, 6);
  ca := _rand_between(0, fs.a_max); cd := _rand_between(0, fs.d_max);
  s_a := fs.base_a + least(10, roll_a + fs.edge_a) + ca;
  s_d := fs.base_d + least(10, roll_d + fs.edge_d) + cd;
  win := s_a > s_d;                                   -- a tie goes to the defender
  -- the winner's hit lands in full, the loser's only glances
  dmg_a := least(80, round(case when win then s_a else counter * s_a end))::int;
  dmg_d := least(80, round(case when win then counter * s_d else s_d end))::int;

  pct := case when recent >= 3 then 0 else _rand_between(5, 10) / 100.0 end;
  if win then
    taken := floor(them.cash * pct);
    me.cash := me.cash + taken; them.cash := them.cash - taken;
    me.fights_won := me.fights_won + 1; them.fights_lost := them.fights_lost + 1;
  else
    taken := floor(me.cash * pct);
    them.cash := them.cash + taken; me.cash := me.cash - taken;
    them.fights_won := them.fights_won + 1; me.fights_lost := me.fights_lost + 1;
  end if;
  them.health := greatest(0, them.health - dmg_a);
  me.health   := greatest(0, me.health - dmg_d);
  me.heat := least(me.heat_max, me.heat + 4);
  me := _bust_roll(me);

  update profiles set cash = me.cash, health = me.health, heat = me.heat, jail_until = me.jail_until,
         fights_won = me.fights_won, fights_lost = me.fights_lost, immune_until = me.immune_until where id = u;
  update profiles set cash = them.cash, health = them.health, fights_won = them.fights_won, fights_lost = them.fights_lost where id = target;

  insert into fights (attacker_id, defender_id, attacker_dmg, defender_dmg, cash_taken, winner_id,
                      attacker_combo, defender_combo, attacker_combo_bonus, defender_combo_bonus)
  values (u, target, dmg_a, dmg_d, taken, case when win then u else target end, fs.a_code, fs.d_code, ca, cd)
  returning * into f;
  if win then perform _event(u, 'fight_win'); else perform _event(target, 'defense'); end if;
  perform _award_milestones(u);
  return jsonb_build_object('won', win, 'damage_dealt', dmg_a, 'damage_taken', dmg_d, 'cash', taken, 'dry', recent >= 3,
                            'their_health', them.health, 'my_health', me.health,
                            'hospitalized_them', them.health <= 19, 'hospitalized_me', me.health <= 19,
                            'busted', _jailed(me) and fs.sa <> 'jail',
                            'my_att', round(fs.a_att)::int, 'my_def', round(fs.a_def)::int,
                            'their_att', round(fs.d_att)::int, 'their_def', round(fs.d_def)::int,
                            'my_score', round(s_a, 1), 'their_score', round(s_d, 1),
                            'my_roll', roll_a, 'their_roll', roll_d, 'edges', fs.edges,
                            'my_combo', fs.a_code, 'their_combo', fs.d_code,
                            'my_combo_bonus', ca, 'their_combo_bonus', cd,
                            'my_combo_max', fs.a_max, 'their_combo_max', fs.d_max);
end $$;

create or replace function fight_preview(target uuid) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); me profiles; them profiles; fs record; recent int; heat_after int; red int;
        counter numeric := _cfg('counter_pct') / 100.0; wins bigint; n bigint; dmin int; dmax int;
        known boolean; seen_combo text; seen_at timestamptz; their text; amax int; dmx int;
begin
  perform _nn(target, 'target');
  if target = u then perform _fail('You cannot attack yourself'); end if;
  if not exists (select 1 from profiles where id = target) then perform _fail('No such player'); end if;
  -- tick both (heat and cash feed the edges), locking in id order like attack()
  if u < target then me := _tick(u); them := _tick(target); else them := _tick(target); me := _tick(u); end if;
  perform _jail_check(me, them);
  select * into fs from _fight_setup(me, them);
  -- Whether they run a combo shows (you can see they're kitted out); which one doesn't, unless they're a thug
  -- or you've hit them before — then it's what they ran that time, which may have changed since.
  if them.is_bot or fs.d_code is null then
    known := true; their := fs.d_code;
  else
    select f.defender_combo, f.created_at into seen_combo, seen_at
      from fights f where f.attacker_id = u and f.defender_id = target and f.combos_logged and f.defender_combo is not null
     order by f.id desc limit 1;
    known := seen_combo is not null; their := seen_combo;
  end if;
  if known then
    amax := _combo_max(fs.a_code, their); dmx := _combo_max(their, fs.a_code);
  else
    amax := _combo_max(fs.a_code, null); dmx := _cfg('combo_neutral')::int;   -- neither counters, as far as you know
  end if;
  select count(*) filter (where x.sa > x.sd), count(*),
         min(least(80, round(case when x.sa > x.sd then counter * x.sd else x.sd end))::int),
         max(least(80, round(case when x.sa > x.sd then counter * x.sd else x.sd end))::int)
    into wins, n, dmin, dmax
    from (select fs.base_a + least(10, ra + fs.edge_a) + ca as sa, fs.base_d + least(10, rd + fs.edge_d) + cd as sd
            from generate_series(0, 6) ra, generate_series(0, 6) rd,
                 generate_series(0, amax) ca, generate_series(0, dmx) cd) x;
  select count(*) into recent from fights where attacker_id = u and defender_id = target and created_at > now() - interval '1 hour';
  heat_after := least(me.heat_max, me.heat + 4);
  red := _heat_red(me);                       -- this attacker's red line (heat upgrades move it up)
  return jsonb_build_object(
    'win_pct', round(100.0 * wins / n)::int,
    'win_exact', round(100.0 * wins / n, 1),
    'dmg_min', dmin, 'dmg_max', dmax,
    'my_health', me.health, 'hospital_risk', me.health - dmax <= 19,
    'dry', recent >= 3, 'hits_this_hour', recent,
    'stamina_cost', 0, 'heat_gain', 4,
    'bust_pct', case when _jailed(me) or heat_after < red then 0 else round(100.0 * (heat_after - red + 1) / 40)::int end,
    'setup', fs.sa, 'their_setup', fs.sd,
    'edges', fs.edges, 'edge_you', fs.edge_a, 'edge_them', fs.edge_d,
    'base_you', round(fs.base_a, 1), 'base_them', round(fs.base_d, 1),
    'combo_you', fs.a_code is not null, 'combo_them', dmx > 0,
    'my_combo', fs.a_code, 'their_combo', their, 'their_combo_known', known, 'their_combo_seen_at', seen_at,
    'their_has_combo', fs.d_code is not null,
    'my_combo_max', amax, 'their_combo_max', dmx,
    'my_att', round(fs.a_att)::int, 'my_def', round(fs.a_def)::int,
    'their_att', round(fs.d_att)::int, 'their_def', round(fs.d_def)::int);
end $$;

create or replace function iap_apply(provider text, event text, transaction_id text, product_id text, player uuid,
                                     expires_at timestamptz, raw jsonb) returns jsonb
language plpgsql security definer set search_path = public as $$
declare who uuid := (select id from profiles where id = iap_apply.player);
        drop_product text := nullif(_cfg_text('store_drop_product'), '');
        gid bigint; pk store_packs; pr profiles; n int; took int;
begin
  perform _nn(iap_apply.provider, 'provider');
  perform _nn(iap_apply.event, 'event');
  perform _nn(iap_apply.transaction_id, 'transaction_id');
  insert into iap_grants (player_id, provider, transaction_id, product_id, event, raw)
  values (who, iap_apply.provider, iap_apply.transaction_id, coalesce(iap_apply.product_id, ''), iap_apply.event, iap_apply.raw)
  on conflict on constraint iap_grants_once do nothing
  returning id into gid;
  if gid is null then return jsonb_build_object('duplicate', true); end if;

  select * into pk from store_packs where id = iap_apply.product_id;
  if pk.id is null and iap_apply.product_id is distinct from drop_product then return jsonb_build_object('ignored', 'unknown product'); end if;
  if who is null then return jsonb_build_object('ignored', 'unknown player'); end if;
  -- Sandbox purchases (TestFlight, App Review) are free. They credit only accounts marked iap_tester (and admins),
  -- so a TestFlight build can't mint diamonds into the live economy. The row above keeps the event on the record.
  if upper(coalesce(iap_apply.raw->>'environment', '')) = 'SANDBOX'
     and not exists (select 1 from profiles where id = who and (iap_tester or is_admin)) then
    return jsonb_build_object('ignored', 'sandbox purchase by a non-tester');
  end if;

  -- a diamond pack
  if pk.id is not null then
    if iap_apply.event in ('INITIAL_PURCHASE', 'NON_RENEWING_PURCHASE') then
      n := pk.diamonds;
      update profiles set diamonds = diamonds + n, diamonds_bought = diamonds_bought + n,
                          diamonds_bought_unspent = diamonds_bought_unspent + n where id = who;
      update iap_grants set diamonds = n where id = gid;
      insert into activity (player_id, kind, data) values (who, 'purchase', jsonb_build_object('diamonds', n));
      return jsonb_build_object('credited', n);
    elsif iap_apply.event in ('CANCELLATION', 'REFUND') then
      if exists (select 1 from iap_grants g where g.provider = iap_apply.provider and g.transaction_id = iap_apply.transaction_id
                   and g.event in ('CANCELLATION', 'REFUND') and g.id <> gid) then
        return jsonb_build_object('ignored', 'already refunded');
      end if;
      -- what this transaction credited (the pack may have changed since), else the pack as it is now
      n := coalesce((select g.diamonds from iap_grants g where g.provider = iap_apply.provider
                       and g.transaction_id = iap_apply.transaction_id and g.diamonds > 0 order by g.id limit 1), pk.diamonds);
      select * into pr from profiles where id = who for update;
      took := least(n, greatest(pr.diamonds, 0));
      -- the spend trigger takes the same amount off diamonds_bought_unspent
      update profiles set diamonds = diamonds - took, diamonds_bought = greatest(0, diamonds_bought - n) where id = who;
      update iap_grants set diamonds = -took where id = gid;
      insert into activity (player_id, kind, data) values (who, 'purchase_refunded', jsonb_build_object('diamonds', took, 'bought', n));
      return jsonb_build_object('revoked', took);
    end if;
    return jsonb_build_object('ignored', iap_apply.event);
  end if;

  -- the Daily Drop subscription
  if iap_apply.event in ('INITIAL_PURCHASE', 'RENEWAL', 'UNCANCELLATION', 'PRODUCT_CHANGE', 'SUBSCRIPTION_EXTENDED') then
    if iap_apply.expires_at is null then return jsonb_build_object('ignored', 'no expiry'); end if;
    if iap_apply.expires_at <= now() then return jsonb_build_object('ignored', 'already expired'); end if;
    -- events can arrive out of order: a late one never shortens the paid-through date
    pr := _drop_subscribe(who, greatest(iap_apply.expires_at, (select drop_until from profiles where id = who)));
    return jsonb_build_object('subscribed', pr.drop_until);
  elsif iap_apply.event = 'EXPIRATION' then
    update profiles set drop_until = now() where id = who and drop_until > now();
    return jsonb_build_object('lapsed', true);
  elsif iap_apply.event = 'REFUND' or (iap_apply.event = 'CANCELLATION' and iap_apply.raw->>'cancel_reason' = 'CUSTOMER_SUPPORT') then
    update profiles set drop_until = now() where id = who and drop_until > now();
    return jsonb_build_object('ended', true);
  elsif iap_apply.event in ('CANCELLATION', 'BILLING_ISSUE') then
    -- auto-renew off: it runs to the paid-through date and EXPIRATION ends it; a billing issue gets Apple's grace period
    return jsonb_build_object('unchanged', iap_apply.event);
  end if;
  return jsonb_build_object('ignored', iap_apply.event);
end $$;

create or replace function admin_set_iap_tester(player uuid, enabled boolean) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid();
begin
  if not _is_admin(u) then perform _fail('Admins only'); end if;
  perform _nn(player, 'player');
  update profiles set iap_tester = coalesce(enabled, false) where id = player;
  if not found then perform _fail('No such player'); end if;
  return jsonb_build_object('player', player, 'iap_tester', coalesce(enabled, false));
end $$;

-- the Daily Drop pause
create table if not exists drop_pause_backup (
  player_id  uuid primary key references profiles(id) on delete cascade,
  drop_since timestamptz not null,
  drop_until timestamptz,
  paused_at  timestamptz not null default now()
);
alter table drop_pause_backup enable row level security;
revoke all on drop_pause_backup from anon, authenticated;
insert into app_text (key, value) values ('drop_paused', '1') on conflict (key) do update set value = excluded.value;
insert into drop_pause_backup (player_id, drop_since, drop_until)
  select id, drop_since, drop_until from profiles where drop_since is not null and (drop_until is null or drop_until > now())
  on conflict (player_id) do nothing;
update profiles set drop_since = null, drop_until = null
 where drop_since is not null and (drop_until is null or drop_until > now());

create or replace function subscribe_drop() returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles;
begin
  if _cfg_text('drop_paused') = '1' then perform _fail('The Daily Drop is paused until the next update'); end if;
  pr := _tick(u);
  if _drop_active(pr) then perform _fail('You''re already subscribed'); end if;
  -- The paid plan hooks in here: once drop_free is 0, subscriptions only start from the payment webhook.
  if _cfg('drop_free') = 0 then perform _fail('Subscribe through the store'); end if;
  pr := _drop_subscribe(u, null);
  return jsonb_build_object('crates', pr.drop_crates, 'since', pr.drop_since);
end $$;

-- product ids on the new bundle id
update store_packs set id = replace(id, 'io.rangelab.cartelwars.', 'io.github.rangerzack.thugempire.') where id like 'io.rangelab.cartelwars.%';
update app_text set value = replace(value, 'io.rangelab.cartelwars.', 'io.github.rangerzack.thugempire.') where key = 'store_drop_product';

do $$ declare f record; begin
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('iap_apply') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('attack', 'fight_preview', 'subscribe_drop', 'admin_set_iap_tester') loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
