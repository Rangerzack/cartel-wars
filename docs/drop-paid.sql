-- Turning the Daily Drop's paid plan on (#16). NOT applied yet: copy this file to supabase/migrations/2026100400000N_drop_paid.sql
-- (next free N) and ship it on the day the io.rangelab.cartelwars.drop.monthly subscription is approved and live in App
-- Store Connect. It is the newest _cfg (20261004000016_drug_refills.sql) with drop_free set to 0: from then on
-- subscribe_drop refuses ("Subscribe through the store"), the app's Subscribe button is the App Store purchase and the
-- web says it's an iPhone subscription. Players already on the free plan keep it, open-ended, until they cancel; to end
-- them at the switch instead (their unopened crates stay) uncomment the last statement.
-- Before copying, check that no later migration has redefined _cfg (grep "create or replace function _cfg(key text) returns numeric language sql immutable set search_path = public as $$
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
    when 'drop_free'          then 0      -- Daily Drop: 0 = a paid App Store subscription (was 1 while free)
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

-- update profiles set drop_since = null where drop_since is not null and drop_until is null;
