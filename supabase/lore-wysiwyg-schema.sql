
alter table lore_entries add column if not exists body_format text not null default 'markdown';

do $$
begin
  if not exists (
    select 1 from pg_constraint where conname = 'lore_entries_body_format_check'
  ) then
    alter table lore_entries
      add constraint lore_entries_body_format_check check (body_format in ('markdown', 'html'));
  end if;
end $$;
