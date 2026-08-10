create table if not exists auction_items (
  id uuid primary key default gen_random_uuid(),
  name text not null,
  description text,
  image_url text,
  starting_bid numeric(10,2) not null default 0 check (starting_bid >= 0),
  min_increment numeric(10,2) not null default 1 check (min_increment > 0),
  status text not null default 'draft' check (status in ('draft', 'live', 'closed')),
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now(),
  closed_at timestamptz,
  winner_player_id uuid references auth.users(id),
  winning_bid_amount numeric(10,2),
  payment_status text not null default 'unpaid' check (payment_status in ('unpaid', 'paid_online', 'paid_at_event'))
);

alter table auction_items add column if not exists ends_at timestamptz;

create unique index if not exists auction_items_one_live on auction_items ((true)) where status = 'live';

alter table auction_items enable row level security;
drop policy if exists "Auction items are publicly readable" on auction_items;
create policy "Auction items are publicly readable"
  on auction_items for select
  using (status in ('live', 'closed'));

drop policy if exists "Auction staff see everything including drafts" on auction_items;
create policy "Auction staff see everything including drafts"
  on auction_items for select
  using ((auth.jwt() -> 'app_metadata' ->> 'auction_staff')::boolean is true or fa_is_site_admin());

create table if not exists auction_bids (
  id uuid primary key default gen_random_uuid(),
  item_id uuid not null references auction_items(id) on delete cascade,
  player_id uuid not null references auth.users(id),
  amount numeric(10,2) not null check (amount > 0),
  created_at timestamptz not null default now()
);

create index if not exists auction_bids_item_idx on auction_bids(item_id, amount desc);
create index if not exists auction_bids_player_idx on auction_bids(player_id, created_at desc);

alter table auction_bids enable row level security;
drop policy if exists "Bids are publicly readable" on auction_bids;
create policy "Bids are publicly readable"
  on auction_bids for select
  using (true);

create or replace function auction_create_item(
  p_name text,
  p_description text,
  p_image_url text,
  p_starting_bid numeric,
  p_min_increment numeric,
  p_ends_at timestamptz default null
)
returns uuid language plpgsql security definer as $$
declare
  v_staff uuid := auth.uid();
  v_name text := trim(coalesce(p_name, ''));
  v_id uuid;
begin
  if not (coalesce((auth.jwt() -> 'app_metadata' ->> 'auction_staff')::boolean, false) or fa_is_site_admin()) then
    raise exception 'Staff only';
  end if;
  if v_name = '' then raise exception 'Item name cannot be empty'; end if;
  if p_starting_bid is null or p_starting_bid < 0 then raise exception 'Starting bid must be zero or more'; end if;
  if p_min_increment is null or p_min_increment <= 0 then raise exception 'Minimum increment must be positive'; end if;
  if p_ends_at is not null and p_ends_at <= now() then raise exception 'End time must be in the future'; end if;

  insert into auction_items (name, description, image_url, starting_bid, min_increment, created_by, ends_at)
    values (v_name, nullif(trim(coalesce(p_description, '')), ''), nullif(trim(coalesce(p_image_url, '')), ''), p_starting_bid, p_min_increment, v_staff, p_ends_at)
    returning id into v_id;

  return v_id;
end;
$$;

create or replace function auction_go_live(p_item_id uuid)
returns void language plpgsql security definer as $$
begin
  if not (coalesce((auth.jwt() -> 'app_metadata' ->> 'auction_staff')::boolean, false) or fa_is_site_admin()) then
    raise exception 'Staff only';
  end if;

  if exists (select 1 from auction_items where status = 'live' and id != p_item_id) then
    raise exception 'Another item is already live. Close it first.';
  end if;

  update auction_items set status = 'live'
    where id = p_item_id and status = 'draft';

  if not found then raise exception 'Item not found or not in draft'; end if;
end;
$$;

create or replace function auction_close(p_item_id uuid)
returns void language plpgsql security definer as $$
declare
  v_top auction_bids;
  v_item auction_items;
  v_is_staff boolean := coalesce((auth.jwt() -> 'app_metadata' ->> 'auction_staff')::boolean, false) or fa_is_site_admin();
begin
  select * into v_item from auction_items where id = p_item_id;
  if not found then raise exception 'Item not found'; end if;
  if v_item.status != 'live' then raise exception 'Item is not live'; end if;

  if not v_is_staff and (v_item.ends_at is null or now() < v_item.ends_at) then
    raise exception 'Staff only';
  end if;

  select * into v_top from auction_bids
    where item_id = p_item_id
    order by amount desc, created_at asc
    limit 1;

  update auction_items
    set status = 'closed',
        closed_at = now(),
        winner_player_id = v_top.player_id,
        winning_bid_amount = v_top.amount
    where id = p_item_id;
end;
$$;

create or replace function auction_place_bid(p_item_id uuid, p_amount numeric)
returns void language plpgsql security definer as $$
declare
  v_player uuid := auth.uid();
  v_item auction_items;
  v_highest numeric;
  v_min_next numeric;
  v_last_bid_at timestamptz;
begin
  if v_player is null then raise exception 'Not signed in'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Bid must be a positive amount'; end if;

  select * into v_item from auction_items where id = p_item_id for update;
  if not found then raise exception 'Item not found'; end if;
  if v_item.status != 'live' then raise exception 'This item is not open for bidding'; end if;
  if v_item.ends_at is not null and now() >= v_item.ends_at then raise exception 'This auction has ended'; end if;

  select max(amount) into v_highest from auction_bids where item_id = p_item_id;
  v_min_next := coalesce(v_highest, v_item.starting_bid - v_item.min_increment) + v_item.min_increment;

  if p_amount < v_min_next then
    raise exception 'Bid must be at least %', to_char(v_min_next, 'FM999999990.00');
  end if;

  select max(created_at) into v_last_bid_at from auction_bids where player_id = v_player;
  if v_last_bid_at is not null and v_last_bid_at > now() - interval '1 hour' then
    raise exception 'You can bid again at %', to_char(v_last_bid_at + interval '1 hour', 'HH12:MI AM');
  end if;

  insert into auction_bids (item_id, player_id, amount) values (p_item_id, v_player, p_amount);
end;
$$;

create or replace function auction_staff_mark_paid(p_item_id uuid)
returns void language plpgsql security definer as $$
begin
  if not (coalesce((auth.jwt() -> 'app_metadata' ->> 'auction_staff')::boolean, false) or fa_is_site_admin()) then
    raise exception 'Staff only';
  end if;

  update auction_items set payment_status = 'paid_at_event'
    where id = p_item_id and status = 'closed' and winner_player_id is not null;

  if not found then raise exception 'Item not found or has no winner'; end if;
end;
$$;

create or replace function auction_winner_mark_pay_at_event(p_item_id uuid)
returns void language plpgsql security definer as $$
declare
  v_player uuid := auth.uid();
begin
  if v_player is null then raise exception 'Not signed in'; end if;

  update auction_items set payment_status = 'paid_at_event'
    where id = p_item_id and status = 'closed' and winner_player_id = v_player and payment_status = 'unpaid';

  if not found then raise exception 'This is not an unpaid win of yours'; end if;
end;
$$;

create or replace function auction_winner_mark_paid_online(p_item_id uuid)
returns void language plpgsql security definer as $$
declare
  v_player uuid := auth.uid();
begin
  if v_player is null then raise exception 'Not signed in'; end if;

  update auction_items set payment_status = 'paid_online'
    where id = p_item_id and status = 'closed' and winner_player_id = v_player and payment_status = 'unpaid';

  if not found then raise exception 'This is not an unpaid win of yours'; end if;
end;
$$;

grant select on auction_items to authenticated;
grant select on auction_bids to authenticated;
