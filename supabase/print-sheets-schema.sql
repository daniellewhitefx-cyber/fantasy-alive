-- Backs the staff "Print Character Sheets" tool: bulk-prints one page per
-- registered character for an event. Event registration itself lives in an
-- external Google Sheet (see js/registration-status.js), not Supabase, so
-- this file only covers the Supabase side: resolving a registrant's email +
-- character name into an actual character record, and pulling everything
-- shown on that character's own character page in one round trip.
-- Requires permissions-schema.sql (fa_is_logistics_or_admin) to already exist.

-- Lists every registered player with their email, so the print tool can
-- match a registrant's email (from the Google Sheet) to a player_id.
create or replace function admin_list_players_with_email()
returns table(id uuid, email text, display_name text) language plpgsql security definer as $$
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

-- Everything shown on a character's own character page (characters.html),
-- for a batch of character ids at once: race/social class/birthday/SP,
-- XP balance, and the full skills list as jsonb.
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
) language plpgsql stable security definer as $$
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
