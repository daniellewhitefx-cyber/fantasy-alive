
create table if not exists character_item_transfers (
  id uuid primary key default gen_random_uuid(),
  from_character_id uuid not null references characters(id) on delete cascade,
  to_character_id uuid not null references characters(id) on delete cascade,
  item_name text not null,
  quantity integer not null check (quantity > 0),
  note text,
  created_at timestamptz not null default now()
);

create index if not exists character_item_transfers_from_idx on character_item_transfers(from_character_id);
create index if not exists character_item_transfers_to_idx on character_item_transfers(to_character_id);

alter table character_item_transfers enable row level security;
drop policy if exists "Players and staff see item transfers" on character_item_transfers;
create policy "Players and staff see item transfers"
  on character_item_transfers for select
  using (
    exists (select 1 from characters c where c.id = from_character_id and c.player_id = (select auth.uid()))
    or exists (select 1 from characters c where c.id = to_character_id and c.player_id = (select auth.uid()))
    or fa_is_logistics_or_admin()
  );

grant select on character_item_transfers to authenticated;

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
  union all
  select item_name, -quantity from shoppe_sales where character_id = p_character_id and from_inventory
  union all
  select item_name, -quantity from character_item_transfers where from_character_id = p_character_id
  union all
  select item_name, quantity from character_item_transfers where to_character_id = p_character_id
$$;

revoke execute on function character_material_ledger(uuid) from public, authenticated, anon;

create or replace function character_send_item(
  p_from_character_id uuid,
  p_to_character_id uuid,
  p_item_name text,
  p_quantity integer,
  p_note text default null
)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
  v_balance integer;
begin
  if v_player is null then raise exception 'Not signed in'; end if;
  if not exists (select 1 from characters where id = p_from_character_id and player_id = v_player) then
    raise exception 'Character not found';
  end if;
  if p_to_character_id is null or p_to_character_id = p_from_character_id then
    raise exception 'Choose a different character to send to';
  end if;
  if not exists (select 1 from characters where id = p_to_character_id) then
    raise exception 'Recipient character not found';
  end if;
  if p_item_name is null or trim(p_item_name) = '' then raise exception 'Item is required'; end if;
  if p_quantity is null or p_quantity <= 0 then raise exception 'Quantity must be greater than 0'; end if;

  select coalesce(sum(delta), 0) into v_balance
    from character_material_ledger(p_from_character_id)
    where lower(material_name) = lower(p_item_name);

  if v_balance < p_quantity then
    raise exception 'Not enough % on hand', p_item_name;
  end if;

  insert into character_item_transfers (from_character_id, to_character_id, item_name, quantity, note)
    values (p_from_character_id, p_to_character_id, trim(p_item_name), p_quantity, nullif(trim(p_note), ''));
end;
$$;

revoke all on function character_send_item(uuid, uuid, text, integer, text) from public, anon;
grant execute on function character_send_item(uuid, uuid, text, integer, text) to authenticated;
