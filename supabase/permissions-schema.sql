
create or replace function fa_is_site_admin()
returns boolean language sql stable
set search_path = public
as $$
  select coalesce((auth.jwt() -> 'app_metadata' ->> 'site_admin')::boolean, false);
$$;

create or replace function fa_is_logistics_or_admin()
returns boolean language sql stable
set search_path = public
as $$
  select fa_is_site_admin() or exists (
    select 1 from department_members dm
    join departments d on d.id = dm.department_id
    where dm.player_id = auth.uid() and d.name = 'Logistics'
  );
$$;

create or replace function fa_is_lore_or_admin()
returns boolean language sql stable
set search_path = public
as $$
  select fa_is_site_admin() or coalesce((auth.jwt() -> 'app_metadata' ->> 'role') = 'lore_editor', false);
$$;
