-- Per-event Luxuries checklist. The old site tracked Luxuries (labs,
-- forges, a horse, ammunition, bandages, etc.) as yes/no boxes a
-- character checked off each event they attended, not as a one-time
-- purchase -- there's no coin transaction to reconcile here, just
-- whether the box is checked for this character at this event.

create table if not exists event_log_luxuries (
  player_id uuid not null references auth.users(id) on delete cascade,
  character_id uuid not null references characters(id) on delete cascade,
  event_slug text not null,
  item_id integer not null references items(id),
  created_at timestamptz not null default now(),
  primary key (character_id, event_slug, item_id)
);

create index if not exists event_log_luxuries_player_idx on event_log_luxuries(player_id, event_slug);

alter table event_log_luxuries enable row level security;

drop policy if exists "Players see their own luxuries" on event_log_luxuries;
create policy "Players see their own luxuries"
  on event_log_luxuries for select
  using (player_id = auth.uid() or fa_is_logistics_or_admin());

-- Checks or unchecks one Luxury for a character at one event.
create or replace function event_log_toggle_luxury(p_event_slug text, p_character_id uuid, p_item_id integer, p_has boolean)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
begin
  if v_player is null then raise exception 'Not signed in'; end if;
  if not exists (select 1 from characters where id = p_character_id and player_id = v_player) then
    raise exception 'Character not found';
  end if;
  if not exists (select 1 from items where id = p_item_id and category_id = (select id from item_category where name = 'Luxuries')) then
    raise exception 'Not a Luxury item';
  end if;

  if p_has then
    insert into event_log_luxuries (player_id, character_id, event_slug, item_id)
      values (v_player, p_character_id, p_event_slug, p_item_id)
      on conflict (character_id, event_slug, item_id) do nothing;
  else
    delete from event_log_luxuries
      where character_id = p_character_id and event_slug = p_event_slug and item_id = p_item_id;
  end if;
end;
$$;
