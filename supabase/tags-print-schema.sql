-- Backs the staff "Print Tags" panels on admin-print-sheets.html: a
-- catalog of physical item tag details (the appraisal price code shown on
-- a tag, plus which modifier line it prints with) and fulfillment of
-- player-submitted tag requests (character_tag_requests, already defined
-- in inventory-schema.sql). Requires permissions-schema.sql
-- (fa_is_logistics_or_admin) and inventory-schema.sql
-- (character_tag_requests) to already exist.

create table if not exists item_catalog (
  id uuid primary key default gen_random_uuid(),
  item_name text not null,
  code text,
  modifier_type text not null default 'none' check (modifier_type in ('none', 'shatter', 'uses')),
  use_count integer,
  -- Richer modifier lines than modifier_type/use_count can express (custom
  -- labels, multiple lines per item, e.g. "Shattered" + "Resist Corrode
  -- Used"), as imported from the legacy tag sheet: [{"label": "...",
  -- "count": N}], where count 0 means a write-in blank rather than
  -- checkboxes. Printed instead of modifier_type/use_count when present;
  -- items added by hand through the staff UI still use the simpler pair.
  modifiers jsonb,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists item_catalog_name_uidx on item_catalog (lower(item_name));

alter table item_catalog enable row level security;
drop policy if exists "Staff see item catalog" on item_catalog;
create policy "Staff see item catalog"
  on item_catalog for select
  using (fa_is_logistics_or_admin());

grant select on item_catalog to authenticated;

-- Adds or updates a catalog entry by item name (case-insensitive), so the
-- same physical item always prints with the same appraisal code and
-- modifier style, while staff can still edit either at any time.
-- p_modifiers carries the flexible custom modifier-line array a staffer
-- builds on a Custom Tag (label + box count per line, count 0 = write-in
-- blank); when provided it takes priority over modifier_type/use_count at
-- print time, same as the imported legacy modifier lines.
create or replace function logistics_upsert_catalog_item(
  p_item_name text, p_code text, p_modifier_type text, p_use_count integer, p_modifiers jsonb default null
)
returns uuid language plpgsql security definer
set search_path = public
as $$
declare
  v_id uuid;
begin
  if not fa_is_logistics_or_admin() then
    raise exception 'Staff only';
  end if;
  if p_item_name is null or trim(p_item_name) = '' then raise exception 'Item name is required'; end if;
  if p_modifier_type not in ('none', 'shatter', 'uses') then raise exception 'Invalid modifier type'; end if;
  if p_modifier_type = 'uses' and (p_use_count is null or p_use_count < 1) then
    raise exception 'Number of uses is required for a multi-use item';
  end if;

  insert into item_catalog (item_name, code, modifier_type, use_count, modifiers, created_by)
    values (
      trim(p_item_name),
      nullif(trim(p_code), ''),
      p_modifier_type,
      case when p_modifier_type = 'uses' then p_use_count else null end,
      p_modifiers,
      auth.uid()
    )
  on conflict (lower(item_name)) do update set
    code = excluded.code,
    modifier_type = excluded.modifier_type,
    use_count = excluded.use_count,
    modifiers = excluded.modifiers,
    updated_at = now()
  returning id into v_id;

  return v_id;
end;
$$;

revoke all on function logistics_upsert_catalog_item(text, text, text, integer, jsonb) from public, anon;
grant execute on function logistics_upsert_catalog_item(text, text, text, integer, jsonb) to authenticated;

-- Marks a pending tag request as fulfilled once its physical tag has been
-- printed and handed off.
create or replace function logistics_fulfill_tag_request(p_request_id uuid)
returns void language plpgsql security definer
set search_path = public
as $$
begin
  if not fa_is_logistics_or_admin() then
    raise exception 'Staff only';
  end if;

  update character_tag_requests set status = 'fulfilled'
    where id = p_request_id and status = 'pending';

  if not found then
    raise exception 'Tag request not found or already handled';
  end if;
end;
$$;

revoke all on function logistics_fulfill_tag_request(uuid) from public, anon;
grant execute on function logistics_fulfill_tag_request(uuid) to authenticated;

-- Every pending tag request, with the player/character names resolved and
-- the matching catalog entry (appraisal code + modifier style) joined in,
-- ordered by player so a printed sheet keeps each player's tags together.
-- Dropped first since adding the modifiers column changes the function's
-- return type, which create or replace can't do in place.
drop function if exists logistics_list_pending_tag_requests();
create or replace function logistics_list_pending_tag_requests()
returns table(
  id uuid,
  player_display_name text,
  character_name text,
  item_name text,
  quantity integer,
  event_slug text,
  created_at timestamptz,
  code text,
  modifier_type text,
  use_count integer,
  modifiers jsonb
) language plpgsql stable security definer
set search_path = public
as $$
begin
  if not fa_is_logistics_or_admin() then
    raise exception 'Staff only';
  end if;

  return query
    select
      r.id,
      coalesce(p.display_name, u.raw_user_meta_data ->> 'display_name', u.email)::text,
      c.name,
      r.item_name,
      r.quantity,
      r.event_slug,
      r.created_at,
      ic.code,
      coalesce(ic.modifier_type, 'none'),
      ic.use_count,
      ic.modifiers
    from character_tag_requests r
    join characters c on c.id = r.character_id
    join auth.users u on u.id = r.player_id
    left join profiles p on p.id = r.player_id
    left join item_catalog ic on lower(ic.item_name) = lower(r.item_name)
    where r.status = 'pending'
    order by coalesce(p.display_name, u.raw_user_meta_data ->> 'display_name', u.email), c.name, r.item_name;
end;
$$;

revoke all on function logistics_list_pending_tag_requests() from public, anon;
grant execute on function logistics_list_pending_tag_requests() to authenticated;
