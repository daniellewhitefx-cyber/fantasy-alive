-- Selling, and real Merchant-tier pricing for buying. The old site's
-- merchant_price_tiers table (already migrated, never wired up) sets
-- what a character actually pays/receives based on their Merchant Trade
-- Skill level: level 0 pays 150% to buy and gets 25% back selling; by
-- level 10 that's 80% to buy and 75% selling. Requires
-- item-catalog-schema.sql, item-catalog-import.sql, crafting-schema.sql,
-- and shoppe-schema.sql to already exist.
--
-- Both buying and selling cost 8 downtime hours "travel" the first time
-- a character deals in a given item category at an event -- buying and
-- selling in the same category on the same trip doesn't cost twice, and
-- once paid the hours aren't refunded by cancelling the purchase/sale
-- that triggered it.
--
-- Selling has two modes: from the character's tracked inventory
-- (character_material_inventory; deducts from the ledger immediately,
-- physical tag assumed handed over as part of the sale) or a promise to
-- turn in the physical tag later (no ledger effect now, but it shows up
-- in Event Info's "Tags Owed to Logistics" box, same as an uncovered
-- craft).

create or replace function fa_character_merchant_level(p_character_id uuid)
returns integer language sql stable security definer
set search_path = public
as $$
  select coalesce(max(level), 0) from character_skills
    where character_id = p_character_id and category = 'Trade Skill' and lower(skill_name) = 'merchant';
$$;

create or replace function fa_merchant_price_pct(p_merchant_level integer)
returns table(buy_pct integer, sell_pct integer) language sql stable
as $$
  select buy_pct, sell_pct from merchant_price_tiers
    where merchant_level = least(greatest(coalesce(p_merchant_level, 0), 0), 10);
$$;

create table if not exists event_log_shopping_trips (
  character_id uuid not null references characters(id) on delete cascade,
  event_slug text not null,
  category text not null,
  hours integer not null default 8,
  created_at timestamptz not null default now(),
  primary key (character_id, event_slug, category)
);

alter table event_log_shopping_trips enable row level security;

drop policy if exists "Players see their own shopping trips" on event_log_shopping_trips;
create policy "Players see their own shopping trips"
  on event_log_shopping_trips for select
  using (
    character_id in (select id from characters where player_id = auth.uid())
    or fa_is_logistics_or_admin()
  );

create table if not exists shoppe_sales (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references auth.users(id) on delete cascade,
  character_id uuid not null references characters(id) on delete cascade,
  event_slug text not null,
  category text not null,
  item_name text not null,
  unit_value_copper integer not null check (unit_value_copper >= 0),
  quantity integer not null default 1 check (quantity > 0),
  total_copper_received integer not null check (total_copper_received >= 0),
  from_inventory boolean not null,
  tag_turned_in boolean not null,
  created_at timestamptz not null default now()
);

create index if not exists shoppe_sales_player_idx on shoppe_sales(player_id, event_slug, created_at);
create index if not exists shoppe_sales_char_idx on shoppe_sales(character_id, event_slug);

alter table shoppe_sales enable row level security;
drop policy if exists "Players see their own shoppe sales" on shoppe_sales;
create policy "Players see their own shoppe sales"
  on shoppe_sales for select
  using (player_id = auth.uid() or fa_is_logistics_or_admin());

grant select on shoppe_sales, event_log_shopping_trips to authenticated;

-- One-time 8-hour travel charge per character/event/category, shared by
-- buying and selling. Returns the number of NEW hours charged (8 the
-- first time this category is touched this event, 0 on every call
-- after) so callers can fold it into their own hours-budget check.
create or replace function fa_charge_shopping_travel(p_character_id uuid, p_event_slug text, p_category text)
returns integer language plpgsql security definer
set search_path = public
as $$
begin
  insert into event_log_shopping_trips (character_id, event_slug, category)
    values (p_character_id, p_event_slug, p_category)
  on conflict (character_id, event_slug, category) do nothing;
  if found then return 8; end if;
  return 0;
end;
$$;

-- Extends character_material_ledger (crafting-schema.sql) with a third
-- source: items sold from inventory (from_inventory = true) leave the
-- ledger as a negative delta, same shape as materials consumed by a
-- craft. Sales not from inventory don't touch the ledger at all -- the
-- item was never tracked as owned to begin with.
create or replace function character_material_ledger(p_character_id uuid)
returns table(material_name text, delta integer) language sql stable security definer
set search_path = public
as $$
  select item_name, quantity from shoppe_purchases where character_id = p_character_id
  union all
  select item_name, qty_produced from crafting_log where character_id = p_character_id
  union all
  select cmc.material_name, -cmc.quantity from crafting_materials_consumed cmc
    join crafting_log cl on cl.id = cmc.crafting_log_id
    where cl.character_id = p_character_id
  union all
  select item_name, -quantity from shoppe_sales where character_id = p_character_id and from_inventory
$$;

-- Extends event_log_training_summary (crafting-schema.sql) so Hours
-- Remaining also reflects shopping-trip travel time.
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
  into v_hours_spent;

  return jsonb_build_object(
    'spendable_sp', v_spendable_sp,
    'hours_spent', v_hours_spent
  );
end;
$$;

-- Replaces shoppe_buy_item: now charges the Merchant-tier buy markup
-- (face value at Merchant level 0 and above -- 150% down to 80% -- not
-- the old flat face-value price) and the one-time 8-hour category
-- travel charge, when shopping as a character. Cast purchases (no
-- character) are unaffected: face value, no hours cost, same as before.
create or replace function shoppe_buy_item(
  p_event_slug text,
  p_character_id uuid,
  p_category text,
  p_item_name text,
  p_availability_tier integer,
  p_unit_cost_copper integer,
  p_quantity integer,
  p_hours_budget integer default null
)
returns uuid language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
  v_total integer;
  v_id uuid;
  v_merchant_level integer;
  v_buy_pct integer := 100;
  v_hours_spent integer;
  v_new_hours integer := 0;
begin
  if v_player is null then raise exception 'Not signed in'; end if;
  if p_quantity is null or p_quantity < 1 then raise exception 'Quantity must be at least 1'; end if;
  if p_unit_cost_copper is null or p_unit_cost_copper < 0 then raise exception 'Invalid item cost'; end if;
  if p_character_id is not null and not exists (select 1 from characters where id = p_character_id and player_id = v_player) then
    raise exception 'Character not found';
  end if;

  if p_character_id is not null then
    v_merchant_level := fa_character_merchant_level(p_character_id);

    -- Merchant level N unlocks buying items at Availability tier N.
    if coalesce(p_availability_tier, 1) > 1 and p_availability_tier > v_merchant_level then
      raise exception 'Requires Merchant level % to buy this (this character has level %)', p_availability_tier, v_merchant_level;
    end if;

    select pct.buy_pct into v_buy_pct from fa_merchant_price_pct(v_merchant_level) pct;

    if p_hours_budget is not null then
      select coalesce((event_log_training_summary(p_event_slug, p_character_id) ->> 'hours_spent')::integer, 0)
        into v_hours_spent;
      v_new_hours := case when exists (
        select 1 from event_log_shopping_trips where character_id = p_character_id and event_slug = p_event_slug and category = p_category
      ) then 0 else 8 end;
      if v_hours_spent + v_new_hours > p_hours_budget then
        raise exception 'Not enough downtime hours left to travel for this category';
      end if;
    end if;
  end if;

  v_total := ceil(p_unit_cost_copper * v_buy_pct / 100.0)::integer * p_quantity;
  if v_total > 0 and bank_balance(v_player) < v_total then
    raise exception 'Not enough Copper';
  end if;

  if p_character_id is not null then
    perform fa_charge_shopping_travel(p_character_id, p_event_slug, p_category);
  end if;

  insert into shoppe_purchases (player_id, character_id, event_slug, category, item_name, unit_cost_copper, quantity, total_cost_copper)
    values (v_player, p_character_id, p_event_slug, p_category, p_item_name, ceil(p_unit_cost_copper * v_buy_pct / 100.0)::integer, p_quantity, v_total)
    returning id into v_id;

  if v_total > 0 then
    insert into bank_transactions (player_id, type, amount, note, created_by)
      values (v_player, 'withdrawal', v_total, 'Shoppe: ' || p_quantity || 'x ' || p_item_name || ' (' || p_event_slug || ')', v_player);
  end if;

  return v_id;
end;
$$;

create or replace function shoppe_sell_item(
  p_event_slug text,
  p_character_id uuid,
  p_category text,
  p_item_name text,
  p_unit_value_copper integer,
  p_quantity integer,
  p_from_inventory boolean,
  p_hours_budget integer
)
returns uuid language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
  v_total integer;
  v_id uuid;
  v_merchant_level integer;
  v_sell_pct integer;
  v_on_hand integer;
  v_hours_spent integer;
  v_new_hours integer;
begin
  if v_player is null then raise exception 'Not signed in'; end if;
  if p_quantity is null or p_quantity < 1 then raise exception 'Quantity must be at least 1'; end if;
  if p_unit_value_copper is null or p_unit_value_copper < 0 then raise exception 'Invalid item value'; end if;
  if not exists (select 1 from characters where id = p_character_id and player_id = v_player) then
    raise exception 'Character not found';
  end if;

  if p_from_inventory then
    select coalesce(sum(delta), 0) into v_on_hand
      from character_material_ledger(p_character_id) where lower(material_name) = lower(p_item_name);
    if v_on_hand < p_quantity then
      raise exception 'Not enough % on hand (have %, need %)', p_item_name, v_on_hand, p_quantity;
    end if;
  end if;

  v_merchant_level := fa_character_merchant_level(p_character_id);
  select pct.sell_pct into v_sell_pct from fa_merchant_price_pct(v_merchant_level) pct;

  select coalesce((event_log_training_summary(p_event_slug, p_character_id) ->> 'hours_spent')::integer, 0)
    into v_hours_spent;
  v_new_hours := case when exists (
    select 1 from event_log_shopping_trips where character_id = p_character_id and event_slug = p_event_slug and category = p_category
  ) then 0 else 8 end;
  if v_hours_spent + v_new_hours > p_hours_budget then
    raise exception 'Not enough downtime hours left to travel for this category';
  end if;

  v_total := floor(p_unit_value_copper * v_sell_pct / 100.0)::integer * p_quantity;

  perform fa_charge_shopping_travel(p_character_id, p_event_slug, p_category);

  insert into shoppe_sales (player_id, character_id, event_slug, category, item_name, unit_value_copper, quantity, total_copper_received, from_inventory, tag_turned_in)
    values (v_player, p_character_id, p_event_slug, p_category, p_item_name, p_unit_value_copper, p_quantity, v_total, p_from_inventory, not p_from_inventory)
    returning id into v_id;

  if v_total > 0 then
    insert into bank_transactions (player_id, type, amount, note, created_by)
      values (v_player, 'deposit', v_total, 'Shoppe sale: ' || p_quantity || 'x ' || p_item_name || ' (' || p_event_slug || ')', v_player);
  end if;

  return v_id;
end;
$$;

create or replace function shoppe_cancel_sale(p_sale_id uuid)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
  v_sale shoppe_sales%rowtype;
begin
  if v_player is null then raise exception 'Not signed in'; end if;

  select * into v_sale from shoppe_sales where id = p_sale_id and player_id = v_player;
  if not found then raise exception 'Sale not found'; end if;

  delete from shoppe_sales where id = p_sale_id;

  if v_sale.total_copper_received > 0 then
    insert into bank_transactions (player_id, type, amount, note, created_by)
      values (v_player, 'withdrawal', v_sale.total_copper_received, 'Reversed sale: ' || v_sale.item_name || ' (' || v_sale.event_slug || ')', v_player);
  end if;
end;
$$;
