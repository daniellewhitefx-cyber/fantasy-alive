
create or replace function fa_is_backstory_viewer()
returns boolean language sql stable
set search_path = public
as $$
  select fa_is_lore_or_admin()
    or fa_is_logistics_or_admin()
    or fa_is_plot_or_admin()
    or coalesce((auth.jwt() -> 'app_metadata' ->> 'character_staff')::boolean, false);
$$;
