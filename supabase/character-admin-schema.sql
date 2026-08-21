drop policy if exists "Players see their own characters" on characters;
create policy "Players see their own characters"
  on characters for select
  using (
    player_id = (select auth.uid())
    or ((select auth.jwt()) -> 'app_metadata' ->> 'remort_staff')::boolean is true
    or ((select auth.jwt()) -> 'app_metadata' ->> 'character_staff')::boolean is true
    or fa_is_site_admin()
  );

drop policy if exists "Players see their own character skills" on character_skills;
create policy "Players see their own character skills"
  on character_skills for select
  using (
    player_id = (select auth.uid())
    or ((select auth.jwt()) -> 'app_metadata' ->> 'character_staff')::boolean is true
    or fa_is_site_admin()
  );

drop function if exists character_staff_update_details(uuid, text, text, text, date);

create or replace function character_staff_update_details(
  p_character_id uuid,
  p_name text,
  p_race text,
  p_pronouns text,
  p_birthday date,
  p_social_class text
)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  v_name text := trim(coalesce(p_name, ''));
  v_race text := trim(coalesce(p_race, ''));
  v_social_class text := trim(coalesce(p_social_class, ''));
begin
  if not (coalesce((auth.jwt() -> 'app_metadata' ->> 'character_staff')::boolean, false) or fa_is_site_admin()) then
    raise exception 'Staff only';
  end if;

  if v_name = '' then raise exception 'Character name cannot be empty'; end if;
  if length(v_name) > 60 then raise exception 'Character name is too long'; end if;

  if v_race not in (
    'Human', 'Elf', 'Dwarf', 'Gnome', 'Curtainborn', 'Orc',
    'D''Shunn', 'Minotaur', 'Malkin', 'Goblin', 'Lizardfolk'
  ) then
    raise exception 'Unknown race: %', v_race;
  end if;

  if v_social_class = '' then raise exception 'Social class cannot be empty'; end if;
  if length(v_social_class) > 40 then raise exception 'Social class is too long'; end if;

  update characters set
    name = v_name,
    race = v_race,
    pronouns = nullif(trim(coalesce(p_pronouns, '')), ''),
    birthday = p_birthday,
    social_class = v_social_class
    where id = p_character_id;

  if not found then raise exception 'Character not found'; end if;
end;
$$;

create or replace function character_staff_set_starting_sp(p_character_id uuid, p_new_sp integer)
returns void language plpgsql security definer
set search_path = public
as $$
begin
  if not (coalesce((auth.jwt() -> 'app_metadata' ->> 'character_staff')::boolean, false) or fa_is_site_admin()) then
    raise exception 'Staff only';
  end if;
  if p_new_sp is null or p_new_sp < 0 then raise exception 'Starting SP must be zero or more'; end if;

  update characters set starting_sp = p_new_sp where id = p_character_id;
  if not found then raise exception 'Character not found'; end if;
end;
$$;

create or replace function character_staff_add_skill(
  p_character_id uuid,
  p_category text,
  p_skill_name text,
  p_focus text,
  p_level integer,
  p_sp_cost integer
)
returns uuid language plpgsql security definer
set search_path = public
as $$
declare
  v_owner uuid;
  v_skill_id uuid;
  v_focus text := nullif(p_focus, '');
  v_level integer := greatest(1, coalesce(p_level, 1));
  v_sp_cost integer := greatest(0, coalesce(p_sp_cost, 0));
begin
  if not (coalesce((auth.jwt() -> 'app_metadata' ->> 'character_staff')::boolean, false) or fa_is_site_admin()) then
    raise exception 'Staff only';
  end if;
  if coalesce(trim(p_skill_name), '') = '' then raise exception 'Skill name cannot be empty'; end if;

  select player_id into v_owner from characters where id = p_character_id;
  if v_owner is null then raise exception 'Character not found'; end if;

  select id into v_skill_id
    from character_skills
    where character_id = p_character_id
      and skill_name = trim(p_skill_name)
      and focus is not distinct from v_focus;

  if v_skill_id is not null then
    update character_skills set
      level = v_level,
      sp_cost = v_sp_cost,
      total_sp_paid = total_sp_paid + v_sp_cost
    where id = v_skill_id;
  else
    insert into character_skills (character_id, player_id, category, skill_name, focus, level, sp_cost, total_sp_paid)
      values (
        p_character_id,
        v_owner,
        coalesce(nullif(trim(p_category), ''), 'Skill'),
        trim(p_skill_name),
        v_focus,
        v_level,
        v_sp_cost,
        v_sp_cost
      )
      returning id into v_skill_id;
  end if;

  return v_skill_id;
end;
$$;

create or replace function character_staff_remove_skill(p_skill_id uuid)
returns void language plpgsql security definer
set search_path = public
as $$
begin
  if not (coalesce((auth.jwt() -> 'app_metadata' ->> 'character_staff')::boolean, false) or fa_is_site_admin()) then
    raise exception 'Staff only';
  end if;

  delete from character_skills where id = p_skill_id;
  if not found then raise exception 'Skill not found'; end if;
end;
$$;

create table if not exists xp_transactions (
  id uuid primary key default gen_random_uuid(),
  character_id uuid not null references characters(id) on delete cascade,
  player_id uuid not null references auth.users(id) on delete cascade,
  amount integer not null,
  note text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists xp_transactions_character_idx on xp_transactions(character_id, created_at desc);

alter table xp_transactions enable row level security;

drop policy if exists "Players and staff see XP transactions" on xp_transactions;
create policy "Players and staff see XP transactions"
  on xp_transactions for select
  using (
    player_id = (select auth.uid())
    or ((select auth.jwt()) -> 'app_metadata' ->> 'character_staff')::boolean is true
    or fa_is_site_admin()
  );

create table if not exists oc_transactions (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references auth.users(id) on delete cascade,
  amount integer not null,
  note text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists oc_transactions_player_idx on oc_transactions(player_id, created_at desc);

alter table oc_transactions enable row level security;

drop policy if exists "Players and staff see OC transactions" on oc_transactions;
create policy "Players and staff see OC transactions"
  on oc_transactions for select
  using (
    player_id = (select auth.uid())
    or ((select auth.jwt()) -> 'app_metadata' ->> 'character_staff')::boolean is true
    or fa_is_site_admin()
  );

create or replace function xp_balance(p_character uuid)
returns integer language sql stable security definer
set search_path = public
as $$
  select coalesce(sum(amount), 0)::integer from xp_transactions where character_id = p_character;
$$;

revoke execute on function xp_balance(uuid) from public, authenticated, anon;

create or replace function xp_my_character_balance(p_character_id uuid)
returns integer language plpgsql stable security definer
set search_path = public
as $$
begin
  if not exists (select 1 from characters where id = p_character_id and player_id = auth.uid()) then
    raise exception 'Character not found';
  end if;
  return xp_balance(p_character_id);
end;
$$;

create or replace function character_staff_xp_balance(p_character_id uuid)
returns integer language plpgsql stable security definer
set search_path = public
as $$
begin
  if not (coalesce((auth.jwt() -> 'app_metadata' ->> 'character_staff')::boolean, false) or fa_is_site_admin()) then
    raise exception 'Staff only';
  end if;
  return xp_balance(p_character_id);
end;
$$;

create or replace function character_staff_adjust_xp(p_character_id uuid, p_amount integer, p_note text)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  v_owner uuid;
  v_staff uuid := auth.uid();
begin
  if not (coalesce((auth.jwt() -> 'app_metadata' ->> 'character_staff')::boolean, false) or fa_is_site_admin()) then
    raise exception 'Staff only';
  end if;
  if p_amount is null or p_amount = 0 then raise exception 'Amount cannot be zero'; end if;

  select player_id into v_owner from characters where id = p_character_id;
  if v_owner is null then raise exception 'Character not found'; end if;

  insert into xp_transactions (character_id, player_id, amount, note, created_by)
    values (p_character_id, v_owner, p_amount, p_note, v_staff);
end;
$$;

create or replace function oc_balance(p_player uuid)
returns integer language sql stable security definer
set search_path = public
as $$
  select coalesce(sum(amount), 0)::integer from oc_transactions where player_id = p_player;
$$;

revoke execute on function oc_balance(uuid) from public, authenticated, anon;

create or replace function oc_my_balance()
returns integer language sql stable security definer
set search_path = public
as $$
  select oc_balance(auth.uid());
$$;

create or replace function character_staff_oc_balance(p_player uuid)
returns integer language plpgsql stable security definer
set search_path = public
as $$
begin
  if not (coalesce((auth.jwt() -> 'app_metadata' ->> 'character_staff')::boolean, false) or fa_is_site_admin()) then
    raise exception 'Staff only';
  end if;
  return oc_balance(p_player);
end;
$$;

create or replace function character_staff_adjust_oc(p_player_id uuid, p_amount integer, p_note text)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  v_staff uuid := auth.uid();
begin
  if not (coalesce((auth.jwt() -> 'app_metadata' ->> 'character_staff')::boolean, false) or fa_is_site_admin()) then
    raise exception 'Staff only';
  end if;
  if p_amount is null or p_amount = 0 then raise exception 'Amount cannot be zero'; end if;
  if not exists (select 1 from auth.users where id = p_player_id) then
    raise exception 'Player not found';
  end if;

  insert into oc_transactions (player_id, amount, note, created_by)
    values (p_player_id, p_amount, p_note, v_staff);
end;
$$;

grant select on xp_transactions to authenticated;
grant select on oc_transactions to authenticated;
