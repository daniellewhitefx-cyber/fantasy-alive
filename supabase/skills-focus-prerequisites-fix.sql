
update skill_prerequisites
set prerequisite_focus_id = (select id from skill_focuses where name = 'Hand to Hand')
where id = 246;

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

insert into skill_focus_prerequisites (id, focus_id, prerequisite_skill_id, prerequisite_level) values
  (6, 152, 51, 1)
on conflict (id) do nothing;

update skills set focus_type_id = 18 where id = 34;

delete from skill_prerequisites where id = 282;
