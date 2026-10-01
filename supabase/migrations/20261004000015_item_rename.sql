-- Renaming a rare item (Zack, 2026-10-01).
--
-- "Escobar's Machete" named a real drug lord. App Review rejects real people's names in game content (5.2, the same
-- reason the store screenshots strip real names), so the item is now "Kingpin's Machete". Only the name changes: its
-- id, numbers and owners stay, and combo_parts keys on item_id (the combos migration looked the name up once, at
-- insert), so the Back Alley combo keeps counting it.

update item_defs set name = 'Kingpin''s Machete' where name = 'Escobar''s Machete';
