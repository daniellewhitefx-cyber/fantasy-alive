alter table profiles add column if not exists locked boolean not null default false;
alter table profiles add column if not exists locked_at timestamptz;
alter table profiles add column if not exists locked_reason text;
alter table profiles add column if not exists locked_by uuid references auth.users(id) on delete set null;

create or replace function admin_set_player_locked(p_player_id uuid, p_locked boolean, p_reason text default null)
returns void language plpgsql security definer
set search_path = public
as $$
begin
  if not fa_is_site_admin() then
    raise exception 'Only site admins can lock or unlock accounts';
  end if;

  if p_player_id = auth.uid() and p_locked then
    raise exception 'You cannot lock your own account';
  end if;

  update profiles
  set locked = p_locked,
      locked_at = case when p_locked then now() else null end,
      locked_reason = case when p_locked then p_reason else null end,
      locked_by = case when p_locked then auth.uid() else null end
  where id = p_player_id;
end;
$$;

revoke all on function admin_set_player_locked(uuid, boolean, text) from public, anon;
grant execute on function admin_set_player_locked(uuid, boolean, text) to authenticated;

drop function if exists admin_list_waiver_status();

create function admin_list_waiver_status()
returns table(
  player_id uuid,
  email text,
  display_name text,
  waiver_signed_at timestamptz,
  waiver_legal_name text,
  waiver_signature_name text,
  waiver_guardian_signature_name text,
  contact_updated_at timestamptz,
  contact_full_name text,
  contact_characters text,
  contact_home_address text,
  contact_city text,
  contact_postal_code text,
  contact_phone text,
  contact1_name text,
  contact1_phone text,
  contact1_relationship text,
  contact1_email text,
  contact2_name text,
  contact2_phone text,
  contact2_relationship text,
  contact2_email text,
  medical_conditions text,
  other_notes text,
  locked boolean,
  locked_at timestamptz,
  locked_reason text
) language plpgsql stable security definer
set search_path = public
as $$
begin
  if not fa_is_logistics_or_admin() then
    raise exception 'Staff only';
  end if;

  return query
    select
      u.id,
      u.email::text,
      coalesce(p.display_name, u.raw_user_meta_data ->> 'display_name', u.email)::text,
      lw.signed_at,
      lw.legal_name,
      lw.signature_name,
      lw.guardian_signature_name,
      ecf.updated_at,
      ecf.full_name,
      ecf.characters,
      ecf.home_address,
      ecf.city,
      ecf.postal_code,
      ecf.phone,
      ecf.contact1_name,
      ecf.contact1_phone,
      ecf.contact1_relationship,
      ecf.contact1_email,
      ecf.contact2_name,
      ecf.contact2_phone,
      ecf.contact2_relationship,
      ecf.contact2_email,
      ecf.medical_conditions,
      ecf.other_notes,
      coalesce(p.locked, false),
      p.locked_at,
      p.locked_reason
    from auth.users u
    left join profiles p on p.id = u.id
    left join liability_waivers lw on lw.player_id = u.id
    left join emergency_contact_forms ecf on ecf.player_id = u.id
    order by 3;
end;
$$;

revoke all on function admin_list_waiver_status() from public, anon;
grant execute on function admin_list_waiver_status() to authenticated;
