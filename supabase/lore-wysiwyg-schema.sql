-- Adds the body_format column that lets lore_entries.body hold either the
-- original custom markdown-ish syntax ('markdown', the default, used by
-- every existing entry) or sanitized HTML produced by the new visual
-- editor ('html'). Existing rows are untouched and keep rendering exactly
-- as before; only entries created or re-saved through the new editor
-- switch to 'html'.

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
