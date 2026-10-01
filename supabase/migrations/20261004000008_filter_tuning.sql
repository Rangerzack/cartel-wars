-- Tuning the word filter (Zack, 2026-10-01).
--
--  * Split-up words: the "anywhere" tier used to strip every non-letter from the whole text and search what was left, so
--    "music until dawn" was refused (musi[c unt]il). Now the text's words are grouped first: two neighbours join when either
--    has 1–2 letters or both have 1–3, which is what a split-up word looks like (f.u.c.k, fu ck, nig ger, nigg er), while two
--    ordinary words (music until, panic until, doc until) stay apart. An "anywhere" word matches inside any group, or when
--    whole groups in a row spell it exactly (white power, Sieg Heil: the listed phrases are two ordinary words). This applies
--    everywhere, names included.
--  * Chat switch: banned_words.chat says whether an "anywhere" or "inside a word" word also blocks chat messages and forum
--    posts. Slurs and hate do; crude-but-not-hate words (shit, bitch, porn…) don't, so "bullshit" and "son of a b1tch" go
--    through in chat while names, avatars, bios, crew names and descriptions and forum titles stay strict. Whole-word words
--    never reached chat and still don't. mod_words('chat', word) flips the switch and logs set_word.

alter table banned_words add column if not exists chat boolean not null default true;
update banned_words set chat = false
 where word in ('shit', 'bitch', 'whore', 'slut', 'porn', 'penis', 'vagina', 'asshole', 'jizz', 'dildo', 'blowjob', 'handjob', 'cumshot');

alter table mod_log drop constraint if exists mod_log_action_check;
alter table mod_log add constraint mod_log_action_check
  check (action in ('reset_name', 'reset_avatar', 'clear_bio', 'dismiss', 'add_word', 'remove_word', 'set_word'));

-- ---------------------------------------------------------------------------
-- The filter
-- ---------------------------------------------------------------------------
-- The text's words (lower-cased, swaps undone, camelCase split) with split-up words joined back: neighbours join when
-- either has ≤ 2 letters or both have ≤ 3, along the whole run ('f u c k off' → {fuckoff}; 'music until dawn' stays three).
create or replace function _squash_groups(t text) returns text[]
language plpgsql immutable set search_path = public as $$
declare tok text; prev text; cur text := ''; groups text[] := '{}';
begin
  foreach tok in array regexp_split_to_array(_leet(regexp_replace(coalesce(t, ''), '([a-z])([A-Z])', '\1 \2', 'g')), '[^a-z]+') loop
    continue when tok = '';
    if prev is not null and (length(prev) <= 2 or length(tok) <= 2 or (length(prev) <= 3 and length(tok) <= 3)) then
      cur := cur || tok;
    else
      if cur <> '' then groups := groups || cur; end if;
      cur := tok;
    end if;
    prev := tok;
  end loop;
  if cur <> '' then groups := groups || cur; end if;
  return groups;
end $$;

-- The tiers to check, and whether only the words marked chat count. Squash words are matched against the groups joined by
-- spaces: inside one group (no space in the pattern), or as whole groups in a row ('white power').
drop function if exists _blocked_by(text, text[]);
create or replace function _blocked_by(t text, tiers text[], chat_only boolean) returns boolean
language sql stable set search_path = public as $$
  with toks as (select tok from regexp_split_to_table(_leet(regexp_replace(coalesce(t, ''), '([a-z])([A-Z])', '\1 \2', 'g')), '[^a-z]+') tok
                 where tok <> ''),
       sq as (select array_to_string(_squash_groups(t), ' ') s),
       bw as (select * from banned_words where chat or not chat_only)
  select ('squash' = any(tiers) and exists (select 1 from bw b, sq where b.match = 'squash'
             and (sq.s ~ _word_pattern(b.word) or sq.s ~ ('(^| )' || replace(_word_pattern(b.word), '+', '+ ?') || '( |$)'))))
      or ('part' = any(tiers) and exists (select 1 from bw b, toks where b.match = 'part' and toks.tok ~ _word_pattern(b.word)))
      or ('word' = any(tiers) and exists (select 1 from bw b, toks where b.match = 'word' and toks.tok ~ ('^' || _word_pattern(b.word) || 's?$'))) $$;

-- Names, avatars, bios, crew emblems and descriptions, forum titles: every tier, every word.
create or replace function _is_blocked(t text) returns boolean
language sql stable set search_path = public as $$ select _blocked_by(t, array['squash', 'part', 'word'], false) $$;

-- Chat messages and forum posts: anywhere and inside-a-word words marked chat, so swearing goes through and slurs don't.
create or replace function _is_blocked_hard(t text) returns boolean
language sql stable set search_path = public as $$ select _blocked_by(t, array['squash', 'part'], true) $$;

-- ---------------------------------------------------------------------------
-- mod_words: list | add (how it matches, and whether it reaches chat) | remove | chat (flip whether it reaches chat)
-- ---------------------------------------------------------------------------
drop function if exists mod_words(text, text, text);
create or replace function mod_words(action text default 'list', word text default null, how text default 'word', chat boolean default true) returns jsonb
language plpgsql security definer set search_path = public as $$
declare u uuid := _uid(); w text := lower(trim(coalesce(mod_words.word, ''))); c boolean := coalesce(mod_words.chat, true); b banned_words;
begin
  if not _is_admin(u) then perform _fail('Admins only'); end if;
  if action = 'add' then
    if w !~ '^[a-z]{2,30}$' then perform _fail('Words are 2–30 letters, a to z'); end if;
    if how not in ('squash', 'part', 'word') then perform _fail('Match anywhere, inside a word, or whole word'); end if;
    insert into banned_words (word, match, chat, added_by) values (w, how, c, u)
      on conflict on constraint banned_words_pkey do update set match = excluded.match, chat = excluded.chat;
    insert into mod_log (admin_id, action, new_value)
    values (u, 'add_word', w || ' (' || how || case when how = 'word' then '' when c then ', chat on' else ', chat off' end || ')');
  elsif action = 'remove' then
    delete from banned_words x where x.word = w;
    if not found then perform _fail('Not on the list'); end if;
    insert into mod_log (admin_id, action, old_value) values (u, 'remove_word', w);
  elsif action = 'chat' then
    select * into b from banned_words x where x.word = w for update;
    if b.word is null then perform _fail('Not on the list'); end if;
    if b.match = 'word' then perform _fail('Whole-word matches never block chat'); end if;
    update banned_words x set chat = not b.chat where x.word = w;
    insert into mod_log (admin_id, action, new_value)
    values (u, 'set_word', w || ' (' || b.match || case when b.chat then ', chat off' else ', chat on' end || ')');
  elsif action <> 'list' then
    perform _fail('Unknown action');
  end if;
  return (select coalesce(jsonb_agg(jsonb_build_object('word', x.word, 'match', x.match, 'chat', x.chat) order by x.match, x.word), '[]'::jsonb)
            from banned_words x);
end $$;

-- ---------------------------------------------------------------------------
-- Grants
-- ---------------------------------------------------------------------------
do $$ declare f record; begin
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname = 'mod_words' loop
    execute format('revoke all on function %s from public, anon', f.sig);
    execute format('grant execute on function %s to authenticated', f.sig);
  end loop;
  for f in select p.oid::regprocedure::text as sig from pg_proc p join pg_namespace n on n.oid = p.pronamespace
           where n.nspname = 'public' and p.proname in ('_squash_groups', '_blocked_by', '_is_blocked', '_is_blocked_hard') loop
    execute format('revoke all on function %s from public, anon, authenticated', f.sig);
  end loop;
end $$;
