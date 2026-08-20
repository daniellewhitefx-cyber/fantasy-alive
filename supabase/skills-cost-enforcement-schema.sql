-- Re-defines character_create (characters-schema.sql) and
-- character_update_remort (remort-schema.sql) to price every submitted
-- skill from the real catalog via skills_true_total_cost/
-- skills_level_limit instead of trusting the client's claimed sp_cost
-- and level outright. A client bug (or a deliberately crafted RPC call)
-- could otherwise buy a leveled skill directly at a high level for the
-- price of a single relevel step, or push a skill's level past its
-- catalog-defined cap. Requires characters-schema.sql, remort-schema.sql,
-- and skills-cost-validation-schema.sql to already exist.

create or replace function character_create(
  p_name text,
  p_race text,
  p_pronouns text,
  p_birthday date,
  p_skills jsonb
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

  select count(*) into v_existing_count from characters where player_id = v_player;

  if v_existing_count >= 2 then
    raise exception 'You already have 2 characters. Only 2 characters are allowed per player.';
  end if;

  -- A player's very first character gets a flat 30 SP, since everyone is
  -- starting fresh on the new site rather than a brand new player at their
  -- first event. Every character after that follows the normal rulebook
  -- starting SP for their race.
  if v_existing_count = 0 then
    v_starting_sp := 30;
  else
    v_starting_sp := case when v_race = 'Human' then 15 else 10 end;
  end if;

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

      v_spent := v_spent + v_true_cost;
    end loop;
  end if;

  if v_spent > v_starting_sp then
    raise exception 'Chosen skills cost % SP, more than the % SP starting budget', v_spent, v_starting_sp;
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
      v_focus := nullif(v_skill ->> 'focus', '');
      v_level := coalesce((v_skill ->> 'level')::integer, 1);
      v_true_cost := skills_true_total_cost(v_skill_name, v_focus, v_level, v_race);

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

  return v_char_id;
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
  v_skill_name text;
  v_focus text;
  v_level integer;
  v_true_cost integer;
  v_limit integer;
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

      v_spent := v_spent + v_true_cost;
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
      v_skill_name := trim(v_skill ->> 'skill_name');
      v_focus := nullif(v_skill ->> 'focus', '');
      v_level := coalesce((v_skill ->> 'level')::integer, 1);
      v_true_cost := skills_true_total_cost(v_skill_name, v_focus, v_level, v_char.race);

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
end;
$$;
