-- Widens fa_is_backstory_viewer() (from backstory-remort-redo.sql) to also
-- cover character_staff, so the "View Backstory" button on
-- admin-characters.html actually has something to show -- that page is
-- gated on character_staff/site_admin, a different permission dimension
-- than the Lore/Logistics/Plot department checks the function already
-- covered. Requires backstory-remort-redo.sql to already exist.

create or replace function fa_is_backstory_viewer()
returns boolean language sql stable
set search_path = public
as $$
  select fa_is_lore_or_admin()
    or fa_is_logistics_or_admin()
    or fa_is_plot_or_admin()
    or coalesce((auth.jwt() -> 'app_metadata' ->> 'character_staff')::boolean, false);
$$;
