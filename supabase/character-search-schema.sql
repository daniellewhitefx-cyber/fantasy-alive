drop view if exists character_names;

create or replace function character_names()
returns table(id uuid, name text, player_id uuid)
language sql security definer
set search_path = public
as $$
  select id, name, player_id from characters;
$$;

grant execute on function character_names() to authenticated;
