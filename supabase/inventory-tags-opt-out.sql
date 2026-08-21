
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
