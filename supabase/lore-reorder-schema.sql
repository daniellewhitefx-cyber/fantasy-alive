

alter table lore_entries add column if not exists sort_order integer not null default 0;

with ordered as (
  select id, row_number() over (partition by category order by title asc) as rn
  from lore_entries
)
update lore_entries e
set sort_order = ordered.rn * 10
from ordered
where ordered.id = e.id
and e.sort_order = 0;
