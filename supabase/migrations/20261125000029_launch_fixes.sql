-- Launch fixes, part 1 (docs/LAUNCH.md).
--
-- 1. attack(): fights against players and thugs now take the 2 stamina that fight_preview has always quoted. The
--    function checked for 2 and never took them, so fights were free (playtest note: "can grind out millions on an
--    empty energy bar"). Crew fights, turf wars and hood fights already charged; this brings attack() in line.
-- 2. iap_apply(): sandbox purchases (TestFlight and App Review, which Apple doesn't charge for) credit only accounts
--    marked iap_tester, and admins. Anyone else's sandbox purchase is still recorded in iap_grants, and ignored.
--    admin_set_iap_tester(player, enabled) marks an account; mark the App Review demo account before submitting.
--
-- Rollback: re-run attack() from 20261002000001_combos_jail.sql and iap_apply() from 20261004000012_store.sql.
-- The new column and function are harmless to leave in place.

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
  if me.stamina < 2 then perform _fail('You need at least 2 stamina to fight'); end if;
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
  me.stamina := me.stamina - 2;                       -- the 2 stamina fight_preview quotes (was checked, never taken)
  me.heat := least(me.heat_max, me.heat + 4);
  me := _bust_roll(me);

  update profiles set stamina = me.stamina, cash = me.cash, health = me.health, heat = me.heat, jail_until = me.jail_until,
         fights_won = me.fights_won, fights_lost = me.fights_lost, immune_until = me.immune_until where id = u;
  update profiles set cash = them.cash, health = them.health, fights_won = them.fights_won, fights_lost = them.fights_lost where id = target;

  insert into fights (attacker_id, defender_id, attacker_dmg, defender_dmg, cash_taken, winner_id,
                      attacker_combo, defender_combo, attacker_combo_bonus, defender_combo_bonus)
  values (u, target, dmg_a, dmg_d, taken, case when win then u else target end, fs.a_code, fs.d_code, ca, cd)
  returning * into f;
  if win then perform _event(u, 'fight_win'); else perform _event(target, 'defense'); end if;
  perform _award_milestones(u);
  return jsonb_build_object('won', win, 'stamina', me.stamina, 'damage_dealt', dmg_a, 'damage_taken', dmg_d, 'cash', taken, 'dry', recent >= 3,
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

do $$ declare f record; begin
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('iap_apply') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('attack', 'admin_set_iap_tester') loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
