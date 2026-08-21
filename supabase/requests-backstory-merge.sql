
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
