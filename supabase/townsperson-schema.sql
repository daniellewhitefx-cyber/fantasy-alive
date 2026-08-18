-- Lets a brand-new player mark themselves as a Townsperson (RP only, no
-- character, no combat, no downtime log) from the character creator instead
-- of building a player character, so they stop being redirected there on
-- every members-area page load. Mirrors is_cast/player_set_cast_only in
-- characters-schema.sql.
alter table profiles add column if not exists is_townsperson boolean not null default false;

create or replace function player_set_townsperson_only(p_enabled boolean)
returns void language plpgsql security definer as $$
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  update profiles set is_townsperson = p_enabled where id = auth.uid();
end;
$$;
