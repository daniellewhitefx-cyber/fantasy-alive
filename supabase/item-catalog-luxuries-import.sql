-- Luxuries (labs, forges, hired help, housing, horses, and other
-- coin-bought conveniences) lived in their own small table in the old
-- site (characters_luxury) and were never carried over when the rest of
-- the item catalog was migrated. Adding them as a real Luxuries category
-- in the shared item catalog so they show up in the Shoppe (and Print
-- Tags) like everything else.

insert into item_category (id, name) values
  (17, 'Luxuries')
on conflict (id) do nothing;

insert into items (id, name, copper_value, level, energy, audit, availability_id, category_id, focus_category_id) values
  (2429, 'Alchemical Laboratory', 100, null, null, 0, 1, 17, null),
  (2430, 'Herbalism Laboratory', 100, null, null, 0, 1, 17, null),
  (2431, 'Master-Crafted Herbalism Laboratory', 200, null, null, 0, 1, 17, null),
  (2432, 'Forge', 50, null, null, 0, 1, 17, null),
  (2433, 'Master-Crafted Forge', 100, null, null, 0, 1, 17, null),
  (2434, 'Servant', 50, null, null, 0, 1, 17, null),
  (2435, 'Guard/Soldier', 100, null, null, 0, 1, 17, null),
  (2436, 'Cabin/House (per 10-foot square)', 10, null, null, 0, 1, 17, null),
  (2437, 'Shrine or Altar', 20, null, null, 0, 1, 17, null),
  (2438, 'Church/Chapel', 50, null, null, 0, 1, 17, null),
  (2439, 'Horse', 20, null, null, 0, 1, 17, null),
  (2440, 'Ammunition', 8, null, null, 0, 1, 17, null),
  (2441, 'Bandages', 4, null, null, 0, 1, 17, null),
  (2442, 'Master-Crafted Tools', 0, null, null, 0, 1, 17, null),
  (2443, 'Master-Crafted Alchemical Laboratory', 200, null, null, 0, 1, 17, null),
  (2444, 'Tools', 0, null, null, 0, 1, 17, null)
on conflict (id) do nothing;
