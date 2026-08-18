-- One-time patch for lore content already imported into the live database.
-- Removes the "Fantasy Alive: Ottawa/Kingston" paragraph from the welcome
-- lore entry, regardless of which import script (lore-schema.sql or
-- lore-import.sql) was used to originally create it. Safe to run more than
-- once: if the paragraph is already gone, each replace() is a no-op.

update lore_entries
set body = replace(
  body,
  $old1$Fantasy Alive: Ottawa/Kingston is set in the Broken Reach, a no-man's-land between the kingdoms of Harodom and Eldersire. Following a war between these kingdoms, and a series of natural and supernatural disasters, the area was declared neutral territory, and those seeking to make a new life for themselves came to the area, where they founded the rapidly growing town of Scarsinvale. It's a hard life in Scarsinvale, but the miners, farmers, craftsmen, warriors, priests, assassins and wizards who make up the town seek to promote its well-being while protecting it from the undead, strange magics, and horrible monsters that plague the area, to say nothing of the all-too-familiar threat of bandits. FA:OK is currently on hiatus, but is expected to return soon.

$old1$,
  ''
)
where slug = 'welcome';

update lore_entries
set body = replace(
  body,
  $old2$Fantasy Alive: Ottawa/Kingstonis set in the Broken Reach, a no-man’s-land between the kingdoms of Harodom and Eldersire. Following a war between these kingdoms, and a series of natural and supernatural disasters, the area was declared neutral territory, and those seeking to make a new life for themselves came to the area, where they founded the rapidly growing town of Scarsinvale. It’s a hard life in Scarsinvale, but the miners, farmers, craftsmen, warriors, priests, assassins and wizards that make up the town seek to promote its well-being while protecting it from the undead, strange magics, and horrible monsters that plague the area – to say nothing of the all-too-familiar bandits and the threat of other settlements taking so that they do not need to create. FA:OKis currently on hiatus, but is expected to return soon.

$old2$,
  ''
)
where slug = 'welcome-to-the-world-of-fantasy-alive';
