-- Backs the per-event downtime log. Events themselves are defined
-- client-side in js/registration-status.js (FA_EVENT_DEFS) rather than
-- a table here, so log entries are keyed by the event's slug (see
-- faEventSlug()) instead of a foreign key. This file covers the first
-- log tab: spending Ogre Chips for XP or Copper.

create table if not exists event_log_oc_spends (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references auth.users(id) on delete cascade,
  event_slug text not null,
  kind text not null check (kind in ('xp', 'copper')),
  character_id uuid references characters(id) on delete cascade,
  oc_amount integer not null check (oc_amount > 0),
  created_at timestamptz not null default now()
);

create index if not exists event_log_oc_spends_player_event_idx
  on event_log_oc_spends(player_id, event_slug, kind);

alter table event_log_oc_spends enable row level security;

drop policy if exists "Players see their own OC spends" on event_log_oc_spends;
create policy "Players see their own OC spends"
  on event_log_oc_spends for select
  using (player_id = auth.uid() or fa_is_logistics_or_admin());

create or replace function event_log_spend_oc_for_xp(p_event_slug text, p_character_id uuid, p_oc_amount integer)
returns void language plpgsql security definer as $$
declare
  v_player uuid := auth.uid();
  v_oc_balance integer;
  v_already_spent integer;
begin
  if v_player is null then raise exception 'Not signed in'; end if;
  if p_oc_amount is null or p_oc_amount <= 0 then raise exception 'Amount must be greater than 0'; end if;

  if not exists (select 1 from characters where id = p_character_id and player_id = v_player) then
    raise exception 'Character not found';
  end if;

  select coalesce(sum(amount), 0) into v_oc_balance from oc_transactions where player_id = v_player;
  if p_oc_amount > v_oc_balance then raise exception 'Not enough Ogre Chips'; end if;

  select coalesce(sum(oc_amount), 0) into v_already_spent
    from event_log_oc_spends
    where player_id = v_player and event_slug = p_event_slug and kind = 'xp';
  if v_already_spent + p_oc_amount > 100 then
    raise exception 'You can only spend up to 100 OC on XP per event (% already spent)', v_already_spent;
  end if;

  insert into oc_transactions (player_id, amount, note, created_by)
    values (v_player, -p_oc_amount, 'Spent on XP (' || p_event_slug || ')', v_player);

  insert into xp_transactions (character_id, player_id, amount, note, created_by)
    values (p_character_id, v_player, p_oc_amount, 'Bought with OC (' || p_event_slug || ')', v_player);

  insert into event_log_oc_spends (player_id, event_slug, kind, character_id, oc_amount)
    values (v_player, p_event_slug, 'xp', p_character_id, p_oc_amount);
end;
$$;

create or replace function event_log_spend_oc_for_copper(p_event_slug text, p_oc_amount integer)
returns void language plpgsql security definer as $$
declare
  v_player uuid := auth.uid();
  v_oc_balance integer;
  v_already_spent integer;
begin
  if v_player is null then raise exception 'Not signed in'; end if;
  if p_oc_amount is null or p_oc_amount <= 0 then raise exception 'Amount must be greater than 0'; end if;

  select coalesce(sum(amount), 0) into v_oc_balance from oc_transactions where player_id = v_player;
  if p_oc_amount > v_oc_balance then raise exception 'Not enough Ogre Chips'; end if;

  select coalesce(sum(oc_amount), 0) into v_already_spent
    from event_log_oc_spends
    where player_id = v_player and event_slug = p_event_slug and kind = 'copper';
  if v_already_spent + p_oc_amount > 100 then
    raise exception 'You can only spend up to 100 OC on Copper per event (% already spent)', v_already_spent;
  end if;

  insert into oc_transactions (player_id, amount, note, created_by)
    values (v_player, -p_oc_amount, 'Spent on Copper (' || p_event_slug || ')', v_player);

  insert into bank_transactions (player_id, type, amount, note, created_by)
    values (v_player, 'log_bank', p_oc_amount * 10, 'Bought with OC (' || p_event_slug || ')', v_player);

  insert into event_log_oc_spends (player_id, event_slug, kind, oc_amount)
    values (v_player, p_event_slug, 'copper', p_oc_amount);
end;
$$;

-- How much of the 100 OC cap this player has used, per direction, for
-- one event. Used to render remaining allowance and to prefill history.
create or replace function event_log_oc_summary(p_event_slug text)
returns jsonb language plpgsql stable security definer as $$
declare
  v_player uuid := auth.uid();
  v_xp_spent integer;
  v_copper_spent integer;
begin
  select coalesce(sum(oc_amount), 0) into v_xp_spent
    from event_log_oc_spends where player_id = v_player and event_slug = p_event_slug and kind = 'xp';
  select coalesce(sum(oc_amount), 0) into v_copper_spent
    from event_log_oc_spends where player_id = v_player and event_slug = p_event_slug and kind = 'copper';
  return jsonb_build_object('xp_spent', v_xp_spent, 'copper_spent', v_copper_spent);
end;
$$;

grant select on event_log_oc_spends to authenticated;
