alter table profiles add column if not exists is_townsperson boolean not null default false;

create or replace function player_set_townsperson_only(p_enabled boolean)
returns void language plpgsql security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  update profiles set is_townsperson = p_enabled where id = auth.uid();
end;
$$;
