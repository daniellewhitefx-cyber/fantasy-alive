-- Character Inventory: a read view of a character's material/item ledger
-- (character_material_inventory, defined in crafting-schema.sql, already
-- combines Shoppe purchases and crafted items) plus the ability to
-- request that logistics prepare a physical tag for an on-hand item, to
-- be picked up at the next event. Requesting a tag doesn't change the
-- digital ledger -- it's just a fulfillment queue for staff.

create table if not exists character_tag_requests (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references auth.users(id) on delete cascade,
  character_id uuid not null references characters(id) on delete cascade,
  item_name text not null,
  quantity integer not null default 1 check (quantity > 0),
  event_slug text not null,
  status text not null default 'pending' check (status in ('pending', 'fulfilled', 'cancelled')),
  created_at timestamptz not null default now()
);

create index if not exists character_tag_requests_char_idx on character_tag_requests(character_id, status);

alter table character_tag_requests enable row level security;
drop policy if exists "Players see their own tag requests" on character_tag_requests;
create policy "Players see their own tag requests"
  on character_tag_requests for select
  using (player_id = auth.uid() or fa_is_logistics_or_admin());

grant select on character_tag_requests to authenticated;

create or replace function character_request_tag(
  p_character_id uuid,
  p_item_name text,
  p_quantity integer,
  p_event_slug text
)
returns uuid language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
  v_id uuid;
begin
  if v_player is null then raise exception 'Not signed in'; end if;
  if p_quantity is null or p_quantity < 1 then raise exception 'Quantity must be at least 1'; end if;
  if p_item_name is null or trim(p_item_name) = '' then raise exception 'Item name is required'; end if;
  if p_event_slug is null or trim(p_event_slug) = '' then raise exception 'Event is required'; end if;

  if not exists (select 1 from characters where id = p_character_id and player_id = v_player) then
    raise exception 'Character not found';
  end if;

  if exists (
    select 1 from character_tag_requests
    where character_id = p_character_id and status = 'pending' and lower(item_name) = lower(p_item_name)
  ) then
    raise exception 'A tag for this item has already been requested';
  end if;

  insert into character_tag_requests (player_id, character_id, item_name, quantity, event_slug)
    values (v_player, p_character_id, p_item_name, p_quantity, p_event_slug)
    returning id into v_id;

  return v_id;
end;
$$;

create or replace function character_cancel_tag_request(p_request_id uuid)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
begin
  if v_player is null then raise exception 'Not signed in'; end if;

  if not exists (select 1 from character_tag_requests where id = p_request_id and player_id = v_player) then
    raise exception 'Tag request not found';
  end if;

  delete from character_tag_requests where id = p_request_id;
end;
$$;
