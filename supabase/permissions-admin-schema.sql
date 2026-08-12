-- Lets site_admin accounts grant and revoke staff permissions and
-- department memberships for other players from the Permissions page,
-- instead of editing app_metadata by hand in the Supabase dashboard.
--
-- Permission changes only take effect for a player the next time their
-- session refreshes or they log in again, since app_metadata is baked
-- into the JWT at token issuance.

drop policy if exists "Players see their own department memberships" on department_members;
create policy "Players see their own department memberships"
  on department_members for select
  using (player_id = auth.uid() or fa_is_site_admin());

-- Lists every registered player for the Permissions page. Reads auth.users
-- directly rather than the profiles table, since a handful of accounts
-- predate profiles being reliably backfilled on signup (see
-- fix-signup-error.sql) and would otherwise be missing from the list.
create or replace function admin_list_players()
returns table(id uuid, display_name text) language plpgsql security definer as $$
begin
  if not fa_is_site_admin() then
    raise exception 'Only site admins can list players';
  end if;

  return query
    select u.id, coalesce(p.display_name, u.raw_user_meta_data ->> 'display_name', u.email)
    from auth.users u
    left join profiles p on p.id = u.id
    order by 2;
end;
$$;

create or replace function admin_get_player_flags(p_player_id uuid)
returns jsonb language plpgsql security definer as $$
declare
  v_meta jsonb;
begin
  if not fa_is_site_admin() then
    raise exception 'Only site admins can view player permissions';
  end if;

  select raw_app_meta_data into v_meta from auth.users where id = p_player_id;
  return coalesce(v_meta, '{}'::jsonb);
end;
$$;

create or replace function admin_set_staff_flag(p_player_id uuid, p_flag text, p_enabled boolean)
returns void language plpgsql security definer as $$
begin
  if not fa_is_site_admin() then
    raise exception 'Only site admins can change player permissions';
  end if;

  if p_flag not in (
    'site_admin', 'character_staff', 'bank_staff', 'auction_staff',
    'announcements_staff', 'remort_staff'
  ) then
    raise exception 'Unknown permission flag: %', p_flag;
  end if;

  if p_player_id = auth.uid() and p_flag = 'site_admin' and p_enabled = false then
    raise exception 'You cannot remove your own Site Admin permission';
  end if;

  update auth.users
  set raw_app_meta_data = coalesce(raw_app_meta_data, '{}'::jsonb) || jsonb_build_object(p_flag, p_enabled)
  where id = p_player_id;
end;
$$;

create or replace function admin_set_role(p_player_id uuid, p_role text)
returns void language plpgsql security definer as $$
begin
  if not fa_is_site_admin() then
    raise exception 'Only site admins can change player permissions';
  end if;

  if p_role is not null and p_role not in ('lore_editor') then
    raise exception 'Unknown role: %', p_role;
  end if;

  update auth.users
  set raw_app_meta_data = case
    when p_role is null then coalesce(raw_app_meta_data, '{}'::jsonb) - 'role'
    else coalesce(raw_app_meta_data, '{}'::jsonb) || jsonb_build_object('role', p_role)
  end
  where id = p_player_id;
end;
$$;

create or replace function admin_set_department_member(p_player_id uuid, p_department_id uuid, p_enabled boolean)
returns void language plpgsql security definer as $$
begin
  if not fa_is_site_admin() then
    raise exception 'Only site admins can change department memberships';
  end if;

  if p_enabled then
    insert into department_members (department_id, player_id)
    values (p_department_id, p_player_id)
    on conflict do nothing;
  else
    delete from department_members
    where department_id = p_department_id and player_id = p_player_id;
  end if;
end;
$$;
