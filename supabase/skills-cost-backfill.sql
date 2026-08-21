
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
    return null;
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


select
  cs.id as character_skill_id,
  ch.name as character_name,
  ch.race,
  cs.skill_name,
  cs.focus,
  cs.level,
  cs.sp_cost as current_sp_cost,
  skills_true_cost(cs.skill_name, cs.focus, cs.level, ch.race) as correct_sp_cost,
  skills_true_cost(cs.skill_name, cs.focus, cs.level, ch.race) - cs.sp_cost as delta
from character_skills cs
join characters ch on ch.id = cs.character_id
where skills_true_cost(cs.skill_name, cs.focus, cs.level, ch.race) is not null
  and skills_true_cost(cs.skill_name, cs.focus, cs.level, ch.race) != cs.sp_cost
order by abs(skills_true_cost(cs.skill_name, cs.focus, cs.level, ch.race) - cs.sp_cost) desc;

select
  ch.id as character_id,
  ch.name as character_name,
  ch.race,
  sum(cs.sp_cost) as total_sp_currently_recorded,
  sum(coalesce(skills_true_cost(cs.skill_name, cs.focus, cs.level, ch.race), cs.sp_cost)) as total_sp_after_recompute,
  sum(coalesce(skills_true_cost(cs.skill_name, cs.focus, cs.level, ch.race), cs.sp_cost) - cs.sp_cost) as net_change
from character_skills cs
join characters ch on ch.id = cs.character_id
group by ch.id, ch.name, ch.race
having sum(coalesce(skills_true_cost(cs.skill_name, cs.focus, cs.level, ch.race), cs.sp_cost) - cs.sp_cost) != 0
order by abs(sum(coalesce(skills_true_cost(cs.skill_name, cs.focus, cs.level, ch.race), cs.sp_cost) - cs.sp_cost)) desc;


update character_skills cs
set sp_cost = skills_true_cost(cs.skill_name, cs.focus, cs.level, ch.race)
from characters ch
where ch.id = cs.character_id
  and skills_true_cost(cs.skill_name, cs.focus, cs.level, ch.race) is not null
  and skills_true_cost(cs.skill_name, cs.focus, cs.level, ch.race) != cs.sp_cost;
