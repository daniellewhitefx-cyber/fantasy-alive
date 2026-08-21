
drop function if exists character_names();

create function character_names()
returns table(id uuid, name text, player_id uuid, portrait_url text)
language sql security definer
set search_path = public
as $$
  select id, name, player_id, portrait_url from characters;
$$;

grant execute on function character_names() to authenticated;
