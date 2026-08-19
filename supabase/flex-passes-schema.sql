-- Flex Passes: multi-event prepaid bundles, moved from the old
-- endlessadventures.ca Shopify store onto this site's own payment flow
-- (the Stripe-style checkout already used for event Registration).
-- Purchasing one grants a block of credits to the PLAYER's account, not
-- tied to a single character or event; each credit is later redeemed at
-- Registration to cover one event's admission or one event's Full Event
-- Meal Plan. Same running-ledger pattern as XP/OC -- current balance is
-- the sum of every transaction. Requires character-admin-schema.sql
-- (oc_transactions) and event-log-schema.sql (event_log_set_oc_spend,
-- which this file also extends to raise the OC-to-XP cap for holders of
-- an active pass).

create table if not exists flex_pass_transactions (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references auth.users(id) on delete cascade,
  pass_id text not null,
  event_credits integer not null default 0,
  meal_credits integer not null default 0,
  note text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists flex_pass_transactions_player_idx on flex_pass_transactions(player_id, created_at desc);

alter table flex_pass_transactions enable row level security;

drop policy if exists "Players and staff see their flex pass transactions" on flex_pass_transactions;
create policy "Players and staff see their flex pass transactions"
  on flex_pass_transactions for select
  using (
    player_id = auth.uid()
    or (auth.jwt() -> 'app_metadata' ->> 'character_staff')::boolean is true
    or fa_is_site_admin()
  );

grant select on flex_pass_transactions to authenticated;

-- Server-side catalog (mirrors the old store's three variants) so a
-- purchase can't grant itself arbitrary credits/OC by calling the RPC
-- with a made-up pass ID -- the client only ever sends which pass was
-- bought, never the amounts.
create or replace function fa_flex_pass_catalog(p_pass_id text)
returns table(pass_name text, price integer, event_credits integer, meal_credits integer, oc_bonus integer)
language sql immutable
as $$
  select t.pass_name, t.price, t.event_credits, t.meal_credits, t.oc_bonus from (values
    ('flex3', '3-Event Flex Pass', 219, 3, 0, 150),
    ('flex6', '6-Event Flex Pass', 438, 6, 0, 300),
    ('flexmeal6', '6 Meal Plan Flex Pass', 582, 0, 6, 150)
  ) as t(pass_id, pass_name, price, event_credits, meal_credits, oc_bonus)
  where t.pass_id = p_pass_id;
$$;

create or replace function flex_pass_my_balance()
returns table(event_credits integer, meal_credits integer) language sql stable security definer
set search_path = public
as $$
  select coalesce(sum(event_credits), 0)::integer, coalesce(sum(meal_credits), 0)::integer
    from flex_pass_transactions where player_id = auth.uid();
$$;

-- Internal helper for the OC-to-XP cap raise below: "active" means the
-- player currently holds at least one unredeemed credit of either kind.
create or replace function fa_flex_pass_active(p_player uuid)
returns boolean language sql stable security definer
set search_path = public
as $$
  select coalesce((
    select sum(event_credits) + sum(meal_credits) from flex_pass_transactions where player_id = p_player
  ), 0) > 0;
$$;

revoke execute on function fa_flex_pass_active(uuid) from public, authenticated, anon;

create or replace function flex_pass_purchase_grant(p_pass_id text)
returns uuid language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
  v_catalog record;
  v_id uuid;
begin
  if v_player is null then raise exception 'Not signed in'; end if;

  select * into v_catalog from fa_flex_pass_catalog(p_pass_id);
  if not found then raise exception 'Unknown Flex Pass'; end if;

  insert into flex_pass_transactions (player_id, pass_id, event_credits, meal_credits, note, created_by)
    values (v_player, p_pass_id, v_catalog.event_credits, v_catalog.meal_credits, 'Purchased ' || v_catalog.pass_name, v_player)
    returning id into v_id;

  if v_catalog.oc_bonus > 0 then
    insert into oc_transactions (player_id, amount, note, created_by)
      values (v_player, v_catalog.oc_bonus, v_catalog.pass_name || ' bonus OC', v_player);
  end if;

  return v_id;
end;
$$;

create or replace function flex_pass_redeem(p_kind text)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
  v_balance record;
begin
  if v_player is null then raise exception 'Not signed in'; end if;
  if p_kind not in ('event', 'meal') then raise exception 'Invalid Flex Pass credit type'; end if;

  select * into v_balance from flex_pass_my_balance();

  if p_kind = 'event' then
    if v_balance.event_credits < 1 then raise exception 'No Flex event credits available'; end if;
    insert into flex_pass_transactions (player_id, pass_id, event_credits, note, created_by)
      values (v_player, 'redeem', -1, 'Redeemed for event registration', v_player);
  else
    if v_balance.meal_credits < 1 then raise exception 'No Flex meal credits available'; end if;
    insert into flex_pass_transactions (player_id, pass_id, meal_credits, note, created_by)
      values (v_player, 'redeem', -1, 'Redeemed for event meal plan', v_player);
  end if;
end;
$$;

-- Raises the OC-to-XP/Copper cap from 100 to 150 while a Flex Pass is
-- active, per the old store's "150 OC bonus events" benefit. The table
-- check constraint has to allow the higher ceiling; the per-player cap
-- is still enforced inside the function itself.
alter table event_log_oc_spends drop constraint if exists event_log_oc_spends_oc_amount_check;
alter table event_log_oc_spends add constraint event_log_oc_spends_oc_amount_check check (oc_amount >= 0 and oc_amount <= 150);

create or replace function event_log_set_oc_spend(p_event_slug text, p_kind text, p_character_id uuid, p_oc_amount integer)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
  v_current integer;
  v_delta integer;
  v_oc_balance integer;
  v_cap integer;
begin
  if v_player is null then raise exception 'Not signed in'; end if;
  if p_kind not in ('xp', 'copper') then raise exception 'Unknown kind'; end if;

  v_cap := case when fa_flex_pass_active(v_player) then 150 else 100 end;
  if p_oc_amount is null or p_oc_amount < 0 or p_oc_amount > v_cap then
    raise exception 'Amount must be between 0 and %', v_cap;
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
  on conflict (player_id, event_slug, kind) do update set oc_amount = excluded.oc_amount, character_id = excluded.character_id, updated_at = now();
end;
$$;
