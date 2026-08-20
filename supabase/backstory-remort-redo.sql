-- Two follow-ups to backstory-schema.sql (run that file first):
--
-- 1. A remorted character is a wholly new person -- Plot benefits from
--    knowing who they are now, but the player already scored XP once on
--    this character_id and shouldn't score it again. Replaces the
--    is_resubmission boolean with a three-way kind ('first',
--    'resubmission', 'remort'), auto-detected the same way
--    is_resubmission was: by comparing the character's most recent
--    completed remort against their most recent approved backstory,
--    whichever is later wins. lore_decide_backstory now hard-ignores
--    any XP passed in for a 'remort' row, so there's no client-side path
--    to awarding it twice.
-- 2. Logistics and Plot can now read every backstory submission
--    alongside Lore (view only -- deciding stays Lore/admin-only via
--    lore_decide_backstory's own check, untouched here).
--
-- Requires backstory-schema.sql and event-splash-schema.sql
-- (fa_is_plot_or_admin) to already exist.

alter table character_backstories add column if not exists kind text;
update character_backstories set kind = case when is_resubmission then 'resubmission' else 'first' end where kind is null;
alter table character_backstories alter column kind set not null;
alter table character_backstories alter column kind set default 'first';
alter table character_backstories drop constraint if exists character_backstories_kind_check;
alter table character_backstories add constraint character_backstories_kind_check check (kind in ('first', 'resubmission', 'remort'));
alter table character_backstories drop column if exists is_resubmission;

create or replace function character_submit_backstory(p_character_id uuid, p_body text)
returns uuid language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
  v_char_name text;
  v_last_approved_at timestamptz;
  v_last_remort_at timestamptz;
  v_kind text;
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

  select max(decided_at) into v_last_approved_at
    from character_backstories where character_id = p_character_id and status = 'approved';

  select max(completed_at) into v_last_remort_at
    from character_remort_requests where character_id = p_character_id and status = 'completed';

  if v_last_approved_at is null then
    v_kind := 'first';
  elsif v_last_remort_at is not null and v_last_remort_at > v_last_approved_at then
    v_kind := 'remort';
  else
    v_kind := 'resubmission';
  end if;

  insert into character_backstories (character_id, player_id, body, kind)
    values (p_character_id, v_player, trim(p_body), v_kind)
    returning id into v_id;

  v_subject := (case v_kind
    when 'remort' then 'Remort backstory submitted: '
    when 'resubmission' then 'Backstory revision submitted: '
    else 'New backstory submitted: '
  end) || v_char_name;

  for v_lore_editor in
    select id from auth.users where (raw_app_meta_data ->> 'role') = 'lore_editor'
  loop
    perform message_send(v_lore_editor.id, null, 'Ready for review on the Backstory Requests page.', v_subject, p_character_id, null);
  end loop;

  return v_id;
end;
$$;

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
  v_xp integer;
begin
  if not fa_is_lore_or_admin() then
    raise exception 'Lore staff only';
  end if;
  if p_status not in ('approved', 'denied', 'revision_requested') then
    raise exception 'Invalid status';
  end if;

  select * into v_row from character_backstories where id = p_id and status = 'pending';
  if not found then raise exception 'Submission not found or already decided'; end if;

  -- A remort backstory documents a new character concept for Plot, but
  -- never earns XP -- the player already scored on this character_id's
  -- previous identity. Ignore whatever XP staff enters for one of these.
  v_xp := case when v_row.kind = 'remort' then null else p_xp_awarded end;

  if p_status = 'approved' and v_row.kind != 'remort' and (v_xp is null or v_xp < 0) then
    raise exception 'XP awarded is required to approve a backstory';
  end if;

  update character_backstories set
    status = p_status,
    lore_notes = nullif(trim(coalesce(p_notes, '')), ''),
    xp_awarded = case when p_status = 'approved' then v_xp else null end,
    decided_at = now(),
    decided_by = v_staff
    where id = p_id;

  if p_status = 'approved' and v_xp is not null and v_xp > 0 then
    insert into xp_transactions (character_id, player_id, amount, note, created_by)
      values (v_row.character_id, v_row.player_id, v_xp, 'Backstory approved', v_staff);
  end if;
end;
$$;

create or replace function fa_is_backstory_viewer()
returns boolean language sql stable
set search_path = public
as $$
  select fa_is_lore_or_admin() or fa_is_logistics_or_admin() or fa_is_plot_or_admin();
$$;

drop policy if exists "Players and Lore see backstory submissions" on character_backstories;
drop policy if exists "Players and staff see backstory submissions" on character_backstories;
create policy "Players and staff see backstory submissions"
  on character_backstories for select
  using (player_id = auth.uid() or fa_is_backstory_viewer());
