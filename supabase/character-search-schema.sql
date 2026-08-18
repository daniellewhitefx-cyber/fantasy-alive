-- Was previously a plain view, which Supabase's security linter flags as
-- a "Security Definer View": since it deliberately needs to look up other
-- players' character names (for billing, friends, kudos, messages, and
-- notifications) it has to bypass the characters table's own RLS (which
-- otherwise restricts each player to their own characters), and a bare
-- view does that implicitly and non-obviously. A security definer
-- function makes that same elevated access explicit and auditable,
-- matching the pattern used everywhere else in this project, and isn't
-- flagged by the linter since it targets views specifically.
drop view if exists character_names;

create or replace function character_names()
returns table(id uuid, name text, player_id uuid)
language sql security definer
set search_path = public
as $$
  select id, name, player_id from characters;
$$;

grant execute on function character_names() to authenticated;
