-- Event registration, moved off the external Google Sheet (see
-- js/registration-status.js's old FA_REGISTRATION_ENDPOINT) and onto
-- Supabase. Registering is still a one-shot action per player per
-- event (no self-serve edit -- same limitation the Sheet had), but now
-- lives alongside everything else the site already tracks, keyed by
-- character_id instead of fragile email/character-name string
-- matching. Requires characters-schema.sql, permissions-schema.sql
-- (fa_is_logistics_or_admin), and flex-passes-schema.sql
-- (flex_pass_redeem) to already exist.

create table if not exists registrations (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references auth.users(id) on delete cascade,
  event_slug text not null,
  who text not null check (who in ('character', 'cast', 'townsperson')),
  character_id uuid references characters(id) on delete set null,
  character_name text not null,
  pass_id text,
  pass_name text,
  pass_price integer not null default 0,
  combat_status text,
  days_attending text[] not null default '{}',
  meal_name text,
  meal_price integer not null default 0,
  single_meal_choice text,
  meal_slots jsonb not null default '{}'::jsonb,
  total integer not null default 0,
  payment_method text,
  allergy_notes text,
  disability_notes text,
  created_at timestamptz not null default now(),
  unique (player_id, event_slug)
);

create index if not exists registrations_event_idx on registrations(event_slug);

alter table registrations enable row level security;

drop policy if exists "Players and staff see registrations" on registrations;
create policy "Players and staff see registrations"
  on registrations for select
  using (player_id = auth.uid() or fa_is_logistics_or_admin());

grant select on registrations to authenticated;

create or replace function register_for_event(
  p_event_slug text,
  p_who text,
  p_character_id uuid,
  p_character_name text,
  p_pass_id text,
  p_pass_name text,
  p_pass_price integer,
  p_pass_is_flex boolean,
  p_combat_status text,
  p_days_attending text[],
  p_meal_name text,
  p_meal_price integer,
  p_meal_is_flex boolean,
  p_single_meal_choice text,
  p_meal_slots jsonb,
  p_total integer,
  p_payment_method text,
  p_allergy_notes text,
  p_disability_notes text
)
returns uuid language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
  v_character_name text;
  v_id uuid;
begin
  if v_player is null then raise exception 'Not signed in'; end if;
  if p_who not in ('character', 'cast', 'townsperson') then raise exception 'Invalid registration type'; end if;
  if coalesce(trim(p_event_slug), '') = '' then raise exception 'Event is required'; end if;

  if p_who = 'character' then
    select name into v_character_name from characters where id = p_character_id and player_id = v_player;
    if v_character_name is null then raise exception 'Character not found'; end if;
  else
    v_character_name := coalesce(nullif(trim(p_character_name), ''), initcap(p_who));
  end if;

  insert into registrations (
    player_id, event_slug, who, character_id, character_name,
    pass_id, pass_name, pass_price, combat_status, days_attending,
    meal_name, meal_price, single_meal_choice, meal_slots,
    total, payment_method, allergy_notes, disability_notes
  ) values (
    v_player, p_event_slug, p_who, case when p_who = 'character' then p_character_id else null end, v_character_name,
    p_pass_id, p_pass_name, coalesce(p_pass_price, 0), p_combat_status, coalesce(p_days_attending, '{}'),
    p_meal_name, coalesce(p_meal_price, 0), p_single_meal_choice, coalesce(p_meal_slots, '{}'::jsonb),
    coalesce(p_total, 0), p_payment_method, nullif(trim(coalesce(p_allergy_notes, '')), ''), nullif(trim(coalesce(p_disability_notes, '')), '')
  )
  on conflict (player_id, event_slug) do update set
    who = excluded.who, character_id = excluded.character_id, character_name = excluded.character_name,
    pass_id = excluded.pass_id, pass_name = excluded.pass_name, pass_price = excluded.pass_price,
    combat_status = excluded.combat_status, days_attending = excluded.days_attending,
    meal_name = excluded.meal_name, meal_price = excluded.meal_price,
    single_meal_choice = excluded.single_meal_choice, meal_slots = excluded.meal_slots,
    total = excluded.total, payment_method = excluded.payment_method,
    allergy_notes = excluded.allergy_notes, disability_notes = excluded.disability_notes
  returning id into v_id;

  if p_pass_is_flex then
    perform flex_pass_redeem('event');
  end if;
  if p_meal_is_flex then
    perform flex_pass_redeem('meal');
  end if;

  return v_id;
end;
$$;

create or replace function my_event_registration(p_event_slug text)
returns setof registrations language sql stable security definer
set search_path = public
as $$
  select * from registrations where player_id = auth.uid() and event_slug = p_event_slug;
$$;

-- Semi-public roster: who's registered and as what, for the currently
-- signed-in player to find their own entry and for the Event Info tab's
-- character splash roster / cast count. Deliberately excludes payment
-- and logistics-only fields (allergy/disability notes, pass/meal
-- pricing) -- those stay staff-only, see staff_event_registrations.
create or replace function event_roster(p_event_slug text)
returns table(player_id uuid, who text, character_id uuid, character_name text)
language plpgsql stable security definer
set search_path = public
as $$
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  return query
    select r.player_id, r.who, r.character_id, r.character_name
    from registrations r
    where r.event_slug = p_event_slug;
end;
$$;

create or replace function staff_event_registrations(p_event_slug text)
returns table(
  id uuid, player_id uuid, player_name text, player_email text,
  who text, character_id uuid, character_name text,
  pass_name text, pass_price integer, combat_status text, days_attending text[],
  meal_name text, meal_price integer, single_meal_choice text, meal_slots jsonb,
  total integer, payment_method text, allergy_notes text, disability_notes text,
  created_at timestamptz
)
language plpgsql stable security definer
set search_path = public
as $$
begin
  if not fa_is_logistics_or_admin() then raise exception 'Staff only'; end if;

  return query
    select
      r.id, r.player_id, coalesce(p.display_name, u.raw_user_meta_data ->> 'display_name', u.email)::text, u.email::text,
      r.who, r.character_id, r.character_name,
      r.pass_name, r.pass_price, r.combat_status, r.days_attending,
      r.meal_name, r.meal_price, r.single_meal_choice, r.meal_slots,
      r.total, r.payment_method, r.allergy_notes, r.disability_notes,
      r.created_at
    from registrations r
    join auth.users u on u.id = r.player_id
    left join profiles p on p.id = r.player_id
    where r.event_slug = p_event_slug
    order by r.character_name;
end;
$$;
