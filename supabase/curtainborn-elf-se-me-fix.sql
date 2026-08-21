
delete from race_starting_skills where race = 'Curtainborn' and skill_id = 73;
delete from race_starting_skills where race = 'Elf' and skill_id = 68;

delete from character_skills
  where skill_name = 'Spiritual Energy' and level = 5 and sp_cost = 0
    and character_id in (select id from characters where race = 'Curtainborn');

delete from character_skills
  where skill_name = 'Magical Energy' and level = 5 and sp_cost = 0
    and character_id in (select id from characters where race = 'Elf');
