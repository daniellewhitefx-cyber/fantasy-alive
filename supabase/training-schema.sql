-- Training tab on the Current Event log: players spend downtime Hours
-- (see faTrainingHoursBudget() in js/registration-status.js for the
-- 100-hours-per-week-between-events budget) to learn brand-new skills
-- for their registered character. Each skill also has to fit within
-- the character's spendable Skill Points -- their starting SP plus
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

grant select on event_log_training_purchases to authenticated;
