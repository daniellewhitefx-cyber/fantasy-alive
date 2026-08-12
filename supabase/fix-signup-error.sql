-- Fixes "Database error saving new user" on signup.
-- The handle_new_user trigger runs on every auth.users insert; if the
-- profile insert inside it throws for any reason, it was blocking the
-- entire signup instead of just failing to create the profile row.
-- This makes that insert best-effort so signups can never be blocked
-- by it again, then backfills any accounts that got created without
-- a profile while this was broken.

create or replace function handle_new_user()
returns trigger language plpgsql security definer as $$
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
