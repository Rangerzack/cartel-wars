-- In-app purchases (#15, #16): diamond packs and the Daily Drop subscription, sold through Apple in the iOS app.
-- RevenueCat tells us what was bought through its webhook (supabase/functions/iap-webhook, see docs/ops.md).
-- Zack hasn't set prices yet, so nothing here names one: the price is whatever StoreKit shows on the phone.
--
--  * store_packs is the pack list (App Store product id → diamonds). get_catalog shows the active ones as
--    store.packs; the subscription's product id is app_text 'store_drop_product'. Changing packs is an update to
--    this table, not a release. A pack switched off still pays out if someone bought it.
--  * iap_apply(...) is the webhook's one entry point. The edge function calls it with the service key; players can't.
--    Every call writes one iap_grants row, ignored ones included, so the webhook can be audited, and
--    (provider, transaction_id, event) is unique, so RevenueCat's retries change nothing.
--      - a pack's INITIAL_PURCHASE or NON_RENEWING_PURCHASE credits its diamonds;
--      - a pack's CANCELLATION (how RevenueCat reports an Apple refund) or REFUND takes them back, never below 0;
--      - the subscription's INITIAL_PURCHASE, RENEWAL, UNCANCELLATION, PRODUCT_CHANGE or SUBSCRIPTION_EXTENDED pays
--        the Daily Drop through the period's end (_drop_subscribe), never shortening a later paid-through date;
--        EXPIRATION lets it lapse; a refund (CANCELLATION with cancel_reason CUSTOMER_SUPPORT) ends it now; a plain
--        CANCELLATION (auto-renew off) and BILLING_ISSUE (Apple's grace period) change nothing.
--  * #17: purchased diamonds can't be gifted. That's Apple's rule on gifting in-app purchases, and it closes the
--    stolen card → alt account → chargeback loop. profiles.diamonds_bought_unspent counts the purchased diamonds a
--    player still holds, and send_diamonds only sends the rest. Spending uses purchased diamonds first: a trigger takes
--    every drop in `diamonds` off the purchased count too (floored at 0), so the twenty-odd spend sites stay as they are.
--  * A paid Daily Drop is Apple's to cancel, so unsubscribe_drop refuses it. get_me's drop says whether it's paid.

-- ---------------------------------------------------------------------------
-- Schema
-- ---------------------------------------------------------------------------
create table if not exists store_packs (
  id       text primary key,                       -- the App Store product id
  diamonds int not null check (diamonds > 0),
  sort     int not null,
  active   boolean not null default true           -- false: not shown in the store (a purchase still pays out)
);
alter table store_packs enable row level security;
revoke all on store_packs from anon, authenticated;

-- The suggested packs from #7. Prices are set per product in App Store Connect.
insert into store_packs (id, diamonds, sort) values
  ('io.rangelab.cartelwars.diamonds.100',     100, 1),
  ('io.rangelab.cartelwars.diamonds.550',     550, 2),
  ('io.rangelab.cartelwars.diamonds.1200',   1200, 3),
  ('io.rangelab.cartelwars.diamonds.2600',   2600, 4),
  ('io.rangelab.cartelwars.diamonds.7000',   7000, 5),
  ('io.rangelab.cartelwars.diamonds.15000', 15000, 6)
on conflict (id) do nothing;

insert into app_text (key, value) values ('store_drop_product', 'io.rangelab.cartelwars.drop.monthly') on conflict (key) do nothing;

-- One row per webhook event. diamonds: what it credited (+) or took back (−); 0 for everything else.
-- player_id goes null when the player deletes their account; the purchase record stays.
create table if not exists iap_grants (
  id             bigserial primary key,
  player_id      uuid references profiles(id) on delete set null,
  provider       text not null default 'revenuecat',
  transaction_id text not null,
  product_id     text not null,
  event          text not null,
  diamonds       int not null default 0,
  raw            jsonb,                             -- the provider's event as it came in (cancel_reason, environment …)
  created_at     timestamptz not null default now(),
  constraint iap_grants_once unique (provider, transaction_id, event)
);
create index if not exists iap_grants_player_idx on iap_grants(player_id, id desc);
alter table iap_grants enable row level security;
revoke all on iap_grants from anon, authenticated;

alter table profiles add column if not exists diamonds_bought         bigint not null default 0;  -- lifetime, net of refunds
alter table profiles add column if not exists diamonds_bought_unspent bigint not null default 0;  -- purchased and still held

-- ---------------------------------------------------------------------------
-- #17: spending takes purchased diamonds first
-- ---------------------------------------------------------------------------
-- Any drop in `diamonds` comes off diamonds_bought_unspent too, on top of what the statement set it to, floored at 0 and
-- never above what's left. send_diamonds adds the gift back in the same statement: a gift is earned diamonds.
create or replace function _diamonds_spent() returns trigger language plpgsql set search_path = public as $$
begin
  new.diamonds_bought_unspent := least(greatest(0, new.diamonds_bought_unspent - (old.diamonds - new.diamonds)), greatest(0, new.diamonds));
  return new;
end $$;
drop trigger if exists profiles_diamonds_spent on profiles;
create trigger profiles_diamonds_spent before update of diamonds on profiles
  for each row when (new.diamonds < old.diamonds) execute function _diamonds_spent();

-- ---------------------------------------------------------------------------
-- The webhook's entry point (service role only)
-- ---------------------------------------------------------------------------
-- raw is the provider's event; for RevenueCat that's the body's `event` object. Returns what it did:
-- {duplicate}, {credited}, {revoked}, {subscribed}, {lapsed}, {ended}, {unchanged} or {ignored: why}.
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

-- ---------------------------------------------------------------------------
-- Catalog and state
-- ---------------------------------------------------------------------------
-- 20261004000004's get_catalog, plus store: the active packs and the subscription's product id (no prices: StoreKit has them).
create or replace function get_catalog() returns jsonb
language sql stable security definer set search_path = public as $$
  select jsonb_build_object(
    'actions', (select jsonb_agg(to_jsonb(a) order by a.sort) from action_defs a),
    'items', (select jsonb_agg(to_jsonb(i) order by i.sort) from item_defs i),
    'commodities', (select jsonb_agg(to_jsonb(c) order by c.sort) from commodities c),
    'hoodlums', (select jsonb_agg(to_jsonb(h)) from hoodlum_defs h),
    'businesses', (select jsonb_agg(to_jsonb(b) order by b.sort) from business_defs b),
    'drop_prizes', (select jsonb_agg(to_jsonb(z) order by z.sort) from drop_prizes z),
    'store', jsonb_build_object(
      'packs', (select coalesce(jsonb_agg(jsonb_build_object('id', s.id, 'diamonds', s.diamonds) order by s.sort), '[]'::jsonb)
                  from store_packs s where s.active),
      'drop_product', _cfg_text('store_drop_product')),
    'combo_styles', (select jsonb_agg(jsonb_build_object('code', s.code, 'name', s.name, 'icon', s.icon, 'blurb', s.blurb,
                       'beats', (select coalesce(jsonb_agg(k.beats order by b.sort), '[]'::jsonb) from combo_counters k
                                   join combo_styles b on b.code = k.beats where k.style = s.code)) order by s.sort) from combo_styles s),
    'milestones', (select jsonb_agg(to_jsonb(m) order by m.kind, m.n) from milestone_defs m),
    'combos', (select jsonb_agg(jsonb_build_object('code', c.code, 'name', c.name, 'style', c.style, 'tier', c.tier,
                 'parts', (select jsonb_agg(p.items order by p.part) from (select part, jsonb_agg(item_id order by item_id) items
                             from combo_parts where combo = c.code group by part) p)) order by c.sort) from combo_defs c),
    'config', jsonb_build_object(
      'bribe_per_heat', _cfg('bribe_per_heat'), 'hospital_per_point', _cfg('hospital_per_point'),
      'refill_diamonds', _cfg('refill_diamonds'), 'hustler_price', _cfg('hustler_price'),
      'hustler_hours', _cfg('hustler_hours'), 'listing_min', _cfg('listing_min'), 'listing_max', _cfg('listing_max'),
      'crew_max', _cfg('crew_max'), 'bail_base', _cfg('bail_base'), 'bail_per_minute', _cfg('bail_per_minute'),
      'extra_grow_diamonds', _cfg('extra_grow_diamonds'), 'heat_yellow', _cfg('heat_yellow'), 'heat_red', _cfg('heat_red'),
      'health_price_scale', _cfg('health_price_scale'), 'health_regen_minutes', _cfg('health_regen_minutes'),
      'health_regen_amount', _cfg('health_regen_amount'), 'path_rep', _cfg('path_rep'),
      'path_switch_diamonds', _cfg('path_switch_diamonds'), 'siege_wins', _cfg('siege_wins'),
      'siege_min_thugs', _cfg('siege_min_thugs'), 'block_bonus_hours', _cfg('block_bonus_hours'),
      'stamina_regen_minutes', _cfg('stamina_regen_minutes'), 'stamina_regen_amount', _cfg('stamina_regen_amount'),
      'regen_minutes', _cfg('regen_minutes'), 'hospital_release_pct', _cfg('hospital_release_pct'),
      'daily_cash', _cfg('daily_cash'), 'counter_pct', _cfg('counter_pct'), 'drop_stamina', _cfg('drop_stamina'),
      'bot_min_strength', _cfg('bot_min_strength'), 'jail_minutes', _cfg('jail_minutes'),
      'drop_max_crates', _cfg('drop_max_crates'), 'drop_price_cents', _cfg('drop_price_cents'), 'drop_free', _cfg('drop_free'),
      'combo_counter', _cfg('combo_counter'), 'combo_neutral', _cfg('combo_neutral'),
      'base_slots', _cfg('base_slots'), 'max_slots', _cfg('max_slots'), 'boost_diamonds', _cfg('boost_diamonds'), 'boost_amount', _cfg('boost_amount'),
      'boost_hours', _cfg('boost_hours')) || jsonb_build_object(   -- jsonb_build_object takes at most 100 arguments
      'refill_full', _cfg('refill_full'), 'path_grow_level', _cfg('path_grow_level'),
      'trader_cut_pct', _cfg('trader_cut_pct'), 'trader_markup_pct', _cfg('trader_markup_pct'),
      'listing_max_pct', _cfg('listing_max_pct'), 'market_fee_pct', _cfg('market_fee_pct'),
      'order_max', _cfg('order_max'), 'orders_open_max', _cfg('orders_open_max'),
      'price_pressure_max_pct', _cfg('price_pressure_max_pct'), 'price_recover_hours', _cfg('price_recover_hours'),
      'heat_base', _cfg('heat_base'), 'heat_upgrade_diamonds', _cfg('heat_upgrade_diamonds'), 'heat_upgrade_amount', _cfg('heat_upgrade_amount'),
      'jail_diamonds', _cfg('jail_diamonds'), 'slot_diamonds_base', _cfg('slot_diamonds_base'), 'slot_diamonds_every', _cfg('slot_diamonds_every'))
  ) $$;


-- 20261004000010's get_me, plus drop.drop_paid: the plan came from the App Store (the client shows Manage subscription).
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
    -- the market: street details (for previewing a hustle), my open buy orders, and what the next product refill restores
    'street', _street_json(),
    'orders', (select coalesce(jsonb_agg(jsonb_build_object('id', o.id, 'commodity', o.commodity, 'qty', o.qty, 'filled', o.filled,
                    'unit_price', o.unit_price, 'expires_at', o.expires_at) order by o.created_at desc), '[]'::jsonb)
               from buy_orders o where o.buyer_id = u and o.status = 'open'),
    'refill_share', _refill_share(pr.refills_used),
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
-- Player RPCs
-- ---------------------------------------------------------------------------
-- #17: only earned diamonds can be sent. The + n on diamonds_bought_unspent cancels what the spend trigger would take
-- off it, so the purchased count stays where it was.
create or replace function send_diamonds(target uuid, n integer) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles;
begin
  perform _nn(n, 'amount');
  pr := _tick(u);
  if target = u then perform _fail('Cannot send to yourself'); end if;
  if n <= 0 or n > pr.diamonds then perform _fail('Invalid amount'); end if;
  if n > pr.diamonds - pr.diamonds_bought_unspent then perform _fail('You can only send diamonds you earned in the game'); end if;
  if not exists (select 1 from profiles where id = target) then perform _fail('No such player'); end if;
  update profiles set diamonds = diamonds - n, diamonds_bought_unspent = diamonds_bought_unspent + n where id = u;
  update profiles set diamonds = diamonds + n where id = target;
  return jsonb_build_object('sent', n);
end $$;

-- 20261001000001's unsubscribe_drop, except a paid plan: Apple bills it, so it's cancelled in the device settings and
-- runs to its paid-through date (the webhook's EXPIRATION ends it).
create or replace function unsubscribe_drop() returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles;
begin
  pr := _tick(u);
  if not _drop_active(pr) then perform _fail('You''re not subscribed'); end if;
  if pr.drop_until is not null then perform _fail('Manage your subscription in your device settings'); end if;
  update profiles set drop_since = null, drop_until = null where id = u;
  return jsonb_build_object('crates', pr.drop_crates);
end $$;

-- 20261004000011's delete_account; had_purchases now counts diamonds bought too.
create or replace function delete_account(confirm text) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); pr profiles; c crews; s poker_seats; h poker_hands; l listings; o buy_orders; touched bigint[];
begin
  select * into pr from profiles where id = u for update;
  if pr.id is null then perform _fail('No such player'); end if;
  if pr.is_bot then perform _fail('Thugs can''t be deleted'); end if;
  if lower(trim(coalesce(confirm, ''))) <> lower(trim(pr.name)) then perform _fail('Type your street name to confirm'); end if;

  -- stand up from the poker table (poker_leave)
  select * into s from poker_seats where player_id = u for update;
  if s.player_id is not null then
    select * into h from poker_hands where table_id = s.table_id and finished_at is null for update;
    if h.id is not null and exists (select 1 from poker_hand_players where hand_id = h.id and seat = s.seat and not folded) then
      update poker_hand_players set folded = true, acted = true where hand_id = h.id and seat = s.seat;
      if h.to_act = s.seat or (select count(*) from poker_hand_players where hand_id = h.id and not folded) <= 1 then
        perform _poker_advance(h.id);
      end if;
    end if;
    update profiles set cash = cash + s.stack where id = u;
    delete from poker_seats where player_id = u;
  end if;

  -- listings back to storage (cancel_listing), buy orders' held cash back on hand (cancel_order)
  for l in select * from listings where seller_id = u and status in ('open', 'returned') for update loop
    perform _return_product(u, l.commodity, l.qty, l.id, 'cancelled');
  end loop;
  for o in select * from buy_orders where buyer_id = u and status = 'open' for update loop
    update profiles set cash = cash + o.qty::bigint * o.unit_price where id = u;
    update buy_orders set status = 'cancelled' where id = o.id;
  end loop;

  -- leave the crew, with the Capo's succession (crew_leave)
  select * into c from crews where id = pr.crew_id for update;
  if c.id is not null then perform _crew_remove(c, u); end if;
  -- a Don is always a Capo in the cartel, so the above already moved the title; this only guards a stray don_id
  update cartels ca set don_id = (select x.capo_id from crews x where x.cartel_id = ca.id and x.capo_id is not null order by x.created_at limit 1)
   where ca.don_id = u;

  delete from messages where channel like 'dm:%' and position(u::text in channel) > 0;
  delete from chat_reads where channel like 'dm:%' and position(u::text in channel) > 0;

  -- other players' threads this player replied in, to recount once the replies are gone
  select coalesce(array_agg(distinct thread_id), '{}') into touched from forum_posts where author_id = u;

  -- paid: a Daily Drop plan from the store (only its webhook sets drop_until) or diamonds bought and not refunded
  insert into deleted_accounts (days_played, had_purchases)
  values (floor(extract(epoch from now() - pr.created_at) / 86400)::int, pr.drop_until is not null or pr.diamonds_bought > 0);

  delete from auth.users where id = u;

  update forum_threads t
     set reply_count = (select count(*) from forum_posts p where p.thread_id = t.id),
         last_post_at = coalesce((select max(p.created_at) from forum_posts p where p.thread_id = t.id), t.created_at),
         last_poster_id = coalesce((select p.author_id from forum_posts p where p.thread_id = t.id order by p.id desc limit 1), t.author_id)
   where t.id = any(touched);

  return jsonb_build_object('deleted', true);
end $$;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
do $$ declare f record; begin
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('get_catalog', 'get_me', 'send_diamonds', 'unsubscribe_drop', 'delete_account') loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
  -- the webhook's entry point: the edge function calls it with the service key, nobody else can
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'iap_apply' loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
    if exists (select 1 from pg_roles where rolname = 'service_role') then
      execute format('grant execute on function %s to service_role', f.sig);
    end if;
  end loop;
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = '_diamonds_spent' loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
end $$;
