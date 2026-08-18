-- Emergency Contact Form: one row per player, upsertable, so a player
-- can review and update their info before each event. Logistics needs
-- to be able to look this up in a real emergency, so it's readable by
-- fa_is_logistics_or_admin() in addition to the player themselves.

create table if not exists emergency_contact_forms (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references auth.users(id) on delete cascade unique,
  full_name text not null,
  characters text,
  home_address text not null,
  city text not null,
  postal_code text not null,
  phone text not null,
  contact1_name text not null,
  contact1_phone text not null,
  contact1_relationship text not null,
  contact1_email text,
  contact2_name text,
  contact2_phone text,
  contact2_relationship text,
  contact2_email text,
  medical_conditions text,
  other_notes text,
  signature_name text not null,
  signed_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

alter table emergency_contact_forms enable row level security;
drop policy if exists "Players see their own emergency contact form" on emergency_contact_forms;
create policy "Players see their own emergency contact form"
  on emergency_contact_forms for select
  using (player_id = auth.uid() or fa_is_logistics_or_admin());

grant select on emergency_contact_forms to authenticated;

create or replace function emergency_contact_save(
  p_full_name text,
  p_characters text,
  p_home_address text,
  p_city text,
  p_postal_code text,
  p_phone text,
  p_contact1_name text,
  p_contact1_phone text,
  p_contact1_relationship text,
  p_contact1_email text,
  p_contact2_name text,
  p_contact2_phone text,
  p_contact2_relationship text,
  p_contact2_email text,
  p_medical_conditions text,
  p_other_notes text,
  p_signature_name text
)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
begin
  if v_player is null then raise exception 'Not signed in'; end if;
  if coalesce(trim(p_full_name), '') = '' then raise exception 'Name is required'; end if;
  if coalesce(trim(p_home_address), '') = '' then raise exception 'Home address is required'; end if;
  if coalesce(trim(p_city), '') = '' then raise exception 'City is required'; end if;
  if coalesce(trim(p_postal_code), '') = '' then raise exception 'Postal code is required'; end if;
  if coalesce(trim(p_phone), '') = '' then raise exception 'Phone number is required'; end if;
  if coalesce(trim(p_contact1_name), '') = '' then raise exception 'At least one emergency contact is required'; end if;
  if coalesce(trim(p_contact1_phone), '') = '' then raise exception 'Emergency contact phone number is required'; end if;
  if coalesce(trim(p_signature_name), '') = '' then raise exception 'A signature is required'; end if;

  insert into emergency_contact_forms (
    player_id, full_name, characters, home_address, city, postal_code, phone,
    contact1_name, contact1_phone, contact1_relationship, contact1_email,
    contact2_name, contact2_phone, contact2_relationship, contact2_email,
    medical_conditions, other_notes, signature_name, signed_at, updated_at
  ) values (
    v_player, trim(p_full_name), nullif(trim(p_characters), ''), trim(p_home_address), trim(p_city), trim(p_postal_code), trim(p_phone),
    trim(p_contact1_name), trim(p_contact1_phone), trim(p_contact1_relationship), nullif(trim(p_contact1_email), ''),
    nullif(trim(p_contact2_name), ''), nullif(trim(p_contact2_phone), ''), nullif(trim(p_contact2_relationship), ''), nullif(trim(p_contact2_email), ''),
    nullif(trim(p_medical_conditions), ''), nullif(trim(p_other_notes), ''), trim(p_signature_name), now(), now()
  )
  on conflict (player_id) do update set
    full_name = excluded.full_name,
    characters = excluded.characters,
    home_address = excluded.home_address,
    city = excluded.city,
    postal_code = excluded.postal_code,
    phone = excluded.phone,
    contact1_name = excluded.contact1_name,
    contact1_phone = excluded.contact1_phone,
    contact1_relationship = excluded.contact1_relationship,
    contact1_email = excluded.contact1_email,
    contact2_name = excluded.contact2_name,
    contact2_phone = excluded.contact2_phone,
    contact2_relationship = excluded.contact2_relationship,
    contact2_email = excluded.contact2_email,
    medical_conditions = excluded.medical_conditions,
    other_notes = excluded.other_notes,
    signature_name = excluded.signature_name,
    signed_at = now(),
    updated_at = now();
end;
$$;
