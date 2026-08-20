-- Flips Inventory tag requests from opt-in to opt-out: previously a
-- player had to click "Receive Tag at Next Event" per item to ask for
-- one; now every on-hand item is auto-queued for a tag the moment they
-- open Inventory, and declining an item is the explicit action instead.
-- Requires inventory-schema.sql to already exist.

-- Dedupe first so the new unique index can be created: keep the most
-- recently created row per (character, item, event).
delete from character_tag_requests t
  using character_tag_requests newer
  where t.character_id = newer.character_id
    and lower(t.item_name) = lower(newer.item_name)
    and t.event_slug = newer.event_slug
    and (
      newer.created_at > t.created_at
      or (newer.created_at = t.created_at and newer.id > t.id)
    );

create unique index if not exists character_tag_requests_char_item_event_uidx
  on character_tag_requests (character_id, lower(item_name), event_slug);

-- Requesting a tag is now an upsert: a fresh item gets a new pending
-- row, an item the player previously declined gets flipped back to
-- pending (with whatever quantity is asked for now) instead of failing
-- with "already requested".
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

  insert into character_tag_requests (player_id, character_id, item_name, quantity, event_slug, status)
    values (v_player, p_character_id, trim(p_item_name), p_quantity, p_event_slug, 'pending')
  on conflict (character_id, lower(item_name), event_slug) do update set
    quantity = excluded.quantity,
    status = 'pending',
    player_id = excluded.player_id
  returning id into v_id;

  return v_id;
end;
$$;

-- Declining a tag is now a soft cancel (not a delete), so it sticks --
-- re-opening Inventory won't silently re-request something the player
-- already turned down.
create or replace function character_cancel_tag_request(p_request_id uuid)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
begin
  if v_player is null then raise exception 'Not signed in'; end if;

  update character_tag_requests set status = 'cancelled'
    where id = p_request_id and player_id = v_player and status = 'pending';

  if not found then raise exception 'Tag request not found'; end if;
end;
$$;

-- Auto-queues a tag request for every on-hand inventory item that
-- doesn't already have a request (of any status) for this event, so a
-- player who never visits Inventory still gets their tags queued by
-- default. Called from the Inventory page on load; safe to call
-- repeatedly since it only fills in the gaps left by items that don't
-- have a request yet -- it never touches one a player already decided
-- on, whether that's a pending request or a decline.
create or replace function character_ensure_tag_requests(p_character_id uuid, p_event_slug text)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
begin
  if v_player is null then raise exception 'Not signed in'; end if;
  if p_event_slug is null or trim(p_event_slug) = '' then raise exception 'Event is required'; end if;
  if not exists (select 1 from characters where id = p_character_id and player_id = v_player) then
    raise exception 'Character not found';
  end if;

  insert into character_tag_requests (player_id, character_id, item_name, quantity, event_slug, status)
  select v_player, p_character_id, inv.material_name, inv.balance, p_event_slug, 'pending'
    from character_material_inventory(p_character_id) inv
  on conflict (character_id, lower(item_name), event_slug) do nothing;
end;
$$;
