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

  return v_id;
end;
$$;
