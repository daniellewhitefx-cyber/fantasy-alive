
create table if not exists scroll_spell_tags (
  id uuid primary key default gen_random_uuid(),
  spell_name text not null,
  incant text,
  cast_prefix text,
  symbol_data text,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now()
);

create unique index if not exists scroll_spell_tags_name_uidx on scroll_spell_tags (lower(spell_name));

alter table scroll_spell_tags enable row level security;
drop policy if exists "Staff see scroll spell tags" on scroll_spell_tags;
create policy "Staff see scroll spell tags"
  on scroll_spell_tags for select
  using (fa_is_logistics_or_admin());

grant select on scroll_spell_tags to authenticated;

create or replace function logistics_upsert_scroll_cast_prefix(p_spell_name text, p_cast_prefix text)
returns void language plpgsql security definer
set search_path = public
as $$
begin
  if not fa_is_logistics_or_admin() then
    raise exception 'Staff only';
  end if;

  update scroll_spell_tags
    set cast_prefix = nullif(trim(p_cast_prefix), ''), updated_at = now()
    where lower(spell_name) = lower(trim(p_spell_name));

  if not found then
    raise exception 'Unknown spell: %', p_spell_name;
  end if;
end;
$$;

revoke all on function logistics_upsert_scroll_cast_prefix(text, text) from public, anon;
grant execute on function logistics_upsert_scroll_cast_prefix(text, text) to authenticated;
