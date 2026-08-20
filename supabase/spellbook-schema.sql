-- Character Spellbook: lets a player toggle which spells their character
-- personally knows via Magery, trust-based like the Luxuries checklist (no
-- server-side level/prereq check). Spells granted by Clerical Investment
-- are NOT stored here -- they're derived client-side (js/spellbook-data.js)
-- from the character's worshipped deity/level against the Deities lore
-- articles, since they're automatic rather than chosen.
-- Requires characters-schema.sql (characters) and permissions-schema.sql
-- (fa_is_site_admin) to already exist.

create table if not exists character_known_spells (
  id uuid primary key default gen_random_uuid(),
  character_id uuid not null references characters(id) on delete cascade,
  player_id uuid not null references auth.users(id) on delete cascade,
  spell_name text not null,
  created_at timestamptz not null default now()
);

create unique index if not exists character_known_spells_char_spell_uidx
  on character_known_spells (character_id, lower(spell_name));

alter table character_known_spells enable row level security;

drop policy if exists "Players see their own known spells" on character_known_spells;
create policy "Players see their own known spells"
  on character_known_spells for select
  using (player_id = auth.uid() or fa_is_site_admin());

grant select on character_known_spells to authenticated;

create or replace function character_learn_spell(p_character_id uuid, p_spell_name text)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
begin
  if v_player is null then raise exception 'Not signed in'; end if;
  if p_spell_name is null or trim(p_spell_name) = '' then raise exception 'Spell name is required'; end if;

  if not exists (select 1 from characters where id = p_character_id and player_id = v_player) then
    raise exception 'Character not found';
  end if;

  insert into character_known_spells (character_id, player_id, spell_name)
    values (p_character_id, v_player, trim(p_spell_name))
  on conflict (character_id, lower(spell_name)) do nothing;
end;
$$;

revoke all on function character_learn_spell(uuid, text) from public, anon;
grant execute on function character_learn_spell(uuid, text) to authenticated;

create or replace function character_unlearn_spell(p_character_id uuid, p_spell_name text)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
begin
  if v_player is null then raise exception 'Not signed in'; end if;

  if not exists (select 1 from characters where id = p_character_id and player_id = v_player) then
    raise exception 'Character not found';
  end if;

  delete from character_known_spells
    where character_id = p_character_id and lower(spell_name) = lower(p_spell_name);
end;
$$;

revoke all on function character_unlearn_spell(uuid, text) from public, anon;
grant execute on function character_unlearn_spell(uuid, text) to authenticated;
