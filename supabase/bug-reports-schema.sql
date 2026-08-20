-- Lets any signed-in player submit a bug report (from a popup reachable
-- sitewide via the members sidebar) and site admins review/resolve them
-- on a dedicated staff page. Requires permissions-schema.sql (for
-- fa_is_site_admin()) to already exist.

create table if not exists bug_reports (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references auth.users(id) on delete cascade,
  page_url text,
  description text not null,
  status text not null default 'open' check (status in ('open', 'resolved')),
  resolved_by uuid references auth.users(id) on delete set null,
  resolved_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists bug_reports_status_idx on bug_reports(status, created_at);

alter table bug_reports enable row level security;

drop policy if exists "Players can view their own bug reports" on bug_reports;
create policy "Players can view their own bug reports"
  on bug_reports for select
  using (player_id = auth.uid() or fa_is_site_admin());

create or replace function bug_report_submit(p_description text, p_page_url text)
returns uuid
language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
  v_desc text := trim(coalesce(p_description, ''));
  v_id uuid;
begin
  if v_player is null then raise exception 'Not signed in'; end if;
  if v_desc = '' then raise exception 'Please describe the bug before sending.'; end if;
  if length(v_desc) > 4000 then raise exception 'That report is too long (4000 characters max).'; end if;

  insert into bug_reports (player_id, page_url, description)
    values (v_player, nullif(trim(coalesce(p_page_url, '')), ''), v_desc)
    returning id into v_id;

  return v_id;
end;
$$;

grant execute on function bug_report_submit(text, text) to authenticated;

create or replace function bug_report_mark_resolved(p_id uuid)
returns void
language plpgsql security definer
set search_path = public
as $$
begin
  if not fa_is_site_admin() then raise exception 'Staff only'; end if;

  update bug_reports set status = 'resolved', resolved_by = auth.uid(), resolved_at = now()
    where id = p_id;
  if not found then raise exception 'Bug report not found'; end if;
end;
$$;

grant execute on function bug_report_mark_resolved(uuid) to authenticated;
