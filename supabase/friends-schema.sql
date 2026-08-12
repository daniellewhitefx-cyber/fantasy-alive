create table if not exists character_friends (
  character_id uuid not null references characters(id) on delete cascade,
  friend_character_id uuid not null references characters(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (character_id, friend_character_id),
  constraint character_friends_not_self check (character_id <> friend_character_id)
);

alter table character_friends enable row level security;

drop policy if exists "Players manage their own characters friends" on character_friends;
create policy "Players manage their own characters friends"
  on character_friends for all
  using (
    character_id in (select id from characters where player_id = auth.uid())
    or fa_is_site_admin()
  )
  with check (
    character_id in (select id from characters where player_id = auth.uid())
    or fa_is_site_admin()
  );
