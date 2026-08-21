

create table if not exists market_settings (
  id boolean primary key default true check (id),
  is_open boolean not null default false,
  updated_by uuid references auth.users(id) on delete set null,
  updated_at timestamptz not null default now()
);

insert into market_settings (id, is_open) values (true, false)
  on conflict (id) do nothing;

alter table market_settings enable row level security;
drop policy if exists "Anyone signed in can see market status" on market_settings;
create policy "Anyone signed in can see market status"
  on market_settings for select
  using (true);

grant select on market_settings to authenticated;

create or replace function market_set_open(p_is_open boolean)
returns void language plpgsql security definer
set search_path = public
as $$
begin
  if not fa_is_logistics_or_admin() then
    raise exception 'Logistics only';
  end if;

  update market_settings
    set is_open = coalesce(p_is_open, false), updated_by = auth.uid(), updated_at = now()
    where id = true;
end;
$$;

revoke all on function market_set_open(boolean) from public, anon;
grant execute on function market_set_open(boolean) to authenticated;


create table if not exists market_listings (
  id uuid primary key default gen_random_uuid(),
  seller_character_id uuid references characters(id) on delete cascade,
  npc_seller_name text,
  listed_by uuid not null references auth.users(id) on delete cascade,
  item_name text not null,
  quantity integer not null check (quantity > 0),
  price_coin numeric(12,2) not null check (price_coin >= 0),
  status text not null default 'active' check (status in ('active', 'sold', 'cancelled')),
  buyer_character_id uuid references characters(id) on delete set null,
  created_at timestamptz not null default now(),
  sold_at timestamptz,
  check (
    (seller_character_id is not null and npc_seller_name is null)
    or (seller_character_id is null and npc_seller_name is not null)
  )
);

create index if not exists market_listings_status_idx on market_listings(status);
create index if not exists market_listings_seller_idx on market_listings(seller_character_id);

alter table market_listings enable row level security;
drop policy if exists "Market listings visibility" on market_listings;
create policy "Market listings visibility"
  on market_listings for select
  using (
    listed_by = (select auth.uid())
    or exists (select 1 from characters c where c.id = buyer_character_id and c.player_id = (select auth.uid()))
    or fa_is_logistics_or_admin()
    or fa_is_plot_or_admin()
    or (status = 'active' and coalesce((select is_open from market_settings where id = true), false))
  );

grant select on market_listings to authenticated;

create or replace function market_create_listing(
  p_item_name text,
  p_quantity integer,
  p_price_coin numeric,
  p_character_id uuid default null,
  p_npc_seller_name text default null
)
returns uuid language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
  v_balance integer;
  v_id uuid;
  v_npc_name text;
begin
  if v_player is null then raise exception 'Not signed in'; end if;
  if p_item_name is null or trim(p_item_name) = '' then raise exception 'Item is required'; end if;
  if p_quantity is null or p_quantity <= 0 then raise exception 'Quantity must be greater than 0'; end if;
  if p_price_coin is null or p_price_coin < 0 then raise exception 'Price must be zero or more'; end if;
  if p_character_id is not null and p_npc_seller_name is not null then
    raise exception 'Choose either a character or an NPC seller, not both';
  end if;

  if p_character_id is not null then
    if not exists (select 1 from characters where id = p_character_id and player_id = v_player) then
      raise exception 'Character not found';
    end if;

    select coalesce(sum(delta), 0) into v_balance
      from character_material_ledger(p_character_id)
      where lower(material_name) = lower(p_item_name);
    if v_balance < p_quantity then raise exception 'Not enough % on hand', p_item_name; end if;

    insert into market_listings (seller_character_id, listed_by, item_name, quantity, price_coin)
      values (p_character_id, v_player, trim(p_item_name), p_quantity, p_price_coin)
      returning id into v_id;
  else
    v_npc_name := nullif(trim(coalesce(p_npc_seller_name, '')), '');
    if v_npc_name is null then raise exception 'Enter a name for the NPC seller'; end if;
    if not fa_is_logistics_or_admin() and not fa_is_plot_or_admin() then
      raise exception 'Only Plot and Logistics can list an item for an NPC';
    end if;

    insert into market_listings (npc_seller_name, listed_by, item_name, quantity, price_coin)
      values (v_npc_name, v_player, trim(p_item_name), p_quantity, p_price_coin)
      returning id into v_id;
  end if;

  return v_id;
end;
$$;

revoke all on function market_create_listing(text, integer, numeric, uuid, text) from public, anon;
grant execute on function market_create_listing(text, integer, numeric, uuid, text) to authenticated;

create or replace function market_cancel_listing(p_listing_id uuid)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
  v_listing market_listings;
begin
  if v_player is null then raise exception 'Not signed in'; end if;

  select * into v_listing from market_listings where id = p_listing_id;
  if not found then raise exception 'Listing not found'; end if;
  if v_listing.status != 'active' then raise exception 'This listing is no longer active'; end if;
  if v_listing.listed_by != v_player and not fa_is_logistics_or_admin() then
    raise exception 'Not authorized';
  end if;

  update market_listings set status = 'cancelled' where id = p_listing_id;
end;
$$;

revoke all on function market_cancel_listing(uuid) from public, anon;
grant execute on function market_cancel_listing(uuid) to authenticated;


alter table bank_transactions drop constraint if exists bank_transactions_type_check;
alter table bank_transactions add constraint bank_transactions_type_check check (type in (
  'deposit', 'withdrawal', 'transfer_in', 'transfer_out',
  'bill_payment_in', 'bill_payment_out', 'log_bank',
  'market_sale_in', 'market_purchase_out'
));

create or replace function bank_balance(p_player uuid)
returns numeric language sql stable security definer
set search_path = public
as $$
  select coalesce(sum(
    case
      when type in ('deposit', 'transfer_in', 'bill_payment_in', 'log_bank', 'market_sale_in') then amount
      when type in ('withdrawal', 'transfer_out', 'bill_payment_out', 'market_purchase_out') then -amount
      else 0
    end
  ), 0)
  from bank_transactions
  where player_id = p_player;
$$;

revoke execute on function bank_balance(uuid) from public, authenticated, anon;

create or replace function market_buy_item(p_listing_id uuid, p_buyer_character_id uuid)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
  v_listing market_listings;
  v_is_open boolean;
  v_seller_player uuid;
  v_seller_balance integer;
begin
  if v_player is null then raise exception 'Not signed in'; end if;

  select is_open into v_is_open from market_settings where id = true;
  if not coalesce(v_is_open, false) then raise exception 'The market is closed'; end if;

  if not exists (select 1 from characters where id = p_buyer_character_id and player_id = v_player) then
    raise exception 'Character not found';
  end if;

  select * into v_listing from market_listings where id = p_listing_id for update;
  if not found then raise exception 'Listing not found'; end if;
  if v_listing.status != 'active' then raise exception 'This listing is no longer available'; end if;
  if v_listing.seller_character_id = p_buyer_character_id then raise exception 'You cannot buy your own listing'; end if;

  if v_listing.seller_character_id is not null then
    select coalesce(sum(delta), 0) into v_seller_balance
      from character_material_ledger(v_listing.seller_character_id)
      where lower(material_name) = lower(v_listing.item_name);
    if v_seller_balance < v_listing.quantity then
      update market_listings set status = 'cancelled' where id = p_listing_id;
      raise exception 'This item is no longer available from the seller';
    end if;
    select player_id into v_seller_player from characters where id = v_listing.seller_character_id;
  end if;

  if bank_balance(v_player) < v_listing.price_coin then
    raise exception 'Insufficient coin';
  end if;

  if v_listing.price_coin > 0 then
    insert into bank_transactions (player_id, type, amount, note, counterparty_id, created_by)
      values (
        v_player, 'market_purchase_out', v_listing.price_coin,
        'Bought ' || v_listing.quantity || 'x ' || v_listing.item_name || ' from ' || coalesce(v_listing.npc_seller_name, 'another player'),
        v_seller_player, v_player
      );

    if v_seller_player is not null then
      insert into bank_transactions (player_id, type, amount, note, counterparty_id, created_by)
        values (
          v_seller_player, 'market_sale_in', v_listing.price_coin,
          'Sold ' || v_listing.quantity || 'x ' || v_listing.item_name || ' at the Market',
          v_player, v_player
        );
    end if;
  end if;

  if v_listing.seller_character_id is not null then
    insert into character_item_transfers (from_character_id, to_character_id, item_name, quantity, note)
      values (v_listing.seller_character_id, p_buyer_character_id, v_listing.item_name, v_listing.quantity, 'Bought at the Market');
  else
    insert into staff_item_grants (character_id, granted_by, item_name, quantity, note)
      values (
        p_buyer_character_id, v_listing.listed_by, v_listing.item_name, v_listing.quantity,
        'Bought from ' || v_listing.npc_seller_name || ' at the Market'
      );
  end if;

  update market_listings
    set status = 'sold', buyer_character_id = p_buyer_character_id, sold_at = now()
    where id = p_listing_id;
end;
$$;

revoke all on function market_buy_item(uuid, uuid) from public, anon;
grant execute on function market_buy_item(uuid, uuid) to authenticated;
