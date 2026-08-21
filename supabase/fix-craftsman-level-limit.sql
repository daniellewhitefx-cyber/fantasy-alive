
update skill_details
set level_limit = 10, focus_limit = null
where id in (139, 140, 141, 183)
  and skill_id = 85
  and level_limit is null
  and focus_limit = 10;
