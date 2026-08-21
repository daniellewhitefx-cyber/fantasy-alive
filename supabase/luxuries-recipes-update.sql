
update event_log_luxuries set item_id = 2429
  where item_id = 2430
    and not exists (
      select 1 from event_log_luxuries e2
      where e2.character_id = event_log_luxuries.character_id
        and e2.event_slug = event_log_luxuries.event_slug
        and e2.item_id = 2429
    );
delete from event_log_luxuries where item_id = 2430;

update event_log_luxuries set item_id = 2443
  where item_id = 2431
    and not exists (
      select 1 from event_log_luxuries e2
      where e2.character_id = event_log_luxuries.character_id
        and e2.event_slug = event_log_luxuries.event_slug
        and e2.item_id = 2443
    );
delete from event_log_luxuries where item_id = 2431;

delete from event_log_luxuries where item_id = 2444;

delete from items where id in (2430, 2431, 2444);

update items set name = 'Laboratory' where id = 2429;
update items set name = 'MC Laboratory' where id = 2443;
update items set name = 'MC Forge' where id = 2433;
update items set name = 'Servant (each)' where id = 2434;
update items set name = 'Cabin/House (per 10 ft. square)' where id = 2436;
update items set name = 'Shrine/Altar' where id = 2437;
update items set name = 'Church' where id = 2438;
update items set name = 'MC Tools' where id = 2442;

create table if not exists luxury_recipes (
  item_id integer primary key references items(id),
  skill_text text,
  ingredients_text text,
  craft_hours text,
  effect_text text
);

alter table luxury_recipes enable row level security;

drop policy if exists "Members read luxury recipes" on luxury_recipes;
create policy "Members read luxury recipes" on luxury_recipes for select using (auth.uid() is not null);

grant select on luxury_recipes to authenticated;

insert into luxury_recipes (item_id, skill_text, ingredients_text, craft_hours, effect_text) values
  (2442, 'Craftsman: Blacksmith (10)', '2 Iron', '8 hrs', '+5 hrs Downtime/Week'),
  (2429, 'Alchemist/Herbalist (5), Glassblower (5)', '2 Iron, 4 Hardware, Container 20, Chest 2', '75 hrs', 'Can make potions, can batch recipes x2.'),
  (2443, 'Alchemist/Herbalist (10), Glassblower (10)', '2 Iron, 4 Hardware, Container 20, Chest 2', '225 hrs', 'Can make potions, can batch recipes x5.'),
  (2432, 'Craftsman: Blacksmith (1), Craftsman: Mason/Carpenter (1)', '5 Iron, 5 Hardware, 5 Stone, 5 Lumber', '75 hrs', 'Can smith steel (weapons/armour).'),
  (2433, 'Craftsman: Blacksmith (10), Craftsman: Mason/Carpenter (10)', '5 Iron, 5 Hardware, 5 Stone, 5 Lumber', '225 hrs', 'Can smith steel (weapons/armour), +10 hrs for smith production/week.'),
  (2434, 'N/A', 'N/A', 'N/A', 'No mechanical effect.'),
  (2435, 'N/A', 'N/A', 'N/A', 'No mechanical effect.'),
  (2436, 'Craftsman: Carpenter (1)', '25 Hardware, 50 Lumber, requires use of land.', '50 hrs', 'No mechanical effect.'),
  (2437, 'Theology', '10 Candles, 5 Hardware, 1 Chest, 5 Cloth, 3 Containers, 3 Lumber, 2 Iron', '8 hrs', 'At-game effect only.'),
  (2438, 'Theology, Craftsman: Carpenter (1)', '10 Candles, 30 Hardware, 1 Chest, 5 Cloth, 3 Containers, 53 Lumber, 2 Iron', '58 hrs', 'Acts as +1 level of Clerical Investment when working for a cause.'),
  (2439, 'N/A', 'Mommy Horse and Daddy Horse', 'N/A', '+5 hrs downtime/week for Merchant skill.'),
  (2440, 'N/A', 'N/A', 'N/A', 'Arrows/bolts/sling stones at event.'),
  (2441, 'N/A', 'N/A', 'N/A', 'Bandages at event.')
on conflict (item_id) do update set
  skill_text = excluded.skill_text,
  ingredients_text = excluded.ingredients_text,
  craft_hours = excluded.craft_hours,
  effect_text = excluded.effect_text;
