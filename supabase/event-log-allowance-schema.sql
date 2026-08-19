-- Social Class allowance: characters of higher standing (nobility and up)
-- receive a Copper stipend each event, based on the old site's per-class
-- "upkeep" reference numbers (characters_charactersocialclass.upkeep in
-- the legacy database). Granted automatically, once per character per
-- event, the first time they visit Current Event while registered.

create table if not exists social_class_allowances (
  social_class text primary key,
  copper integer not null check (copper >= 0)
);

insert into social_class_allowances (social_class, copper) values
  ('Vagabond', 0),
  ('Serf', 5),
  ('Guard', 0),
  ('Apprentice', 5),
  ('Yeoman', 10),
  ('Yeoman (Well Fed!)', 5),
  ('Citizen', 10),
  ('Ward', 0),
  ('Knight', 20),
  ('Magistrate', 20),
  ('Lord', 20),
  ('Lady', 20),
  ('Baron', 50),
  ('Baroness', 50),
  ('Duke', 100),
  ('Duchess', 100),
  ('King', 1000),
  ('Queen', 1000)
on conflict (social_class) do update set copper = excluded.copper;

alter table social_class_allowances enable row level security;

drop policy if exists "Anyone can read allowance amounts" on social_class_allowances;
create policy "Anyone can read allowance amounts"
  on social_class_allowances for select
  using (true);

grant select on social_class_allowances to authenticated;

create table if not exists event_log_allowance_claims (
  character_id uuid not null references characters(id) on delete cascade,
  event_slug text not null,
  copper integer not null,
  created_at timestamptz not null default now(),
  primary key (character_id, event_slug)
);

alter table event_log_allowance_claims enable row level security;

drop policy if exists "Players see their own allowance claims" on event_log_allowance_claims;
create policy "Players see their own allowance claims"
  on event_log_allowance_claims for select
  using (
    character_id in (select id from characters where player_id = auth.uid())
    or fa_is_logistics_or_admin()
  );

-- Grants this character's Social Class allowance for this event, once.
-- Safe to call every time the player visits Current Event -- returns the
-- Copper amount only the first time (when it actually deposits it),
-- null on every later call for the same character/event.
create or replace function event_log_claim_allowance(p_event_slug text, p_character_id uuid)
returns integer language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
  v_social_class text;
  v_copper integer;
begin
  if v_player is null then raise exception 'Not signed in'; end if;
  select social_class into v_social_class from characters
    where id = p_character_id and player_id = v_player;
  if not found then raise exception 'Character not found'; end if;

  select copper into v_copper from social_class_allowances where social_class = v_social_class;
  v_copper := coalesce(v_copper, 0);

  insert into event_log_allowance_claims (character_id, event_slug, copper)
    values (p_character_id, p_event_slug, v_copper)
  on conflict (character_id, event_slug) do nothing;
  if not found then return null; end if;

  if v_copper > 0 then
    insert into bank_transactions (player_id, type, amount, note)
      values (v_player, 'log_bank', v_copper, v_social_class || ' allowance (' || p_event_slug || ')');
  end if;

  return v_copper;
end;
$$;
