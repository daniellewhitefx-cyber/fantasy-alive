create table if not exists departments (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  created_at timestamptz not null default now()
);

insert into departments (name) values ('Plot'), ('Logistics'), ('Lore')
  on conflict (name) do nothing;

create table if not exists department_members (
  department_id uuid not null references departments(id) on delete cascade,
  player_id uuid not null references auth.users(id) on delete cascade,
  primary key (department_id, player_id)
);

alter table departments enable row level security;
drop policy if exists "Departments are publicly readable" on departments;
create policy "Departments are publicly readable"
  on departments for select
  using (true);

alter table department_members enable row level security;
drop policy if exists "Players see their own department memberships" on department_members;
create policy "Players see their own department memberships"
  on department_members for select
  using (player_id = auth.uid());

create table if not exists messages (
  id uuid primary key default gen_random_uuid(),
  sender_id uuid not null references auth.users(id) on delete cascade,
  recipient_player_id uuid references auth.users(id) on delete cascade,
  recipient_department_id uuid references departments(id) on delete cascade,
  body text not null,
  created_at timestamptz not null default now(),
  check (
    (recipient_player_id is not null and recipient_department_id is null)
    or (recipient_player_id is null and recipient_department_id is not null)
  )
);

alter table messages add column if not exists subject text not null default 'No subject';
alter table messages add column if not exists thread_key text;
alter table messages add column if not exists sender_character_id uuid references characters(id) on delete set null;
alter table messages add column if not exists sender_department_id uuid references departments(id) on delete set null;

alter table messages drop constraint if exists messages_sender_identity_check;
alter table messages add constraint messages_sender_identity_check
  check (not (sender_character_id is not null and sender_department_id is not null));

update messages set thread_key = case
    when recipient_department_id is not null then 'dept:' || recipient_department_id::text || ':' || subject
    else 'dm:' || least(sender_id, recipient_player_id)::text || ':' || greatest(sender_id, recipient_player_id)::text || ':' || subject
  end
  where thread_key is null;

alter table messages alter column thread_key set not null;

create index if not exists messages_recipient_player_idx on messages(recipient_player_id, created_at desc);
create index if not exists messages_recipient_department_idx on messages(recipient_department_id, created_at desc);
create index if not exists messages_sender_idx on messages(sender_id, created_at desc);
create index if not exists messages_thread_key_idx on messages(thread_key, created_at);

alter table messages enable row level security;

drop policy if exists "Players see messages they sent or can receive" on messages;
create policy "Players see messages they sent or can receive"
  on messages for select
  using (
    sender_id = auth.uid()
    or recipient_player_id = auth.uid()
    or exists (
      select 1 from department_members dm
      where dm.department_id = messages.recipient_department_id
        and dm.player_id = auth.uid()
    )
  );

create table if not exists message_reads (
  message_id uuid not null references messages(id) on delete cascade,
  player_id uuid not null references auth.users(id) on delete cascade,
  read_at timestamptz not null default now(),
  primary key (message_id, player_id)
);

alter table message_reads enable row level security;
drop policy if exists "Players see their own read receipts" on message_reads;
create policy "Players see their own read receipts"
  on message_reads for select
  using (player_id = auth.uid());

drop function if exists message_send(uuid, uuid, text);
drop function if exists message_send(uuid, uuid, text, text);

create or replace function message_send(
  p_recipient_player_id uuid,
  p_recipient_department_id uuid,
  p_body text,
  p_subject text default null,
  p_sender_character_id uuid default null,
  p_sender_department_id uuid default null
)
returns uuid language plpgsql security definer as $$
declare
  v_sender uuid := auth.uid();
  v_body text := trim(coalesce(p_body, ''));
  v_subject text := nullif(trim(coalesce(p_subject, '')), '');
  v_thread_key text;
  v_message_id uuid;
begin
  if v_sender is null then raise exception 'Not signed in'; end if;
  if v_body = '' then raise exception 'Message cannot be empty'; end if;
  if v_subject is null then v_subject := 'No subject'; end if;

  if (p_recipient_player_id is null) = (p_recipient_department_id is null) then
    raise exception 'Message needs exactly one recipient';
  end if;

  if p_sender_character_id is not null and p_sender_department_id is not null then
    raise exception 'Choose only one sender identity';
  end if;

  if p_sender_character_id is not null then
    if not exists (select 1 from characters where id = p_sender_character_id and player_id = v_sender) then
      raise exception 'Character not found';
    end if;
  end if;

  if p_sender_department_id is not null then
    if not exists (select 1 from department_members where department_id = p_sender_department_id and player_id = v_sender) then
      raise exception 'You are not a member of that department';
    end if;
  end if;

  if p_recipient_player_id is not null then
    if not exists (select 1 from auth.users where id = p_recipient_player_id) then
      raise exception 'Recipient not found';
    end if;
    if v_sender < p_recipient_player_id then
      v_thread_key := 'dm:' || v_sender::text || ':' || p_recipient_player_id::text || ':' || v_subject;
    else
      v_thread_key := 'dm:' || p_recipient_player_id::text || ':' || v_sender::text || ':' || v_subject;
    end if;
  else
    if not exists (select 1 from departments where id = p_recipient_department_id) then
      raise exception 'Department not found';
    end if;
    v_thread_key := 'dept:' || p_recipient_department_id::text || ':' || v_subject;
  end if;

  insert into messages (sender_id, recipient_player_id, recipient_department_id, subject, thread_key, body, sender_character_id, sender_department_id)
    values (v_sender, p_recipient_player_id, p_recipient_department_id, v_subject, v_thread_key, v_body, p_sender_character_id, p_sender_department_id)
    returning id into v_message_id;

  if p_recipient_player_id is not null then
    delete from message_folder_assignments
      where thread_key = v_thread_key and player_id = p_recipient_player_id;
  else
    delete from message_folder_assignments
      where thread_key = v_thread_key
        and player_id != v_sender
        and player_id in (
          select dm.player_id from department_members dm where dm.department_id = p_recipient_department_id
        );
  end if;

  return v_message_id;
end;
$$;

create or replace function message_mark_read(p_message_id uuid)
returns void language plpgsql security definer as $$
declare
  v_player uuid := auth.uid();
begin
  if v_player is null then raise exception 'Not signed in'; end if;

  if not exists (
    select 1 from messages m
    where m.id = p_message_id
      and (
        m.sender_id = v_player
        or m.recipient_player_id = v_player
        or exists (
          select 1 from department_members dm
          where dm.department_id = m.recipient_department_id and dm.player_id = v_player
        )
      )
  ) then
    raise exception 'Message not found';
  end if;

  insert into message_reads (message_id, player_id)
    values (p_message_id, v_player)
    on conflict (message_id, player_id) do nothing;
end;
$$;

create or replace function message_unread_count()
returns integer language sql stable security definer as $$
  select count(*)::integer
  from messages m
  where m.sender_id != auth.uid()
    and (
      m.recipient_player_id = auth.uid()
      or exists (
        select 1 from department_members dm
        where dm.department_id = m.recipient_department_id and dm.player_id = auth.uid()
      )
    )
    and not exists (
      select 1 from message_reads mr
      where mr.message_id = m.id and mr.player_id = auth.uid()
    );
$$;

create table if not exists message_folders (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references auth.users(id) on delete cascade,
  name text not null,
  created_at timestamptz not null default now(),
  unique (player_id, name)
);

alter table message_folders enable row level security;
drop policy if exists "Players see their own folders" on message_folders;
create policy "Players see their own folders"
  on message_folders for select
  using (player_id = auth.uid());

create table if not exists message_folder_assignments (
  player_id uuid not null references auth.users(id) on delete cascade,
  thread_key text not null,
  folder_id uuid not null references message_folders(id) on delete cascade,
  primary key (player_id, thread_key)
);

alter table message_folder_assignments enable row level security;
drop policy if exists "Players see their own folder assignments" on message_folder_assignments;
create policy "Players see their own folder assignments"
  on message_folder_assignments for select
  using (player_id = auth.uid());

create or replace function message_folder_create(p_name text)
returns uuid language plpgsql security definer as $$
declare
  v_player uuid := auth.uid();
  v_name text := trim(coalesce(p_name, ''));
  v_id uuid;
begin
  if v_player is null then raise exception 'Not signed in'; end if;
  if v_name = '' then raise exception 'Folder name cannot be empty'; end if;

  insert into message_folders (player_id, name)
    values (v_player, v_name)
    on conflict (player_id, name) do update set name = excluded.name
    returning id into v_id;

  return v_id;
end;
$$;

create or replace function message_folder_rename(p_folder_id uuid, p_name text)
returns void language plpgsql security definer as $$
declare
  v_player uuid := auth.uid();
  v_name text := trim(coalesce(p_name, ''));
begin
  if v_player is null then raise exception 'Not signed in'; end if;
  if v_name = '' then raise exception 'Folder name cannot be empty'; end if;

  update message_folders set name = v_name
    where id = p_folder_id and player_id = v_player;

  if not found then raise exception 'Folder not found'; end if;
end;
$$;

create or replace function message_folder_delete(p_folder_id uuid)
returns void language plpgsql security definer as $$
declare
  v_player uuid := auth.uid();
begin
  if v_player is null then raise exception 'Not signed in'; end if;

  delete from message_folders where id = p_folder_id and player_id = v_player;

  if not found then raise exception 'Folder not found'; end if;
end;
$$;

create or replace function message_set_folder(p_thread_key text, p_folder_id uuid)
returns void language plpgsql security definer as $$
declare
  v_player uuid := auth.uid();
begin
  if v_player is null then raise exception 'Not signed in'; end if;

  if p_folder_id is null then
    delete from message_folder_assignments where player_id = v_player and thread_key = p_thread_key;
    return;
  end if;

  if not exists (select 1 from message_folders where id = p_folder_id and player_id = v_player) then
    raise exception 'Folder not found';
  end if;

  insert into message_folder_assignments (player_id, thread_key, folder_id)
    values (v_player, p_thread_key, p_folder_id)
    on conflict (player_id, thread_key) do update set folder_id = excluded.folder_id;
end;
$$;

alter table profiles add column if not exists activity_last_seen_at timestamptz;

create or replace function notifications_mark_seen()
returns void language plpgsql security definer as $$
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  update profiles set activity_last_seen_at = now() where id = auth.uid();
end;
$$;

create or replace function notifications_summary()
returns jsonb language plpgsql stable security definer as $$
declare
  v_player uuid := auth.uid();
  v_last_seen timestamptz;
  v_unread_messages integer;
  v_new_xp integer;
  v_new_oc integer;
  v_new_bank integer;
  v_new_kudos integer;
  v_new_remort integer;
begin
  if v_player is null then raise exception 'Not signed in'; end if;

  select activity_last_seen_at into v_last_seen from profiles where id = v_player;

  v_unread_messages := message_unread_count();

  select count(*) into v_new_xp
    from xp_transactions
    where player_id = v_player
      and (v_last_seen is null or created_at > v_last_seen);

  select count(*) into v_new_oc
    from oc_transactions
    where player_id = v_player
      and (v_last_seen is null or created_at > v_last_seen);

  select
    (select count(*) from bank_transactions
      where player_id = v_player
        and created_by is distinct from v_player
        and (v_last_seen is null or created_at > v_last_seen))
    + (select count(*) from bank_bills
      where to_player_id = v_player
        and status = 'pending'
        and (v_last_seen is null or created_at > v_last_seen))
    + (select count(*) from bank_bills
      where from_player_id = v_player
        and status = 'declined'
        and resolved_at is not null
        and (v_last_seen is null or resolved_at > v_last_seen))
  into v_new_bank;

  select count(*) into v_new_kudos
    from kudos
    where from_player_id = v_player
      and status in ('approved', 'denied')
      and decided_at is not null
      and (v_last_seen is null or decided_at > v_last_seen);

  select count(*) into v_new_remort
    from character_remort_requests
    where player_id = v_player
      and status in ('approved', 'denied')
      and decided_at is not null
      and (v_last_seen is null or decided_at > v_last_seen);

  return jsonb_build_object(
    'unread_messages', v_unread_messages,
    'new_xp', v_new_xp,
    'new_oc', v_new_oc,
    'new_bank', v_new_bank,
    'new_kudos', v_new_kudos,
    'new_remort', v_new_remort,
    'total', v_unread_messages + v_new_xp + v_new_oc + v_new_bank + v_new_kudos + v_new_remort
  );
end;
$$;

grant select on departments to authenticated;
grant select on department_members to authenticated;
grant select on messages to authenticated;
grant select on message_reads to authenticated;
grant select on message_folders to authenticated;
grant select on message_folder_assignments to authenticated;
