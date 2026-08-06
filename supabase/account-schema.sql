alter table profiles add column if not exists pronouns text;

create table if not exists member_private_notes (
  id uuid primary key references auth.users(id) on delete cascade,
  allergy_notes text,
  disability_notes text,
  updated_at timestamptz not null default now()
);

alter table member_private_notes enable row level security;

drop policy if exists "Members see only their own private notes" on member_private_notes;
create policy "Members see only their own private notes"
  on member_private_notes for select
  using (id = auth.uid());

create or replace function account_set_display_name(p_display_name text)
returns void language plpgsql security definer as $$
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  if p_display_name is null or length(trim(p_display_name)) = 0 then
    raise exception 'Display name cannot be empty';
  end if;
  update profiles set display_name = trim(p_display_name) where id = auth.uid();
end;
$$;

create or replace function account_set_pronouns(p_pronouns text)
returns void language plpgsql security definer as $$
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  update profiles set pronouns = nullif(trim(coalesce(p_pronouns, '')), '') where id = auth.uid();
end;
$$;

create or replace function account_set_allergy_notes(p_notes text)
returns void language plpgsql security definer as $$
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  insert into member_private_notes (id, allergy_notes)
    values (auth.uid(), nullif(trim(coalesce(p_notes, '')), ''))
  on conflict (id) do update
    set allergy_notes = excluded.allergy_notes, updated_at = now();
end;
$$;

create or replace function account_set_disability_notes(p_notes text)
returns void language plpgsql security definer as $$
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  insert into member_private_notes (id, disability_notes)
    values (auth.uid(), nullif(trim(coalesce(p_notes, '')), ''))
  on conflict (id) do update
    set disability_notes = excluded.disability_notes, updated_at = now();
end;
$$;

grant select on member_private_notes to authenticated;
