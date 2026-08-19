-- Corrects the appraisal codes imported by
-- item-catalog-appraisal-codes-import.sql. That import scraped a snapshot
-- of the legacy Tags spreadsheet's Code column, which turned out to be
-- wrong in two ways: only ~1,844 items matched by exact name against the
-- real catalog (many armour variants etc. didn't), and -- more
-- importantly -- the single letter at each end of the code is driven by
-- =RAND() in the spreadsheet's own formula, so it (and the whole value,
-- when the random lookup happens to fail) changes every time the sheet
-- recalculates. It is not real per-item data.
--
-- The middle 12-character segment is real, though: per the rulebook's
-- Appraising rule, it deterministically encodes the item's Copper value
-- across six lettered positions (A-F, each one digit of the value
-- zero-padded to 6 digits, reassembled in alphabetical order to recover
-- the value) plus one more for Availability (rank 1-8). That part is
-- recomputed here directly from the real items table (copper_value,
-- availability_id) for every item in the catalog, so every item gets a
-- correct, complete, and stable code -- not just the ones that happened
-- to match a legacy sheet name. The two decorative outer letters carry no
-- game-mechanical meaning (confirmed with the site owner), so they're
-- just a fixed per-item filler rather than an attempt to replicate the
-- spreadsheet's unreproducible random ones.

insert into item_catalog (item_name, code)
select
  i.name,
  concat(
    chr(65 + (i.id * 7) % 26), '    ',
    'D', substr(v6, 4, 1),
    'A', substr(v6, 1, 1),
    'F', substr(v6, 6, 1),
    'C', substr(v6, 3, 1),
    'Av', i.availability_id::text,
    'E', substr(v6, 5, 1),
    'B', substr(v6, 2, 1),
    '    ', chr(65 + ((i.id * 13) + 5) % 26)
  )
from (
  select distinct on (lower(name)) id, name, lpad(copper_value::text, 6, '0') as v6, availability_id
  from items
  order by lower(name), id
) i
on conflict (lower(item_name)) do update set
  code = excluded.code,
  updated_at = now();
