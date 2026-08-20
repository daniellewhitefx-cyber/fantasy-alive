-- Server-side mirror of js/skills-catalog.js's resolveCostDetail() and
-- skillsParseCost(), promoted from the one-off skills-cost-backfill.sql
-- audit script into a permanent function so character_create and
-- character_update_remort can validate a skill purchase's SP cost and
-- level cap instead of trusting whatever the client submits. Requires
-- skills-catalog-schema.sql to already exist.

create or replace function skills_true_cost(p_skill_name text, p_focus text, p_level integer, p_race text)
returns integer
language plpgsql
stable
set search_path = public
as $$
declare
  v_skill_id integer;
  v_overwrite boolean;
  v_skill_cost integer;
  v_skill_level_cost text;
  v_is_race_specific boolean := false;
  v_focus_cost integer;
  v_focus_level_cost text;
  v_value integer;
  v_level_cost text;
begin
  select id, overwrite_cost_for_focus into v_skill_id, v_overwrite
  from skills where name = p_skill_name;

  if v_skill_id is null then
    return null; -- unrecognized skill name
  end if;

  select cost, level_cost into v_skill_cost, v_skill_level_cost
  from skill_details
  where skill_id = v_skill_id and race = p_race
  limit 1;

  if found then
    v_is_race_specific := true;
  else
    select cost, level_cost into v_skill_cost, v_skill_level_cost
    from skill_details
    where skill_id = v_skill_id and race is null
    limit 1;
  end if;

  -- Mirrors js/skills-catalog.js's resolveCostDetail(): a race-specific
  -- override on the skill always wins outright; otherwise a skill with
  -- its own real (non-overwritten) cost uses that; otherwise fall
  -- through to the chosen focus's own price (Craftsman/Labourer/Weapon
  -- Skill), falling back to the skill's own row if the focus has none.
  if v_skill_cost is not null and v_is_race_specific then
    v_value := v_skill_cost;
    v_level_cost := v_skill_level_cost;
  elsif v_skill_cost is not null and not coalesce(v_overwrite, false) then
    v_value := v_skill_cost;
    v_level_cost := v_skill_level_cost;
  else
    v_focus_cost := null;
    v_focus_level_cost := null;
    if p_focus is not null then
      select fd.cost, fd.level_cost into v_focus_cost, v_focus_level_cost
      from skill_focuses f
      join skill_focus_details fd on fd.focus_id = f.id
      where f.name = p_focus and fd.race = p_race
      limit 1;

      if v_focus_cost is null then
        select cost, level_cost into v_focus_cost, v_focus_level_cost
        from skill_focuses where name = p_focus limit 1;
      end if;
    end if;

    if v_focus_cost is not null then
      v_value := v_focus_cost;
      v_level_cost := v_focus_level_cost;
    else
      v_value := v_skill_cost;
      v_level_cost := v_skill_level_cost;
    end if;
  end if;

  if v_value is null then
    return null;
  end if;

  if v_level_cost = '+' then
    return v_value + greatest(1, p_level);
  elsif v_level_cost = '*' then
    return v_value * greatest(1, p_level);
  else
    return v_value;
  end if;
end;
$$;

-- The cost of a single relevel step (levels N to N+1) is skills_true_cost
-- at level N+1 -- correct for the live Training tab, where a skill is
-- always releveled one step at a time. Buying a skill directly at a
-- starting level (character creation, remort) instead needs the sum of
-- every level's own price from 1 up to that level.
create or replace function skills_true_total_cost(p_skill_name text, p_focus text, p_level integer, p_race text)
returns integer
language plpgsql
stable
set search_path = public
as $$
declare
  v_total integer := 0;
  v_lvl integer;
  v_cost integer;
begin
  for v_lvl in 1..greatest(1, coalesce(p_level, 1)) loop
    v_cost := skills_true_cost(p_skill_name, p_focus, v_lvl, p_race);
    if v_cost is null then return null; end if;
    v_total := v_total + v_cost;
  end loop;
  return v_total;
end;
$$;

-- The highest level a skill can be bought/releveled to (null = uncapped).
-- Level caps live only on skill_details, not skill_focus_details -- a
-- capped skill's limit applies no matter which focus it's taken with.
create or replace function skills_level_limit(p_skill_name text, p_race text)
returns integer
language plpgsql
stable
set search_path = public
as $$
declare
  v_skill_id integer;
  v_limit integer;
begin
  select id into v_skill_id from skills where name = p_skill_name;
  if v_skill_id is null then return null; end if;

  select level_limit into v_limit from skill_details
    where skill_id = v_skill_id and race = p_race limit 1;
  if found then return v_limit; end if;

  select level_limit into v_limit from skill_details
    where skill_id = v_skill_id and race is null limit 1;
  return v_limit;
end;
$$;

revoke execute on function skills_true_cost(text, text, integer, text) from public, anon;
revoke execute on function skills_true_total_cost(text, text, integer, text) from public, anon;
revoke execute on function skills_level_limit(text, text) from public, anon;
grant execute on function skills_true_cost(text, text, integer, text) to authenticated;
grant execute on function skills_true_total_cost(text, text, integer, text) to authenticated;
grant execute on function skills_level_limit(text, text) to authenticated;
