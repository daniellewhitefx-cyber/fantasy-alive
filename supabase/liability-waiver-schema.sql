-- Consent to Participate in EAO Games and Release From Liability: one
-- row per player, re-signable so a returning player can re-sign after
-- a policy update. The full waiver text lives on the page itself
-- (mirrors the Policies page's Consent to Participate section), this
-- table just records that a specific player affirmed both required
-- acknowledgements and typed their name as a signature.

create table if not exists liability_waivers (
  id uuid primary key default gen_random_uuid(),
  player_id uuid not null references auth.users(id) on delete cascade unique,
  legal_name text not null,
  acknowledged_safety_rules boolean not null default false,
  acknowledged_health_policy boolean not null default false,
  signature_name text not null,
  guardian_signature_name text,
  signed_at timestamptz not null default now()
);

alter table liability_waivers enable row level security;
drop policy if exists "Players see their own liability waiver" on liability_waivers;
create policy "Players see their own liability waiver"
  on liability_waivers for select
  using (player_id = auth.uid() or fa_is_logistics_or_admin());

grant select on liability_waivers to authenticated;

create or replace function liability_waiver_sign(
  p_legal_name text,
  p_acknowledged_safety_rules boolean,
  p_acknowledged_health_policy boolean,
  p_signature_name text,
  p_guardian_signature_name text
)
returns void language plpgsql security definer as $$
declare
  v_player uuid := auth.uid();
begin
  if v_player is null then raise exception 'Not signed in'; end if;
  if coalesce(trim(p_legal_name), '') = '' then raise exception 'Legal name is required'; end if;
  if coalesce(trim(p_signature_name), '') = '' then raise exception 'A signature is required'; end if;
  if not coalesce(p_acknowledged_safety_rules, false) then raise exception 'You must acknowledge the safety rules to sign'; end if;
  if not coalesce(p_acknowledged_health_policy, false) then raise exception 'You must acknowledge the Health and Care of Player Policy to sign'; end if;

  insert into liability_waivers (
    player_id, legal_name, acknowledged_safety_rules, acknowledged_health_policy, signature_name, guardian_signature_name, signed_at
  ) values (
    v_player, trim(p_legal_name), true, true, trim(p_signature_name), nullif(trim(p_guardian_signature_name), ''), now()
  )
  on conflict (player_id) do update set
    legal_name = excluded.legal_name,
    acknowledged_safety_rules = excluded.acknowledged_safety_rules,
    acknowledged_health_policy = excluded.acknowledged_health_policy,
    signature_name = excluded.signature_name,
    guardian_signature_name = excluded.guardian_signature_name,
    signed_at = now();
end;
$$;
