-- Cartel Wars — content seed. All numbers are tunable; see SPEC.md for what's sourced vs ours.

insert into commodities (code, name, base_price, hustler_units, refill_stamina, refill_health, grow_rate, grow_cap, grow_price, sort) values
  ('herb',  'Herb',  60,  16, 400, 200, 20, 200,  5000, 1),
  ('dust',  'Dust',  200,  8, 280, 100,  8,  80, 15000, 2),
  ('pills', 'Pills', 600,  4, 100,  50,  3,  30, 40000, 3);

insert into street_prices (commodity, price) select code, base_price from commodities;

-- Items ---------------------------------------------------------------------
insert into item_defs (name, category, att, def, capacity, price, combo_tag, sort) values
  -- weapons
  ('Brass Knuckles',    'weapon', 4,   0, 0,    500,  'melee',   10),
  ('Switchblade',       'weapon', 6,   0, 0,   1200,  'melee',   11),
  ('Baseball Bat',      'weapon', 8,   0, 0,   2000,  'melee',   12),
  ('Machete',           'weapon', 12,  0, 0,   4500,  'melee',   13),
  ('Glock 18',          'weapon', 18,  0, 0,   8000,  'pistol',  14),
  ('Sawed-off Shotgun', 'weapon', 26,  0, 0,  15000,  'shotgun', 15),
  ('Uzi',               'weapon', 34,  0, 0,  28000,  'smg',     16),
  ('MAC-10',            'weapon', 40,  0, 0,  40000,  'smg',     17),
  ('AK-47',             'weapon', 55,  0, 0,  75000,  'rifle',   18),
  ('M4 Carbine',        'weapon', 65,  0, 0, 110000,  'rifle',   19),
  ('Sniper Rifle',      'weapon', 80,  0, 0, 180000,  'rifle',   20),
  ('RPG',               'weapon', 110, 0, 0, 350000,  'heavy',   21),
  ('Minigun',           'weapon', 150, 0, 0, 700000,  'heavy',   22),
  -- jail weapons
  ('Shank',             'jail_weapon', 5,  0, 0,   800, 'shiv',  30),
  ('Toothbrush Shiv',   'jail_weapon', 8,  0, 0,  1500, 'shiv',  31),
  ('Sock of Batteries', 'jail_weapon', 12, 0, 0,  3000, 'melee', 32),
  ('Razor Blade Comb',  'jail_weapon', 16, 0, 0,  6000, 'shiv',  33),
  ('Sharpened Spoon',   'jail_weapon', 22, 0, 0, 12000, 'shiv',  34),
  ('Cell Block Pipe',   'jail_weapon', 35, 0, 0, 30000, 'melee', 35),
  -- protection
  ('Leather Jacket',    'protection', 0,  5,  0,   1000, 'melee',   40),
  ('Helmet',            'protection', 0,  8,  0,   2500, 'melee',   41),
  ('Prison Yard Muscle','protection', 0,  15, 0,   8000, 'shiv',    42),
  ('Kevlar Vest',       'protection', 0,  18, 0,   9000, 'pistol',  43),
  ('Riot Shield',       'protection', 0,  28, 0,  20000, 'shotgun', 44),
  ('Grenades',          'protection', 20, 10, 0,  35000, 'heavy',   45),
  ('Tactical Vest',     'protection', 0,  40, 0,  45000, 'smg',     46),
  ('Body Armor',        'protection', 0,  55, 0,  90000, 'rifle',   47),
  ('Bulletproof Plate', 'protection', 0,  90, 0, 250000, 'heavy',   48),
  -- transport (only the best one counts for att/def; capacity gates marketplace batches)
  ('Motorcycle',        'transport', 2,  2,   25,   3000, null, 60),
  ('Sedan',             'transport', 4,  6,  100,  12000, null, 61),
  ('Van',               'transport', 3,  10, 300,  35000, null, 62),
  ('Armored SUV',       'transport', 10, 25, 200,  90000, null, 63),
  ('Box Truck',         'transport', 5,  15, 600, 120000, null, 64),
  ('Cargo Truck',       'transport', 8,  20, 1000, 300000, null, 65);

-- Actions -------------------------------------------------------------------
insert into action_defs (sort, name, description, stamina_cost, pay_min, pay_max, heat_gain, cash_cost, requires_item, min_crew, is_jail, effect)
select v.sort, v.name, v.description, v.stamina, v.pay_min, v.pay_max, v.heat, v.cash_cost,
       (select id from item_defs where name = v.item), v.min_crew, v.is_jail, v.effect
from (values
  ( 1, 'Sling on the Corner',              'Move dime bags to whoever walks by.',                    1,   140,   220, 1,    0, null::text,          0, false, null::text),
  ( 2, 'Run a Package',                    'Carry a package across the hood, no questions.',          1,   200,   320, 1,    0, null,                0, false, null),
  ( 3, 'Lookout for the Block',            'Whistle when the cruisers roll through.',                 2,   300,   500, 1,    0, null,                0, false, null),
  ( 4, 'Shake Down a Shop Owner',          'Remind him who keeps the block safe.',                    2,   450,   700, 2,    0, 'Brass Knuckles',    0, false, null),
  ( 5, 'Jack a Car Stereo',                'Quick smash and grab.',                                   2,   500,   900, 2,    0, null,                0, false, null),
  ( 6, 'Collect Protection Money',         'Everybody pays. Everybody.',                              3,   800,  1300, 2,    0, 'Baseball Bat',      0, false, null),
  ( 7, 'Fence Stolen Goods',               'Turn hot merchandise into cold cash.',                    3,  1000,  1600, 2,    0, null,                0, false, null),
  ( 8, 'Move Product Across Town',         'Keep it under the speed limit.',                          3,  1200,  2000, 3,    0, 'Motorcycle',        0, false, null),
  ( 9, 'Rob a Bodega',                     'In and out in ninety seconds.',                           4,  1500,  2600, 4,    0, 'Glock 18',          0, false, null),
  (10, 'Intimidate a Witness',             'Memories fade with the right encouragement.',             4,  2000,  3000, 3,    0, null,                0, false, null),
  (11, 'Hijack a Delivery Van',            'Follow it to a quiet street.',                            5,  2500,  4200, 4,    0, 'Sedan',             0, false, null),
  (12, 'Torch a Rival Stash House',        'Send a message they can smell from downtown.',            5,  3000,  5000, 5,    0, null,                2, false, null),
  (13, 'Bribe a Customs Agent',            'A friend at the port is worth every dollar.',             6,  3500,  6000, 2, 1000, null,                0, false, null),
  (14, 'Run Guns to the Docks',            'The buyers don''t like to wait.',                         6,  4000,  7000, 5,    0, 'Van',               0, false, null),
  (15, 'Rob an Armored Car',               'Three minutes before backup arrives.',                    7,  5000,  9000, 6,    0, 'Sawed-off Shotgun', 3, false, null),
  (16, 'Kidnap a Banker',                  'He knows the vault codes. He''ll talk.',                  7,  6000, 10000, 6,    0, null,                0, false, null),
  (17, 'Smuggle a Shipment Through the Port','Paperwork says furniture.',                             8,  7000, 12000, 4,    0, 'Box Truck',         0, false, null),
  (18, 'Hit a Rival''s Grow Op',           'Take their product and their pride.',                     8,  8000, 14000, 6,    0, 'Uzi',               3, false, null),
  (19, 'Launder Cash Through a Casino',    'Dirty money in, clean chips out.',                        9,  9000, 15000, 2, 3000, null,                0, false, null),
  (20, 'Take Over a Chop Shop',            'New management, same parts.',                             9, 10000, 17000, 6,    0, 'AK-47',             4, false, null),
  (21, 'Assassinate a Snitch',             'One shot from the parking structure.',                   10, 12000, 20000, 8,    0, 'Sniper Rifle',      0, false, null),
  (22, 'Raid a Federal Evidence Lockup',   'Get the tapes before the trial.',                        11, 15000, 25000, 8,    0, 'M4 Carbine',        5, false, null),
  (23, 'Hijack a Cartel Plane',            'Wheels up before the tower notices.',                    12, 18000, 28000, 7,    0, 'RPG',               5, false, null),
  (24, 'Take Down a Rival Don',            'Cut the head off and the body follows.',                 12, 22000, 31000, 8,    0, 'Minigun',           6, false, null),
  (25, 'Bribe Police To Get In Jail',      'Sometimes the safest place is behind bars.',             10,     0,     0, 0, 1000, null,                0, false, 'go_to_jail'),
  -- jail actions
  (30, 'Run the Commissary Racket',        'Ramen is currency in here.',                              1,   100,   200, 0,    0, null,                0, true,  null),
  (31, 'Smuggle Cigarettes',               'A carton goes a long way.',                               2,   250,   450, 0,    0, null,                0, true,  null),
  (32, 'Collect Gambling Debts',           'The yard always pays up.',                                3,   400,   700, 0,    0, 'Shank',             0, true,  null),
  (33, 'Run the Phone Hustle',             'Every call costs extra.',                                 3,   500,   900, 0,    0, null,                0, true,  null),
  (34, 'Shake Down New Fish',              'Welcome to the block.',                                   4,   700,  1200, 0,    0, 'Sharpened Spoon',   0, true,  null),
  (35, 'Broker a Prison Contract',         'Somebody outside needs a favor done inside.',            6,  1500,  3000, 0,    0, 'Cell Block Pipe',   0, true,  null)
) as v(sort, name, description, stamina, pay_min, pay_max, heat, cash_cost, item, min_crew, is_jail, effect)
order by v.sort;

-- Hoodlums ------------------------------------------------------------------
insert into hoodlum_defs (code, name, att, def, intel, base_price) values
  ('thug',      'Thug',      10, 10, 0, 1000),
  ('spy',       'Spy',        0,  0, 7,  500),
  ('mercenary', 'Mercenary', 60,  0, 0, 4000),
  ('enforcer',  'Enforcer',   0, 60, 0, 4000);

-- Territory: four islands, three hoods each, four blocks per hood ---------
insert into hoods (island, name, price, daily_income, base_resistance) values
  ('North Shore', 'Harbor Row',        16000,  320000,  200),
  ('North Shore', 'Cannery District',  20000,  400000,  300),
  ('North Shore', 'The Bluffs',        24000,  480000,  450),
  ('Eastside',    'Rail Yards',        22000,  440000,  400),
  ('Eastside',    'Little Medellín',   28000,  560000,  600),
  ('Eastside',    'Ironworks',         32000,  640000,  800),
  ('Southbay',    'Boardwalk',         30000,  600000,  700),
  ('Southbay',    'Marina Flats',      36000,  720000,  950),
  ('Southbay',    'Casino Strip',      42000,  840000, 1300),
  ('West Harbor', 'Container Port',    40000,  800000, 1200),
  ('West Harbor', 'Refinery Road',     46000,  920000, 1600),
  ('West Harbor', 'The Heights',       50000, 1000000, 2000);

insert into blocks (hood_id, name)
select h.id, h.name || ' — Block ' || chr(64 + s) from hoods h cross join generate_series(1, 4) s order by h.id, s;
