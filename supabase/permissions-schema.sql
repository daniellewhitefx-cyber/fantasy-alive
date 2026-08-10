-- Run this file before any other schema file that references
-- fa_is_site_admin(). Logistics staff get a single site_admin flag in
-- their Supabase app_metadata instead of every individual _staff flag,
-- so they can act anywhere on the site.

create or replace function fa_is_site_admin()
returns boolean language sql stable as $$
  select coalesce((auth.jwt() -> 'app_metadata' ->> 'site_admin')::boolean, false);
$$;
