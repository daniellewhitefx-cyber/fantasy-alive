create table if not exists home_feed_items (
  id uuid primary key default gen_random_uuid(),
  title text not null,
  description text,
  image_url text,
  link_url text,
  badge text,
  sort_order integer not null default 0,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists home_feed_items_sort_idx on home_feed_items(sort_order, created_at desc);

alter table home_feed_items enable row level security;

drop policy if exists "Home feed items are publicly readable" on home_feed_items;
create policy "Home feed items are publicly readable"
  on home_feed_items for select
  using (true);

create or replace function home_feed_create(
  p_title text,
  p_description text,
  p_image_url text,
  p_link_url text,
  p_badge text,
  p_sort_order integer
)
returns uuid language plpgsql security definer
set search_path = public
as $$
declare
  v_title text := trim(coalesce(p_title, ''));
  v_id uuid;
begin
  if not fa_is_site_admin() then raise exception 'Staff only'; end if;
  if v_title = '' then raise exception 'Title cannot be empty'; end if;
  if length(v_title) > 80 then raise exception 'Title is too long'; end if;

  insert into home_feed_items (title, description, image_url, link_url, badge, sort_order, created_by)
    values (
      v_title,
      nullif(trim(coalesce(p_description, '')), ''),
      nullif(trim(coalesce(p_image_url, '')), ''),
      nullif(trim(coalesce(p_link_url, '')), ''),
      nullif(trim(coalesce(p_badge, '')), ''),
      coalesce(p_sort_order, 0),
      auth.uid()
    )
    returning id into v_id;

  return v_id;
end;
$$;

create or replace function home_feed_update(
  p_id uuid,
  p_title text,
  p_description text,
  p_image_url text,
  p_link_url text,
  p_badge text,
  p_sort_order integer
)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  v_title text := trim(coalesce(p_title, ''));
begin
  if not fa_is_site_admin() then raise exception 'Staff only'; end if;
  if v_title = '' then raise exception 'Title cannot be empty'; end if;
  if length(v_title) > 80 then raise exception 'Title is too long'; end if;

  update home_feed_items set
    title = v_title,
    description = nullif(trim(coalesce(p_description, '')), ''),
    image_url = nullif(trim(coalesce(p_image_url, '')), ''),
    link_url = nullif(trim(coalesce(p_link_url, '')), ''),
    badge = nullif(trim(coalesce(p_badge, '')), ''),
    sort_order = coalesce(p_sort_order, 0)
    where id = p_id;

  if not found then raise exception 'Feed item not found'; end if;
end;
$$;

create or replace function home_feed_delete(p_id uuid)
returns void language plpgsql security definer
set search_path = public
as $$
begin
  if not fa_is_site_admin() then raise exception 'Staff only'; end if;

  delete from home_feed_items where id = p_id;
  if not found then raise exception 'Feed item not found'; end if;
end;
$$;

grant select on home_feed_items to authenticated, anon;
