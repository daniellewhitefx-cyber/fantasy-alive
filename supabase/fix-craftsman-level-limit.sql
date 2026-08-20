-- skills-catalog-import.sql's skill_details seed had Craftsman's (skill_id
-- 85) level_limit value shifted one column over into focus_limit for all
-- four of its rows (default, Dwarf, Curtainborn, Minotaur), leaving
-- level_limit null (uncapped) instead of 10 -- matching its sibling trade
-- skills Labourer and Merchant, which both correctly have level_limit=10.
-- This corrects the already-imported rows; skills-catalog-import.sql
-- itself has been fixed so a fresh import won't recreate the bug.

update skill_details
set level_limit = 10, focus_limit = null
where id in (139, 140, 141, 183)
  and skill_id = 85
  and level_limit is null
  and focus_limit = 10;
