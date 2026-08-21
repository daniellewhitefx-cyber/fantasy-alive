
insert into item_catalog (item_name, code)
select
  i.name,
  concat(
    chr(65 + (i.id * 7) % 26), '    ',
    'D', substr(v6, 4, 1),
    'A', substr(v6, 1, 1),
    'F', substr(v6, 6, 1),
    'C', substr(v6, 3, 1),
    'Av', i.availability_id::text,
    'E', substr(v6, 5, 1),
    'B', substr(v6, 2, 1),
    '    ', chr(65 + ((i.id * 13) + 5) % 26)
  )
from (
  select distinct on (lower(name)) id, name, lpad(copper_value::text, 6, '0') as v6, availability_id
  from items
  order by lower(name), id
) i
on conflict (lower(item_name)) do update set
  code = excluded.code,
  updated_at = now();
