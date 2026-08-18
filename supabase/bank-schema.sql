create table if not exists profiles (
  id uuid primary key references auth.users(id) on delete cascade,
  display_name text not null,
  auto_bank_log_coin boolean not null default false,
  created_at timestamptz not null default now()
);

alter table profiles enable row level security;

drop policy if exists "Profiles are publicly readable" on profiles;
create policy "Profiles are publicly readable"
  on profiles for select
  using (true);

create or replace function handle_new_user()
returns trigger language plpgsql security definer as $$
begin
  begin
    insert into profiles (id, display_name)
    values (new.id, coalesce(new.raw_user_meta_data ->> 'display_name', new.email))
    on conflict (id) do nothing;
  exception when others then
    raise warning 'handle_new_user: failed to create profile for %: %', new.id, sqlerrm;
  end;
  return new;
end;
$$;

drop trigger if exists on_auth_user_created on auth.users;
create trigger on_auth_user_created
  after insert on auth.users
  for each row execute function handle_new_user();

insert into profiles (id, display_name)
select id, coalesce(raw_user_meta_data ->> 'display_name', email) from auth.users
on conflict (id) do nothing;

create or replace function bank_set_auto_bank_preference(p_enabled boolean)
returns void language plpgsql security definer as $$
begin
  if auth.uid() is null then raise exception 'Not signed in'; end if;
  update profiles set auto_bank_log_coin = p_enabled where id = auth.uid();
end;
$$;

create table if not exists bank_transactions (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references auth.users(id) on delete cascade,
  type text not null check (type in (
    'deposit', 'withdrawal', 'transfer_in', 'transfer_out',
    'bill_payment_in', 'bill_payment_out', 'log_bank'
  )),
  amount numeric(12,2) not null check (amount > 0),
  note text,
  counterparty_id uuid references auth.users(id) on delete set null,
  created_by uuid references auth.users(id) on delete set null,
  created_at timestamptz not null default now()
);

create index if not exists bank_transactions_player_idx on bank_transactions(player_id, created_at desc);

alter table bank_transactions enable row level security;

drop policy if exists "Players see their own transactions" on bank_transactions;
create policy "Players see their own transactions"
  on bank_transactions for select
  using (
    player_id = auth.uid()
    or (auth.jwt() -> 'app_metadata' ->> 'bank_staff')::boolean is true
    or fa_is_site_admin()
  );

create or replace function bank_balance(p_player uuid)
returns numeric language sql stable security definer as $$
  select coalesce(sum(
    case
      when type in ('deposit', 'transfer_in', 'bill_payment_in', 'log_bank') then amount
      when type in ('withdrawal', 'transfer_out', 'bill_payment_out') then -amount
      else 0
    end
  ), 0)
  from bank_transactions
  where player_id = p_player;
$$;

revoke execute on function bank_balance(uuid) from public, authenticated, anon;

create or replace function bank_my_balance()
returns numeric language sql stable security definer as $$
  select bank_balance(auth.uid());
$$;

create or replace function bank_staff_player_balance(p_player uuid)
returns numeric language plpgsql stable security definer as $$
begin
  if not (coalesce((auth.jwt() -> 'app_metadata' ->> 'bank_staff')::boolean, false) or fa_is_site_admin()) then
    raise exception 'Staff only';
  end if;
  return bank_balance(p_player);
end;
$$;

create or replace function bank_send_coin(p_recipient uuid, p_amount numeric, p_note text)
returns void language plpgsql security definer as $$
declare
  v_sender uuid := auth.uid();
begin
  if v_sender is null then raise exception 'Not signed in'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Amount must be positive'; end if;
  if p_recipient = v_sender then raise exception 'Cannot send coin to yourself'; end if;
  if not exists (select 1 from auth.users where id = p_recipient) then
    raise exception 'Recipient not found';
  end if;
  if bank_balance(v_sender) < p_amount then raise exception 'Insufficient balance'; end if;

  insert into bank_transactions (player_id, type, amount, note, counterparty_id, created_by)
    values (v_sender, 'transfer_out', p_amount, p_note, p_recipient, v_sender);
  insert into bank_transactions (player_id, type, amount, note, counterparty_id, created_by)
    values (p_recipient, 'transfer_in', p_amount, p_note, v_sender, v_sender);
end;
$$;

create table if not exists bank_bills (
  id uuid primary key default gen_random_uuid(),
  from_player_id uuid not null references auth.users(id) on delete cascade,
  to_player_id uuid not null references auth.users(id) on delete cascade,
  amount numeric(12,2) not null check (amount > 0),
  note text,
  status text not null default 'pending' check (status in ('pending', 'paid', 'declined', 'cancelled')),
  created_at timestamptz not null default now(),
  resolved_at timestamptz
);

alter table bank_bills enable row level security;

drop policy if exists "Bills are visible to both parties" on bank_bills;
create policy "Bills are visible to both parties"
  on bank_bills for select
  using (from_player_id = auth.uid() or to_player_id = auth.uid());

create or replace function bank_request_bill(p_target uuid, p_amount numeric, p_note text)
returns void language plpgsql security definer as $$
declare
  v_from uuid := auth.uid();
begin
  if v_from is null then raise exception 'Not signed in'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Amount must be positive'; end if;
  if p_target = v_from then raise exception 'Cannot bill yourself'; end if;
  if not exists (select 1 from auth.users where id = p_target) then
    raise exception 'Player not found';
  end if;

  insert into bank_bills (from_player_id, to_player_id, amount, note)
    values (v_from, p_target, p_amount, p_note);
end;
$$;

create or replace function bank_pay_bill(p_bill_id uuid)
returns void language plpgsql security definer as $$
declare
  v_bill bank_bills;
  v_payer uuid := auth.uid();
begin
  select * into v_bill from bank_bills where id = p_bill_id for update;
  if not found then raise exception 'Bill not found'; end if;
  if v_bill.to_player_id != v_payer then raise exception 'This bill is not addressed to you'; end if;
  if v_bill.status != 'pending' then raise exception 'This bill is no longer pending'; end if;
  if bank_balance(v_payer) < v_bill.amount then raise exception 'Insufficient balance'; end if;

  insert into bank_transactions (player_id, type, amount, note, counterparty_id, created_by)
    values (v_payer, 'bill_payment_out', v_bill.amount, v_bill.note, v_bill.from_player_id, v_payer);
  insert into bank_transactions (player_id, type, amount, note, counterparty_id, created_by)
    values (v_bill.from_player_id, 'bill_payment_in', v_bill.amount, v_bill.note, v_payer, v_payer);

  update bank_bills set status = 'paid', resolved_at = now() where id = p_bill_id;
end;
$$;

create or replace function bank_decline_bill(p_bill_id uuid)
returns void language plpgsql security definer as $$
declare
  v_bill bank_bills;
begin
  select * into v_bill from bank_bills where id = p_bill_id for update;
  if not found then raise exception 'Bill not found'; end if;
  if v_bill.to_player_id != auth.uid() then raise exception 'This bill is not addressed to you'; end if;
  if v_bill.status != 'pending' then raise exception 'This bill is no longer pending'; end if;
  update bank_bills set status = 'declined', resolved_at = now() where id = p_bill_id;
end;
$$;

create or replace function bank_cancel_bill(p_bill_id uuid)
returns void language plpgsql security definer as $$
declare
  v_bill bank_bills;
begin
  select * into v_bill from bank_bills where id = p_bill_id for update;
  if not found then raise exception 'Bill not found'; end if;
  if v_bill.from_player_id != auth.uid() then raise exception 'This is not your bill to cancel'; end if;
  if v_bill.status != 'pending' then raise exception 'This bill is no longer pending'; end if;
  update bank_bills set status = 'cancelled', resolved_at = now() where id = p_bill_id;
end;
$$;

create table if not exists bank_withdrawal_requests (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references auth.users(id) on delete cascade,
  amount numeric(12,2) not null check (amount > 0),
  note text,
  status text not null default 'pending' check (status in ('pending', 'fulfilled', 'cancelled')),
  created_at timestamptz not null default now(),
  fulfilled_at timestamptz,
  fulfilled_by uuid references auth.users(id) on delete set null
);

alter table bank_withdrawal_requests enable row level security;

drop policy if exists "Players see their own withdrawal requests, staff sees all" on bank_withdrawal_requests;
create policy "Players see their own withdrawal requests, staff sees all"
  on bank_withdrawal_requests for select
  using (
    player_id = auth.uid()
    or (auth.jwt() -> 'app_metadata' ->> 'bank_staff')::boolean is true
    or fa_is_site_admin()
  );

drop policy if exists "Players create their own withdrawal requests" on bank_withdrawal_requests;
create policy "Players create their own withdrawal requests"
  on bank_withdrawal_requests for insert
  with check (player_id = auth.uid());

create or replace function bank_request_withdrawal(p_amount numeric, p_note text)
returns void language plpgsql security definer as $$
declare
  v_player uuid := auth.uid();
begin
  if v_player is null then raise exception 'Not signed in'; end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Amount must be positive'; end if;
  insert into bank_withdrawal_requests (player_id, amount, note)
    values (v_player, p_amount, p_note);
end;
$$;

create or replace function bank_cancel_withdrawal(p_request_id uuid)
returns void language plpgsql security definer as $$
declare
  v_req bank_withdrawal_requests;
begin
  select * into v_req from bank_withdrawal_requests where id = p_request_id for update;
  if not found then raise exception 'Request not found'; end if;
  if v_req.player_id != auth.uid() then raise exception 'This is not your request'; end if;
  if v_req.status != 'pending' then raise exception 'This request is no longer pending'; end if;
  update bank_withdrawal_requests set status = 'cancelled' where id = p_request_id;
end;
$$;

create or replace function bank_staff_fulfill_withdrawal(p_request_id uuid)
returns void language plpgsql security definer as $$
declare
  v_req bank_withdrawal_requests;
  v_staff uuid := auth.uid();
begin
  if not (coalesce((auth.jwt() -> 'app_metadata' ->> 'bank_staff')::boolean, false) or fa_is_site_admin()) then
    raise exception 'Staff only';
  end if;

  select * into v_req from bank_withdrawal_requests where id = p_request_id for update;
  if not found then raise exception 'Request not found'; end if;
  if v_req.status != 'pending' then raise exception 'This request is no longer pending'; end if;
  if bank_balance(v_req.player_id) < v_req.amount then
    raise exception 'Player no longer has sufficient balance for this request';
  end if;

  insert into bank_transactions (player_id, type, amount, note, created_by)
    values (v_req.player_id, 'withdrawal', v_req.amount, v_req.note, v_staff);

  update bank_withdrawal_requests
    set status = 'fulfilled', fulfilled_at = now(), fulfilled_by = v_staff
    where id = p_request_id;
end;
$$;

create or replace function bank_staff_deposit(p_player uuid, p_amount numeric, p_note text)
returns void language plpgsql security definer as $$
declare
  v_staff uuid := auth.uid();
begin
  if not (coalesce((auth.jwt() -> 'app_metadata' ->> 'bank_staff')::boolean, false) or fa_is_site_admin()) then
    raise exception 'Staff only';
  end if;
  if p_amount is null or p_amount <= 0 then raise exception 'Amount must be positive'; end if;
  if not exists (select 1 from auth.users where id = p_player) then
    raise exception 'Player not found';
  end if;

  insert into bank_transactions (player_id, type, amount, note, created_by)
    values (p_player, 'deposit', p_amount, p_note, v_staff);
end;
$$;

grant select on profiles to authenticated, anon;
grant select on bank_transactions to authenticated;
grant select on bank_bills to authenticated;
grant select, insert on bank_withdrawal_requests to authenticated;
