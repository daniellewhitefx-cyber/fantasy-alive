

create table if not exists oc_submission_requests (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references auth.users(id) on delete cascade,
  amount integer not null check (amount > 0),
  reason text not null,
  status text not null default 'pending' check (status in ('pending', 'approved', 'denied')),
  created_at timestamptz not null default now(),
  reviewed_at timestamptz,
  reviewed_by uuid references auth.users(id) on delete set null
);

create index if not exists oc_submission_requests_player_idx on oc_submission_requests(player_id, created_at desc);

alter table oc_submission_requests enable row level security;

drop policy if exists "Players and staff see OC submissions" on oc_submission_requests;
create policy "Players and staff see OC submissions"
  on oc_submission_requests for select
  using (player_id = (select auth.uid()) or fa_is_logistics_or_admin());

create or replace function oc_submit_request(p_amount integer, p_reason text)
returns uuid language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
  v_id uuid;
begin
  if v_player is null then raise exception 'Not signed in'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Amount must be greater than 0'; end if;
  if p_reason is null or trim(p_reason) = '' then raise exception 'Reasoning is required'; end if;

  insert into oc_submission_requests (player_id, amount, reason)
    values (v_player, p_amount, trim(p_reason))
    returning id into v_id;

  return v_id;
end;
$$;

create or replace function oc_submission_approve(p_id uuid)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  v_staff uuid := auth.uid();
  v_req oc_submission_requests;
begin
  if not fa_is_logistics_or_admin() then raise exception 'Staff only'; end if;

  select * into v_req from oc_submission_requests where id = p_id and status = 'pending';
  if not found then raise exception 'Request not found or already decided'; end if;

  insert into oc_transactions (player_id, amount, note, created_by)
    values (v_req.player_id, v_req.amount, v_req.reason, v_staff);

  update oc_submission_requests
    set status = 'approved', reviewed_at = now(), reviewed_by = v_staff
    where id = p_id;
end;
$$;

create or replace function oc_submission_deny(p_id uuid)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  v_staff uuid := auth.uid();
begin
  if not fa_is_logistics_or_admin() then raise exception 'Staff only'; end if;

  update oc_submission_requests
    set status = 'denied', reviewed_at = now(), reviewed_by = v_staff
    where id = p_id and status = 'pending';

  if not found then raise exception 'Request not found or already decided'; end if;
end;
$$;

grant select on oc_submission_requests to authenticated;


alter table kudos add column if not exists status text not null default 'pending' check (status in ('pending', 'approved', 'denied'));
alter table kudos add column if not exists decided_at timestamptz;

drop policy if exists "Players see kudos they gave" on kudos;
drop policy if exists "Players see kudos about them" on kudos;
create policy "Players see kudos about them"
  on kudos for select
  using (
    from_player_id = (select auth.uid())
    or to_player_id = (select auth.uid())
    or to_character_id in (select id from characters where player_id = (select auth.uid()))
    or fa_is_logistics_or_admin()
  );

create or replace function kudos_approve(p_id uuid)
returns void language plpgsql security definer
set search_path = public
as $$
begin
  if not fa_is_logistics_or_admin() then raise exception 'Staff only'; end if;

  update kudos set status = 'approved', decided_at = now() where id = p_id and status = 'pending';
  if not found then raise exception 'Request not found or already decided'; end if;
end;
$$;

create or replace function kudos_deny(p_id uuid)
returns void language plpgsql security definer
set search_path = public
as $$
begin
  if not fa_is_logistics_or_admin() then raise exception 'Staff only'; end if;

  update kudos set status = 'denied', decided_at = now() where id = p_id and status = 'pending';
  if not found then raise exception 'Request not found or already decided'; end if;
end;
$$;


drop policy if exists "Players and staff see remort requests" on character_remort_requests;
create policy "Players and staff see remort requests"
  on character_remort_requests for select
  using (
    player_id = (select auth.uid())
    or ((select auth.jwt()) -> 'app_metadata' ->> 'remort_staff')::boolean is true
    or fa_is_logistics_or_admin()
  );

create or replace function character_approve_remort(p_request_id uuid)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  v_staff uuid := auth.uid();
begin
  if not (coalesce((auth.jwt() -> 'app_metadata' ->> 'remort_staff')::boolean, false) or fa_is_logistics_or_admin()) then
    raise exception 'Staff only';
  end if;

  update character_remort_requests
    set status = 'approved', decided_at = now(), decided_by = v_staff
    where id = p_request_id and status = 'pending';

  if not found then raise exception 'Request not found or already decided'; end if;
end;
$$;

create or replace function character_deny_remort(p_request_id uuid)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  v_staff uuid := auth.uid();
begin
  if not (coalesce((auth.jwt() -> 'app_metadata' ->> 'remort_staff')::boolean, false) or fa_is_logistics_or_admin()) then
    raise exception 'Staff only';
  end if;

  update character_remort_requests
    set status = 'denied', decided_at = now(), decided_by = v_staff
    where id = p_request_id and status = 'pending';

  if not found then raise exception 'Request not found or already decided'; end if;
end;
$$;


create or replace function requests_pending_count()
returns integer language plpgsql stable security definer
set search_path = public
as $$
begin
  if not fa_is_logistics_or_admin() then
    return 0;
  end if;

  return (
    (select count(*) from character_remort_requests where status = 'pending') +
    (select count(*) from oc_submission_requests where status = 'pending') +
    (select count(*) from kudos where status = 'pending')
  )::integer;
end;
$$;
