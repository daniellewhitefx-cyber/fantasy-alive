create table if not exists kudos (
  id uuid primary key default gen_random_uuid(),
  from_player_id uuid not null references auth.users(id) on delete cascade,
  to_character_id uuid not null references characters(id) on delete cascade,
  message text not null,
  created_at timestamptz not null default now()
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
