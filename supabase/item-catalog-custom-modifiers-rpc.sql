
drop function if exists logistics_upsert_catalog_item(text, text, text, integer);

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
