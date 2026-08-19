-- Lets staff save a completely custom tag (with flexible, custom-labeled
-- modifier lines, not just the Shattered/Uses pair) to the catalog for
-- reuse from the new Custom Tag panel on admin-print-tags.html.
--
-- Extends logistics_upsert_catalog_item with an optional p_modifiers jsonb
-- array. Adding a parameter to a function does NOT replace it in place --
-- Postgres treats the old and new argument lists as different overloads,
-- so the old 4-argument version has to be dropped first or both would
-- exist side by side (confirmed locally: calling with 4 args became
-- ambiguous between the two once the 5-arg version was added without a
-- drop).

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
