
create table if not exists event_log_oc_skill_purchases (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references auth.users(id) on delete cascade,
  character_id uuid not null references characters(id) on delete cascade,
  event_slug text not null,
  character_skill_id uuid not null references character_skills(id) on delete cascade,
  category text not null,
  skill_name text not null,
  focus text,
  level integer not null default 1,
  oc_cost integer not null check (oc_cost >= 0),
  created_at timestamptz not null default now()
);

create unique index if not exists event_log_oc_skill_purchases_char_event_idx
  on event_log_oc_skill_purchases(character_id, event_slug);

alter table event_log_oc_skill_purchases enable row level security;

drop policy if exists "Players see their own OC skill purchases" on event_log_oc_skill_purchases;
create policy "Players see their own OC skill purchases"
  on event_log_oc_skill_purchases for select
  using (player_id = (select auth.uid()) or fa_is_logistics_or_admin());

grant select on event_log_oc_skill_purchases to authenticated;

create or replace function fa_xp_cost_for_sp(p_current_total_sp integer, p_additional_sp integer)
returns integer language plpgsql immutable
set search_path = public
as $$
declare
  v_current_sp integer := p_current_total_sp;
  v_remaining_sp integer := p_additional_sp;
  v_total_xp integer := 0;
  v_tier record;
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
    exit when v_remaining_sp <= 0;
    continue when v_current_sp >= v_tier.ceiling;
    v_sp_this_tier := least(v_tier.ceiling - v_current_sp, v_remaining_sp);
    v_total_xp := v_total_xp + v_sp_this_tier * v_tier.rate;
    v_current_sp := v_current_sp + v_sp_this_tier;
    v_remaining_sp := v_remaining_sp - v_sp_this_tier;
  end loop;

  return v_total_xp;
end;
$$;

create or replace function character_total_sp_pool(p_character_id uuid)
returns integer language plpgsql stable security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
  v_starting_sp integer;
  v_spent_sp integer;
  v_xp_balance integer;
begin
  if v_player is null then raise exception 'Not signed in'; end if;

  select starting_sp into v_starting_sp from characters
    where id = p_character_id and player_id = v_player;
  if not found then raise exception 'Character not found'; end if;

  select coalesce(sum(total_sp_paid), 0) into v_spent_sp from character_skills where character_id = p_character_id;
  v_xp_balance := xp_balance(p_character_id);

  return fa_convert_xp_to_sp(v_xp_balance, v_starting_sp, v_spent_sp);
end;
$$;

create or replace function event_log_buy_skill_with_oc(
  p_event_slug text,
  p_character_id uuid,
  p_category text,
  p_skill_name text,
  p_focus text,
  p_level integer
)
returns uuid language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
  v_starting_sp integer;
  v_race text;
  v_category text := coalesce(nullif(trim(p_category), ''), 'Skill');
  v_skill_name text := trim(coalesce(p_skill_name, ''));
  v_focus text := nullif(p_focus, '');
  v_level integer := greatest(1, coalesce(p_level, 1));
  v_limit integer;
  v_true_cost integer;
  v_spent_sp integer;
  v_xp_balance integer;
  v_total_pool integer;
  v_oc_cost integer;
  v_oc_balance integer;
  v_skill_id uuid;
  v_row record;
begin
  if v_player is null then raise exception 'Not signed in'; end if;
  if v_skill_name = '' then raise exception 'Skill name cannot be empty'; end if;

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

  if exists (
    select 1 from event_log_oc_skill_purchases
    where character_id = p_character_id and event_slug = p_event_slug
  ) then
    raise exception 'You already bought a skill with Ogre Chips this event';
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

  v_true_cost := skills_true_total_cost(v_skill_name, v_focus, v_level, v_race);
  if v_true_cost is null then
    raise exception 'Could not price skill: % %', v_skill_name, coalesce(v_focus, '');
  end if;

  for v_row in
    select * from event_log_training_purchases
    where character_id = p_character_id and event_slug = p_event_slug
    order by created_at desc
  loop
    if v_row.is_relevel then
      update character_skills
        set level = v_row.prev_level, sp_cost = v_row.prev_sp_cost, total_sp_paid = total_sp_paid - v_row.sp_cost
        where id = v_row.character_skill_id;
    else
      delete from character_skills where id = v_row.character_skill_id;
    end if;
  end loop;

  delete from event_log_training_purchases where character_id = p_character_id and event_slug = p_event_slug;

  select coalesce(sum(total_sp_paid), 0) into v_spent_sp from character_skills where character_id = p_character_id;
  v_xp_balance := xp_balance(p_character_id);
  v_total_pool := fa_convert_xp_to_sp(v_xp_balance, v_starting_sp, v_spent_sp);
  v_oc_cost := fa_xp_cost_for_sp(v_total_pool, v_true_cost);

  select coalesce(sum(amount), 0) into v_oc_balance from oc_transactions where player_id = v_player;
  if v_oc_cost > v_oc_balance then
    raise exception 'Not enough Ogre Chips';
  end if;

  insert into character_skills (character_id, player_id, category, skill_name, focus, level, sp_cost, total_sp_paid)
    values (p_character_id, v_player, v_category, v_skill_name, v_focus, v_level, 0, 0)
    returning id into v_skill_id;

  insert into oc_transactions (player_id, amount, note, created_by)
    values (v_player, -v_oc_cost, 'Bought ' || v_skill_name || ' with Ogre Chips (' || p_event_slug || ')', v_player);

  insert into event_log_oc_skill_purchases
    (player_id, character_id, event_slug, character_skill_id, category, skill_name, focus, level, oc_cost)
    values (v_player, p_character_id, p_event_slug, v_skill_id, v_category, v_skill_name, v_focus, v_level, v_oc_cost);

  return v_skill_id;
end;
$$;

create or replace function event_log_cancel_oc_skill_purchase(p_purchase_id uuid)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
  v_char_skill_id uuid;
  v_oc_cost integer;
begin
  if v_player is null then raise exception 'Not signed in'; end if;

  select character_skill_id, oc_cost into v_char_skill_id, v_oc_cost
    from event_log_oc_skill_purchases
    where id = p_purchase_id and player_id = v_player;
  if not found then raise exception 'Purchase not found'; end if;

  delete from character_skills where id = v_char_skill_id;

  insert into oc_transactions (player_id, amount, note, created_by)
    values (v_player, v_oc_cost, 'Refunded Ogre Chips (cancelled skill purchase)', v_player);
end;
$$;
