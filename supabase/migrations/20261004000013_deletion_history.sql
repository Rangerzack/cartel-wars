-- Two follow-ups to account deletion (#8).
--
--  * Deleting a crew member straight from auth.users ("Delete user" in the Supabase dashboard) failed: the profile
--    delete trigger took the player out of their crew with _crew_remove, which updates the row being deleted, and
--    Postgres refuses that ("tuple to be deleted was already modified by an operation triggered by the current
--    command"). The succession is now _crew_succession, which leaves the leaving player's profile alone. The trigger
--    runs it before the delete, and a crew left empty is deleted after, once the profile no longer points at it (deleting
--    it before would set that profile's crew_id to null, the same refused update). _crew_remove (leave, kick,
--    delete_account) is the profile update plus the same succession, so all of them share one rule.
--  * Fights stay when one side deletes their account. fights.attacker_id and defender_id cascaded, so the fight left
--    the other player's log and their win/loss record no longer added up to it. Both are now set null instead, and
--    winner_id (no foreign key until now) gets the same, so no trace of the id is left. get_fights shows a gone side as
--    "Deleted player" with no id, and combo_meta keeps counting those fights.

-- ---------------------------------------------------------------------------
-- Crew succession without touching the leaving player's profile
-- ---------------------------------------------------------------------------
-- When pid goes: the Co-Capo slot empties if it was theirs; a Capo hands over to the Co-Capo, else the longest-standing
-- member. With nobody left the crew winds down (blocks freed, sieges on them dropped, out of its cartel) and this returns
-- true: the caller deletes the crew once pid's profile no longer points at it.
create or replace function _crew_succession(c crews, pid uuid) returns boolean language plpgsql set search_path = public as $$
declare successor uuid;
begin
  if c.co_capo_id = pid then update crews set co_capo_id = null where id = c.id; end if;
  if c.capo_id is distinct from pid then return false; end if;
  select id into successor from profiles where crew_id = c.id and id <> pid
   order by (id = c.co_capo_id) desc, created_at limit 1;
  if successor is not null then
    update crews set capo_id = successor, co_capo_id = case when co_capo_id = successor then null else co_capo_id end where id = c.id;
    if c.cartel_id is not null then update cartels set don_id = successor where id = c.cartel_id and don_id = pid; end if;
    return false;
  end if;
  delete from block_siege where block_id in (select id from blocks where owner_crew_id = c.id);
  update blocks set owner_crew_id = null, taken_at = null, bonus_at = null where owner_crew_id = c.id;
  update hoods set owner_crew_id = null where owner_crew_id = c.id;
  if c.cartel_id is not null then perform _cartel_drop_crew(c.cartel_id, c.id); end if;
  return true;
end $$;

create or replace function _crew_remove(c crews, pid uuid) returns void language plpgsql set search_path = public as $$
begin
  update profiles set crew_id = null where id = pid;
  if _crew_succession(c, pid) then delete from crews where id = c.id; end if;
end $$;

create or replace function _before_profile_delete() returns trigger language plpgsql security definer set search_path = public as $$
declare c crews;
begin
  if old.crew_id is not null then
    select * into c from crews where id = old.crew_id for update;
    if c.id is not null then perform _crew_succession(c, old.id); end if;
  end if;
  return old;
end $$;

-- A crew of one disbands: its last member's profile is gone now, so the crew row can go too.
create or replace function _after_profile_delete() returns trigger language plpgsql security definer set search_path = public as $$
begin
  delete from crews x where x.id = old.crew_id and not exists (select 1 from profiles p where p.crew_id = x.id);
  return null;
end $$;
drop trigger if exists profiles_after_delete on profiles;
create trigger profiles_after_delete after delete on profiles for each row
  when (old.crew_id is not null) execute function _after_profile_delete();

-- ---------------------------------------------------------------------------
-- Fights outlive the players in them
-- ---------------------------------------------------------------------------
alter table fights
  alter column attacker_id drop not null,
  alter column defender_id drop not null,
  drop constraint fights_attacker_id_fkey,
  drop constraint fights_defender_id_fkey,
  add constraint fights_attacker_id_fkey foreign key (attacker_id) references profiles(id) on delete set null,
  add constraint fights_defender_id_fkey foreign key (defender_id) references profiles(id) on delete set null,
  add constraint fights_winner_id_fkey   foreign key (winner_id)   references profiles(id) on delete set null;

create or replace function get_fights(limit_n integer default 30) returns jsonb
language sql security definer set search_path = public stable as $$
  select coalesce(jsonb_agg(jsonb_build_object('id', f.id, 'attacker', coalesce(a.name, 'Deleted player'), 'attacker_id', f.attacker_id,
           'defender', coalesce(d.name, 'Deleted player'), 'defender_id', f.defender_id, 'attacker_dmg', f.attacker_dmg, 'defender_dmg', f.defender_dmg,
           'cash', f.cash_taken, 'won', coalesce(f.winner_id = auth.uid(), false), 'i_attacked', coalesce(f.attacker_id = auth.uid(), false),
           'at', f.created_at,
           'attacker_combo', f.attacker_combo, 'defender_combo', f.defender_combo,
           'attacker_combo_bonus', f.attacker_combo_bonus, 'defender_combo_bonus', f.defender_combo_bonus)
           order by f.id desc), '[]'::jsonb)
  from (select * from fights where attacker_id = auth.uid() or defender_id = auth.uid()
        order by id desc limit limit_n) f
  left join profiles a on a.id = f.attacker_id left join profiles d on d.id = f.defender_id $$;

-- A deleted defender was a person (thugs can't be deleted), so the fight still counts. A deleted winner's id is gone
-- from winner_id too, so a null winner beside a null attacker is the attacker's win.
create or replace function combo_meta() returns jsonb
language sql security definer set search_path = public stable as $$
  with active as (select id from profiles where not is_bot and last_seen > now() - interval '7 days'),
       runs as (select _active_combo(a.id, 'offense') as off, _active_combo(a.id, 'defense') as def from active a),
       wk as (select f.* from fights f left join profiles d on d.id = f.defender_id
               where f.created_at > now() - interval '7 days' and not coalesce(d.is_bot, false))
  select jsonb_build_object(
    'players', (select count(*) from active),
    'offense', (select coalesce(jsonb_object_agg(off, n), '{}'::jsonb) from (select off, count(*) n from runs where off is not null group by 1) x),
    'defense', (select coalesce(jsonb_object_agg(def, n), '{}'::jsonb) from (select def, count(*) n from runs where def is not null group by 1) x),
    'fights', (select count(*) from wk),
    'attacks', (select coalesce(jsonb_object_agg(attacker_combo, jsonb_build_object('n', n, 'won', won)), '{}'::jsonb)
                  from (select attacker_combo, count(*) n, count(*) filter (where winner_id is not distinct from attacker_id) won
                          from wk where attacker_combo is not null group by 1) x)) $$;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
do $$ declare f record; begin
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('get_fights', 'combo_meta') loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('_crew_succession', '_crew_remove', '_before_profile_delete', '_after_profile_delete') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
end $$;
