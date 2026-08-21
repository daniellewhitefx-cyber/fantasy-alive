
create table if not exists character_status_effects (
  id uuid primary key default gen_random_uuid(),
  character_id uuid not null references characters(id) on delete cascade,
  player_id uuid not null references auth.users(id) on delete cascade,
  stat_name text not null,
  delta integer not null,
  description text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists character_status_effects_char_idx on character_status_effects(character_id, stat_name, created_at desc);

alter table character_status_effects enable row level security;

drop policy if exists "Players and staff see character status effects" on character_status_effects;
create policy "Players and staff see character status effects"
  on character_status_effects for select
  using (
    player_id = auth.uid()
    or (auth.jwt() -> 'app_metadata' ->> 'character_staff')::boolean is true
    or fa_is_site_admin()
  );

grant select on character_status_effects to authenticated;

create or replace function character_status_effect_totals(p_character_id uuid)
returns table(stat_name text, total integer) language sql stable security definer
set search_path = public
as $$
  select stat_name, sum(delta)::integer as total
    from character_status_effects
    where character_id = p_character_id
    group by stat_name
    order by stat_name;
$$;

revoke execute on function character_status_effect_totals(uuid) from public, authenticated, anon;

create or replace function character_my_status_effects(p_character_id uuid)
returns table(stat_name text, total integer) language plpgsql stable security definer
set search_path = public
as $$
begin
  if not exists (select 1 from characters where id = p_character_id and player_id = auth.uid()) then
    raise exception 'Character not found';
  end if;
  return query select * from character_status_effect_totals(p_character_id);
end;
$$;

create or replace function character_staff_status_effects(p_character_id uuid)
returns table(stat_name text, total integer) language plpgsql stable security definer
set search_path = public
as $$
begin
  if not (coalesce((auth.jwt() -> 'app_metadata' ->> 'character_staff')::boolean, false) or fa_is_site_admin()) then
    raise exception 'Staff only';
  end if;
  return query select * from character_status_effect_totals(p_character_id);
end;
$$;

create or replace function character_staff_add_status_effect(
  p_character_id uuid,
  p_stat_name text,
  p_delta integer,
  p_description text
)
returns uuid language plpgsql security definer
set search_path = public
as $$
declare
  v_owner uuid;
  v_staff uuid := auth.uid();
  v_stat_name text := trim(coalesce(p_stat_name, ''));
  v_id uuid;
begin
  if not (coalesce((auth.jwt() -> 'app_metadata' ->> 'character_staff')::boolean, false) or fa_is_site_admin()) then
    raise exception 'Staff only';
  end if;
  if v_stat_name = '' then raise exception 'Stat name cannot be empty'; end if;
  if p_delta is null or p_delta = 0 then raise exception 'Amount cannot be zero'; end if;

  select player_id into v_owner from characters where id = p_character_id;
  if v_owner is null then raise exception 'Character not found'; end if;

  insert into character_status_effects (character_id, player_id, stat_name, delta, description, created_by)
    values (p_character_id, v_owner, v_stat_name, p_delta, nullif(trim(coalesce(p_description, '')), ''), v_staff)
    returning id into v_id;

  return v_id;
end;
$$;
