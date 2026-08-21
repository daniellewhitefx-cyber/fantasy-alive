
create or replace function staff_player_characters(p_player_id uuid)
returns table(id uuid, name text) language plpgsql stable security definer
set search_path = public
as $$
begin
  if not fa_is_logistics_or_admin() then raise exception 'Staff only'; end if;
  return query select c.id, c.name from characters c where c.player_id = p_player_id order by c.name;
end;
$$;

create or replace function staff_update_registration(
  p_id uuid,
  p_who text,
  p_character_id uuid,
  p_character_name text,
  p_pass_name text,
  p_pass_price integer,
  p_combat_status text,
  p_days_attending text[],
  p_meal_name text,
  p_meal_price integer,
  p_single_meal_choice text,
  p_meal_slots jsonb,
  p_total integer,
  p_payment_method text,
  p_allergy_notes text,
  p_disability_notes text
)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  v_reg registrations%rowtype;
  v_character_name text;
begin
  if not fa_is_logistics_or_admin() then raise exception 'Staff only'; end if;
  if p_who not in ('character', 'cast', 'townsperson') then raise exception 'Invalid registration type'; end if;

  select * into v_reg from registrations where id = p_id;
  if not found then raise exception 'Registration not found'; end if;

  if p_who = 'character' then
    select name into v_character_name from characters where id = p_character_id and player_id = v_reg.player_id;
    if v_character_name is null then raise exception 'That character does not belong to this player'; end if;
  else
    v_character_name := coalesce(nullif(trim(p_character_name), ''), initcap(p_who));
  end if;

  update registrations set
    who = p_who,
    character_id = case when p_who = 'character' then p_character_id else null end,
    character_name = v_character_name,
    pass_name = nullif(trim(coalesce(p_pass_name, '')), ''),
    pass_price = coalesce(p_pass_price, 0),
    combat_status = nullif(trim(coalesce(p_combat_status, '')), ''),
    days_attending = coalesce(p_days_attending, '{}'),
    meal_name = nullif(trim(coalesce(p_meal_name, '')), ''),
    meal_price = coalesce(p_meal_price, 0),
    single_meal_choice = nullif(trim(coalesce(p_single_meal_choice, '')), ''),
    meal_slots = coalesce(p_meal_slots, '{}'::jsonb),
    total = coalesce(p_total, 0),
    payment_method = nullif(trim(coalesce(p_payment_method, '')), ''),
    allergy_notes = nullif(trim(coalesce(p_allergy_notes, '')), ''),
    disability_notes = nullif(trim(coalesce(p_disability_notes, '')), '')
  where id = p_id;
end;
$$;

create or replace function staff_delete_registration(p_id uuid)
returns boolean language plpgsql security definer
set search_path = public
as $$
declare
  v_staff uuid := auth.uid();
  v_reg registrations%rowtype;
  v_credited boolean := false;
begin
  if not fa_is_logistics_or_admin() then raise exception 'Staff only'; end if;

  select * into v_reg from registrations where id = p_id;
  if not found then raise exception 'Registration not found'; end if;

  delete from registrations where id = p_id;

  if v_reg.payment_method = 'Online (paid)' then
    insert into flex_pass_transactions (player_id, pass_id, event_credits, note, created_by)
      values (v_reg.player_id, 'refund', 1, 'Registration for ' || v_reg.event_slug || ' cancelled by staff, paid online -- 1 event credit issued', v_staff);
    v_credited := true;
  end if;

  return v_credited;
end;
$$;
