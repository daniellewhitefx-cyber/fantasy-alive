-- Two changes to the Work tab, per player request:
--
-- 1. Working for a Living (Trade Skills) can now be done for any number
--    of hours, not just multiples of 8. Pay scales proportionally to a
--    full 8 hour shift (5 Copper per level) and rounds up to the nearest
--    Copper.
--
-- 2. Adds Working for a Cause: characters can use their Clerical
--    Investment the same way, per the rulebook ("[Clerics] can use their
--    levels of Clerical Investment to work for a cause instead").
--    Deposited straight to the player's own bank balance, same as
--    Working for a Living.
--
-- Existing working sessions are unaffected; only new sessions use the new
-- rules.

alter table event_log_working_sessions
  drop constraint if exists event_log_working_sessions_hours_worked_check;
alter table event_log_working_sessions
  add constraint event_log_working_sessions_hours_worked_check check (hours_worked > 0);

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
