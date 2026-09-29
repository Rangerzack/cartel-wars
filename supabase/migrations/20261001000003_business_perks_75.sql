-- Business perks 25% lower: every business's base (one outer-ring block) and ceiling go to 75% of their
-- launch values. Everything built on them is linear in those two numbers (the ring scale, full hood x1.5,
-- cartel x1.75, stacking at a quarter each, the double-the-best cap, the ceiling), so every perk anywhere
-- lands at exactly 75% of what it was — Deceptive Chaos's maxed perks included.
--
-- The buy-low-sell-high guard still holds with room to spare: vehicles bought at 70% (Chop Shop −30%)
-- resell for at most 57.5% (Repo Co).
--
--   business                          base → ceiling   (was)
--   Grow House / Dust Lab / Pill F.   7.5% → 37.5%     (10% → 50%)
--   Utility Co                        3.75% → 18.75%   (5% → 25%)
--   Chop Shop                         7.5% → 30%       (10% → 40%)
--   Trucking Co                       18.75% → 75%     (25% → 100%)
--   Repo Co                           3.75% → 7.5%     (5% → 10%; resale 53.75% → 57.5%)
--   Strip Club / Night Club           7.5% → 30%       (10% → 40%)
--   Dispensary                        3.75% → 15%      (5% → 20%)
--   Gym / Shooting Range / Security   7.5% → 30%       (10% → 40%)
--   Pawn Shop                         3.75% → 15%      (5% → 20%)
--   Pharmacy / Warehouse              7.5% → 30%       (10% → 40%)
--   Clinic / Bent Cop                 7.5% → 30%       (10% → 40%)
--   Law Office                        11.25% → 30%     (15% → 40%)
-- Written as values rather than "x 0.75" so running it twice can't cut twice.
update business_defs d set base = v.base, ceiling = v.ceiling
  from (values ('grow_house',     0.075,  0.375),
               ('dust_lab',       0.075,  0.375),
               ('pill_factory',   0.075,  0.375),
               ('utility',        0.0375, 0.1875),
               ('chop_shop',      0.075,  0.30),
               ('trucking',       0.1875, 0.75),
               ('repo',           0.0375, 0.075),
               ('strip_club',     0.075,  0.30),
               ('night_club',     0.075,  0.30),
               ('dispensary',     0.0375, 0.15),
               ('gym',            0.075,  0.30),
               ('shooting_range', 0.075,  0.30),
               ('security_firm',  0.075,  0.30),
               ('pawn_shop',      0.0375, 0.15),
               ('pharmacy',       0.075,  0.30),
               ('warehouse',      0.075,  0.30),
               ('clinic',         0.075,  0.30),
               ('law_office',     0.1125, 0.30),
               ('bent_cop',       0.075,  0.30)) v(code, base, ceiling)
 where d.code = v.code;
