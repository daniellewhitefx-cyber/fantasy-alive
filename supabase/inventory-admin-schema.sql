-- Lets logistics/site admins grant items directly into a character's
-- inventory, alongside the existing Manage Characters (admin-characters.html)
-- tools for XP/OC. Grants are additive rows in their own table, folded
-- into the same derived material ledger that Shoppe purchases and
-- crafted items already use, so a granted item shows up in the
-- character's normal Inventory/Crafting views with no other changes.

create table if not exists staff_item_grants (
  id uuid primary key default gen_random_uuid(),
  character_id uuid not null references characters(id) on delete cascade,
  granted_by uuid references auth.users(id) on delete set null,
  item_name text not null,
  quantity integer not null check (quantity <> 0),
  note text,
  created_at timestamptz not null default now()
);

create index if not exists staff_item_grants_char_idx on staff_item_grants(character_id);

alter table staff_item_grants enable row level security;
drop policy if exists "Players and staff see item grants" on staff_item_grants;
create policy "Players and staff see item grants"
  on staff_item_grants for select
  using (
    exists (select 1 from characters c where c.id = character_id and c.player_id = auth.uid())
    or fa_is_logistics_or_admin()
  );

grant select on staff_item_grants to authenticated;

-- Extends character_material_ledger (defined in crafting-schema.sql) to
-- also fold in staff-granted items alongside Shoppe purchases and
-- crafted items.
create or replace function character_material_ledger(p_character_id uuid)
returns table(material_name text, delta integer) language sql stable security definer
set search_path = public
as $$
  select item_name, quantity from shoppe_purchases where character_id = p_character_id
  union all
  select item_name, qty_produced from crafting_log where character_id = p_character_id
  union all
  select cmc.material_name, -cmc.quantity from crafting_materials_consumed cmc
    join crafting_log cl on cl.id = cmc.crafting_log_id
    where cl.character_id = p_character_id
  union all
  select item_name, quantity from staff_item_grants where character_id = p_character_id
$$;

revoke execute on function character_material_ledger(uuid) from public, authenticated, anon;

-- Staff-facing equivalent of character_material_inventory (defined in
-- crafting-schema.sql), which only allows a character's own player to
-- view it. This variant is for the Manage Characters admin tool.
create or replace function character_staff_material_inventory(p_character_id uuid)
returns table(material_name text, balance integer) language plpgsql stable security definer
set search_path = public
as $$
begin
  if not fa_is_logistics_or_admin() then
    raise exception 'Not authorized';
  end if;
  return query
    select l.material_name, sum(l.delta)::integer as balance
    from character_material_ledger(p_character_id) l
    group by l.material_name
    having sum(l.delta) > 0
    order by l.material_name;
end;
$$;

revoke all on function character_staff_material_inventory(uuid) from public, anon;
grant execute on function character_staff_material_inventory(uuid) to authenticated;

create or replace function character_staff_grant_item(
  p_character_id uuid, p_item_name text, p_quantity integer, p_note text
)
returns void language plpgsql security definer
set search_path = public
as $$
begin
  if not fa_is_logistics_or_admin() then
    raise exception 'Not authorized';
  end if;
  if p_item_name is null or trim(p_item_name) = '' then raise exception 'Item name is required'; end if;
  if p_quantity is null or p_quantity = 0 then raise exception 'Quantity must be non-zero'; end if;
  if not exists (select 1 from characters where id = p_character_id) then
    raise exception 'Character not found';
  end if;

  insert into staff_item_grants (character_id, granted_by, item_name, quantity, note)
    values (p_character_id, auth.uid(), p_item_name, p_quantity, nullif(trim(p_note), ''));
end;
$$;

revoke all on function character_staff_grant_item(uuid, text, integer, text) from public, anon;
grant execute on function character_staff_grant_item(uuid, text, integer, text) to authenticated;
