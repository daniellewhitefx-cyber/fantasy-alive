-- Matches character-admin-schema.sql's version of this same policy
-- exactly, so re-running either file in either order always lands on
-- the correct, staff-aware rule instead of whichever file ran last
-- silently overwriting the other's policy of the same name.
drop policy if exists "Players see their own characters" on characters;
create policy "Players see their own characters"
  on characters for select
  using (
    player_id = auth.uid()
    or (auth.jwt() -> 'app_metadata' ->> 'remort_staff')::boolean is true
    or (auth.jwt() -> 'app_metadata' ->> 'character_staff')::boolean is true
    or fa_is_site_admin()
  );

create table if not exists character_remort_requests (
  id uuid primary key default gen_random_uuid(),
  character_id uuid not null references characters(id) on delete cascade,
  player_id uuid not null references auth.users(id) on delete cascade,
  status text not null default 'pending' check (status in ('pending', 'approved', 'completed', 'denied')),
  requested_at timestamptz not null default now(),
  decided_at timestamptz,
  decided_by uuid references auth.users(id) on delete set null,
  completed_at timestamptz
);

create index if not exists character_remort_requests_character_idx on character_remort_requests(character_id);

alter table character_remort_requests enable row level security;

-- Matches requests-schema.sql's version of this same policy exactly,
-- so re-running either file in either order always lands on the
-- correct, Logistics-department-aware rule instead of whichever file
-- ran last silently overwriting the other's policy of the same name.
drop policy if exists "Players and staff see remort requests" on character_remort_requests;
create policy "Players and staff see remort requests"
  on character_remort_requests for select
  using (
    player_id = auth.uid()
    or (auth.jwt() -> 'app_metadata' ->> 'remort_staff')::boolean is true
    or fa_is_logistics_or_admin()
  );

create or replace function character_request_remort(p_character_id uuid)
returns uuid language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
  v_req_id uuid;
begin
  if v_player is null then raise exception 'Not signed in'; end if;

  if not exists (select 1 from characters where id = p_character_id and player_id = v_player) then
    raise exception 'Character not found';
  end if;

  if exists (
    select 1 from character_remort_requests
    where character_id = p_character_id and status in ('pending', 'approved')
  ) then
    raise exception 'There is already an open remort request for this character';
  end if;

  insert into character_remort_requests (character_id, player_id)
    values (p_character_id, v_player)
    returning id into v_req_id;

  return v_req_id;
end;
$$;

create or replace function character_approve_remort(p_request_id uuid)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  v_staff uuid := auth.uid();
begin
  if not (coalesce((auth.jwt() -> 'app_metadata' ->> 'remort_staff')::boolean, false) or fa_is_site_admin()) then
    raise exception 'Staff only';
  end if;

  update character_remort_requests
    set status = 'approved', decided_at = now(), decided_by = v_staff
    where id = p_request_id and status = 'pending';

  if not found then raise exception 'Request not found or already decided'; end if;
end;
$$;

create or replace function character_deny_remort(p_request_id uuid)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  v_staff uuid := auth.uid();
begin
  if not (coalesce((auth.jwt() -> 'app_metadata' ->> 'remort_staff')::boolean, false) or fa_is_site_admin()) then
    raise exception 'Staff only';
  end if;

  update character_remort_requests
    set status = 'denied', decided_at = now(), decided_by = v_staff
    where id = p_request_id and status = 'pending';

  if not found then raise exception 'Request not found or already decided'; end if;
end;
$$;

create or replace function character_update_remort(
  p_character_id uuid,
  p_name text,
  p_pronouns text,
  p_birthday date,
  p_skills jsonb
)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
  v_char characters;
  v_name text := trim(coalesce(p_name, ''));
  v_spent integer := 0;
  v_skill jsonb;
begin
  if v_player is null then raise exception 'Not signed in'; end if;

  select * into v_char from characters where id = p_character_id and player_id = v_player;
  if not found then raise exception 'Character not found'; end if;

  if not exists (
    select 1 from character_remort_requests
    where character_id = p_character_id and status = 'approved'
  ) then
    raise exception 'This character does not have an approved remort in progress';
  end if;

  if v_name = '' then raise exception 'Character name cannot be empty'; end if;
  if length(v_name) > 60 then raise exception 'Character name is too long'; end if;

  if p_skills is not null then
    for v_skill in select * from jsonb_array_elements(p_skills) loop
      v_spent := v_spent + coalesce((v_skill ->> 'sp_cost')::integer, 0);
    end loop;
  end if;

  if v_spent > v_char.starting_sp then
    raise exception 'Chosen skills cost % SP, more than the % SP budget', v_spent, v_char.starting_sp;
  end if;

  update characters set
    name = v_name,
    pronouns = nullif(trim(coalesce(p_pronouns, '')), ''),
    birthday = p_birthday
    where id = p_character_id;

  delete from character_skills where character_id = p_character_id;

  if p_skills is not null then
    for v_skill in select * from jsonb_array_elements(p_skills) loop
      if coalesce(trim(v_skill ->> 'skill_name'), '') = '' then
        raise exception 'Every chosen skill needs a name';
      end if;
      insert into character_skills (character_id, player_id, category, skill_name, focus, level, sp_cost, total_sp_paid)
        values (
          p_character_id,
          v_player,
          coalesce(nullif(trim(v_skill ->> 'category'), ''), 'Skill'),
          trim(v_skill ->> 'skill_name'),
          nullif(v_skill ->> 'focus', ''),
          coalesce((v_skill ->> 'level')::integer, 1),
          coalesce((v_skill ->> 'sp_cost')::integer, 0),
          coalesce((v_skill ->> 'sp_cost')::integer, 0)
        );
    end loop;
  end if;
end;
$$;

create or replace function character_confirm_remort(p_character_id uuid)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
begin
  if v_player is null then raise exception 'Not signed in'; end if;

  if not exists (select 1 from characters where id = p_character_id and player_id = v_player) then
    raise exception 'Character not found';
  end if;

  update character_remort_requests
    set status = 'completed', completed_at = now()
    where character_id = p_character_id and status = 'approved';

  if not found then raise exception 'No approved remort in progress for this character'; end if;
end;
$$;

grant select on character_remort_requests to authenticated;
