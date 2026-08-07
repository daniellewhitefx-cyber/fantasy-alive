create table if not exists characters (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  race text not null,
  pronouns text,
  birthday date,
  starting_sp integer not null,
  created_at timestamptz not null default now()
);

create index if not exists characters_player_idx on characters(player_id, created_at);

alter table characters enable row level security;

drop policy if exists "Players see their own characters" on characters;
create policy "Players see their own characters"
  on characters for select
  using (player_id = auth.uid());

create table if not exists character_skills (
  id uuid primary key default gen_random_uuid(),
  character_id uuid not null references characters(id) on delete cascade,
  player_id uuid not null references auth.users(id) on delete cascade,
  category text not null,
  skill_name text not null,
  focus text,
  level integer not null default 1 check (level >= 1),
  sp_cost integer not null check (sp_cost >= 0),
  created_at timestamptz not null default now()
);

create index if not exists character_skills_character_idx on character_skills(character_id);

alter table character_skills enable row level security;

drop policy if exists "Players see their own character skills" on character_skills;
create policy "Players see their own character skills"
  on character_skills for select
  using (player_id = auth.uid());

create or replace function character_create(
  p_name text,
  p_race text,
  p_pronouns text,
  p_birthday date,
  p_skills jsonb
)
returns uuid language plpgsql security definer as $$
declare
  v_player uuid := auth.uid();
  v_name text := trim(coalesce(p_name, ''));
  v_race text := trim(coalesce(p_race, ''));
  v_starting_sp integer;
  v_char_id uuid;
  v_skill jsonb;
  v_spent integer := 0;
  v_existing_count integer;
begin
  if v_player is null then raise exception 'Not signed in'; end if;

  if v_name = '' then raise exception 'Character name cannot be empty'; end if;
  if length(v_name) > 60 then raise exception 'Character name is too long'; end if;

  if v_race not in (
    'Human', 'Elf', 'Dwarf', 'Gnome', 'Curtainborn', 'Orc',
    'D''Shunn', 'Minotaur', 'Malkin', 'Goblin', 'Lizardfolk'
  ) then
    raise exception 'Unknown race: %', v_race;
  end if;

  select count(*) into v_existing_count from characters where player_id = v_player;

  if v_existing_count >= 2 then
    raise exception 'You already have 2 characters. Only 2 characters are allowed per player.';
  end if;

  -- A player's very first character gets a flat 30 SP, since everyone is
  -- starting fresh on the new site rather than a brand new player at their
  -- first event. Every character after that follows the normal rulebook
  -- starting SP for their race.
  if v_existing_count = 0 then
    v_starting_sp := 30;
  else
    v_starting_sp := case when v_race = 'Human' then 15 else 10 end;
  end if;

  if p_skills is not null then
    for v_skill in select * from jsonb_array_elements(p_skills) loop
      v_spent := v_spent + coalesce((v_skill ->> 'sp_cost')::integer, 0);
    end loop;
  end if;

  if v_spent > v_starting_sp then
    raise exception 'Chosen skills cost % SP, more than the % SP starting budget', v_spent, v_starting_sp;
  end if;

  insert into characters (player_id, name, race, pronouns, birthday, starting_sp)
    values (
      v_player, v_name, v_race,
      nullif(trim(coalesce(p_pronouns, '')), ''),
      p_birthday,
      v_starting_sp
    )
    returning id into v_char_id;

  if p_skills is not null then
    for v_skill in select * from jsonb_array_elements(p_skills) loop
      if coalesce(trim(v_skill ->> 'skill_name'), '') = '' then
        raise exception 'Every chosen skill needs a name';
      end if;
      insert into character_skills (character_id, player_id, category, skill_name, focus, level, sp_cost)
        values (
          v_char_id,
          v_player,
          coalesce(nullif(trim(v_skill ->> 'category'), ''), 'Skill'),
          trim(v_skill ->> 'skill_name'),
          nullif(v_skill ->> 'focus', ''),
          coalesce((v_skill ->> 'level')::integer, 1),
          coalesce((v_skill ->> 'sp_cost')::integer, 0)
        );
    end loop;
  end if;

  return v_char_id;
end;
$$;

alter table character_skills add column if not exists teachable boolean not null default false;

create or replace function character_set_skill_teachable(p_skill_id uuid, p_teachable boolean)
returns void language plpgsql security definer as $$
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;

  update character_skills set teachable = p_teachable
    where id = p_skill_id and player_id = auth.uid();

  if not found then raise exception 'Skill not found'; end if;
end;
$$;

grant select on characters to authenticated;
grant select on character_skills to authenticated;
