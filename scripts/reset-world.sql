-- A fresh start for every real player (Zack, 2026-10-05: "reset everyone's account and give them 5 million and 500
-- diamonds"; full wipe, $1M on hand and $4M in the bank, thugs left as they are). Not a migration: run it by hand,
-- once, in one go (it is one statement, so it all happens or none of it does). Back up first (reset-backup.sql).
--
-- Each real player goes back to a brand-new player (what _create_profile makes) with the stake below instead of the
-- starter cash: reputation, stats, upgrades, items, setups, combos, thugs, product, grow houses, hustlers, market
-- orders, milestones, path, boost, refills, hospital and jail. Crews and cartels are disbanded, every block and hood is
-- unclaimed, and street prices go back to base. History goes for everyone, thugs included: fights, casino rounds,
-- market trades, the bank ledger, the territory log, accolades, rare finds, crate openings and the activity feed.
--
-- Kept: accounts, names, avatars, bios, join dates, admin flags, mutes, Daily Drop subscriptions and their unopened
-- crates, purchase records, global chat and DMs (crew and cartel chat go with the crews), the forum, blocks between
-- players, reports and the moderation log. The NPC thugs keep their levels, stashes, gear and fight records.
do $$
declare
  on_hand   constant bigint := 1000000;
  in_bank   constant bigint := 4000000;
  diamonds_ constant int    := 500;
  real uuid[];
begin
  select coalesce(array_agg(id), '{}') into real from profiles where not is_bot;

  -- the world: every block and hood unclaimed (an owner going to nobody isn't a takeover, so no feed lines), the
  -- crews and cartels gone with everything that hangs off them, prices back to base
  update blocks set owner_crew_id = null, taken_at = null, bonus_at = null;
  update hoods set owner_crew_id = null, last_payout_at = now();
  delete from block_siege;
  delete from block_garrison;
  delete from crew_fights;
  delete from crew_applications;
  delete from cartel_votes;
  delete from cartel_invites;
  update profiles set crew_id = null where crew_id is not null;
  delete from crews;
  delete from cartels;
  delete from chat_reads where channel like 'crew:%' or channel like 'cartel:%';
  delete from messages where channel like 'crew:%' or channel like 'cartel:%';
  update street_prices s set price = c.base_price, wiggle = 0, wiggle_at = now(), pressure = 0, pressure_at = now(), updated_at = now()
    from commodities c where c.code = s.commodity;

  -- games in progress and the market
  delete from poker_hand_players;
  delete from poker_hands;
  delete from poker_seats;
  delete from blackjack_games;
  delete from craps_games;
  delete from listings where seller_id = any(real);
  delete from buy_orders where buyer_id = any(real);

  -- what each player had
  delete from inventory where player_id = any(real);
  delete from setup_items where player_id = any(real);
  delete from setup_combos where player_id = any(real);
  delete from player_hoodlums where player_id = any(real);
  delete from grow_houses where player_id = any(real);
  delete from hustlers where player_id = any(real);
  delete from storage where player_id = any(real);
  insert into storage (player_id, commodity, qty) select p, c.code, 0 from unnest(real) p cross join commodities c;
  delete from milestones where player_id = any(real);
  delete from milestone_repeats where player_id = any(real);

  -- history, everyone's
  delete from fights;
  delete from casino_bets;
  delete from market_trades;
  delete from bank_ledger;
  delete from territory_log;
  delete from accolade_events;
  delete from rare_finds;
  delete from drop_opens;
  delete from activity;

  -- each player: a new player's numbers, plus the stake
  update profiles set
    reputation = default, rep_earned = default, path = null, path_chosen_at = null,
    stamina = default, stamina_max = default, stamina_tick = default,
    health = default, health_max = default, health_tick = default, health_bought = default, health_bought_at = null,
    heat = default, heat_max = default, last_tick = default, jail_until = null, in_hospital = false,
    inventory_slots = default, storage_cap = default,
    refills_used = default, refills_reset_at = default, drug_refills = default, free_refills = default, free_hustlers = default,
    actions_done = default, fights_won = default, fights_lost = default, turf_attacks = default, casino_wagered = default,
    market_volume = default, imports = default, daily_day = default, boost_side = null, boost_until = null,
    cash = on_hand, bank = in_bank, diamonds = diamonds_, diamonds_bought_unspent = 0,
    immune_until = now() + make_interval(hours => _cfg('immunity_hours')::int)
  where id = any(real);
end $$;
