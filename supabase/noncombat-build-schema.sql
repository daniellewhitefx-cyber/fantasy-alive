alter table characters add column if not exists noncombat_build_saved_at timestamptz;

create table if not exists character_noncombat_skills (
  id uuid primary key default gen_random_uuid(),
  character_id uuid not null references characters(id) on delete cascade,
  player_id uuid not null references auth.users(id) on delete cascade,
  category text not null,
  skill_name text not null,
  focus text,
  level integer not null default 1,
  sp_cost integer not null default 0,
  total_sp_paid integer not null default 0,
  created_at timestamptz not null default now()
);

create index if not exists character_noncombat_skills_char_idx on character_noncombat_skills(character_id);

alter table character_noncombat_skills enable row level security;

drop policy if exists "Players see their own non-combat build skills" on character_noncombat_skills;
create policy "Players see their own non-combat build skills"
  on character_noncombat_skills for select
  using (
    player_id = (select auth.uid())
    or ((select auth.jwt()) -> 'app_metadata' ->> 'character_staff')::boolean is true
    or fa_is_site_admin()
  );

grant select on character_noncombat_skills to authenticated;

create or replace function character_noncombat_build_save(p_character_id uuid, p_skills jsonb)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
  v_char characters;
  v_spent integer := 0;
  v_skill jsonb;
  v_skill_name text;
  v_category text;
  v_focus text;
  v_level integer;
  v_true_cost integer;
  v_limit integer;
begin
  if v_player is null then raise exception 'Not signed in'; end if;

  select * into v_char from characters where id = p_character_id and player_id = v_player;
  if not found then raise exception 'Character not found'; end if;

  if p_skills is not null then
    for v_skill in select * from jsonb_array_elements(p_skills) loop
      v_skill_name := trim(v_skill ->> 'skill_name');
      if coalesce(v_skill_name, '') = '' then raise exception 'Every chosen skill needs a name'; end if;
      v_category := coalesce(nullif(trim(v_skill ->> 'category'), ''), 'Skill');
      if v_category in ('Combat Skill', 'Weapon Skill') then
        raise exception 'A Non-Combat Build can''t include % (%)', v_skill_name, v_category;
      end if;
      v_focus := nullif(v_skill ->> 'focus', '');
      v_level := coalesce((v_skill ->> 'level')::integer, 1);

      v_true_cost := skills_true_total_cost(v_skill_name, v_focus, v_level, v_char.race);
      if v_true_cost is null then
        raise exception 'Could not price skill: % %', v_skill_name, coalesce(v_focus, '');
      end if;

      v_limit := skills_level_limit(v_skill_name, v_char.race);
      if v_limit is not null and v_level > v_limit then
        raise exception '% cannot go above level %', v_skill_name, v_limit;
      end if;

      v_spent := v_spent + v_true_cost;
    end loop;
  end if;

  if v_spent > v_char.starting_sp then
    raise exception 'Chosen skills cost % SP, more than the % SP budget', v_spent, v_char.starting_sp;
  end if;

  delete from character_noncombat_skills where character_id = p_character_id;

  if p_skills is not null then
    for v_skill in select * from jsonb_array_elements(p_skills) loop
      v_skill_name := trim(v_skill ->> 'skill_name');
      v_category := coalesce(nullif(trim(v_skill ->> 'category'), ''), 'Skill');
      v_focus := nullif(v_skill ->> 'focus', '');
      v_level := coalesce((v_skill ->> 'level')::integer, 1);
      v_true_cost := skills_true_total_cost(v_skill_name, v_focus, v_level, v_char.race);

      insert into character_noncombat_skills (character_id, player_id, category, skill_name, focus, level, sp_cost, total_sp_paid)
        values (p_character_id, v_player, v_category, v_skill_name, v_focus, v_level, v_true_cost, v_true_cost);
    end loop;
  end if;

  update characters set noncombat_build_saved_at = now() where id = p_character_id;
end;
$$;

grant execute on function character_noncombat_build_save(uuid, jsonb) to authenticated;
