-- Adds portrait_url to character_names() (character-search-schema.sql) so
-- pages that already use it for cross-player character lookups -- like
-- Friends -- can show a character's portrait without a second query.
-- portrait_url is already a public URL (character-portraits storage
-- bucket is public), so exposing it here is no different from exposing
-- it on the characters table's own public columns. Requires
-- character-search-schema.sql and character-portrait-schema.sql to
-- already exist.

-- Postgres won't let CREATE OR REPLACE change a function's return row
-- type (adding a column counts as a change), so the old signature has
-- to be dropped first.
drop function if exists character_names();

create function character_names()
returns table(id uuid, name text, player_id uuid, portrait_url text)
language sql security definer
set search_path = public
as $$
  select id, name, player_id, portrait_url from characters;
$$;

grant execute on function character_names() to authenticated;
