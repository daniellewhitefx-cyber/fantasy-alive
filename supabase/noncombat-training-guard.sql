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
  v_rate integer;
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
  v_rate := fa_xp_per_sp(v_starting_sp + v_spent_sp);
  v_spendable_sp := greatest(0, v_starting_sp + floor(v_xp_balance::numeric / v_rate)::integer - v_spent_sp);

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
  v_rate integer;
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
  v_rate := fa_xp_per_sp(v_starting_sp + v_spent_sp);
  v_spendable_sp := greatest(0, v_starting_sp + floor(v_xp_balance::numeric / v_rate)::integer - v_spent_sp);

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
