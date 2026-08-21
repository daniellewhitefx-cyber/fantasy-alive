
create table if not exists event_log_upkeep_costs (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references auth.users(id) on delete cascade,
  character_id uuid not null references characters(id) on delete cascade,
  event_slug text not null,
  description text not null,
  copper_cost numeric(12,2) not null check (copper_cost > 0),
  repeating boolean not null default false,
  series_id uuid not null default gen_random_uuid(),
  actioned boolean not null default false,
  actioned_by uuid references auth.users(id) on delete set null,
  actioned_at timestamptz,
  created_at timestamptz not null default now(),
  unique (series_id, event_slug)
);

create index if not exists event_log_upkeep_costs_char_event_idx
  on event_log_upkeep_costs(character_id, event_slug);

alter table event_log_upkeep_costs enable row level security;
drop policy if exists "Players see their own upkeep costs" on event_log_upkeep_costs;
create policy "Players see their own upkeep costs"
  on event_log_upkeep_costs for select
  using (player_id = auth.uid() or fa_is_logistics_or_admin());

grant select on event_log_upkeep_costs to authenticated;

create or replace function event_log_log_upkeep(
  p_event_slug text,
  p_character_id uuid,
  p_description text,
  p_copper_cost numeric,
  p_repeating boolean
)
returns uuid language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
  v_description text := trim(coalesce(p_description, ''));
  v_id uuid;
begin
  if v_player is null then raise exception 'Not signed in'; end if;
  if v_description = '' then raise exception 'Description cannot be empty'; end if;
  if p_copper_cost is null or p_copper_cost <= 0 then raise exception 'Copper cost must be positive'; end if;

  if not exists (select 1 from characters where id = p_character_id and player_id = v_player) then
    raise exception 'Character not found';
  end if;

  insert into event_log_upkeep_costs (player_id, character_id, event_slug, description, copper_cost, repeating)
    values (v_player, p_character_id, p_event_slug, v_description, p_copper_cost, coalesce(p_repeating, false))
    returning id into v_id;

  insert into bank_transactions (player_id, type, amount, note, created_by)
    values (v_player, 'withdrawal', p_copper_cost, 'Upkeep: ' || v_description || ' (' || p_event_slug || ')', v_player);

  return v_id;
end;
$$;

create or replace function event_log_cancel_upkeep(p_id uuid)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
  v_row event_log_upkeep_costs%rowtype;
begin
  if v_player is null then raise exception 'Not signed in'; end if;

  select * into v_row from event_log_upkeep_costs
    where id = p_id and player_id = v_player and actioned = false;
  if not found then raise exception 'Upkeep cost not found'; end if;

  insert into bank_transactions (player_id, type, amount, note, created_by)
    values (v_player, 'deposit', v_row.copper_cost, 'Upkeep refund: ' || v_row.description || ' (' || v_row.event_slug || ')', v_player);

  update event_log_upkeep_costs set repeating = false where series_id = v_row.series_id;
  delete from event_log_upkeep_costs where id = p_id;
end;
$$;

create or replace function event_log_stop_upkeep_repeat(p_id uuid)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
begin
  if v_player is null then raise exception 'Not signed in'; end if;

  update event_log_upkeep_costs set repeating = false
    where id = p_id and player_id = v_player;
  if not found then raise exception 'Upkeep cost not found'; end if;
end;
$$;

create or replace function event_log_mark_upkeep_actioned(p_id uuid)
returns void language plpgsql security definer
set search_path = public
as $$
begin
  if not fa_is_logistics_or_admin() then raise exception 'Staff only'; end if;

  update event_log_upkeep_costs
    set actioned = true, actioned_by = auth.uid(), actioned_at = now()
    where id = p_id;
  if not found then raise exception 'Upkeep cost not found'; end if;
end;
$$;

create or replace function event_log_apply_repeating_upkeep(p_event_slug text, p_character_id uuid)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
  v_row record;
  v_new_id uuid;
begin
  if v_player is null then raise exception 'Not signed in'; end if;
  if not exists (select 1 from characters where id = p_character_id and player_id = v_player) then
    raise exception 'Character not found';
  end if;

  for v_row in
    select distinct on (series_id) *
    from event_log_upkeep_costs
    where character_id = p_character_id
    order by series_id, created_at desc
  loop
    if not v_row.repeating then continue; end if;
    if v_row.event_slug = p_event_slug then continue; end if;

    insert into event_log_upkeep_costs (player_id, character_id, event_slug, description, copper_cost, repeating, series_id)
      values (v_row.player_id, p_character_id, p_event_slug, v_row.description, v_row.copper_cost, true, v_row.series_id)
      on conflict (series_id, event_slug) do nothing
      returning id into v_new_id;

    if v_new_id is not null then
      insert into bank_transactions (player_id, type, amount, note, created_by)
        values (v_row.player_id, 'withdrawal', v_row.copper_cost, 'Upkeep: ' || v_row.description || ' (' || p_event_slug || ')', v_player);
    end if;
  end loop;
end;
$$;
