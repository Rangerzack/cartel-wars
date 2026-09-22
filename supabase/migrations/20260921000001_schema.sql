-- Cartel Wars — schema
-- All game state changes go through SECURITY DEFINER RPCs (0002_functions.sql).
-- Tables are locked down; clients never write to them directly.

create extension if not exists pgcrypto;

-- ---------------------------------------------------------------------------
-- Enums
-- ---------------------------------------------------------------------------
create type item_category as enum ('weapon', 'jail_weapon', 'protection', 'transport');
create type setup_kind as enum ('offense', 'defense', 'jail');
create type listing_status as enum ('open', 'sold', 'cancelled', 'expired', 'returned');  -- returned = product waiting for storage room

-- ---------------------------------------------------------------------------
-- Static content
-- ---------------------------------------------------------------------------
create table commodities (
  code            text primary key,            -- herb | dust | pills
  name            text not null,
  base_price      integer not null,            -- $ per unit
  hustler_units   integer not null,            -- units one hustler carries
  refill_stamina  integer not null,            -- units for a full stamina refill
  refill_health   integer not null,            -- units for a full health refill
  grow_rate       integer not null,            -- units / hour at level 1
  grow_cap        integer not null,            -- uncollected cap at level 1
  grow_price      integer not null,            -- $ to build the first grow house
  sort            integer not null
);

create table street_prices (
  commodity   text primary key references commodities(code),
  price       integer not null,
  updated_at  timestamptz not null default now()
);

create table item_defs (
  id          serial primary key,
  name        text not null,
  category    item_category not null,
  att         integer not null default 0,
  def         integer not null default 0,
  capacity    integer not null default 0,     -- transport cargo slots
  price       integer not null,
  rep_price   integer not null default 0,      -- rare items: bought with Reputation instead of cash
  combo_tag   text,                            -- weapon+protection with same tag = combo bonus
  sort        integer not null default 0
);

create table action_defs (
  id            serial primary key,
  name          text not null,
  description   text not null default '',
  stamina_cost  integer not null,
  pay_min       integer not null,
  pay_max       integer not null,
  pay_rep       integer not null default 0,    -- reputation actions pay this instead of cash
  heat_gain     integer not null default 2,
  cash_cost     integer not null default 0,
  requires_item integer references item_defs(id),
  min_crew      integer not null default 0,
  is_jail       boolean not null default false,
  effect        text,                          -- special: 'go_to_jail'
  sort          integer not null default 0
);

create table hoodlum_defs (
  code        text primary key,               -- thug | spy | mercenary | enforcer
  name        text not null,
  att         integer not null,
  def         integer not null,
  intel       integer not null,
  base_price  integer not null
);

-- ---------------------------------------------------------------------------
-- Players
-- ---------------------------------------------------------------------------
create table cartels (
  id          uuid primary key default gen_random_uuid(),
  name        text not null unique,
  don_id      uuid,                            -- fk added below
  bank        bigint not null default 0,
  created_at  timestamptz not null default now()
);

create table crews (
  id          uuid primary key default gen_random_uuid(),
  name        text not null unique,
  emblem      text not null default '🏴' check (char_length(emblem) between 1 and 8),
  description text not null default '',
  capo_id     uuid,                            -- fk added below
  cartel_id   uuid references cartels(id) on delete set null,
  bank        bigint not null default 0,
  created_at  timestamptz not null default now()
);

create table profiles (
  id               uuid primary key references auth.users(id) on delete cascade,
  name             text not null unique check (char_length(name) between 3 and 20),
  avatar           text not null default '🕶️' check (char_length(avatar) between 1 and 8),
  bio              text not null default '' check (char_length(bio) <= 200),
  reputation       integer not null default 0,
  created_at       timestamptz not null default now(),
  cash             bigint not null default 0,
  bank             bigint not null default 0,
  diamonds         integer not null default 0,
  stamina          integer not null default 25,
  stamina_max      integer not null default 25,
  health           integer not null default 100,
  health_max       integer not null default 100,
  heat             integer not null default 0,
  heat_max         integer not null default 100,
  last_tick        timestamptz not null default now(),
  jail_until       timestamptz,
  immune_until     timestamptz not null default now() + interval '48 hours',
  crew_id          uuid references crews(id) on delete set null,
  inventory_slots  integer not null default 6,
  storage_cap      integer not null default 500,
  refills_used     integer not null default 0,
  refills_reset_at timestamptz not null default now(),
  actions_done     integer not null default 0,
  fights_won       integer not null default 0,
  fights_lost      integer not null default 0,
  market_volume    bigint not null default 0,
  imports          bigint not null default 0,
  last_seen        timestamptz not null default now()
);

create index profiles_last_seen_idx on profiles(last_seen desc);
create index profiles_crew_idx on profiles(crew_id);

alter table crews   add constraint crews_capo_fk   foreign key (capo_id) references profiles(id) on delete set null;
alter table cartels add constraint cartels_don_fk  foreign key (don_id)  references profiles(id) on delete set null;

create table milestones (
  player_id  uuid references profiles(id) on delete cascade,
  key        text not null,
  awarded_at timestamptz not null default now(),
  primary key (player_id, key)
);

-- ---------------------------------------------------------------------------
-- Economy
-- ---------------------------------------------------------------------------
create table storage (
  player_id  uuid references profiles(id) on delete cascade,
  commodity  text references commodities(code),
  qty        integer not null default 0 check (qty >= 0),
  primary key (player_id, commodity)
);

create table grow_houses (
  id          uuid primary key default gen_random_uuid(),
  player_id   uuid not null references profiles(id) on delete cascade,
  commodity   text not null references commodities(code),
  level       integer not null default 1,
  running     boolean not null default false,
  started_at  timestamptz,                      -- when the current run began
  banked      integer not null default 0,       -- uncollected units produced before started_at
  unique (player_id, commodity)
);

create table hustlers (
  id          uuid primary key default gen_random_uuid(),
  player_id   uuid not null references profiles(id) on delete cascade,
  commodity   text not null references commodities(code),
  count       integer not null,
  units       integer not null,
  cash_due    bigint not null,
  departs_at  timestamptz not null default now(),
  returns_at  timestamptz not null,
  collected   boolean not null default false
);
create index hustlers_player_idx on hustlers(player_id) where not collected;

create table listings (
  id          uuid primary key default gen_random_uuid(),
  seller_id   uuid not null references profiles(id) on delete cascade,
  commodity   text not null references commodities(code),
  qty         integer not null check (qty >= 0),
  unit_price  integer not null check (unit_price > 0),
  status      listing_status not null default 'open',
  created_at  timestamptz not null default now(),
  expires_at  timestamptz not null default now() + interval '48 hours'
);
create index listings_open_idx on listings(commodity, unit_price) where status = 'open';
create index listings_seller_idx on listings(seller_id) where status = 'open';

-- ---------------------------------------------------------------------------
-- Items
-- ---------------------------------------------------------------------------
create table inventory (
  player_id  uuid references profiles(id) on delete cascade,
  item_id    integer references item_defs(id),
  qty        integer not null default 0 check (qty >= 0),
  primary key (player_id, item_id)
);

create table setup_items (
  player_id  uuid references profiles(id) on delete cascade,
  setup      setup_kind not null,
  item_id    integer references item_defs(id),
  qty        integer not null default 0 check (qty >= 0),
  primary key (player_id, setup, item_id)
);

-- ---------------------------------------------------------------------------
-- Fights
-- ---------------------------------------------------------------------------
create table fights (
  id            bigserial primary key,
  attacker_id   uuid not null references profiles(id) on delete cascade,
  defender_id   uuid not null references profiles(id) on delete cascade,
  attacker_dmg  integer not null,   -- dealt by attacker
  defender_dmg  integer not null,   -- dealt by defender (counter)
  cash_taken    bigint not null default 0,
  winner_id     uuid,
  created_at    timestamptz not null default now()
);
create index fights_attacker_idx on fights(attacker_id, created_at desc);
create index fights_defender_idx on fights(defender_id, created_at desc);

create table crew_fights (
  id              bigserial primary key,
  attacker_crew   uuid not null references crews(id) on delete cascade,
  defender_crew   uuid not null references crews(id) on delete cascade,
  started_by      uuid references profiles(id) on delete set null,
  attack_power    integer not null,
  defense_power   integer not null,
  won             boolean not null,
  cash_taken      bigint not null default 0,
  created_at      timestamptz not null default now()
);
create index crew_fights_pair_idx on crew_fights(attacker_crew, defender_crew, created_at desc);
create index crew_fights_def_idx on crew_fights(defender_crew, created_at desc);

-- ---------------------------------------------------------------------------
-- Crews / cartels social tables
-- ---------------------------------------------------------------------------
create table crew_applications (
  crew_id    uuid references crews(id) on delete cascade,
  player_id  uuid references profiles(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (crew_id, player_id)
);

create table cartel_invites (
  cartel_id  uuid references cartels(id) on delete cascade,
  crew_id    uuid references crews(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (cartel_id, crew_id)
);

-- ---------------------------------------------------------------------------
-- Territory
-- ---------------------------------------------------------------------------
create table hoods (
  id              serial primary key,
  island          text not null,
  name            text not null unique,
  price           integer not null,        -- $ to claim an empty block = price / block count
  daily_income    integer not null,
  base_resistance integer not null,
  owner_crew_id   uuid references crews(id) on delete set null,
  last_payout_at  timestamptz not null default now()
);

create table blocks (
  id             serial primary key,
  hood_id        integer not null references hoods(id) on delete cascade,
  name           text not null,
  owner_crew_id  uuid references crews(id) on delete set null,
  taken_at       timestamptz
);
create index blocks_hood_idx on blocks(hood_id);
create index blocks_owner_idx on blocks(owner_crew_id);

create table player_hoodlums (
  player_id  uuid references profiles(id) on delete cascade,
  code       text references hoodlum_defs(code),
  qty        integer not null default 0 check (qty >= 0),
  primary key (player_id, code)
);

create table block_garrison (
  block_id   integer references blocks(id) on delete cascade,
  code       text references hoodlum_defs(code),
  qty        integer not null default 0 check (qty >= 0),
  primary key (block_id, code)
);

create table territory_log (
  id          bigserial primary key,
  block_id    integer references blocks(id) on delete cascade,
  attacker_id uuid references profiles(id) on delete set null,
  crew_id     uuid references crews(id) on delete set null,
  success     boolean not null,
  attack      integer not null,
  resistance  integer not null,
  created_at  timestamptz not null default now()
);

-- ---------------------------------------------------------------------------
-- Accolades: weekly ranked stripes computed from an event log
-- ---------------------------------------------------------------------------
create table accolade_events (
  id         bigserial primary key,
  player_id  uuid not null references profiles(id) on delete cascade,
  kind       text not null,      -- fight_win | defense | action | import | market | turf
  amount     bigint not null default 1,
  created_at timestamptz not null default now()
);
create index accolade_events_week_idx on accolade_events(kind, created_at, player_id);

-- ---------------------------------------------------------------------------
-- Chat
-- ---------------------------------------------------------------------------
create table messages (
  id          bigserial primary key,
  channel     text not null check (channel ~ '^(global|crew:[0-9a-f-]{36}|cartel:[0-9a-f-]{36}|dm:[0-9a-f-]{36}:[0-9a-f-]{36})$'),  -- dm uuids sorted
  sender_id   uuid not null references profiles(id) on delete cascade,
  sender_name text not null,
  body        text not null check (char_length(body) between 1 and 500),
  created_at  timestamptz not null default now()
);
create index messages_channel_idx on messages(channel, created_at desc);

-- ---------------------------------------------------------------------------
-- Lock everything down. Clients use RPCs only, except reading chat (realtime).
-- ---------------------------------------------------------------------------
do $$
declare t text;
begin
  for t in select tablename from pg_tables where schemaname = 'public' loop
    execute format('alter table public.%I enable row level security', t);
    execute format('revoke all on public.%I from anon, authenticated', t);
  end loop;
end $$;

-- Chat is readable directly (for realtime subscriptions); the policy is defined in 0002 next to can_use_channel().
grant select on messages to authenticated;

-- Realtime publication for chat
do $$
begin
  if exists (select 1 from pg_publication where pubname = 'supabase_realtime') then
    alter publication supabase_realtime add table messages;
  end if;
end $$;
