-- Tracks whether a player has completed (or skipped) the members-area
-- walkthrough tutorial, so it only auto-plays once. Players can always
-- replay it manually regardless of this flag.
alter table profiles add column if not exists has_seen_tutorial boolean not null default false;

create or replace function player_mark_tutorial_seen()
returns void language plpgsql security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  update profiles set has_seen_tutorial = true where id = auth.uid();
end;
$$;
