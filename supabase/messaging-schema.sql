create table if not exists departments (
  id uuid primary key default gen_random_uuid(),
  name text not null unique,
  created_at timestamptz not null default now()
);

insert into departments (name) values ('Plot'), ('Logistics')
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

create index if not exists messages_recipient_player_idx on messages(recipient_player_id, created_at desc);
create index if not exists messages_recipient_department_idx on messages(recipient_department_id, created_at desc);
create index if not exists messages_sender_idx on messages(sender_id, created_at desc);

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

create or replace function message_send(
  p_recipient_player_id uuid,
  p_recipient_department_id uuid,
  p_body text
)
returns uuid language plpgsql security definer as $$
declare
  v_sender uuid := auth.uid();
  v_body text := trim(coalesce(p_body, ''));
  v_message_id uuid;
begin
  if v_sender is null then raise exception 'Not signed in'; end if;
  if v_body = '' then raise exception 'Message cannot be empty'; end if;

  if (p_recipient_player_id is null) = (p_recipient_department_id is null) then
    raise exception 'Message needs exactly one recipient';
  end if;

  if p_recipient_player_id is not null then
    if not exists (select 1 from auth.users where id = p_recipient_player_id) then
      raise exception 'Recipient not found';
    end if;
  else
    if not exists (select 1 from departments where id = p_recipient_department_id) then
      raise exception 'Department not found';
    end if;
  end if;

  insert into messages (sender_id, recipient_player_id, recipient_department_id, body)
    values (v_sender, p_recipient_player_id, p_recipient_department_id, v_body)
    returning id into v_message_id;

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

  return jsonb_build_object(
    'unread_messages', v_unread_messages,
    'new_xp', v_new_xp,
    'new_oc', v_new_oc,
    'total', v_unread_messages + v_new_xp + v_new_oc
  );
end;
$$;

grant select on departments to authenticated;
grant select on department_members to authenticated;
grant select on messages to authenticated;
grant select on message_reads to authenticated;
