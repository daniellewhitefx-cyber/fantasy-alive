
create table if not exists item_availability (
  id integer primary key,
  name text not null unique
);

create table if not exists item_category (
  id integer primary key,
  name text not null unique
);

create table if not exists items (
  id integer primary key,
  name text not null,
  copper_value integer not null,
  level integer,
  energy integer,
  audit integer,
  availability_id integer not null references item_availability(id),
  category_id integer not null references item_category(id),
  focus_category_id integer
);
create index if not exists items_category_idx on items(category_id);
create index if not exists items_name_idx on items(lower(name));

create table if not exists recipes (
  id integer primary key,
  item_id integer not null references items(id),
  quantity_produced integer not null,
  hours numeric not null,
  weapon_items integer not null,
  gem_cost integer not null,
  land boolean not null,
  me_cost integer not null,
  se_cost integer not null,
  e_cost integer not null,
  is_public boolean not null,
  max_tag_size integer not null,
  rep text
);
create index if not exists recipes_item_idx on recipes(item_id);

create table if not exists recipe_materials (
  id integer primary key,
  recipe_id integer not null references recipes(id) on delete cascade,
  item_id integer not null references items(id),
  quantity numeric not null
);
create index if not exists recipe_materials_recipe_idx on recipe_materials(recipe_id);

create table if not exists recipe_requirements (
  id integer primary key,
  recipe_id integer not null references recipes(id) on delete cascade,
  item_id integer not null references items(id),
  quantity integer not null
);
create index if not exists recipe_requirements_recipe_idx on recipe_requirements(recipe_id);

create table if not exists recipe_skill_requirements (
  id integer primary key,
  recipe_id integer not null references recipes(id) on delete cascade,
  skill_id integer not null,
  skill_name text not null,
  focus_id integer,
  focus_name text,
  level integer not null
);
create index if not exists recipe_skill_requirements_recipe_idx on recipe_skill_requirements(recipe_id);

create table if not exists merchant_price_tiers (
  id integer primary key,
  merchant_level integer not null,
  sell_pct integer not null,
  buy_pct integer not null
);

create table if not exists merchant_rarity_tiers (
  id integer primary key,
  merchant_level integer not null,
  availability_id integer not null references item_availability(id),
  sell integer not null,
  buy integer not null
);

alter table item_availability enable row level security;
alter table item_category enable row level security;
alter table items enable row level security;
alter table recipes enable row level security;
alter table recipe_materials enable row level security;
alter table recipe_requirements enable row level security;
alter table recipe_skill_requirements enable row level security;
alter table merchant_price_tiers enable row level security;
alter table merchant_rarity_tiers enable row level security;

drop policy if exists "Members read item catalog" on item_availability;
create policy "Members read item catalog" on item_availability for select using (auth.uid() is not null);
drop policy if exists "Members read item catalog" on item_category;
create policy "Members read item catalog" on item_category for select using (auth.uid() is not null);
drop policy if exists "Members read item catalog" on items;
create policy "Members read item catalog" on items for select using (auth.uid() is not null);
drop policy if exists "Members read item catalog" on recipes;
create policy "Members read item catalog" on recipes for select using (auth.uid() is not null);
drop policy if exists "Members read item catalog" on recipe_materials;
create policy "Members read item catalog" on recipe_materials for select using (auth.uid() is not null);
drop policy if exists "Members read item catalog" on recipe_requirements;
create policy "Members read item catalog" on recipe_requirements for select using (auth.uid() is not null);
drop policy if exists "Members read item catalog" on recipe_skill_requirements;
create policy "Members read item catalog" on recipe_skill_requirements for select using (auth.uid() is not null);
drop policy if exists "Members read item catalog" on merchant_price_tiers;
create policy "Members read item catalog" on merchant_price_tiers for select using (auth.uid() is not null);
drop policy if exists "Members read item catalog" on merchant_rarity_tiers;
create policy "Members read item catalog" on merchant_rarity_tiers for select using (auth.uid() is not null);

grant select on item_availability, item_category, items, recipes, recipe_materials, recipe_requirements, recipe_skill_requirements, merchant_price_tiers, merchant_rarity_tiers to authenticated;
