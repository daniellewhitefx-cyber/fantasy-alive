-- Fixes for two real findings from a site-wide audit.
--
-- 1. fa_character_merchant_level(uuid) and fa_charge_shopping_travel(uuid,
--    text, text) are internal helpers -- only ever called from inside
--    shoppe_buy_item/shoppe_sell_item (shoppe-selling-schema.sql,
--    merchant-rarity-quota-schema.sql), never directly by the client (no
--    RPC call to either exists anywhere in the front end). But
--    security-lint-fixes-2.sql granted them to `authenticated` directly
--    as part of a batch anon-lockdown pass, unlike the analogous internal
--    helpers (character_material_ledger, bank_balance, xp_balance,
--    oc_balance), which are correctly authenticated-revoked and callable
--    only from other SECURITY DEFINER functions. Neither function checks
--    that the caller owns p_character_id, so as shipped, any signed-in
--    player could call fa_charge_shopping_travel directly against
--    another player's character to burn 8 hours of their downtime
--    budget, or call fa_character_merchant_level to read another
--    character's Merchant Trade Skill level. Revoking authenticated
--    access closes both off without touching shoppe_buy_item/
--    shoppe_sell_item at all -- SECURITY DEFINER functions run with the
--    definer's privileges, not the caller's, so the internal calls keep
--    working exactly as before.
--
-- 2. event_log_work_for_copper's own hours-spent guard only summed
--    Training and Working hours, not Crafting, Shopping-trip travel, or
--    Other Task hours -- the other four sources that spend from the same
--    shared per-event downtime budget (per the canonical list in
--    event_log_training_summary, last extended by other-task-schema.sql).
--    A character could craft/shop/log an other task up to their full
--    hours budget, then still Work for Copper on top of that, spending
--    more hours than they actually had. Rewritten to sum all five
--    sources, matching event_log_training_summary exactly.

revoke execute on function fa_character_merchant_level(uuid) from public, authenticated, anon;
revoke execute on function fa_charge_shopping_travel(uuid, text, text) from public, authenticated, anon;

create or replace function event_log_work_for_copper(
  p_event_slug text,
  p_character_id uuid,
  p_hours_budget integer,
  p_character_skill_id uuid,
  p_hours integer
)
returns uuid language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
  v_skill character_skills%rowtype;
  v_hours_spent integer;
  v_copper integer;
  v_session_id uuid;
begin
  if v_player is null then raise exception 'Not signed in'; end if;
  if p_hours is null or p_hours <= 0 then
    raise exception 'Hours must be a positive number';
  end if;
  if p_hours_budget is null or p_hours_budget < 0 then raise exception 'Invalid hours budget'; end if;

  if not exists (select 1 from characters where id = p_character_id and player_id = v_player) then
    raise exception 'Character not found';
  end if;

  select * into v_skill from character_skills
    where id = p_character_skill_id and character_id = p_character_id
    for update;
  if not found then raise exception 'Skill not found'; end if;
  if v_skill.category != 'Trade Skill' and v_skill.skill_name != 'Clerical Investment' then
    raise exception 'Only Trade Skills or Clerical Investment can be worked for Copper';
  end if;

  select
    coalesce((select sum(hours_cost) from event_log_training_purchases where character_id = p_character_id and event_slug = p_event_slug), 0)
    + coalesce((select sum(hours_worked) from event_log_working_sessions where character_id = p_character_id and event_slug = p_event_slug), 0)
    + coalesce((select sum(hours_spent) from crafting_log where character_id = p_character_id and event_slug = p_event_slug), 0)
    + coalesce((select sum(hours) from event_log_shopping_trips where character_id = p_character_id and event_slug = p_event_slug), 0)
    + coalesce((select sum(hours) from event_log_other_tasks where character_id = p_character_id and event_slug = p_event_slug), 0)
  into v_hours_spent;

  if v_hours_spent + p_hours > p_hours_budget then
    raise exception 'Not enough downtime hours left';
  end if;

  v_copper := ceil((p_hours * 5 * v_skill.level)::numeric / 8)::integer;

  insert into event_log_working_sessions
    (player_id, character_id, event_slug, character_skill_id, skill_name, focus, level, hours_worked, copper_earned)
    values (v_player, p_character_id, p_event_slug, p_character_skill_id, v_skill.skill_name, v_skill.focus, v_skill.level, p_hours, v_copper)
    returning id into v_session_id;

  if v_copper > 0 then
    insert into bank_transactions (player_id, type, amount, note, created_by)
      values (v_player, 'deposit', v_copper, 'Working: ' || v_skill.skill_name || ' Lv' || v_skill.level || ' (' || p_event_slug || ')', v_player);
  end if;

  return v_session_id;
end;
$$;
