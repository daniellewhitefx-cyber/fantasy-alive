
create table if not exists event_log_other_tasks (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references auth.users(id) on delete cascade,
  character_id uuid not null references characters(id) on delete cascade,
  event_slug text not null,
  description text not null,
  hours integer not null check (hours > 0),
  actioned boolean not null default false,
  actioned_by uuid references auth.users(id) on delete set null,
  actioned_at timestamptz,
  created_at timestamptz not null default now()
);

create index if not exists event_log_other_tasks_char_event_idx on event_log_other_tasks(character_id, event_slug);
create index if not exists event_log_other_tasks_pending_idx on event_log_other_tasks(created_at) where not actioned;

alter table event_log_other_tasks enable row level security;

drop policy if exists "Players and staff see other task log" on event_log_other_tasks;
create policy "Players and staff see other task log"
  on event_log_other_tasks for select
  using (player_id = auth.uid() or fa_is_logistics_or_admin());

grant select on event_log_other_tasks to authenticated;

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

  select coalesce(sum(total_sp_paid), 0) into v_spent_sp from character_skills where character_id = p_character_id;
  v_xp_balance := xp_balance(p_character_id);
  v_rate := fa_xp_per_sp(v_starting_sp + v_spent_sp);
  v_spendable_sp := greatest(0, v_starting_sp + floor(v_xp_balance::numeric / v_rate)::integer - v_spent_sp);

  select
    coalesce((select sum(hours_cost) from event_log_training_purchases where character_id = p_character_id and event_slug = p_event_slug), 0)
    + coalesce((select sum(hours_worked) from event_log_working_sessions where character_id = p_character_id and event_slug = p_event_slug), 0)
    + coalesce((select sum(hours_spent) from crafting_log where character_id = p_character_id and event_slug = p_event_slug), 0)
    + coalesce((select sum(hours) from event_log_shopping_trips where character_id = p_character_id and event_slug = p_event_slug), 0)
    + coalesce((select sum(hours) from event_log_other_tasks where character_id = p_character_id and event_slug = p_event_slug), 0)
  into v_hours_spent;

  return jsonb_build_object('spendable_sp', v_spendable_sp, 'hours_spent', v_hours_spent);
end;
$$;

create or replace function event_log_log_other_task(
  p_event_slug text,
  p_character_id uuid,
  p_description text,
  p_hours integer,
  p_hours_budget integer
)
returns uuid language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
  v_hours_spent integer;
  v_id uuid;
  v_description text := trim(coalesce(p_description, ''));
begin
  if v_player is null then raise exception 'Not signed in'; end if;
  if v_description = '' then raise exception 'Description is required'; end if;
  if p_hours is null or p_hours <= 0 then raise exception 'Hours must be positive'; end if;
  if p_hours_budget is null or p_hours_budget < 0 then raise exception 'Invalid hours budget'; end if;

  if not exists (select 1 from characters where id = p_character_id and player_id = v_player) then
    raise exception 'Character not found';
  end if;

  select coalesce((event_log_training_summary(p_event_slug, p_character_id) ->> 'hours_spent')::integer, 0)
    into v_hours_spent;

  if v_hours_spent + p_hours > p_hours_budget then
    raise exception 'Not enough downtime hours left';
  end if;

  insert into event_log_other_tasks (player_id, character_id, event_slug, description, hours)
    values (v_player, p_character_id, p_event_slug, v_description, p_hours)
    returning id into v_id;

  return v_id;
end;
$$;

create or replace function event_log_cancel_other_task(p_id uuid)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
begin
  if v_player is null then raise exception 'Not signed in'; end if;

  if not exists (select 1 from event_log_other_tasks where id = p_id and player_id = v_player) then
    raise exception 'Entry not found';
  end if;

  delete from event_log_other_tasks where id = p_id;
end;
$$;

create or replace function event_log_mark_other_task_actioned(p_id uuid)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  v_staff uuid := auth.uid();
begin
  if not fa_is_logistics_or_admin() then raise exception 'Staff only'; end if;

  update event_log_other_tasks
    set actioned = true, actioned_by = v_staff, actioned_at = now()
    where id = p_id and actioned = false;

  if not found then raise exception 'Entry not found or already actioned'; end if;
end;
$$;
