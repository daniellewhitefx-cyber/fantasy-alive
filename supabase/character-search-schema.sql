create or replace view character_names as
  select id, name, player_id from characters;

grant select on character_names to authenticated;
