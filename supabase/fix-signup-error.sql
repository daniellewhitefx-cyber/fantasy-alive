
create or replace function handle_new_user()
returns trigger language plpgsql security definer
set search_path = public
as $$
begin
  begin
    insert into profiles (id, display_name)
    values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', new.email))
    on conflict (id) do nothing;
  exception when others then
    raise warning 'handle_new_user: failed to create profile for %: %', new.id, sqlerrm;
  end;
  return new;
end;
$$;

insert into profiles (id, display_name)
select id, coalesce(raw_user_meta_data ->> 'display_name', email) from auth.users
on conflict (id) do nothing;
