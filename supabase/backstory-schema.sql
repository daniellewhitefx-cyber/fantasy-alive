-- Character Backstory submissions, now a real in-app record instead of
-- an emailed file attachment (the old public backstory.html form and
-- supabase/functions/submit-backstory edge function, both retired).
-- Both the submitting player and the Lore team can read a submission;
-- Lore decides approve/deny/revision-requested, with notes and, on
-- approval, an XP score. A player may have any number of submissions
-- per character over time (first submission, then later revisions),
-- always as a fresh row rather than an edit-in-place, matching the
-- remort/OC/kudos request pattern elsewhere on the site.
-- Requires characters-schema.sql, permissions-schema.sql
-- (fa_is_lore_or_admin), character-admin-schema.sql (xp_transactions),
-- and messaging-schema.sql (message_send) to already exist.

create table if not exists character_backstories (
  id uuid primary key default gen_random_uuid(),
  character_id uuid not null references characters(id) on delete cascade,
  player_id uuid not null references auth.users(id) on delete cascade,
  body text not null,
  is_resubmission boolean not null default false,
  status text not null default 'pending' check (status in ('pending', 'approved', 'denied', 'revision_requested')),
  xp_awarded integer,
  lore_notes text,
  submitted_at timestamptz not null default now(),
  decided_at timestamptz,
  decided_by uuid references auth.users(id) on delete set null
);

create index if not exists character_backstories_character_idx on character_backstories(character_id, submitted_at desc);
create index if not exists character_backstories_status_idx on character_backstories(status, submitted_at);

alter table character_backstories enable row level security;

drop policy if exists "Players and Lore see backstory submissions" on character_backstories;
create policy "Players and Lore see backstory submissions"
  on character_backstories for select
  using (player_id = auth.uid() or fa_is_lore_or_admin());

grant select on character_backstories to authenticated;

create or replace function character_submit_backstory(p_character_id uuid, p_body text)
returns uuid language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
  v_char_name text;
  v_is_resubmission boolean;
  v_id uuid;
  v_subject text;
  v_lore_editor record;
begin
  if v_player is null then raise exception 'Not signed in'; end if;
  if p_body is null or trim(p_body) = '' then raise exception 'Backstory text is required'; end if;

  select name into v_char_name from characters where id = p_character_id and player_id = v_player;
  if v_char_name is null then raise exception 'Character not found'; end if;

  if exists (
    select 1 from character_backstories
    where character_id = p_character_id and status = 'pending'
  ) then
    raise exception 'This character already has a backstory submission awaiting review';
  end if;

  -- "Resubmission" means updating an already-accepted backstory with new
  -- in-game developments (the rubric below is literally about describing
  -- adventures since approval) -- not a second attempt at a first backstory
  -- that was denied or sent back for revision, which still gets the first-
  -- submission rubric since nothing has been accepted yet.
  v_is_resubmission := exists (select 1 from character_backstories where character_id = p_character_id and status = 'approved');

  insert into character_backstories (character_id, player_id, body, is_resubmission)
    values (p_character_id, v_player, trim(p_body), v_is_resubmission)
    returning id into v_id;

  v_subject := (case when v_is_resubmission then 'Backstory revision submitted: ' else 'New backstory submitted: ' end) || v_char_name;

  for v_lore_editor in
    select id from auth.users where (raw_app_meta_data ->> 'role') = 'lore_editor'
  loop
    perform message_send(v_lore_editor.id, null, 'Ready for review on the Backstory Requests page.', v_subject, p_character_id, null);
  end loop;

  return v_id;
end;
$$;

revoke all on function character_submit_backstory(uuid, text) from public, anon;
grant execute on function character_submit_backstory(uuid, text) to authenticated;

create or replace function lore_decide_backstory(
  p_id uuid,
  p_status text,
  p_notes text,
  p_xp_awarded integer default null
)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  v_staff uuid := auth.uid();
  v_row character_backstories;
begin
  if not fa_is_lore_or_admin() then
    raise exception 'Lore staff only';
  end if;
  if p_status not in ('approved', 'denied', 'revision_requested') then
    raise exception 'Invalid status';
  end if;
  if p_status = 'approved' and (p_xp_awarded is null or p_xp_awarded < 0) then
    raise exception 'XP awarded is required to approve a backstory';
  end if;

  select * into v_row from character_backstories where id = p_id and status = 'pending';
  if not found then raise exception 'Submission not found or already decided'; end if;

  update character_backstories set
    status = p_status,
    lore_notes = nullif(trim(coalesce(p_notes, '')), ''),
    xp_awarded = case when p_status = 'approved' then p_xp_awarded else null end,
    decided_at = now(),
    decided_by = v_staff
    where id = p_id;

  if p_status = 'approved' then
    insert into xp_transactions (character_id, player_id, amount, note, created_by)
      values (v_row.character_id, v_row.player_id, p_xp_awarded, 'Backstory approved', v_staff);
  end if;
end;
$$;

revoke all on function lore_decide_backstory(uuid, text, text, integer) from public, anon;
grant execute on function lore_decide_backstory(uuid, text, text, integer) to authenticated;

create or replace function lore_pending_backstory_count()
returns integer language plpgsql stable security definer
set search_path = public
as $$
begin
  if not fa_is_lore_or_admin() then return 0; end if;
  return (select count(*) from character_backstories where status = 'pending')::integer;
end;
$$;
