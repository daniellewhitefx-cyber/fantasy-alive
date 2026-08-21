create table if not exists character_friends (
  character_id uuid not null references characters(id) on delete cascade,
  friend_character_id uuid not null references characters(id) on delete cascade,
  created_at timestamptz not null default now(),
  primary key (character_id, friend_character_id),
  constraint character_friends_not_self check (character_id <> friend_character_id)
);

alter table character_friends enable row level security;

do $$
begin
  if not exists (
    select 1 from information_schema.columns
    where table_name = 'character_friends' and column_name = 'status'
  ) then
    alter table character_friends add column status text not null default 'pending' check (status in ('pending', 'accepted'));
    update character_friends set status = 'accepted';
  end if;
end $$;

drop policy if exists "Players manage their own characters friends" on character_friends;

drop policy if exists "Players see their own friend rows" on character_friends;
create policy "Players see their own friend rows"
  on character_friends for select
  using (
    character_id in (select id from characters where player_id = (select auth.uid()))
    or friend_character_id in (select id from characters where player_id = (select auth.uid()))
    or fa_is_site_admin()
  );

drop policy if exists "Players send friend requests from their own characters" on character_friends;
create policy "Players send friend requests from their own characters"
  on character_friends for insert
  with check (
    character_id in (select id from characters where player_id = (select auth.uid()))
    and status = 'pending'
  );

drop policy if exists "Recipients accept friend requests" on character_friends;
create policy "Recipients accept friend requests"
  on character_friends for update
  using (
    friend_character_id in (select id from characters where player_id = (select auth.uid()))
    and status = 'pending'
  )
  with check (
    friend_character_id in (select id from characters where player_id = (select auth.uid()))
    and status = 'accepted'
  );

drop policy if exists "Either side can remove a request or friendship" on character_friends;
create policy "Either side can remove a request or friendship"
  on character_friends for delete
  using (
    character_id in (select id from characters where player_id = (select auth.uid()))
    or friend_character_id in (select id from characters where player_id = (select auth.uid()))
    or fa_is_site_admin()
  );
