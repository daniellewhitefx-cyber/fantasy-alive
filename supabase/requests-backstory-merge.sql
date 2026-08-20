-- Backstory Requests was merged into the unified admin-requests.html hub as
-- a new tab, so requests_pending_count() (the sidebar "Requests" badge) now
-- folds in pending backstory submissions for whoever can act on them (Lore
-- or admins), alongside the existing Logistics-scoped remort/OC/kudos
-- counts. lore_pending_backstory_count() (from backstory-schema.sql) is now
-- unused now that the standalone Backstory Requests page/badge is gone.
-- Requires requests-schema.sql and backstory-schema.sql to already exist.

create or replace function requests_pending_count()
returns integer language plpgsql stable security definer
set search_path = public
as $$
declare
  v_total integer := 0;
begin
  if fa_is_logistics_or_admin() then
    v_total := v_total
      + (select count(*) from character_remort_requests where status = 'pending')
      + (select count(*) from oc_submission_requests where status = 'pending')
      + (select count(*) from kudos where status = 'pending');
  end if;

  if fa_is_lore_or_admin() then
    v_total := v_total + (select count(*) from character_backstories where status = 'pending');
  end if;

  return v_total;
end;
$$;

drop function if exists lore_pending_backstory_count();
