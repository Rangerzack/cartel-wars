-- Season 1, day 4: a content pass on Marcus's missions after seeing them on the phone card.
--  · Six Blocks: the objective line read "Open Your Hood", the same words as the button under it. It names what to do.
--  · Open for Business: "the till's full" promised more than a block taken minutes ago holds (cash accrues by the
--    hour, pro rata, so a fresh block has a dollar or two). The line now says how the till works.
-- Data only; the engine and the other thirteen missions are untouched.
update mission_defs set label = 'Look at your six blocks' where key = 'six_blocks';
update mission_defs set intro = 'The {biz1} on block one still runs, and the till fills by the hour. Go empty it.'
 where key = 'open_for_business';
