-- "Work" tab on the Current Event log: a character spends downtime Hours
-- (the same shared budget Training draws from) using one of their known
-- Trade Skills to earn Copper, per the rulebook: "For every 8 hours of
-- time a character dedicates to using the Craftsman skill they will earn
-- 5 Copper coins per level of skill" -- and "Every trade skill may be
-- used as if it were Craftsman for the purposes of earning money."

create table if not exists event_log_working_sessions (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references auth.users(id) on delete cascade,
  character_id uuid not null references characters(id) on delete cascade,
  event_slug text not null,
  character_skill_id uuid not null references character_skills(id) on delete cascade,
  skill_name text not null,
  focus text,
  level integer not null,
  hours_worked integer not null check (hours_worked > 0 and hours_worked % 8 = 0),
  copper_earned integer not null check (copper_earned >= 0),
  created_at timestamptz not null default now()
);

create index if not exists event_log_working_sessions_char_event_idx
  on event_log_working_sessions(character_id, event_slug);

alter table event_log_working_sessions enable row level security;

drop policy if exists "Players see their own working sessions" on event_log_working_sessions;
create policy "Players see their own working sessions"
  on event_log_working_sessions for select
  using (player_id = auth.uid() or fa_is_logistics_or_admin());

-- Extends event_log_training_summary (defined in training-schema.sql) so
-- Hours Remaining reflects both Training and Working spend against the
-- same shared downtime budget.
create or replace function event_log_training_summary(p_event_slug text, p_character_id uuid)
returns jsonb language plpgsql stable security definer
set search_path = public
as $$
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

  select
    coalesce((select sum(hours_cost) from event_log_training_purchases where character_id = p_character_id and event_slug = p_event_slug), 0)
    + coalesce((select sum(hours_worked) from event_log_working_sessions where character_id = p_character_id and event_slug = p_event_slug), 0)
  into v_hours_spent;

  return jsonb_build_object('spendable_sp', v_spendable_sp, 'hours_spent', v_hours_spent);
end;
$$;

create or replace function event_log_work_for_copper(
  p_event_slug text,
  p_character_id uuid,
  p_hours_budget integer,
  p_character_skill_id uuid,
  p_hours integer
)
returns uuid language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
  v_skill character_skills%rowtype;
  v_hours_spent integer;
  v_copper integer;
  v_session_id uuid;
begin
  if v_player is null then raise exception 'Not signed in'; end if;
  if p_hours is null or p_hours <= 0 or p_hours % 8 != 0 then
    raise exception 'Hours must be a positive multiple of 8';
  end if;
  if p_hours_budget is null or p_hours_budget < 0 then raise exception 'Invalid hours budget'; end if;

  if not exists (select 1 from characters where id = p_character_id and player_id = v_player) then
    raise exception 'Character not found';
  end if;

  select * into v_skill from character_skills
    where id = p_character_skill_id and character_id = p_character_id
    for update;
  if not found then raise exception 'Skill not found'; end if;
  if v_skill.category != 'Trade Skill' then raise exception 'Only Trade Skills can be worked for Copper'; end if;

  select
    coalesce((select sum(hours_cost) from event_log_training_purchases where character_id = p_character_id and event_slug = p_event_slug), 0)
    + coalesce((select sum(hours_worked) from event_log_working_sessions where character_id = p_character_id and event_slug = p_event_slug), 0)
  into v_hours_spent;

  if v_hours_spent + p_hours > p_hours_budget then
    raise exception 'Not enough downtime hours left';
  end if;

  v_copper := (p_hours / 8) * 5 * v_skill.level;

  insert into event_log_working_sessions
    (player_id, character_id, event_slug, character_skill_id, skill_name, focus, level, hours_worked, copper_earned)
    values (v_player, p_character_id, p_event_slug, p_character_skill_id, v_skill.skill_name, v_skill.focus, v_skill.level, p_hours, v_copper)
    returning id into v_session_id;

  if v_copper > 0 then
    insert into bank_transactions (player_id, type, amount, note, created_by)
      values (v_player, 'deposit', v_copper, 'Working: ' || v_skill.skill_name || ' Lv' || v_skill.level || ' (' || p_event_slug || ')', v_player);
  end if;

  return v_session_id;
end;
$$;

create or replace function event_log_cancel_working(p_session_id uuid)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
  v_session event_log_working_sessions%rowtype;
begin
  if v_player is null then raise exception 'Not signed in'; end if;

  select * into v_session from event_log_working_sessions where id = p_session_id and player_id = v_player;
  if not found then raise exception 'Working session not found'; end if;

  delete from event_log_working_sessions where id = p_session_id;

  if v_session.copper_earned > 0 then
    insert into bank_transactions (player_id, type, amount, note, created_by)
      values (v_player, 'withdrawal', v_session.copper_earned, 'Undo working: ' || v_session.skill_name || ' (' || v_session.event_slug || ')', v_player);
  end if;
end;
$$;

grant select on event_log_working_sessions to authenticated;
