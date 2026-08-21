
alter table shoppe_purchases add column if not exists availability_id integer;
alter table shoppe_sales add column if not exists availability_id integer;

create or replace function fa_merchant_rarity_quota(p_merchant_level integer, p_availability_id integer)
returns table(sell_qty integer, buy_qty integer) language sql stable
as $$
  select sell, buy from merchant_rarity_tiers
    where merchant_level = least(greatest(coalesce(p_merchant_level, 0), 0), 10)
      and availability_id = p_availability_id;
$$;

drop function if exists shoppe_buy_item(text, uuid, text, text, integer, integer, integer);
drop function if exists shoppe_sell_item(text, uuid, text, text, integer, integer, boolean, integer);

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
  v_quota_buy integer;
  v_bought_so_far integer;
begin
  if v_player is null then raise exception 'Not signed in'; end if;
  if p_quantity is null or p_quantity < 1 then raise exception 'Quantity must be at least 1'; end if;
  if p_unit_cost_copper is null or p_unit_cost_copper < 0 then raise exception 'Invalid item cost'; end if;
  if p_character_id is not null and not exists (select 1 from characters where id = p_character_id and player_id = v_player) then
    raise exception 'Character not found';
  end if;

  if p_character_id is not null then
    v_merchant_level := fa_character_merchant_level(p_character_id);

    if coalesce(p_availability_tier, 1) > 1 and p_availability_tier > v_merchant_level then
      raise exception 'Requires Merchant level % to buy this (this character has level %)', p_availability_tier, v_merchant_level;
    end if;

    select pct.buy_pct into v_buy_pct from fa_merchant_price_pct(v_merchant_level) pct;

    if p_availability_tier is not null then
      select buy_qty into v_quota_buy from fa_merchant_rarity_quota(v_merchant_level, p_availability_tier);
      if v_quota_buy is not null then
        select coalesce(sum(quantity), 0) into v_bought_so_far from shoppe_purchases
          where character_id = p_character_id and event_slug = p_event_slug and availability_id = p_availability_tier;
        if v_bought_so_far + p_quantity > v_quota_buy then
          raise exception 'Merchant level % can only buy % of this rarity per event (already bought %)', v_merchant_level, v_quota_buy, v_bought_so_far;
        end if;
      end if;
    end if;

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

  insert into shoppe_purchases (player_id, character_id, event_slug, category, item_name, unit_cost_copper, quantity, total_cost_copper, availability_id)
    values (v_player, p_character_id, p_event_slug, p_category, p_item_name, ceil(p_unit_cost_copper * v_buy_pct / 100.0)::integer, p_quantity, v_total, p_availability_tier)
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
  p_hours_budget integer,
  p_availability_tier integer default null
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
  v_quota_sell integer;
  v_sold_so_far integer;
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

  if p_availability_tier is not null then
    select sell_qty into v_quota_sell from fa_merchant_rarity_quota(v_merchant_level, p_availability_tier);
    if v_quota_sell is not null then
      select coalesce(sum(quantity), 0) into v_sold_so_far from shoppe_sales
        where character_id = p_character_id and event_slug = p_event_slug and availability_id = p_availability_tier;
      if v_sold_so_far + p_quantity > v_quota_sell then
        raise exception 'Merchant level % can only sell % of this rarity per event (already sold %)', v_merchant_level, v_quota_sell, v_sold_so_far;
      end if;
    end if;
  end if;

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

  insert into shoppe_sales (player_id, character_id, event_slug, category, item_name, unit_value_copper, quantity, total_copper_received, from_inventory, tag_turned_in, availability_id)
    values (v_player, p_character_id, p_event_slug, p_category, p_item_name, p_unit_value_copper, p_quantity, v_total, p_from_inventory, not p_from_inventory, p_availability_tier)
    returning id into v_id;

  if v_total > 0 then
    insert into bank_transactions (player_id, type, amount, note, created_by)
      values (v_player, 'deposit', v_total, 'Shoppe sale: ' || p_quantity || 'x ' || p_item_name || ' (' || p_event_slug || ')', v_player);
  end if;

  return v_id;
end;
$$;
