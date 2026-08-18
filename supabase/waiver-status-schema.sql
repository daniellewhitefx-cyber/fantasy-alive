-- Backs the staff "Waivers & Contacts" page (admin-waivers.html): lets
-- Logistics see who has signed their liability waiver and who has an
-- emergency contact form on file, plus the actual contact details for
-- use in a real emergency. liability_waivers and emergency_contact_forms
-- (see liability-waiver-schema.sql / emergency-contact-schema.sql) already
-- have RLS policies allowing fa_is_logistics_or_admin() to select them
-- directly, but resolving every player's email/display name requires
-- reading auth.users, which client-side RLS can't do -- so this is one
-- security definer RPC that joins everything server-side in one call.
-- Requires permissions-schema.sql (fa_is_logistics_or_admin) to already
-- exist.

create or replace function admin_list_waiver_status()
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
  other_notes text
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
      ecf.other_notes
    from auth.users u
    left join profiles p on p.id = u.id
    left join liability_waivers lw on lw.player_id = u.id
    left join emergency_contact_forms ecf on ecf.player_id = u.id
    order by 3;
end;
$$;

revoke all on function admin_list_waiver_status() from public, anon;
grant execute on function admin_list_waiver_status() to authenticated;
