create table if not exists registration_noncombat_skills (
  id uuid primary key default gen_random_uuid(),
  registration_id uuid not null references registrations(id) on delete cascade,
  category text not null,
  skill_name text not null,
  focus text,
  level integer not null default 1,
  sp_cost integer not null default 0
);

create index if not exists registration_noncombat_skills_reg_idx on registration_noncombat_skills(registration_id);

alter table registration_noncombat_skills enable row level security;

drop policy if exists "Players and staff see their own registration non-combat skills" on registration_noncombat_skills;
create policy "Players and staff see their own registration non-combat skills"
  on registration_noncombat_skills for select
  using (
    exists (
      select 1 from registrations r
      where r.id = registration_noncombat_skills.registration_id
        and (r.player_id = (select auth.uid()) or fa_is_logistics_or_admin())
    )
  );

grant select on registration_noncombat_skills to authenticated;

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
  v_noncombat_build_saved_at timestamptz;
  v_id uuid;
begin
  if v_player is null then raise exception 'Not signed in'; end if;
  if p_who not in ('character', 'cast', 'townsperson') then raise exception 'Invalid registration type'; end if;
  if coalesce(trim(p_event_slug), '') = '' then raise exception 'Event is required'; end if;

  if p_who = 'character' then
    select name, noncombat_build_saved_at into v_character_name, v_noncombat_build_saved_at
      from characters where id = p_character_id and player_id = v_player;
    if v_character_name is null then raise exception 'Character not found'; end if;
    if p_combat_status = 'Non-Combat' and v_noncombat_build_saved_at is null then
      raise exception 'Set up a Non-Combat Build for this character on the Characters page before registering Non-Combat';
    end if;
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

  delete from registration_noncombat_skills where registration_id = v_id;
  if p_who = 'character' and p_combat_status = 'Non-Combat' then
    insert into registration_noncombat_skills (registration_id, category, skill_name, focus, level, sp_cost)
      select v_id, category, skill_name, focus, level, sp_cost
      from character_noncombat_skills where character_id = p_character_id;
  end if;

  if p_pass_is_flex then
    perform flex_pass_redeem('event');
  end if;
  if p_meal_is_flex then
    perform flex_pass_redeem('meal');
  end if;

  return v_id;
end;
$$;
