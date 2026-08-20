-- Powers the unresolved-count badge on the Bug Reports sidebar link,
-- mirroring requests_pending_count()'s self-gating pattern (returns 0
-- for anyone who isn't a site admin, so any signed-in player can safely
-- call it). Requires bug-reports-schema.sql to already exist.

create or replace function bug_reports_open_count()
returns integer language plpgsql stable security definer
set search_path = public
as $$
begin
  if not fa_is_site_admin() then
    return 0;
  end if;

  return (select count(*) from bug_reports where status = 'open')::integer;
end;
$$;

grant execute on function bug_reports_open_count() to authenticated;
