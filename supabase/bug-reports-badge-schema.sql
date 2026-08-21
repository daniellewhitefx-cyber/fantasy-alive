
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
