-- Training tab on the Current Event log: players spend downtime Hours
-- (see faTrainingHoursBudget() in js/registration-status.js for the
-- 100-hours-per-week-between-events budget) to learn brand-new skills,
-- or level up skills whose cost scales with level, for their
-- registered character. Each skill also has to fit within the
-- character's spendable Skill Points -- their starting SP plus
-- whatever SP their banked XP converts to, minus what they've already
-- spent (see faConvertXpToSp() in js/xp-convert.js for the client-side
-- mirror of this math).

-- Mirrors js/xp-convert.js's faXpPerSp(): the XP cost of the next SP
-- gets worse as a character invests more Skill Points overall.
create or replace function fa_xp_per_sp(p_invested_sp integer)
returns integer language sql immutable as $$
  select case
    when p_invested_sp <= 40 then 10
    when p_invested_sp <= 80 then 15
    when p_invested_sp <= 150 then 20
    when p_invested_sp <= 200 then 25
    else 30
  end;
$$;

create table if not exists event_log_training_purchases (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references auth.users(id) on delete cascade,
  character_id uuid not null references characters(id) on delete cascade,
  event_slug text not null,
  character_skill_id uuid not null references character_skills(id) on delete cascade,
  category text not null,
  skill_name text not null,
  focus text,
  level integer not null default 1,
  sp_cost integer not null check (sp_cost >= 0),
  hours_cost integer not null check (hours_cost >= 0),
  created_at timestamptz not null default now()
);

-- Tracks whether a purchase leveled up an existing skill rather than
-- learning a brand-new one, and what it leveled up from, so cancelling
-- it can revert the level instead of deleting the whole skill.
alter table event_log_training_purchases add column if not exists is_relevel boolean not null default false;
alter table event_log_training_purchases add column if not exists prev_level integer;
alter table event_log_training_purchases add column if not exists prev_sp_cost integer;

create index if not exists event_log_training_purchases_char_event_idx
  on event_log_training_purchases(character_id, event_slug);

alter table event_log_training_purchases enable row level security;

drop policy if exists "Players see their own training purchases" on event_log_training_purchases;
create policy "Players see their own training purchases"
  on event_log_training_purchases for select
  using (player_id = auth.uid() or fa_is_logistics_or_admin());

-- Current spendable SP and hours already spent this log, for the
-- player's own character.
create or replace function event_log_training_summary(p_event_slug text, p_character_id uuid)
returns jsonb language plpgsql stable security definer as $$
declare
  v_player uuid := auth.uid();
  v_starting_sp integer;
  v_spent_sp integer;
  v_xp_balance integer;
  v_rate integer;
  v_spendable_sp integer;
  v_hours_spent integer;
begin
  if v_player is null then raise exception 'Not signed in'; end if;

  select starting_sp into v_starting_sp from characters
    where id = p_character_id and player_id = v_player;
  if not found then raise exception 'Character not found'; end if;

  select coalesce(sum(sp_cost), 0) into v_spent_sp from character_skills where character_id = p_character_id;
  v_xp_balance := xp_balance(p_character_id);
  v_rate := fa_xp_per_sp(v_starting_sp + v_spent_sp);
  v_spendable_sp := greatest(0, v_starting_sp + floor(v_xp_balance::numeric / v_rate)::integer - v_spent_sp);

  select coalesce(sum(hours_cost), 0) into v_hours_spent
    from event_log_training_purchases
    where character_id = p_character_id and event_slug = p_event_slug;

  return jsonb_build_object('spendable_sp', v_spendable_sp, 'hours_spent', v_hours_spent);
end;
$$;

-- Learns a brand-new skill (not releveling an existing one) for the
-- player's own character, paid for with both Hours and spendable SP.
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
returns uuid language plpgsql security definer as $$
declare
  v_player uuid := auth.uid();
  v_starting_sp integer;
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
begin
  if v_player is null then raise exception 'Not signed in'; end if;
  if v_skill_name = '' then raise exception 'Skill name cannot be empty'; end if;
  if p_sp_cost is null or p_sp_cost < 0 then raise exception 'Invalid SP cost'; end if;
  if p_hours_budget is null or p_hours_budget < 0 then raise exception 'Invalid hours budget'; end if;

  select starting_sp into v_starting_sp from characters
    where id = p_character_id and player_id = v_player
    for update;
  if not found then raise exception 'Character not found'; end if;

  if exists (
    select 1 from character_skills
    where character_id = p_character_id
      and lower(skill_name) = lower(v_skill_name)
      and lower(coalesce(category, '')) = lower(v_category)
      and lower(coalesce(focus, '')) = lower(coalesce(v_focus, ''))
  ) then
    raise exception 'You already know that skill';
  end if;

  select coalesce(sum(sp_cost), 0) into v_spent_sp from character_skills where character_id = p_character_id;
  v_xp_balance := xp_balance(p_character_id);
  v_rate := fa_xp_per_sp(v_starting_sp + v_spent_sp);
  v_spendable_sp := greatest(0, v_starting_sp + floor(v_xp_balance::numeric / v_rate)::integer - v_spent_sp);

  if p_sp_cost > v_spendable_sp then
    raise exception 'Not enough spendable Skill Points';
  end if;

  v_hours_cost := p_sp_cost * 5;

  select coalesce(sum(hours_cost), 0) into v_hours_spent
    from event_log_training_purchases
    where character_id = p_character_id and event_slug = p_event_slug;

  if v_hours_spent + v_hours_cost > p_hours_budget then
    raise exception 'Not enough downtime hours left';
  end if;

  insert into character_skills (character_id, player_id, category, skill_name, focus, level, sp_cost)
    values (p_character_id, v_player, v_category, v_skill_name, v_focus, v_level, p_sp_cost)
    returning id into v_skill_id;

  insert into event_log_training_purchases
    (player_id, character_id, event_slug, character_skill_id, category, skill_name, focus, level, sp_cost, hours_cost)
    values (v_player, p_character_id, p_event_slug, v_skill_id, v_category, v_skill_name, v_focus, v_level, p_sp_cost, v_hours_cost);

  return v_skill_id;
end;
$$;

-- Levels up a skill the character already knows (skills whose cost
-- scales with level can be bought again at a higher level). Only the
-- delta between the old and new cost is charged in Hours and SP.
create or replace function event_log_relevel_skill(
  p_event_slug text,
  p_character_id uuid,
  p_hours_budget integer,
  p_character_skill_id uuid,
  p_new_level integer,
  p_new_sp_cost integer
)
returns uuid language plpgsql security definer as $$
declare
  v_player uuid := auth.uid();
  v_starting_sp integer;
  v_spent_sp integer;
  v_xp_balance integer;
  v_rate integer;
  v_spendable_sp integer;
  v_hours_spent integer;
  v_prev_level integer;
  v_prev_sp_cost integer;
  v_delta_sp integer;
  v_delta_hours integer;
  v_purchase_id uuid;
begin
  if v_player is null then raise exception 'Not signed in'; end if;
  if p_new_level is null or p_new_level < 1 then raise exception 'Invalid level'; end if;
  if p_new_sp_cost is null or p_new_sp_cost < 0 then raise exception 'Invalid SP cost'; end if;
  if p_hours_budget is null or p_hours_budget < 0 then raise exception 'Invalid hours budget'; end if;

  if not exists (select 1 from characters where id = p_character_id and player_id = v_player) then
    raise exception 'Character not found';
  end if;

  select level, sp_cost into v_prev_level, v_prev_sp_cost
    from character_skills
    where id = p_character_skill_id and character_id = p_character_id
    for update;
  if not found then raise exception 'Skill not found'; end if;

  if p_new_level <= v_prev_level then raise exception 'New level must be higher than the current level'; end if;

  v_delta_sp := p_new_sp_cost - v_prev_sp_cost;
  if v_delta_sp < 0 then raise exception 'New cost must be higher than the current cost'; end if;

  select starting_sp into v_starting_sp from characters where id = p_character_id;
  select coalesce(sum(sp_cost), 0) into v_spent_sp from character_skills where character_id = p_character_id;
  v_xp_balance := xp_balance(p_character_id);
  v_rate := fa_xp_per_sp(v_starting_sp + v_spent_sp);
  v_spendable_sp := greatest(0, v_starting_sp + floor(v_xp_balance::numeric / v_rate)::integer - v_spent_sp);

  if v_delta_sp > v_spendable_sp then
    raise exception 'Not enough spendable Skill Points';
  end if;

  v_delta_hours := v_delta_sp * 5;

  select coalesce(sum(hours_cost), 0) into v_hours_spent
    from event_log_training_purchases
    where character_id = p_character_id and event_slug = p_event_slug;

  if v_hours_spent + v_delta_hours > p_hours_budget then
    raise exception 'Not enough downtime hours left';
  end if;

  update character_skills set level = p_new_level, sp_cost = p_new_sp_cost where id = p_character_skill_id;

  insert into event_log_training_purchases
    (player_id, character_id, event_slug, character_skill_id, category, skill_name, focus, level, sp_cost, hours_cost, is_relevel, prev_level, prev_sp_cost)
  select v_player, p_character_id, p_event_slug, id, category, skill_name, focus, p_new_level, v_delta_sp, v_delta_hours, true, v_prev_level, v_prev_sp_cost
  from character_skills where id = p_character_skill_id
  returning id into v_purchase_id;

  return v_purchase_id;
end;
$$;

-- Undoes a purchase made this log. A brand-new skill is removed
-- entirely (the training purchase row cascades away with it); a
-- relevel instead reverts the skill back to its level and cost from
-- before the purchase, since the skill itself may predate this log.
create or replace function event_log_cancel_training(p_purchase_id uuid)
returns void language plpgsql security definer as $$
declare
  v_player uuid := auth.uid();
  v_char_skill_id uuid;
  v_is_relevel boolean;
  v_prev_level integer;
  v_prev_sp_cost integer;
begin
  if v_player is null then raise exception 'Not signed in'; end if;

  select character_skill_id, is_relevel, prev_level, prev_sp_cost
    into v_char_skill_id, v_is_relevel, v_prev_level, v_prev_sp_cost
    from event_log_training_purchases
    where id = p_purchase_id and player_id = v_player;
  if not found then raise exception 'Training purchase not found'; end if;

  if v_is_relevel then
    update character_skills set level = v_prev_level, sp_cost = v_prev_sp_cost where id = v_char_skill_id;
    delete from event_log_training_purchases where id = p_purchase_id;
  else
    delete from character_skills where id = v_char_skill_id;
  end if;
end;
$$;

grant select on event_log_training_purchases to authenticated;
