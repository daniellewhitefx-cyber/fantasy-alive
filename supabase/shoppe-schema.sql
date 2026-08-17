-- Event Shoppe: players spend Copper (their existing bank_transactions
-- balance -- the same wallet the Spend OC tab's OC-to-Copper conversion
-- already feeds) to buy items from the catalog sheet. Purchases are
-- logged per event so they show up in a "Purchased This Event" list
-- with the option to cancel/refund, the same shape as Training's
-- event_log_training_purchases.

create table if not exists shoppe_purchases (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references auth.users(id) on delete cascade,
  character_id uuid references characters(id) on delete set null,
  event_slug text not null,
  category text not null,
  item_name text not null,
  unit_cost_copper integer not null check (unit_cost_copper >= 0),
  quantity integer not null default 1 check (quantity > 0),
  total_cost_copper integer not null check (total_cost_copper >= 0),
  created_at timestamptz not null default now()
);

create index if not exists shoppe_purchases_player_idx on shoppe_purchases(player_id, event_slug, created_at);

alter table shoppe_purchases enable row level security;
drop policy if exists "Players see their own shoppe purchases" on shoppe_purchases;
create policy "Players see their own shoppe purchases"
  on shoppe_purchases for select
  using (player_id = auth.uid() or fa_is_logistics_or_admin());

create or replace function shoppe_buy_item(
  p_event_slug text,
  p_character_id uuid,
  p_category text,
  p_item_name text,
  p_availability_tier integer,
  p_unit_cost_copper integer,
  p_quantity integer
)
returns uuid language plpgsql security definer as $$
declare
  v_player uuid := auth.uid();
  v_total integer;
  v_id uuid;
  v_merchant_level integer;
begin
  if v_player is null then raise exception 'Not signed in'; end if;
  if p_quantity is null or p_quantity < 1 then raise exception 'Quantity must be at least 1'; end if;
  if p_unit_cost_copper is null or p_unit_cost_copper < 0 then raise exception 'Invalid item cost'; end if;
  if p_character_id is not null and not exists (select 1 from characters where id = p_character_id and player_id = v_player) then
    raise exception 'Character not found';
  end if;

  -- Merchant level N unlocks buying items at Availability tier N. Only
  -- enforced when shopping as a character (Cast purchases aren't tied to
  -- a character's Trade Skills) and only for tiers above Common (1),
  -- which anyone can buy without any Merchant training.
  if p_character_id is not null and coalesce(p_availability_tier, 1) > 1 then
    select coalesce(max(level), 0) into v_merchant_level
      from character_skills
      where character_id = p_character_id and category = 'Trade Skill' and lower(skill_name) = 'merchant';
    if p_availability_tier > v_merchant_level then
      raise exception 'Requires Merchant level % to buy this (this character has level %)', p_availability_tier, v_merchant_level;
    end if;
  end if;

  v_total := p_unit_cost_copper * p_quantity;
  if v_total > 0 and bank_balance(v_player) < v_total then
    raise exception 'Not enough Copper';
  end if;

  insert into shoppe_purchases (player_id, character_id, event_slug, category, item_name, unit_cost_copper, quantity, total_cost_copper)
    values (v_player, p_character_id, p_event_slug, p_category, p_item_name, p_unit_cost_copper, p_quantity, v_total)
    returning id into v_id;

  if v_total > 0 then
    insert into bank_transactions (player_id, type, amount, note, created_by)
      values (v_player, 'withdrawal', v_total, 'Shoppe: ' || p_quantity || 'x ' || p_item_name || ' (' || p_event_slug || ')', v_player);
  end if;

  return v_id;
end;
$$;

create or replace function shoppe_cancel_purchase(p_purchase_id uuid)
returns void language plpgsql security definer as $$
declare
  v_player uuid := auth.uid();
  v_purchase shoppe_purchases%rowtype;
begin
  if v_player is null then raise exception 'Not signed in'; end if;

  select * into v_purchase from shoppe_purchases where id = p_purchase_id and player_id = v_player;
  if not found then raise exception 'Purchase not found'; end if;

  delete from shoppe_purchases where id = p_purchase_id;

  if v_purchase.total_cost_copper > 0 then
    insert into bank_transactions (player_id, type, amount, note, created_by)
      values (v_player, 'deposit', v_purchase.total_cost_copper, 'Refund: ' || v_purchase.item_name || ' (' || v_purchase.event_slug || ')', v_player);
  end if;
end;
$$;

grant select on shoppe_purchases to authenticated;
