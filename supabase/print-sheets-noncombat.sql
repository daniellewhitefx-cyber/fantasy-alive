drop function if exists admin_character_sheets(uuid[]);

create or replace function admin_character_sheets(p_character_ids uuid[], p_event_slug text)
returns table(
  id uuid,
  name text,
  race text,
  social_class text,
  birthday text,
  starting_sp integer,
  xp integer,
  skills jsonb,
  combat_status text,
  noncombat_skills jsonb
) language plpgsql stable security definer
set search_path = public
as $$
begin
  if not fa_is_logistics_or_admin() then
    raise exception 'Staff only';
  end if;

  return query
    select
      c.id, c.name, c.race, c.social_class, c.birthday::text, c.starting_sp,
      coalesce(xp_balance(c.id), 0),
      coalesce((
        select jsonb_agg(jsonb_build_object(
          'name', cs.skill_name, 'type', cs.category, 'focus', cs.focus,
          'level', cs.level, 'sp', cs.sp_cost
        ) order by cs.skill_name)
        from character_skills cs
        where cs.character_id = c.id
      ), '[]'::jsonb),
      r.combat_status,
      coalesce((
        select jsonb_agg(jsonb_build_object(
          'name', rs.skill_name, 'type', rs.category, 'focus', rs.focus,
          'level', rs.level, 'sp', rs.sp_cost
        ) order by rs.skill_name)
        from registration_noncombat_skills rs
        where rs.registration_id = r.id
      ), '[]'::jsonb)
    from characters c
    left join registrations r on r.character_id = c.id and r.event_slug = p_event_slug
    where c.id = any(p_character_ids);
end;
$$;
