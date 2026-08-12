-- Run this file before any other schema file that references
-- fa_is_site_admin(). Logistics staff get a single site_admin flag in
-- their Supabase app_metadata instead of every individual _staff flag,
-- so they can act anywhere on the site.

create or replace function fa_is_site_admin()
returns boolean language sql stable as $$
  select coalesce((auth.jwt() -> 'app_metadata' ->> 'site_admin')::boolean, false);
$$;

-- The Requests hub (Remort/OC/Kudos approvals) is scoped to site admins
-- and members of the Logistics department, per how the club actually
-- splits that work, rather than a dedicated staff flag.
create or replace function fa_is_logistics_or_admin()
returns boolean language sql stable as $$
  select fa_is_site_admin() or exists (
    select 1 from department_members dm
    join departments d on d.id = dm.department_id
    where dm.player_id = auth.uid() and d.name = 'Logistics'
  );
$$;
