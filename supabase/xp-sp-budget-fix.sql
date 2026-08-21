create or replace function fa_convert_xp_to_sp(p_xp_balance integer, p_starting_sp integer, p_spent_sp integer)
returns integer language plpgsql immutable
set search_path = public
as $$
declare
  v_current_sp integer := p_spent_sp;
  v_remaining_xp integer := p_xp_balance;
  v_xp_converted_sp integer := 0;
  v_tier record;
  v_capacity_sp integer;
  v_affordable_sp integer;
  v_sp_this_tier integer;
begin
  for v_tier in
    select * from (values
      (40, 10),
      (80, 15),
      (150, 20),
      (200, 25),
      (2147483647, 30)
    ) as t(ceiling, rate)
  loop
    exit when v_remaining_xp <= 0;
    continue when v_current_sp >= v_tier.ceiling;
    v_capacity_sp := v_tier.ceiling - v_current_sp;
    v_affordable_sp := floor(v_remaining_xp::numeric / v_tier.rate)::integer;
    v_sp_this_tier := least(v_capacity_sp, v_affordable_sp);
    v_xp_converted_sp := v_xp_converted_sp + v_sp_this_tier;
    v_current_sp := v_current_sp + v_sp_this_tier;
    v_remaining_xp := v_remaining_xp - v_sp_this_tier * v_tier.rate;
  end loop;

  return p_starting_sp + v_xp_converted_sp;
end;
$$;

create or replace function event_log_training_summary(p_event_slug text, p_character_id uuid)
returns jsonb language plpgsql stable security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
  v_starting_sp integer;
  v_spent_sp integer;
  v_xp_balance integer;
  v_spendable_sp integer;
  v_hours_spent integer;
  v_hours_adjustment integer;
begin
  if v_player is null then raise exception 'Not signed in'; end if;

  select starting_sp into v_starting_sp from characters
    where id = p_character_id and player_id = v_player;
  if not found then raise exception 'Character not found'; end if;

  select coalesce(sum(total_sp_paid), 0) into v_spent_sp from character_skills where character_id = p_character_id;
  v_xp_balance := xp_balance(p_character_id);
  v_spendable_sp := greatest(0, fa_convert_xp_to_sp(v_xp_balance, v_starting_sp, v_spent_sp) - v_spent_sp);

  select
    coalesce((select sum(hours_cost) from event_log_training_purchases where character_id = p_character_id and event_slug = p_event_slug), 0)
    + coalesce((select sum(hours_worked) from event_log_working_sessions where character_id = p_character_id and event_slug = p_event_slug), 0)
    + coalesce((select sum(hours_spent) from crafting_log where character_id = p_character_id and event_slug = p_event_slug), 0)
    + coalesce((select sum(hours) from event_log_shopping_trips where character_id = p_character_id and event_slug = p_event_slug), 0)
    + coalesce((select sum(hours) from event_log_other_tasks where character_id = p_character_id and event_slug = p_event_slug), 0)
  into v_hours_spent;

  select coalesce(sum(hours_delta), 0) into v_hours_adjustment
    from event_log_hours_adjustments
    where event_slug = p_event_slug and (character_id = p_character_id or character_id is null);

  return jsonb_build_object('spendable_sp', v_spendable_sp, 'hours_spent', v_hours_spent, 'hours_adjustment', v_hours_adjustment);
end;
$$;

create or replace function event_log_train_skill(
  p_event_slug text,
  p_character_id uuid,
  p_hours_budget integer,
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
  v_player uuid := auth.uid();
  v_starting_sp integer;
  v_race text;
  v_spent_sp integer;
  v_xp_balance integer;
  v_spendable_sp integer;
  v_hours_spent integer;
  v_hours_cost integer;
  v_skill_name text := trim(coalesce(p_skill_name, ''));
  v_category text := coalesce(nullif(trim(p_category), ''), 'Skill');
  v_focus text := nullif(p_focus, '');
  v_level integer := greatest(1, coalesce(p_level, 1));
  v_skill_id uuid;
  v_taught boolean;
  v_limit integer;
begin
  if v_player is null then raise exception 'Not signed in'; end if;
  if v_skill_name = '' then raise exception 'Skill name cannot be empty'; end if;
  if p_sp_cost is null or p_sp_cost < 0 then raise exception 'Invalid SP cost'; end if;
  if p_hours_budget is null or p_hours_budget < 0 then raise exception 'Invalid hours budget'; end if;

  select starting_sp, race into v_starting_sp, v_race from characters
    where id = p_character_id and player_id = v_player
    for update;
  if not found then raise exception 'Character not found'; end if;

  if v_category in ('Combat Skill', 'Weapon Skill') and exists (
    select 1 from registrations
    where event_slug = p_event_slug and character_id = p_character_id and combat_status = 'Non-Combat'
  ) then
    raise exception 'This character is registered Non-Combat for this event, so Combat and Weapon skills can''t be trained';
  end if;

  v_limit := skills_level_limit(v_skill_name, v_race);
  if v_limit is not null and v_level > v_limit then
    raise exception '% cannot go above level %', v_skill_name, v_limit;
  end if;

  if exists (
    select 1 from character_skills
    where character_id = p_character_id
      and lower(skill_name) = lower(v_skill_name)
      and lower(coalesce(category, '')) = lower(v_category)
      and lower(coalesce(focus, '')) = lower(coalesce(v_focus, ''))
  ) then
    raise exception 'You already know that skill';
  end if;

  select coalesce(sum(total_sp_paid), 0) into v_spent_sp from character_skills where character_id = p_character_id;
  v_xp_balance := xp_balance(p_character_id);
  v_spendable_sp := greatest(0, fa_convert_xp_to_sp(v_xp_balance, v_starting_sp, v_spent_sp) - v_spent_sp);

  if p_sp_cost > v_spendable_sp then
    raise exception 'Not enough spendable Skill Points';
  end if;

  v_taught := fa_has_approved_teacher(p_character_id, p_event_slug, v_category, v_skill_name, v_focus);
  v_hours_cost := case when v_taught then ceil(p_sp_cost * 2.5)::integer else p_sp_cost * 5 end;

  select coalesce(sum(hours_cost), 0) into v_hours_spent
    from event_log_training_purchases
    where character_id = p_character_id and event_slug = p_event_slug;

  if v_hours_spent + v_hours_cost > p_hours_budget then
    raise exception 'Not enough downtime hours left';
  end if;

  insert into character_skills (character_id, player_id, category, skill_name, focus, level, sp_cost, total_sp_paid)
    values (p_character_id, v_player, v_category, v_skill_name, v_focus, v_level, p_sp_cost, p_sp_cost)
    returning id into v_skill_id;

  insert into event_log_training_purchases
    (player_id, character_id, event_slug, character_skill_id, category, skill_name, focus, level, sp_cost, hours_cost)
    values (v_player, p_character_id, p_event_slug, v_skill_id, v_category, v_skill_name, v_focus, v_level, p_sp_cost, v_hours_cost);

  return v_skill_id;
end;
$$;

create or replace function event_log_relevel_skill(
  p_event_slug text,
  p_character_id uuid,
  p_hours_budget integer,
  p_character_skill_id uuid,
  p_new_level integer,
  p_new_sp_cost integer
)
returns uuid language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
  v_starting_sp integer;
  v_race text;
  v_spent_sp integer;
  v_xp_balance integer;
  v_spendable_sp integer;
  v_hours_spent integer;
  v_prev_level integer;
  v_prev_sp_cost integer;
  v_category text;
  v_skill_name text;
  v_focus text;
  v_hours_cost integer;
  v_purchase_id uuid;
  v_taught boolean;
  v_limit integer;
begin
  if v_player is null then raise exception 'Not signed in'; end if;
  if p_new_level is null or p_new_level < 1 then raise exception 'Invalid level'; end if;
  if p_new_sp_cost is null or p_new_sp_cost < 0 then raise exception 'Invalid SP cost'; end if;
  if p_hours_budget is null or p_hours_budget < 0 then raise exception 'Invalid hours budget'; end if;

  select race into v_race from characters where id = p_character_id and player_id = v_player;
  if not found then raise exception 'Character not found'; end if;

  select level, sp_cost, category, skill_name, focus
    into v_prev_level, v_prev_sp_cost, v_category, v_skill_name, v_focus
    from character_skills
    where id = p_character_skill_id and character_id = p_character_id
    for update;
  if not found then raise exception 'Skill not found'; end if;

  if v_category in ('Combat Skill', 'Weapon Skill') and exists (
    select 1 from registrations
    where event_slug = p_event_slug and character_id = p_character_id and combat_status = 'Non-Combat'
  ) then
    raise exception 'This character is registered Non-Combat for this event, so Combat and Weapon skills can''t be trained';
  end if;

  if p_new_level <= v_prev_level then raise exception 'New level must be higher than the current level'; end if;

  v_limit := skills_level_limit(v_skill_name, v_race);
  if v_limit is not null and p_new_level > v_limit then
    raise exception '% cannot go above level %', v_skill_name, v_limit;
  end if;

  select starting_sp into v_starting_sp from characters where id = p_character_id;
  select coalesce(sum(total_sp_paid), 0) into v_spent_sp from character_skills where character_id = p_character_id;
  v_xp_balance := xp_balance(p_character_id);
  v_spendable_sp := greatest(0, fa_convert_xp_to_sp(v_xp_balance, v_starting_sp, v_spent_sp) - v_spent_sp);

  if p_new_sp_cost > v_spendable_sp then
    raise exception 'Not enough spendable Skill Points';
  end if;

  v_taught := fa_has_approved_teacher(p_character_id, p_event_slug, v_category, v_skill_name, v_focus);
  v_hours_cost := case when v_taught then ceil(p_new_sp_cost * 2.5)::integer else p_new_sp_cost * 5 end;

  select coalesce(sum(hours_cost), 0) into v_hours_spent
    from event_log_training_purchases
    where character_id = p_character_id and event_slug = p_event_slug;

  if v_hours_spent + v_hours_cost > p_hours_budget then
    raise exception 'Not enough downtime hours left';
  end if;

  update character_skills
    set level = p_new_level, sp_cost = p_new_sp_cost, total_sp_paid = total_sp_paid + p_new_sp_cost
    where id = p_character_skill_id;

  insert into event_log_training_purchases
    (player_id, character_id, event_slug, character_skill_id, category, skill_name, focus, level, sp_cost, hours_cost, is_relevel, prev_level, prev_sp_cost)
  select v_player, p_character_id, p_event_slug, id, category, skill_name, focus, p_new_level, p_new_sp_cost, v_hours_cost, true, v_prev_level, v_prev_sp_cost
  from character_skills where id = p_character_skill_id
  returning id into v_purchase_id;

  return v_purchase_id;
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

  if v_spent > v_budget_sp then
    raise exception 'Chosen skills cost % SP, more than the % SP budget', v_spent, v_budget_sp;
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
