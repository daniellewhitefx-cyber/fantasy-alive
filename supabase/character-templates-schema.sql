
create table if not exists character_templates (
  id integer primary key,
  name text not null unique
);

create table if not exists character_template_archetypes (
  id integer primary key,
  template_id integer not null references character_templates(id) on delete cascade,
  name text not null
);
create index if not exists character_template_archetypes_template_idx on character_template_archetypes(template_id);

create table if not exists character_template_skills (
  id integer primary key,
  template_id integer not null references character_templates(id) on delete cascade,
  archetype_id integer references character_template_archetypes(id) on delete cascade,
  skill_id integer not null,
  skill_name text not null,
  focus_id integer,
  focus_name text,
  level integer not null default 1
);
create index if not exists character_template_skills_template_idx on character_template_skills(template_id);
create index if not exists character_template_skills_archetype_idx on character_template_skills(archetype_id);

alter table character_templates enable row level security;
alter table character_template_archetypes enable row level security;
alter table character_template_skills enable row level security;

drop policy if exists "Members read character templates" on character_templates;
create policy "Members read character templates" on character_templates for select using ((select auth.uid()) is not null);
drop policy if exists "Members read character templates" on character_template_archetypes;
create policy "Members read character templates" on character_template_archetypes for select using ((select auth.uid()) is not null);
drop policy if exists "Members read character templates" on character_template_skills;
create policy "Members read character templates" on character_template_skills for select using ((select auth.uid()) is not null);

grant select on character_templates, character_template_archetypes, character_template_skills to authenticated;
