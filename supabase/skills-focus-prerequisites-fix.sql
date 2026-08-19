-- Implements two focus-specific prerequisites the engine previously
-- couldn't represent, both simplified in the earlier prerequisite
-- rebuild:
--
-- 1. Lethal Hands requires Weapon Skill specifically in Hand to Hand,
--    not just any weapon type. Wires up prerequisite_focus_id, which
--    js/skills-data.js and js/skills-catalog.js now actually read.
--
-- 2. Shield's Physical Prowess requirement only applies to large
--    shields -- small shields need nothing extra. Turns Shield into a
--    focus-based skill (Large Shield / Small Shield), with Physical
--    Prowess only required for the Large Shield focus, via the same
--    skill_focus_prerequisites mechanism already used for 2-Handed
--    Sword/2-Handed Blunt/Polearm. Shield's own flat 4 SP cost is
--    unaffected either way (overwrite_cost_for_focus stays false).

-- Lethal Hands: pin its Weapon Skill prerequisite to Hand to Hand specifically.
update skill_prerequisites
set prerequisite_focus_id = (select id from skill_focuses where name = 'Hand to Hand')
where id = 246;

-- Shield: add the Large Shield / Small Shield focus type and options.
insert into focus_types (id, name) values (18, 'Shield')
on conflict (id) do nothing;

insert into skill_focuses (id, name, cost, tutor, level_cost, description) values
  (152, 'Large Shield', null, null, null, ''),
  (153, 'Small Shield', null, null, null, '')
on conflict (id) do nothing;

insert into skill_focus_type_map (id, focus_id, focus_type_id) values
  (183, 152, 18),
  (184, 153, 18)
on conflict (id) do nothing;

-- Physical Prowess is required only for the Large Shield focus.
insert into skill_focus_prerequisites (id, focus_id, prerequisite_skill_id, prerequisite_level) values
  (6, 152, 51, 1)
on conflict (id) do nothing;

-- Shield becomes a focus-based skill (players now choose Large Shield or
-- Small Shield when learning it).
update skills set focus_type_id = 18 where id = 34;

-- Remove Shield's old flat Physical Prowess prerequisite -- replaced by
-- the Large-Shield-only focus prerequisite above.
delete from skill_prerequisites where id = 282;
