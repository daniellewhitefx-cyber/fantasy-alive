
create table if not exists legacy_events (
  id bigint primary key,
  name text not null,
  event_date date not null
);

alter table legacy_events enable row level security;

drop policy if exists "Anyone can read legacy events" on legacy_events;
create policy "Anyone can read legacy events"
  on legacy_events for select
  using (true);

grant select on legacy_events to authenticated;

alter table xp_transactions add column if not exists legacy_event_id bigint references legacy_events(id) on delete set null;
alter table oc_transactions add column if not exists legacy_event_id bigint references legacy_events(id) on delete set null;
alter table kudos add column if not exists legacy_event_id bigint references legacy_events(id) on delete set null;

create index if not exists xp_transactions_legacy_event_idx on xp_transactions(legacy_event_id) where legacy_event_id is not null;
create index if not exists oc_transactions_legacy_event_idx on oc_transactions(legacy_event_id) where legacy_event_id is not null;
create index if not exists kudos_legacy_event_idx on kudos(legacy_event_id) where legacy_event_id is not null;
