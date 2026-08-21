
create or replace function admin_list_players_with_email()
returns table(id uuid, email text, display_name text) language plpgsql security definer
set search_path = public
as $$
begin
  if not fa_is_logistics_or_admin() then
    raise exception 'Staff only';
  end if;

  return query
    select u.id, u.email::text, coalesce(p.display_name, u.raw_user_meta_data ->> 'display_name', u.email)::text
    from auth.users u
    left join profiles p on p.id = u.id
    order by 3;
end;
$$;

create or replace function admin_character_sheets(p_character_ids uuid[])
returns table(
  id uuid,
  name text,
  race text,
  social_class text,
  birthday text,
  starting_sp integer,
  xp integer,
  skills jsonb
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
      ), '[]'::jsonb)
    from characters c
    where c.id = any(p_character_ids);
end;
$$;
