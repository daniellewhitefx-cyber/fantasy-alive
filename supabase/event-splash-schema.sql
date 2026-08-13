-- Event Splash Page: a roster of who's attending an event and their
-- trades (with privacy opt-outs), plus a Plot-editable Event Info feed.
-- Run this after permissions-schema.sql and messaging-schema.sql (needs
-- fa_is_site_admin() and the departments/department_members tables).

alter table characters add column if not exists is_anonymous boolean not null default false;
alter table characters add column if not exists hide_trades boolean not null default false;

create or replace function character_set_privacy(p_character_id uuid, p_is_anonymous boolean, p_hide_trades boolean)
returns void language plpgsql security definer as $$
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;

  update characters
    set is_anonymous = coalesce(p_is_anonymous, false),
        hide_trades = coalesce(p_hide_trades, false)
    where id = p_character_id and player_id = auth.uid();

  if not found then raise exception 'Character not found'; end if;
end;
$$;

-- The Event Splash Page's roster is resolved server-side (rather than
-- in the client) so an anonymous character's real name never reaches
-- the browser, and a hide-trades character's trades are never sent
-- down at all.
create or replace function event_splash_roster(p_character_names text[])
returns table (
  character_name text,
  is_anonymous boolean,
  hide_trades boolean,
  trades jsonb
) language sql stable security definer as $$
  select
    case when coalesce(c.is_anonymous, false) then 'Anonymous' else c.name end,
    coalesce(c.is_anonymous, false),
    coalesce(c.hide_trades, false),
    case when coalesce(c.hide_trades, false) then '[]'::jsonb
      else coalesce((
        select jsonb_agg(jsonb_build_object('name', cs.skill_name, 'focus', cs.focus, 'level', cs.level) order by cs.skill_name)
        from character_skills cs
        where cs.character_id = c.id and cs.category = 'Trade Skill'
      ), '[]'::jsonb)
    end
  from characters c
  where auth.uid() is not null
    and lower(c.name) = any(select lower(x) from unnest(p_character_names) as x);
$$;

-- The Event Info feed (per-event Plot updates) is scoped to the Plot
-- department + site admins, the same shape as fa_is_logistics_or_admin().
create or replace function fa_is_plot_or_admin()
returns boolean language sql stable as $$
  select fa_is_site_admin() or exists (
    select 1 from department_members dm
    join departments d on d.id = dm.department_id
    where dm.player_id = auth.uid() and d.name = 'Plot'
  );
$$;

create table if not exists event_info_items (
  id uuid primary key default gen_random_uuid(),
  event_slug text not null,
  body text not null,
  created_by uuid references auth.users(id),
  created_at timestamptz not null default now()
);

create index if not exists event_info_items_event_idx on event_info_items(event_slug, created_at desc);

alter table event_info_items enable row level security;
drop policy if exists "Event info items are publicly readable" on event_info_items;
create policy "Event info items are publicly readable"
  on event_info_items for select
  using (true);

create or replace function event_info_post(p_event_slug text, p_body text)
returns uuid language plpgsql security definer as $$
declare
  v_slug text := trim(coalesce(p_event_slug, ''));
  v_body text := trim(coalesce(p_body, ''));
  v_id uuid;
begin
  if not fa_is_plot_or_admin() then raise exception 'Plot staff only'; end if;
  if v_slug = '' then raise exception 'Event required'; end if;
  if v_body = '' then raise exception 'Body cannot be empty'; end if;

  insert into event_info_items (event_slug, body, created_by) values (v_slug, v_body, auth.uid())
    returning id into v_id;

  return v_id;
end;
$$;

create or replace function event_info_delete(p_id uuid)
returns void language plpgsql security definer as $$
begin
  if not fa_is_plot_or_admin() then raise exception 'Plot staff only'; end if;

  delete from event_info_items where id = p_id;
end;
$$;

grant select on event_info_items to authenticated;
