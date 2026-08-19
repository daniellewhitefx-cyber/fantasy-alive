-- Sets "With Will and Mind" as the casting prefix for every scroll spell,
-- uniformly. The legacy sheet only had this line written down for 2 of
-- 213 spells (with a couple different phrasings depending on casting
-- path), but the site owner wants the same line on every scroll rather
-- than tracking per-spell/per-path variants. Safe to re-run; staff can
-- still override any individual spell's prefix later via the inline
-- field on the Scroll Tag print batch.

update scroll_spell_tags
  set cast_prefix = 'With Will and Mind', updated_at = now();
