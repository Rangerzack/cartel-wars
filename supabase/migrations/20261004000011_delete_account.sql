-- In-app account deletion (#8). Apple guideline 5.1.1(v): an app that lets people create an account must let them
-- delete it in the app.
--
--  * delete_account(confirm): the caller types their street name (any case) to confirm. Thugs can't be deleted.
--  * First the player lets go of everything other players depend on:
--      - their crew: the same succession as leaving (_crew_remove): the Co-Capo takes over, else the longest-standing
--        member; a crew of one disbands, which drops it from its cartel (a cartel left with no crews dissolves; if its
--        Don was the one leaving, the Capo of the oldest remaining crew takes over). A Don whose crew carries on hands
--        the cartel to the crew's new Capo. Crew and cartel banks stay where they are.
--      - a poker seat: they stand up as with poker_leave, folding a live hand so the table plays on. Chips they already
--        put into that hand go with them.
--      - open listings and buy orders are cancelled the usual way (product back to storage, held cash back on hand), so
--        nothing is left half-done when the profile goes.
--      - DM conversations with them are dropped on both sides: there's nobody left to answer.
--  * Then the auth user is deleted and the profile cascades with everything that is only theirs: gear, storage, chat
--    lines, forum threads (with their replies) and replies, fights, reports, blocks. Rows that are part of someone else's
--    history keep their place with the name gone (on delete set null): market trades, crew and cartel ledger entries,
--    the territory log, other players' activity lines. Threads that lost replies get their counts recounted.
--  * deleted_accounts keeps a tally with nothing that identifies the player.
--
-- The profile delete trigger (_before_profile_delete) can't take a player out of a crew itself: it updates the row being
-- deleted, which Postgres refuses. Leaving the crew here first leaves it nothing to do.

create table if not exists deleted_accounts (
  id            bigserial primary key,
  deleted_at    timestamptz not null default now(),
  days_played   int,                                  -- whole days from sign-up to deletion
  had_purchases boolean not null default false
);
alter table deleted_accounts enable row level security;
revoke all on deleted_accounts from anon, authenticated;

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

  -- the paid Daily Drop is the only thing for sale so far, and only its payment webhook sets drop_until
  insert into deleted_accounts (days_played, had_purchases)
  values (floor(extract(epoch from now() - pr.created_at) / 86400)::int, pr.drop_until is not null);

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
           where n.nspname = 'public' and p.proname = 'delete_account' loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
end $$;
