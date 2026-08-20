-- skills-catalog-import.sql's skill_prerequisites seed accidentally
-- duplicated the "Weapon Mastery 1" prerequisite onto skill_details.id
-- 98 -- D'Shunn's own Channel Spell cost override -- as well as onto
-- the default (everyone-else) row it actually belongs to. The rulebook
-- (lore-import.sql, playable-races.html) says D'Shunn get Channel Spell
-- "for 10 SP (without any pre-requisites)", so their override should
-- carry none. This deletes the stray copy from already-imported data;
-- skills-catalog-import.sql itself has been fixed so a fresh import
-- won't recreate it.

delete from skill_prerequisites
where id = 216
  and skill_detail_id = 98
  and prerequisite_skill_id = 42;
