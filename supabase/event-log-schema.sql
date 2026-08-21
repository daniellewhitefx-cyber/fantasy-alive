
drop function if exists event_log_spend_oc_for_xp(text, uuid, integer);
drop function if exists event_log_spend_oc_for_copper(text, integer);
drop table if exists event_log_oc_spends cascade;

create table event_log_oc_spends (
  player_id uuid not null references auth.users(id) on delete cascade,
  event_slug text not null,
  kind text not null check (kind in ('xp', 'copper')),
  character_id uuid references characters(id) on delete cascade,
  oc_amount integer not null default 0 check (oc_amount >= 0 and oc_amount <= 100),
  updated_at timestamptz not null default now(),
  primary key (player_id, event_slug, kind)
);

alter table event_log_oc_spends enable row level security;

drop policy if exists "Players see their own OC spends" on event_log_oc_spends;
create policy "Players see their own OC spends"
  on event_log_oc_spends for select
  using (player_id = auth.uid() or fa_is_logistics_or_admin());

create or replace function event_log_set_oc_spend(p_event_slug text, p_kind text, p_character_id uuid, p_oc_amount integer)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
  v_current integer;
  v_delta integer;
  v_oc_balance integer;
begin
  if v_player is null then raise exception 'Not signed in'; end if;
  if p_kind not in ('xp', 'copper') then raise exception 'Unknown kind'; end if;
  if p_oc_amount is null or p_oc_amount < 0 or p_oc_amount > 100 then
    raise exception 'Amount must be between 0 and 100';
  end if;

  if p_kind = 'xp' and not exists (select 1 from characters where id = p_character_id and player_id = v_player) then
    raise exception 'Character not found';
  end if;

  select oc_amount into v_current
    from event_log_oc_spends
    where player_id = v_player and event_slug = p_event_slug and kind = p_kind
    for update;
  if not found then v_current := 0; end if;

  v_delta := p_oc_amount - v_current;
  if v_delta = 0 then return; end if;

  if v_delta > 0 then
    select coalesce(sum(amount), 0) into v_oc_balance from oc_transactions where player_id = v_player;
    if v_delta > v_oc_balance then raise exception 'Not enough Ogre Chips'; end if;
  end if;

  insert into oc_transactions (player_id, amount, note, created_by)
    values (
      v_player, -v_delta,
      (case when p_kind = 'xp' then 'Spent on XP (' else 'Spent on Copper (' end) || p_event_slug || ')',
      v_player
    );

  if p_kind = 'xp' then
    insert into xp_transactions (character_id, player_id, amount, note, created_by)
      values (p_character_id, v_player, v_delta, 'Bought with OC (' || p_event_slug || ')', v_player);
  else
    if v_delta > 0 then
      insert into bank_transactions (player_id, type, amount, note, created_by)
        values (v_player, 'log_bank', v_delta * 10, 'Bought with OC (' || p_event_slug || ')', v_player);
    else
      insert into bank_transactions (player_id, type, amount, note, created_by)
        values (v_player, 'withdrawal', -v_delta * 10, 'Reduced OC-to-Copper (' || p_event_slug || ')', v_player);
    end if;
  end if;

  insert into event_log_oc_spends (player_id, event_slug, kind, character_id, oc_amount)
    values (v_player, p_event_slug, p_kind, p_character_id, p_oc_amount)
  on conflict (player_id, event_slug, kind)
    do update set oc_amount = excluded.oc_amount, character_id = excluded.character_id, updated_at = now();
end;
$$;

create or replace function event_log_oc_summary(p_event_slug text)
returns jsonb language plpgsql stable security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
  v_xp_spent integer;
  v_copper_spent integer;
begin
  select oc_amount into v_xp_spent
    from event_log_oc_spends where player_id = v_player and event_slug = p_event_slug and kind = 'xp';
  select oc_amount into v_copper_spent
    from event_log_oc_spends where player_id = v_player and event_slug = p_event_slug and kind = 'copper';
  return jsonb_build_object('xp_spent', coalesce(v_xp_spent, 0), 'copper_spent', coalesce(v_copper_spent, 0));
end;
$$;

grant select on event_log_oc_spends to authenticated;
