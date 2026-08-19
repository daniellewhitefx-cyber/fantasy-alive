-- Quick-start character templates migrated from the legacy Django
-- database (database.fantasyalivelrp.com): pre-built skill loadouts a
-- player can load into Character Creator as a starting point, then trim
-- to fit their SP budget using the normal skill picker. This file only
-- defines the schema; the actual rows are loaded by
-- character-templates-import.sql, which must be run immediately after
-- this file.
--
-- Plain integer primary keys matching the source system's own IDs, same
-- convention as item-catalog-schema.sql and skills-catalog-schema.sql.
--
-- skill_id/focus_id reference the real skills catalog (see
-- skills-catalog-schema.sql); skill_name/focus_name are also stored
-- denormalized so the template can be displayed/loaded with a single
-- flat query, matching the convention used by recipe_skill_requirements
-- in item-catalog-schema.sql.
--
-- A template_skills row with archetype_id = null applies to every
-- archetype under that template (e.g. every Cleric gets Theology
-- regardless of which deity archetype they pick); a row with an
-- archetype_id set only applies to that specific archetype. Some
-- archetypes (e.g. the Mage schools) have no archetype-specific rows at
-- all in the source data -- loading them only applies the template's
-- base skills, which is expected, not a data gap to fix.

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
create policy "Members read character templates" on character_templates for select using (auth.uid() is not null);
drop policy if exists "Members read character templates" on character_template_archetypes;
create policy "Members read character templates" on character_template_archetypes for select using (auth.uid() is not null);
drop policy if exists "Members read character templates" on character_template_skills;
create policy "Members read character templates" on character_template_skills for select using (auth.uid() is not null);

grant select on character_templates, character_template_archetypes, character_template_skills to authenticated;
