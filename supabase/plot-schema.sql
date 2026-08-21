
create table if not exists plotlines (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  created_by uuid not null references auth.users(id) on delete cascade,
  created_at timestamptz not null default now()
);

create table if not exists plotline_notes (
  id uuid primary key default gen_random_uuid(),
  plotline_id uuid not null references plotlines(id) on delete cascade,
  author_id uuid not null references auth.users(id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now()
);

create index if not exists plotline_notes_plotline_idx on plotline_notes(plotline_id, created_at);

alter table plotlines enable row level security;
alter table plotline_notes enable row level security;

drop policy if exists "Plot team see plotlines" on plotlines;
create policy "Plot team see plotlines"
  on plotlines for select
  using (fa_is_plot_or_admin());

drop policy if exists "Plot team see plotline notes" on plotline_notes;
create policy "Plot team see plotline notes"
  on plotline_notes for select
  using (fa_is_plot_or_admin());

create or replace function plot_create_plotline(p_title text, p_description text default null)
returns uuid language plpgsql security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not fa_is_plot_or_admin() then raise exception 'Plot staff only'; end if;
  if p_title is null or btrim(p_title) = '' then raise exception 'Title is required'; end if;

  insert into plotlines (title, description, created_by)
  values (btrim(p_title), nullif(btrim(coalesce(p_description, '')), ''), auth.uid())
  returning id into v_id;

  return v_id;
end;
$$;

create or replace function plot_post_note(p_plotline_id uuid, p_body text)
returns uuid language plpgsql security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not fa_is_plot_or_admin() then raise exception 'Plot staff only'; end if;
  if p_body is null or btrim(p_body) = '' then raise exception 'Note cannot be empty'; end if;
  if not exists (select 1 from plotlines where id = p_plotline_id) then
    raise exception 'Plotline not found';
  end if;

  insert into plotline_notes (plotline_id, author_id, body)
  values (p_plotline_id, auth.uid(), btrim(p_body))
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function plot_create_plotline(text, text) from public, anon;
grant execute on function plot_create_plotline(text, text) to authenticated;
revoke all on function plot_post_note(uuid, text) from public, anon;
grant execute on function plot_post_note(uuid, text) to authenticated;
