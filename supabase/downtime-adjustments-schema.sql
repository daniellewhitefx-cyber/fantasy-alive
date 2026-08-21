
create table if not exists event_log_hours_adjustments (
  id uuid primary key default gen_random_uuid(),
  event_slug text not null,
  character_id uuid references characters(id) on delete cascade,
  hours_delta integer not null check (hours_delta != 0),
  note text,
  created_by uuid not null references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists event_log_hours_adjustments_event_idx
  on event_log_hours_adjustments(event_slug, character_id);

alter table event_log_hours_adjustments enable row level security;
drop policy if exists "Players see adjustments that affect them, staff see all" on event_log_hours_adjustments;
create policy "Players see adjustments that affect them, staff see all"
  on event_log_hours_adjustments for select
  using (
    character_id is null
    or exists (select 1 from characters c where c.id = character_id and c.player_id = (select auth.uid()))
    or fa_is_logistics_or_admin()
  );

grant select on event_log_hours_adjustments to authenticated;

create or replace function event_log_admin_adjust_hours(
  p_event_slug text,
  p_character_id uuid,
  p_hours_delta integer,
  p_note text
)
returns uuid language plpgsql security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not fa_is_logistics_or_admin() then raise exception 'Staff only'; end if;
  if p_event_slug is null or trim(p_event_slug) = '' then raise exception 'Event is required'; end if;
  if p_hours_delta is null or p_hours_delta = 0 then raise exception 'Hours delta cannot be zero'; end if;
  if p_character_id is not null and not exists (select 1 from characters where id = p_character_id) then
    raise exception 'Character not found';
  end if;

  insert into event_log_hours_adjustments (event_slug, character_id, hours_delta, note, created_by)
    values (p_event_slug, p_character_id, p_hours_delta, nullif(trim(coalesce(p_note, '')), ''), auth.uid())
    returning id into v_id;

  return v_id;
end;
$$;

create or replace function event_log_admin_remove_hours_adjustment(p_id uuid)
returns void language plpgsql security definer
set search_path = public
as $$
begin
  if not fa_is_logistics_or_admin() then raise exception 'Staff only'; end if;

  delete from event_log_hours_adjustments where id = p_id;
  if not found then raise exception 'Adjustment not found'; end if;
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
