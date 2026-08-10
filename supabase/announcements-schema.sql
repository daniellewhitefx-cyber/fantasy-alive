create table if not exists announcements (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  body text not null,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create index if not exists announcements_created_idx on announcements(created_at desc);

alter table announcements enable row level security;
drop policy if exists "Announcements are publicly readable" on announcements;
create policy "Announcements are publicly readable"
  on announcements for select
  using (true);

create or replace function announcement_post(p_title text, p_body text)
returns uuid language plpgsql security definer as $$
declare
  v_staff uuid := auth.uid();
  v_title text := trim(coalesce(p_title, ''));
  v_body text := trim(coalesce(p_body, ''));
  v_id uuid;
begin
  if not coalesce((auth.jwt() -> 'app_metadata' ->> 'announcements_staff')::boolean, false) then
    raise exception 'Staff only';
  end if;
  if v_title = '' then raise exception 'Title cannot be empty'; end if;
  if v_body = '' then raise exception 'Body cannot be empty'; end if;

  insert into announcements (title, body, created_by) values (v_title, v_body, v_staff)
    returning id into v_id;

  return v_id;
end;
$$;

create or replace function announcement_delete(p_id uuid)
returns void language plpgsql security definer as $$
begin
  if not coalesce((auth.jwt() -> 'app_metadata' ->> 'announcements_staff')::boolean, false) then
    raise exception 'Staff only';
  end if;

  delete from announcements where id = p_id;
end;
$$;

grant select on announcements to authenticated;
