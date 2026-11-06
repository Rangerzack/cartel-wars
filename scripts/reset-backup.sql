-- Copies every table reset-world.sql touches into its own schema before a reset, so the old world can be looked at or
-- put back. The schema isn't one the API serves, so nobody can read it from the app. Run it right before
-- reset-world.sql, with `dest` set to that day's date. It refuses to run twice into the same schema (the tables exist).
do $$
declare
  dest constant text := 'reset_backup_20261005';
  t text;
begin
  execute format('create schema if not exists %I', dest);
  execute format('revoke all on schema %I from public, anon, authenticated', dest);
  foreach t in array array['profiles','crews','cartels','blocks','hoods','street_prices','block_siege','block_garrison',
    'crew_fights','crew_applications','cartel_votes','cartel_invites','chat_reads','messages','poker_hand_players',
    'poker_hands','poker_seats','blackjack_games','craps_games','listings','buy_orders','inventory','setup_items',
    'setup_combos','player_hoodlums','grow_houses','hustlers','storage','milestones','milestone_repeats','fights',
    'casino_bets','market_trades','bank_ledger','territory_log','accolade_events','rare_finds','drop_opens','activity'] loop
    execute format('create table %I.%I as table public.%I', dest, t, t);
  end loop;
end $$;
