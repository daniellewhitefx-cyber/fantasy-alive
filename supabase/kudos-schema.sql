create table if not exists kudos (
  id uuid primary key default gen_random_uuid(),
  from_player_id uuid not null references auth.users(id) on delete cascade,
  to_character_id uuid references characters(id) on delete cascade,
  message text not null,
  created_at timestamptz not null default now()
);

-- Kudos can go to a PC (to_character_id) or a Cast member without a
-- character (to_player_id), never both, so Cast can receive kudos too.
alter table kudos alter column to_character_id drop not null;
alter table kudos add column if not exists to_player_id uuid references auth.users(id) on delete cascade;
alter table kudos drop constraint if exists kudos_target_check;
alter table kudos add constraint kudos_target_check check (
  (to_character_id is not null and to_player_id is null) or
  (to_character_id is null and to_player_id is not null)
);

alter table kudos enable row level security;

drop policy if exists "Players see kudos they gave" on kudos;
create policy "Players see kudos they gave"
  on kudos for select
  using (from_player_id = auth.uid() or fa_is_site_admin());

drop policy if exists "Players give kudos" on kudos;
create policy "Players give kudos"
  on kudos for insert
  with check (from_player_id = auth.uid());
