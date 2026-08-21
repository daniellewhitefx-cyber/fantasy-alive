
create table if not exists skill_types (
  id integer primary key,
  name text not null unique
);

create table if not exists focus_types (
  id integer primary key,
  name text not null unique
);

create table if not exists skills (
  id integer primary key,
  name text not null,
  skill_type_id integer not null references skill_types(id),
  focus_type_id integer references focus_types(id),
  stat_name text,
  stat_value integer,
  levelable boolean not null default false,
  overwrite_cost_for_focus boolean not null default false,
  description text
);
create index if not exists skills_type_idx on skills(skill_type_id);
create index if not exists skills_name_idx on skills(lower(name));

create table if not exists skill_focuses (
  id integer primary key,
  name text not null,
  cost integer,
  tutor integer,
  level_cost text,
  description text
);
create index if not exists skill_focuses_name_idx on skill_focuses(lower(name));

create table if not exists skill_focus_type_map (
  id integer primary key,
  focus_id integer not null references skill_focuses(id) on delete cascade,
  focus_type_id integer not null references focus_types(id)
);
create index if not exists skill_focus_type_map_focus_idx on skill_focus_type_map(focus_id);
create index if not exists skill_focus_type_map_type_idx on skill_focus_type_map(focus_type_id);

create table if not exists skill_details (
  id integer primary key,
  skill_id integer not null references skills(id) on delete cascade,
  race text,
  cost integer,
  tutor integer,
  level_limit integer,
  focus_limit integer,
  min_cost integer,
  level_cost text,
  energy_prereq integer,
  lp_prereq integer,
  unique_skill boolean not null default false
);
create index if not exists skill_details_skill_idx on skill_details(skill_id);

create table if not exists skill_focus_details (
  id integer primary key,
  focus_id integer not null references skill_focuses(id) on delete cascade,
  race text,
  cost integer,
  tutor integer,
  level_cost text
);
create index if not exists skill_focus_details_focus_idx on skill_focus_details(focus_id);

create table if not exists skill_prerequisites (
  id integer primary key,
  skill_detail_id integer not null references skill_details(id) on delete cascade,
  prerequisite_skill_id integer not null references skills(id),
  prerequisite_level integer not null,
  prerequisite_skill2_id integer references skills(id),
  prerequisite_level2 integer,
  must_match_focus boolean not null default false,
  prerequisite_focus_id integer references skill_focuses(id),
  prerequisite_focus_level integer
);
create index if not exists skill_prerequisites_detail_idx on skill_prerequisites(skill_detail_id);

create table if not exists skill_focus_prerequisites (
  id integer primary key,
  focus_id integer not null references skill_focuses(id) on delete cascade,
  prerequisite_skill_id integer not null references skills(id),
  prerequisite_level integer not null
);
create index if not exists skill_focus_prerequisites_focus_idx on skill_focus_prerequisites(focus_id);

create table if not exists race_starting_skills (
  id integer primary key,
  race text not null,
  skill_id integer not null references skills(id) on delete cascade,
  level integer not null default 1
);
create index if not exists race_starting_skills_race_idx on race_starting_skills(race);

alter table skill_types enable row level security;
alter table focus_types enable row level security;
alter table skills enable row level security;
alter table skill_focuses enable row level security;
alter table skill_focus_type_map enable row level security;
alter table skill_details enable row level security;
alter table skill_focus_details enable row level security;
alter table skill_prerequisites enable row level security;
alter table skill_focus_prerequisites enable row level security;
alter table race_starting_skills enable row level security;

drop policy if exists "Members read skill catalog" on skill_types;
drop policy if exists "Anyone can read skill catalog" on skill_types;
create policy "Anyone can read skill catalog" on skill_types for select using (true);
drop policy if exists "Members read skill catalog" on focus_types;
drop policy if exists "Anyone can read skill catalog" on focus_types;
create policy "Anyone can read skill catalog" on focus_types for select using (true);
drop policy if exists "Members read skill catalog" on skills;
drop policy if exists "Anyone can read skill catalog" on skills;
create policy "Anyone can read skill catalog" on skills for select using (true);
drop policy if exists "Members read skill catalog" on skill_focuses;
drop policy if exists "Anyone can read skill catalog" on skill_focuses;
create policy "Anyone can read skill catalog" on skill_focuses for select using (true);
drop policy if exists "Members read skill catalog" on skill_focus_type_map;
drop policy if exists "Anyone can read skill catalog" on skill_focus_type_map;
create policy "Anyone can read skill catalog" on skill_focus_type_map for select using (true);
drop policy if exists "Members read skill catalog" on skill_details;
drop policy if exists "Anyone can read skill catalog" on skill_details;
create policy "Anyone can read skill catalog" on skill_details for select using (true);
drop policy if exists "Members read skill catalog" on skill_focus_details;
drop policy if exists "Anyone can read skill catalog" on skill_focus_details;
create policy "Anyone can read skill catalog" on skill_focus_details for select using (true);
drop policy if exists "Members read skill catalog" on skill_prerequisites;
drop policy if exists "Anyone can read skill catalog" on skill_prerequisites;
create policy "Anyone can read skill catalog" on skill_prerequisites for select using (true);
drop policy if exists "Members read skill catalog" on skill_focus_prerequisites;
drop policy if exists "Anyone can read skill catalog" on skill_focus_prerequisites;
create policy "Anyone can read skill catalog" on skill_focus_prerequisites for select using (true);
drop policy if exists "Members read skill catalog" on race_starting_skills;
drop policy if exists "Anyone can read skill catalog" on race_starting_skills;
create policy "Anyone can read skill catalog" on race_starting_skills for select using (true);

grant select on skill_types, focus_types, skills, skill_focuses, skill_focus_type_map,
  skill_details, skill_focus_details, skill_prerequisites, skill_focus_prerequisites,
  race_starting_skills to authenticated, anon;
