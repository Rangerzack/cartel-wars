-- Thugs come off the leaderboards: Top Users (fighters, hustlers, traders), the weekly accolade boards and
-- the ribbons that come from them. Now that fights are head-to-head, thugs win their share of defenses, and
-- they'd otherwise climb the Fights and Defenses boards. They still show in the Players list and the Thugs tab.

create or replace function top_users() returns jsonb
language sql security definer set search_path = public stable as $$
  select jsonb_build_object(
    'fighters', (select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'value', fights_won)) from (select * from profiles where not is_bot order by fights_won desc limit 20) x),
    'hustlers', (select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'value', actions_done)) from (select * from profiles where not is_bot order by actions_done desc limit 20) x),
    'traders',  (select jsonb_agg(jsonb_build_object('id', id, 'name', name, 'value', market_volume)) from (select * from profiles where not is_bot order by market_volume desc limit 20) x),
    'crews',    (select jsonb_agg(jsonb_build_object('id', c.id, 'name', c.name, 'emblem', c.emblem, 'value', (select count(*) from blocks where owner_crew_id = c.id)))
                 from (select * from crews order by (select count(*) from blocks where owner_crew_id = crews.id) desc, created_at limit 20) c)) $$;

create or replace function _accolade_board(from_ts timestamptz, to_ts timestamptz) returns jsonb
language sql stable set search_path = public as $$
  select coalesce(jsonb_object_agg(kind, rows), '{}'::jsonb) from (
    select kind, jsonb_agg(jsonb_build_object('id', player_id, 'name', name, 'value', total) order by total desc) as rows
    from (
      select e.kind, e.player_id, p.name, sum(e.amount) as total,
             row_number() over (partition by e.kind order by sum(e.amount) desc) as rn
        from accolade_events e join profiles p on p.id = e.player_id
       where e.created_at >= from_ts and e.created_at < to_ts and not p.is_bot
       group by e.kind, e.player_id, p.name
    ) t where rn <= 10 group by kind
  ) b $$;

-- Ribbons a player wears this week = their top-3 finishes last week, ranked among players only.
create or replace function _ribbons(p uuid) returns jsonb
language sql stable set search_path = public as $$
  select coalesce(jsonb_agg(jsonb_build_object('kind', kind, 'rank', rank) order by rank, kind), '[]'::jsonb)
  from (
    select kind, rank() over (partition by kind order by total desc) as rank, player_id
      from (select e.kind, e.player_id, sum(e.amount) as total from accolade_events e join profiles pr on pr.id = e.player_id
             where e.created_at >= date_trunc('week', now() at time zone 'utc') at time zone 'utc' - interval '7 days'
               and e.created_at < date_trunc('week', now() at time zone 'utc') at time zone 'utc'
               and not pr.is_bot
             group by e.kind, e.player_id) t
  ) r where r.player_id = p and r.rank <= 3 $$;
