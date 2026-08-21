
alter table race_notable_skills rename to race_starting_skills;
alter table race_starting_skills add column if not exists level integer not null default 1;

insert into race_starting_skills (id, race, skill_id, level) values
  (12, 'Curtainborn', 73, 5),
  (13, 'Elf', 68, 5)
on conflict (id) do nothing;

update skills set levelable = true where id in (53, 63, 69, 81);

drop function if exists character_create(text, text, text, date, jsonb);
drop function if exists character_update_remort(uuid, text, text, date, jsonb);

create or replace function fa_apply_race_starting_skills(
  p_character_id uuid,
  p_player uuid,
  p_race text,
  p_racial_focus text
)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  v_row record;
  v_skill record;
  v_focus text;
  v_grant_cost integer;
  v_existing_id uuid;
begin
  for v_row in select * from race_starting_skills where race = p_race loop
    select s.name, s.focus_type_id, st.name as type_name
      into v_skill
      from skills s
      join skill_types st on st.id = s.skill_type_id
      where s.id = v_row.skill_id;

    v_focus := case when v_skill.focus_type_id is not null
      then nullif(trim(coalesce(p_racial_focus, '')), '')
      else null end;
    if v_skill.focus_type_id is not null and v_focus is null then
      raise exception '% requires a free racial focus choice', v_skill.name;
    end if;

    select id into v_existing_id from character_skills
      where character_id = p_character_id
        and skill_name = v_skill.name
        and coalesce(focus, '') = coalesce(v_focus, '')
      limit 1;

    if found then
      v_grant_cost := coalesce(skills_true_total_cost(v_skill.name, v_focus, v_row.level, p_race), 0);
      update character_skills
        set sp_cost = greatest(0, sp_cost - v_grant_cost),
            total_sp_paid = greatest(0, total_sp_paid - v_grant_cost)
        where id = v_existing_id;
    else
      insert into character_skills (character_id, player_id, category, skill_name, focus, level, sp_cost, total_sp_paid)
        values (
          p_character_id, p_player,
          case when v_skill.type_name = 'Ability' then 'Ability' else v_skill.type_name || ' Skill' end,
          v_skill.name, v_focus, v_row.level, 0, 0
        );
    end if;
  end loop;
end;
$$;

create or replace function character_create(
  p_name text,
  p_race text,
  p_pronouns text,
  p_birthday date,
  p_skills jsonb,
  p_racial_focus text default null
)
returns uuid language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
  v_name text := trim(coalesce(p_name, ''));
  v_race text := trim(coalesce(p_race, ''));
  v_starting_sp integer;
  v_char_id uuid;
  v_skill jsonb;
  v_skill_name text;
  v_focus text;
  v_level integer;
  v_true_cost integer;
  v_limit integer;
  v_spent integer := 0;
  v_existing_count integer;
begin
  if v_player is null then raise exception 'Not signed in'; end if;

  if v_name = '' then raise exception 'Character name cannot be empty'; end if;
  if length(v_name) > 60 then raise exception 'Character name is too long'; end if;

  if v_race not in (
    'Human', 'Elf', 'Dwarf', 'Gnome', 'Curtainborn', 'Orc',
    'D''Shunn', 'Minotaur', 'Malkin', 'Goblin', 'Lizardfolk'
  ) then
    raise exception 'Unknown race: %', v_race;
  end if;

  if p_birthday is null then raise exception 'Date of birth is required'; end if;
  if p_birthday > (current_date - interval '18 years')::date then
    raise exception 'Characters must be at least 18 years old';
  end if;

  select count(*) into v_existing_count from characters where player_id = v_player;

  if v_existing_count >= 2 then
    raise exception 'You already have 2 characters. Only 2 characters are allowed per player.';
  end if;

  if v_existing_count = 0 then
    v_starting_sp := 30;
  else
    v_starting_sp := case when v_race = 'Human' then 15 else 10 end;
  end if;

  insert into characters (player_id, name, race, pronouns, birthday, starting_sp)
    values (
      v_player, v_name, v_race,
      nullif(trim(coalesce(p_pronouns, '')), ''),
      p_birthday,
      v_starting_sp
    )
    returning id into v_char_id;

  if p_skills is not null then
    for v_skill in select * from jsonb_array_elements(p_skills) loop
      v_skill_name := trim(v_skill ->> 'skill_name');
      if coalesce(v_skill_name, '') = '' then raise exception 'Every chosen skill needs a name'; end if;
      v_focus := nullif(v_skill ->> 'focus', '');
      v_level := coalesce((v_skill ->> 'level')::integer, 1);

      v_true_cost := skills_true_total_cost(v_skill_name, v_focus, v_level, v_race);
      if v_true_cost is null then
        raise exception 'Could not price skill: % %', v_skill_name, coalesce(v_focus, '');
      end if;

      v_limit := skills_level_limit(v_skill_name, v_race);
      if v_limit is not null and v_level > v_limit then
        raise exception '% cannot go above level %', v_skill_name, v_limit;
      end if;

      insert into character_skills (character_id, player_id, category, skill_name, focus, level, sp_cost, total_sp_paid)
        values (
          v_char_id,
          v_player,
          coalesce(nullif(trim(v_skill ->> 'category'), ''), 'Skill'),
          v_skill_name,
          v_focus,
          v_level,
          v_true_cost,
          v_true_cost
        );
    end loop;
  end if;

  perform fa_apply_race_starting_skills(v_char_id, v_player, v_race, p_racial_focus);

  select coalesce(sum(sp_cost), 0) into v_spent from character_skills where character_id = v_char_id;
  if v_spent > v_starting_sp then
    raise exception 'Chosen skills cost % SP, more than the % SP starting budget', v_spent, v_starting_sp;
  end if;

  return v_char_id;
end;
$$;

create or replace function character_update_remort(
  p_character_id uuid,
  p_name text,
  p_pronouns text,
  p_birthday date,
  p_skills jsonb,
  p_racial_focus text default null
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
  v_skill_name text;
  v_focus text;
  v_level integer;
  v_true_cost integer;
  v_limit integer;
  v_real_spent_sp integer;
  v_xp_balance integer;
  v_budget_sp integer;
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

  select coalesce(sum(sp_cost), 0) into v_real_spent_sp from character_skills where character_id = p_character_id;
  v_xp_balance := xp_balance(p_character_id);
  v_budget_sp := fa_convert_xp_to_sp(v_xp_balance, v_char.starting_sp, v_real_spent_sp);

  if v_name = '' then raise exception 'Character name cannot be empty'; end if;
  if length(v_name) > 60 then raise exception 'Character name is too long'; end if;

  if p_birthday is null then raise exception 'Date of birth is required'; end if;
  if p_birthday > (current_date - interval '18 years')::date then
    raise exception 'Characters must be at least 18 years old';
  end if;

  update characters set
    name = v_name,
    pronouns = nullif(trim(coalesce(p_pronouns, '')), ''),
    birthday = p_birthday
    where id = p_character_id;

  delete from character_skills where character_id = p_character_id;

  if p_skills is not null then
    for v_skill in select * from jsonb_array_elements(p_skills) loop
      v_skill_name := trim(v_skill ->> 'skill_name');
      if coalesce(v_skill_name, '') = '' then raise exception 'Every chosen skill needs a name'; end if;
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

      insert into character_skills (character_id, player_id, category, skill_name, focus, level, sp_cost, total_sp_paid)
        values (
          p_character_id,
          v_player,
          coalesce(nullif(trim(v_skill ->> 'category'), ''), 'Skill'),
          v_skill_name,
          v_focus,
          v_level,
          v_true_cost,
          v_true_cost
        );
    end loop;
  end if;

  perform fa_apply_race_starting_skills(p_character_id, v_player, v_char.race, p_racial_focus);

  select coalesce(sum(sp_cost), 0) into v_spent from character_skills where character_id = p_character_id;
  if v_spent > v_budget_sp then
    raise exception 'Chosen skills cost % SP, more than the % SP budget', v_spent, v_budget_sp;
  end if;
end;
$$;

do $$
declare
  v_char record;
  v_focus text;
begin
  for v_char in select id, player_id, race from characters loop
    if not exists (select 1 from race_starting_skills where race = v_char.race) then
      continue;
    end if;

    v_focus := null;
    if v_char.race = 'Malkin' then
      select focus into v_focus from character_skills
        where character_id = v_char.id and skill_name = 'Weapon Skill' and focus is not null
        limit 1;
    end if;

    begin
      perform fa_apply_race_starting_skills(v_char.id, v_char.player_id, v_char.race, v_focus);
    exception when others then
      raise notice 'Skipped racial backfill for character %: %', v_char.id, sqlerrm;
    end;
  end loop;
end;
$$;
