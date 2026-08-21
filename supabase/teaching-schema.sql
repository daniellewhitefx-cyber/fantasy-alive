
create table if not exists character_teach_requests (
  id uuid primary key default gen_random_uuid(),
  event_slug text not null,
  student_player_id uuid not null references auth.users(id) on delete cascade,
  student_character_id uuid not null references characters(id) on delete cascade,
  teacher_player_id uuid not null references auth.users(id) on delete cascade,
  teacher_character_id uuid not null references characters(id) on delete cascade,
  teacher_character_skill_id uuid not null references character_skills(id) on delete cascade,
  category text not null,
  skill_name text not null,
  focus text,
  level integer not null,
  status text not null default 'pending' check (status in ('pending', 'approved', 'declined', 'cancelled')),
  requested_at timestamptz not null default now(),
  decided_at timestamptz
);

create index if not exists character_teach_requests_student_idx
  on character_teach_requests(student_character_id, event_slug);
create index if not exists character_teach_requests_teacher_idx
  on character_teach_requests(teacher_player_id, status);

alter table character_teach_requests enable row level security;
drop policy if exists "Students and teachers see their own teach requests" on character_teach_requests;
create policy "Students and teachers see their own teach requests"
  on character_teach_requests for select
  using (student_player_id = (select auth.uid()) or teacher_player_id = (select auth.uid()) or fa_is_logistics_or_admin());

grant select on character_teach_requests to authenticated;

create or replace function teachable_skills_directory()
returns table(
  character_skill_id uuid,
  character_id uuid,
  character_name text,
  player_id uuid,
  player_name text,
  category text,
  skill_name text,
  focus text,
  level integer
)
language sql stable security definer
set search_path = public
as $$
  select cs.id, c.id, c.name, c.player_id, coalesce(p.display_name, 'Unknown player'),
    cs.category, cs.skill_name, cs.focus, cs.level
  from character_skills cs
  join characters c on c.id = cs.character_id
  left join profiles p on p.id = c.player_id
  where cs.teachable = true and c.player_id != auth.uid()
  order by cs.skill_name, cs.focus;
$$;

grant execute on function teachable_skills_directory() to authenticated;

create or replace function teach_request_create(
  p_event_slug text,
  p_student_character_id uuid,
  p_teacher_character_skill_id uuid
)
returns uuid language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
  v_teacher_skill character_skills%rowtype;
  v_request_id uuid;
begin
  if v_player is null then raise exception 'Not signed in'; end if;
  if p_event_slug is null or trim(p_event_slug) = '' then raise exception 'Event is required'; end if;

  if not exists (select 1 from characters where id = p_student_character_id and player_id = v_player) then
    raise exception 'Character not found';
  end if;

  select * into v_teacher_skill from character_skills where id = p_teacher_character_skill_id;
  if not found then raise exception 'Teacher skill not found'; end if;
  if not v_teacher_skill.teachable then raise exception 'That skill is not marked teachable'; end if;
  if v_teacher_skill.character_id = p_student_character_id then
    raise exception 'Cannot request to learn from your own character';
  end if;

  if exists (
    select 1 from character_teach_requests
    where student_character_id = p_student_character_id
      and teacher_character_skill_id = p_teacher_character_skill_id
      and event_slug = p_event_slug
      and status in ('pending', 'approved')
  ) then
    raise exception 'You already have a request for this skill this event';
  end if;

  insert into character_teach_requests
    (event_slug, student_player_id, student_character_id, teacher_player_id, teacher_character_id,
     teacher_character_skill_id, category, skill_name, focus, level)
    values (p_event_slug, v_player, p_student_character_id, v_teacher_skill.player_id, v_teacher_skill.character_id,
      p_teacher_character_skill_id, v_teacher_skill.category, v_teacher_skill.skill_name, v_teacher_skill.focus, v_teacher_skill.level)
    returning id into v_request_id;

  return v_request_id;
end;
$$;

create or replace function teach_request_approve(p_id uuid)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
begin
  if v_player is null then raise exception 'Not signed in'; end if;

  update character_teach_requests
    set status = 'approved', decided_at = now()
    where id = p_id and teacher_player_id = v_player and status = 'pending';
  if not found then raise exception 'Request not found'; end if;
end;
$$;

create or replace function teach_request_decline(p_id uuid)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
begin
  if v_player is null then raise exception 'Not signed in'; end if;

  update character_teach_requests
    set status = 'declined', decided_at = now()
    where id = p_id and teacher_player_id = v_player and status = 'pending';
  if not found then raise exception 'Request not found'; end if;
end;
$$;

create or replace function teach_request_cancel(p_id uuid)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
begin
  if v_player is null then raise exception 'Not signed in'; end if;

  update character_teach_requests
    set status = 'cancelled', decided_at = now()
    where id = p_id and student_player_id = v_player and status = 'pending';
  if not found then raise exception 'Request not found'; end if;
end;
$$;

create or replace function fa_has_approved_teacher(
  p_student_character_id uuid, p_event_slug text, p_category text, p_skill_name text, p_focus text
)
returns boolean language sql stable security definer
set search_path = public
as $$
  select exists (
    select 1 from character_teach_requests
    where student_character_id = p_student_character_id
      and event_slug = p_event_slug
      and status = 'approved'
      and lower(category) = lower(p_category)
      and lower(skill_name) = lower(p_skill_name)
      and lower(coalesce(focus, '')) = lower(coalesce(p_focus, ''))
  );
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
begin
  if v_player is null then raise exception 'Not signed in'; end if;
  if p_new_level is null or p_new_level < 1 then raise exception 'Invalid level'; end if;
  if p_new_sp_cost is null or p_new_sp_cost < 0 then raise exception 'Invalid SP cost'; end if;
  if p_hours_budget is null or p_hours_budget < 0 then raise exception 'Invalid hours budget'; end if;

  if not exists (select 1 from characters where id = p_character_id and player_id = v_player) then
    raise exception 'Character not found';
  end if;

  select level, sp_cost, category, skill_name, focus
    into v_prev_level, v_prev_sp_cost, v_category, v_skill_name, v_focus
    from character_skills
    where id = p_character_skill_id and character_id = p_character_id
    for update;
  if not found then raise exception 'Skill not found'; end if;

  if p_new_level <= v_prev_level then raise exception 'New level must be higher than the current level'; end if;

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
