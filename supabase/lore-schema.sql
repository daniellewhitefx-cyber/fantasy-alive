

create table if not exists lore_entries (
  id uuid primary key default gen_random_uuid(),
  slug text unique not null,
  title text not null,
  category text not null,
  body text not null,
  created_at timestamptz not null default now(),
  updated_at timestamptz not null default now(),
  created_by uuid references auth.users(id) on delete set null
);

alter table lore_entries enable row level security;

drop policy if exists "Lore entries are publicly readable" on lore_entries;
create policy "Lore entries are publicly readable"
  on lore_entries for select
  using (true);

drop policy if exists "Only lore editors can insert" on lore_entries;
create policy "Only lore editors can insert"
  on lore_entries for insert
  with check ((auth.jwt() -> 'app_metadata' ->> 'role') = 'lore_editor' or fa_is_site_admin());

drop policy if exists "Only lore editors can update" on lore_entries;
create policy "Only lore editors can update"
  on lore_entries for update
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'lore_editor' or fa_is_site_admin());

drop policy if exists "Only lore editors can delete" on lore_entries;
create policy "Only lore editors can delete"
  on lore_entries for delete
  using ((auth.jwt() -> 'app_metadata' ->> 'role') = 'lore_editor' or fa_is_site_admin());


insert into storage.buckets (id, name, public)
values ('lore-images', 'lore-images', true)
on conflict (id) do nothing;

-- No SELECT policy: the bucket is public (public = true above), so
-- object bytes are already served at /storage/v1/object/public/... with
-- no RLS check at all. A SELECT policy here isn't needed for that and
-- only adds the ability to enumerate every file in the bucket via the
-- API, which Supabase's linter flags as unwanted (public_bucket_allows_listing).
drop policy if exists "Public read for lore images" on storage.objects;

drop policy if exists "Lore editors can upload images" on storage.objects;
create policy "Lore editors can upload images"
  on storage.objects for insert
  with check (bucket_id = 'lore-images' and ((auth.jwt() -> 'app_metadata' ->> 'role') = 'lore_editor' or fa_is_site_admin()));

drop policy if exists "Lore editors can delete images" on storage.objects;
create policy "Lore editors can delete images"
  on storage.objects for delete
  using (bucket_id = 'lore-images' and ((auth.jwt() -> 'app_metadata' ->> 'role') = 'lore_editor' or fa_is_site_admin()));


insert into lore_entries (slug, title, category, body) values
('welcome', 'Welcome to the World of Fantasy Alive!', 'Getting Started', $body1$Welcome, adventurer! Fantasy Alive is set on the continent of Ariel, with two games set within the Lakes Region. The region is dotted with ruins dating back to the fallen Golden Age of Magic, containing monsters, traps, exquisite treasures, and lost magics, as, over the centuries, kingdoms have risen and fallen, leaving behind the wonders that they created, and the horrors that they were unable to destroy.

Fantasy Alive: Toronto is set in the kingdom of Harodom, a predominantly human kingdom that has recently experienced wars and multiple changes to the social order that have led to greater social mobility, and the opportunity for chancing adventurers to seek their fortune and have their names written in the rolls of valour. Warriors, mages, clerics, merchants and chancers have flooded to a small, as-yet-unnamed settlement near the Ire, a large salt-water body that holds many a curiosity within its depths, with the new settlement offering the promise of growth, and whispers of ancient secrets.

Wherever you may choose to make your mark, the time is ripe to do so now. Go forth, bold adventurer! Uncover ancient mysteries, seek out caches of lost wealth, stand fast against evil, or fall to it! Write your name among the stars, and start your journey into the world of Fantasy Alive!$body1$),

('how-to-use', 'How to Use This Resource', 'Getting Started', $body2$> Reading a book is like having a one-sided conversation with a dead person across centuries. Well, I say one-sided, but honestly, sometimes I shout at them.
> -- Cleric Macklewheat of Fiona, Goddess of Knowledge, Remarks on the Book of Foundations (1939 A.T.)

Welcome to the Fantasy Alive Wiki! Within this resource is information that can be useful when building your character, learning about the world of Fantasy Alive and its lore, understanding the rules and how they work within the setting, and finding a place in this world of magic and wonder. It's also a great reference resource for those familiar with the setting who want to look up information that they might find useful in the course of play.

Rules sections describe the rules of play, as outlined in the handbook. In addition to being a searchable guide, these sections are also bite-sized and digestible, which may help some people better understand the material. There may be some areas in these sections that talk about how people within the setting of Fantasy Alive understand these rules of their world, they might not view it as a game, but wizards and clerics know how levels of magical spells work, because it's relevant to what they do every day.

Lore sections will often use phrases like “it is usually the case that”, or “many people believe”. While it's far from certain that any character would know all of the information found within the lore, any of this information could be something known or believed by a new character, or an experienced one. Although this information is 'known' to be the case, the very nature of adventure is that new discoveries are made all the time, and exceptions prove every rule.

Check back regularly, as this resource is still under construction, and more pages and information will become available as it is completed!$body2$),

('history-of-ariel', 'The History of Ariel', 'History', $body3$The Book of Foundations tells of the creation of the plane of Ariel, the mortal plane. It is unknown when the Book of Foundations was created, who wrote it, or how it was compiled. Pages have been found scattered across Ariel and throughout time since the Tear; many have been proven to be forgeries, while others surface only to disappear again for decades or centuries at a time. It is agreed, particularly from the few verified pages that have surfaced, that it includes the part each god played in the creation of Ariel.

## The Golden Age, Before the Tear (B.T.)

There are two eras in Ariel: Before the Tear (B.T.) and After the Tear (A.T.). No one knows how long the Golden Age lasted. What is known is that there was a vast empire ruled by Alexander, and it ushered in a time of unity and prosperity. It is commonly accepted that during this time no person within the empire wanted for food, as it was given to every citizen without personal cost, and temples to every god were openly and equally worshipped across the landscape. It is widely believed Alexander was an elf, one of the first races in Ariel, though in recent decades stories have emerged that cast doubt on this. What has remained is the romanticized idea of what this time was like, the pedestal all rulers since have compared themselves against.

## The Tear

Marking the end of the Golden Age, the Tear is more enigmatic and mythical than the empire of Alexander and the Golden Age itself. There are no records that agree on what the Tear was, how it began, when it was, or if it has even concluded. What is agreed upon is that it was likely magical or divine in origin, and upset the balance of Ariel as a plane. This shift caused the end of the Golden Age and of Alexander's empire and rule, and began what is referred to as the Dark Age.

## The Dark Age, approximately 1 A.T. to 500 A.T.

The first 500 years after the fall of the Golden Age were a time of darkness, metaphorically and perhaps even literally. Whereas all people were once unified, the vacuum of power and the shift from the Tear had a great effect, and the world as it was known crumbled into obscurity. Lawlessness ruled supreme as infrastructure fell apart, armies vied for control of fiefdoms and cities, and common people dispersed across all landscapes. Entire crop yields would be lost, and commerce and trade became hazardous and difficult, with survival taking precedence over all else. Warlords reigned supreme, with many rumoured to be demi-gods, either benevolent or cruel. This was the most tumultuous time Ariel has, or possibly will, ever see, and is the reason why no truly significant evidence of the Golden Age, or the Tear, exists.

## The Age of Reason, approximately 500 A.T. to 1100 A.T.

The divisions and reign of the warlords of the first 500 years After the Tear came to an unceremonious end and bled into what is now called the Age of Reason. Settlements, city-states, and other smaller powers solidified over the next 500 to 600 years, giving rise to new ideologies, technologies, and intermingling of the races. Boundaries somewhat solidified, and new laws came into being in each area to best suit the people who lived there. Unknown ancient wisdom again came to light, leading to a greater awareness of foreign lands and peoples that had fallen into legend.

## The Age of Heroes, or the Age of Blood, approximately 1100 A.T. to 1700 A.T.

Commonly known by either name, this next half millennia saw yet another upheaval of balance and power across Ariel. Likeminded powers banded together and formed alliances that would have lasting effects for powerful bloodlines of rulers, expansion of borders, and a surge in the worship of gods associated with each nation. This led to great renown for some families and individuals, mere mortals reaching heights of prestige previously unheard of. The rise of skirmishes and short wars led to a consistent spilling of blood, shifts in power, and the rise of heroes.

## The Age of Nations, approximately 1700 A.T. to the present

Also known as the Modern Age, the constant raids, skirmishes, and wars of the prior era gave way to the fall of smaller states and the creation of powerful kingdoms, empires, and nations. As trade and commerce expanded, so did technologies and political discourse, creating fairly concrete political borders and treaties. Stability has been greatly cemented in this period, for better or worse, and standing armies and institutions have flourished. Many say the height of this age has not yet been reached, but without a doubt it is the greatest time of prosperity, and magic, since the Golden Age.

~ Authored by Jared Hindle, Fantasy Alive Lore Team 2022. Copyright © Endless Adventures Ontario.$body3$),

('war-of-the-twins', 'The War of the Twins', 'History', $body4$> Sing, minstrel, of the Twins, Sarna, Render of Cities, and Tivolous, The Betrayer. Sing of their lust for conquest, their mad aspirations to godhood, and yes, sing too of their defeat, won at great cost. But defeat and destruction are not one and the same, so sing too of what came after…
> -- Prologue, The Tragedy of The Twins (2022 A.T.)

## The War Begins, 1502 A.T.

The War of the Twins is thought to have begun in 1502 A.T., when two elven twins identifying themselves as Sarna and Tivolous made known that they had raised armies of the undead and of infernals. Using these forces, and their own powerful magics, the Twins quickly assailed the nation of Deepwood, starting with the great city of Darkwood, likely in an effort to stem opposition from the powerful contingent of mages headquartered at the University.

From there, the war spread outward, threatening nearby human and elven lands, forcing a retreat across what would later be known as Lake Haro and Lake Ire. Refugees brought with them whatever portable magics and treasures they could muster, in an effort to keep culturally and mystically significant resources out of the hands of the Twins. Over the next nineteen years, the Twins bled forces allied against them, until their apparent assassination at the hands of the Elven dúath warriors, Paragon and Nystula.

The Twins were then imprisoned in the city in which they were fortified when the Alliance made their final stand, as great magics were worked to seal the city against escape by undead or infernal forces, or the Twins themselves, and to send it deep beneath the earth.

## Immediate Aftermath

Following the War of the Twins, there was a massive effort to keep allied forces and civilians fed. A great deal of otherwise arable farmland had been destroyed or magically corrupted during the war, so food was imported at great expense from more distant lands, including the territories of the Skrulmiter minotaurs and the gnomish nation of Whistlewind. Simultaneously, efforts were made to Cleanse the damaged land, and to put down both the undead formerly in service to the Twins and those that had arisen naturally from the horrors of the war.

While some effort was made to recover treasures lost in the retreat from the Twins' advance, many were marked as missing, possibly permanently. In an effort to ensure that the Twins were never released from their underground prison, there was a grudging agreement between representatives of the Alliance to strike both the location of the city that held the two warlords from maps and history, and to even censor its name. Many ruins dating back to this time were abandoned when they could no longer be held due to logistical or tactical limitations, some of them with supplies intact.

Where nations had fallen, new nations, some claiming a lineage from their predecessors, and others striking fresh ground, sprang up. The gnomish nation of Detter does not overlap with where the city of Detter had been, but served to honour those who had perished in the city's defence. The fledgling kingdom of Michian expanded rapidly, using an orderly and martial tradition to reclaim lands lost to the Twins under their own banner.

## The End of the Twins, 1999 to 2024 A.T.

In 1999 A.T., explorers, prospectors, and scouts from the Kingdom of Harodom found substantial iron deposits in the area that would become known as the town of Yorik. Simultaneously, they found something else: a massive city, ancient by the standards of humans, haunted by potent undead and infernal forces. Within, the Twins still dwelt, Sarna having become a Lich, and Tivolous, a magically enhanced wraith. In order to justify a garrison, mines were built in the region, in accord with minotaur nomads who had also found the area rich ground for mining.

Over the next twenty years, the Twins, able to send occasional emissaries or manifestations to the surface, battled one another and the adventurers who settled in Yorik. In 2022, these battles finally came to a head, with both Sarna and Tivolous being defeated using enormously powerful magic called upon by the Adventurers of Yorik, and it is suspected, the direct intervention of at least one god.

The "Undercity", as it was called, remained a perilous place, haunted by the taint of the undead and infernals it had housed for centuries. Although many treasures that had been in the city when it first descended underground were there to be found, the city was a death trap, and most who ventured beneath were not seen again, even with the Twins defeated. Eventually, in 2024, a powerful infernal was locked within the magical trap, and its explosive death levelled the city, destroying all things subject to magic within.

~ Authored by Andrew Dunlop, Fantasy Alive Lore Team 2026. Copyright © Endless Adventures Ontario.$body4$),

('ruins-of-the-lakes-region', 'Ruins of the Lakes Region', 'History', $body5$> Exploring a ruin, there are some things you should keep a wary eye out for. Giant spiders have been known to nest in any reasonably dry, sheltered area, places where something truly awful happened tend to generate undead by the score, and the people who lived there might have had creative thoughts when it came to home defence. If you find a place that's pretty well picked-over, it's disappointing but safe. If there's treasure still to be found, the cautious wanderer might well ask… "why?"
> -- Antillicus Bosch, Exploring Other People's Basements (1873 A.T.)

The Lakes Region is famously honeycombed with ruins dating back through the war-torn history of Ariel, as generations of peoples of all species have found their way to the banks of the lakes and seen the opportunities made available by access to large, mostly fresh water lakes, teeming with fish and surrounded by fertile soil. The oldest of these ruins predate the Tear, the strange mystical event that ended the Golden Age of Magic.

Of course, not all ruins are that old; a building can become a ruin if left untended for even a short amount of time. Nevertheless, the storied ruins, the ones rumoured to hold treasure and even rare magical items, tend to date back to earlier times, often holding rarities alongside the final resting places of heroes of legend, or at least their abandoned experiments in magical craft.

In addition to holding monsters, the unquiet dead, nesting wildlife, and dedicated guardians, ruins are often dotted with traps. Some of these impediments are intentional deadfalls and death traps designed to deter incautious explorers, while others may even be accidentally created, perils resting against doors and in poorly supported roofs.

## Golden Age Ruins

The oldest and rarest of ruins: the basements of ancient buildings, crypts holding the bones of the long-forgotten dead, and magical hideaways where wonders of a now lost age were forged. While ruins dating back to the Golden Age will sometimes contain writing, they refer to peoples and places that are difficult to positively connect to any known historical figures or locations, and maps describe a landmass different in terrain and description than the continent of Ariel. Golden Age ruins are often magically rich, sometimes with magical items, and sometimes with features of the buildings themselves, which may suggest magical conveniences were more common during this bygone era. Some of these amenities still work, but the most resilient seem to be security measures, in the forms of magical barriers, anti-magic corridors, and animated statues prepared to bludgeon unwary explorers.

## Empire of Lannick Ruins

The first Human Emperor of the recorded era, Lannick's empire was short-lived but extremely martial, leading to the construction of redoubts and fortifications, the bones of which still dot the countryside. In dungeons deep, ghosts of those who fell to the ambition of Lannick and his generals still walk, and the treasures collected by his armies are still rumoured to lurk in undiscovered shadowy halls. Famous to this era were maps and charts detailing where ruins lay, drawn up by scouts and squads that surveyed their assigned regions. With the empire's dissolution following Lannick's assassination by persons unknown, such maps may still lead to troves that yet lay buried, though only the most perilous remain unplundered.

## War of the Twins Ruins

The rapid expansion of the Twins, Sarna and Tivolous, crossed much of the Lakes Region, with undead and infernal forces causing temples, mages, and scholars to flee, many crossing Lake Haro and the Ire to seek refuge in the lands that are now Harodom and Eldersire. Although many relics and treasures from this era were eventually recovered by Alliance forces, many are still missing, with the very real possibility that treasure-laden ships may have sunk, or hidden and fortified temples were captured by these unholy forces. Arms and armour from the era will still sometimes turn up, well-forged steel carefully maintained and repaired as the years have gone by. Such ruins from this period are usually either occupied by remnant forces of the Army of the Twins, or so heavily fortified against such forces that exploring them remains perilous.

## Modern Ruins

Although the era following the founding of Harodom has been celebrated as a new Age of Reason, there have still been conflicts and natural disasters that have caused the rapid fleeing of areas, or the death of their inhabitants. In the last twenty years, no fewer than four major wars have rocked the Lakes Region, with the Breaking of the Reach causing mage towers, merchant houses, and entire towns to be abandoned as inhabitants fled or perished. These new ruins contain threats, often in the form of restless undead, but no less magical and mechanical traps set by those who thought they might one day reclaim lost treasures. Still others are marked with creatures that have moved in since the building was abandoned.

As changing environmental effects have led to Alwyn's weather patterns changing, sinkholes and mudslides have also revealed ruins lost but not forgotten, and those willing to delve into a likely hole in the ground may find nothing but mud, or treasures, traps, and terrors that make the delving a story to be told in days and years to come.

~ Authored by Andrew Dunlop, Fantasy Alive Lore Team 2026. Copyright © Endless Adventures Ontario.$body5$)

on conflict (slug) do nothing;
