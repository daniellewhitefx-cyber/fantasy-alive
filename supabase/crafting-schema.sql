-- "Crafting" tab on the Current Event log: a character with a Trade Skill
-- spends downtime Hours (the same shared budget Training/Work draw from)
-- and consumes tracked Materials to produce a named item from the
-- rulebook's Production List. Materials come from a derived ledger
-- combining Shoppe purchases (raw materials bought as Material/Equipment
-- items) and previously crafted items, since some recipes consume other
-- crafted goods (e.g. Chain Links feeding into Chainmail, Hardware
-- feeding into a dozen other recipes).
--
-- At craft time a player can also mark that they're turning in a
-- physical tag for the item; unmarked crafts are still tracked in the
-- character's account/material ledger, just without a tag flagged as
-- needed yet.

create table if not exists crafting_log (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references auth.users(id) on delete cascade,
  character_id uuid not null references characters(id) on delete cascade,
  event_slug text not null,
  character_skill_id uuid not null references character_skills(id) on delete cascade,
  skill_name text not null,
  item_name text not null,
  category text not null,
  level_required integer not null default 1,
  hours_spent integer not null check (hours_spent > 0),
  qty_produced integer not null default 1 check (qty_produced > 0),
  tag_turned_in boolean not null default false,
  created_at timestamptz not null default now()
);

create index if not exists crafting_log_char_event_idx on crafting_log(character_id, event_slug);

alter table crafting_log enable row level security;
drop policy if exists "Players see their own crafting log" on crafting_log;
create policy "Players see their own crafting log"
  on crafting_log for select
  using (player_id = auth.uid() or fa_is_logistics_or_admin());

create table if not exists crafting_materials_consumed (
  id uuid primary key default gen_random_uuid(),
  crafting_log_id uuid not null references crafting_log(id) on delete cascade,
  material_name text not null,
  quantity integer not null check (quantity > 0)
);

alter table crafting_materials_consumed enable row level security;
drop policy if exists "Players see their own consumed materials" on crafting_materials_consumed;
create policy "Players see their own consumed materials"
  on crafting_materials_consumed for select
  using (
    exists (
      select 1 from crafting_log cl
      where cl.id = crafting_log_id and (cl.player_id = auth.uid() or fa_is_logistics_or_admin())
    )
  );

grant select on crafting_log to authenticated;
grant select on crafting_materials_consumed to authenticated;

-- Combined per-character material ledger: positive rows from Shoppe
-- Material/Equipment purchases and from items the character has crafted
-- (which can themselves be used as materials in later recipes), negative
-- rows from materials already consumed by past crafts.
create or replace function character_material_ledger(p_character_id uuid)
returns table(material_name text, delta integer) language sql stable security definer as $$
  select item_name, quantity from shoppe_purchases where character_id = p_character_id
  union all
  select item_name, qty_produced from crafting_log where character_id = p_character_id
  union all
  select cmc.material_name, -cmc.quantity from crafting_materials_consumed cmc
    join crafting_log cl on cl.id = cmc.crafting_log_id
    where cl.character_id = p_character_id
$$;

revoke execute on function character_material_ledger(uuid) from public, authenticated, anon;

-- Only returns materials the character actually has on hand (balance >
-- 0). A tag-covered craft can drive a material negative in the ledger,
-- but that's a debt, not inventory -- it's surfaced separately on the
-- Event Info tab's "Tags Owed to Logistics" box instead of showing up
-- here as a confusing negative quantity.
create or replace function character_material_inventory(p_character_id uuid)
returns table(material_name text, balance integer) language plpgsql stable security definer as $$
begin
  if not exists (select 1 from characters where id = p_character_id and player_id = auth.uid()) then
    raise exception 'Character not found';
  end if;
  return query
    select l.material_name, sum(l.delta)::integer as balance
    from character_material_ledger(p_character_id) l
    group by l.material_name
    having sum(l.delta) > 0
    order by l.material_name;
end;
$$;

-- Extends event_log_training_summary (defined in training-schema.sql,
-- already extended once by working-schema.sql) so Hours Remaining
-- reflects Training, Working, and Crafting spend against the same
-- shared downtime budget.
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

  select
    coalesce((select sum(hours_cost) from event_log_training_purchases where character_id = p_character_id and event_slug = p_event_slug), 0)
    + coalesce((select sum(hours_worked) from event_log_working_sessions where character_id = p_character_id and event_slug = p_event_slug), 0)
    + coalesce((select sum(hours_spent) from crafting_log where character_id = p_character_id and event_slug = p_event_slug), 0)
  into v_hours_spent;

  return jsonb_build_object('spendable_sp', v_spendable_sp, 'hours_spent', v_hours_spent);
end;
$$;

create or replace function craft_item(
  p_event_slug text,
  p_character_id uuid,
  p_hours_budget integer,
  p_character_skill_id uuid,
  p_item_name text,
  p_category text,
  p_level_required integer,
  p_hours integer,
  p_qty_produced integer,
  p_materials jsonb,
  p_tag_turned_in boolean
)
returns uuid language plpgsql security definer as $$
declare
  v_player uuid := auth.uid();
  v_skill character_skills%rowtype;
  v_hours_spent integer;
  v_crafting_log_id uuid;
  v_material jsonb;
  v_name text;
  v_qty integer;
  v_balance integer;
begin
  if v_player is null then raise exception 'Not signed in'; end if;
  if p_hours is null or p_hours <= 0 then raise exception 'Hours must be positive'; end if;
  if p_hours_budget is null or p_hours_budget < 0 then raise exception 'Invalid hours budget'; end if;
  if p_qty_produced is null or p_qty_produced < 1 then raise exception 'Invalid quantity produced'; end if;

  if not exists (select 1 from characters where id = p_character_id and player_id = v_player) then
    raise exception 'Character not found';
  end if;

  select * into v_skill from character_skills
    where id = p_character_skill_id and character_id = p_character_id
    for update;
  if not found then raise exception 'Skill not found'; end if;
  if v_skill.category != 'Trade Skill' then raise exception 'Only Trade Skills can craft'; end if;
  if v_skill.level < coalesce(p_level_required, 1) then
    raise exception 'Requires % level %, this character has level %', v_skill.skill_name, p_level_required, v_skill.level;
  end if;

  select
    coalesce((select sum(hours_cost) from event_log_training_purchases where character_id = p_character_id and event_slug = p_event_slug), 0)
    + coalesce((select sum(hours_worked) from event_log_working_sessions where character_id = p_character_id and event_slug = p_event_slug), 0)
    + coalesce((select sum(hours_spent) from crafting_log where character_id = p_character_id and event_slug = p_event_slug), 0)
  into v_hours_spent;

  if v_hours_spent + p_hours > p_hours_budget then
    raise exception 'Not enough downtime hours left';
  end if;

  -- A checked "tag" means the player is promising to hand logistics
  -- physical tags covering these materials at the start of the next
  -- event, so the on-hand check is skipped entirely rather than
  -- blocking the craft. The materials are still recorded as consumed
  -- below either way, so the ledger reflects what's actually owed
  -- (surfaced on the Event Info tab's "Tags Owed to Logistics" box).
  if not coalesce(p_tag_turned_in, false) then
    for v_material in select * from jsonb_array_elements(coalesce(p_materials, '[]'::jsonb))
    loop
      v_name := v_material ->> 'name';
      v_qty := (v_material ->> 'qty')::integer;
      select coalesce(sum(delta), 0) into v_balance
        from character_material_ledger(p_character_id)
        where lower(material_name) = lower(v_name);
      if v_balance < v_qty then
        raise exception 'Not enough % on hand (have %, need %)', v_name, v_balance, v_qty;
      end if;
    end loop;
  end if;

  insert into crafting_log
    (player_id, character_id, event_slug, character_skill_id, skill_name, item_name, category, level_required, hours_spent, qty_produced, tag_turned_in)
    values (v_player, p_character_id, p_event_slug, p_character_skill_id, v_skill.skill_name, p_item_name, p_category, coalesce(p_level_required, 1), p_hours, p_qty_produced, coalesce(p_tag_turned_in, false))
    returning id into v_crafting_log_id;

  for v_material in select * from jsonb_array_elements(coalesce(p_materials, '[]'::jsonb))
  loop
    insert into crafting_materials_consumed (crafting_log_id, material_name, quantity)
      values (v_crafting_log_id, v_material ->> 'name', (v_material ->> 'qty')::integer);
  end loop;

  return v_crafting_log_id;
end;
$$;

create or replace function cancel_craft(p_crafting_log_id uuid)
returns void language plpgsql security definer as $$
declare
  v_player uuid := auth.uid();
begin
  if v_player is null then raise exception 'Not signed in'; end if;

  if not exists (select 1 from crafting_log where id = p_crafting_log_id and player_id = v_player) then
    raise exception 'Crafting log entry not found';
  end if;

  delete from crafting_log where id = p_crafting_log_id;
end;
$$;
