-- Fixes for two real findings from Supabase's Performance/Security
-- Advisor lints.
--
-- 1. bank_balance(uuid) / xp_balance(uuid) / oc_balance(uuid) are internal
--    SECURITY DEFINER helpers meant to be called only from other functions
--    (bank_my_balance, bank_staff_player_balance, character_staff_xp_balance,
--    etc), never directly by a client. bank-schema.sql and
--    character-admin-schema.sql already revoke execute on them right after
--    creation -- but Supabase's linter is currently showing all three as
--    callable by the authenticated role via /rest/v1/rpc/..., which would
--    let any signed-in player look up ANY other player's bank/XP/OC balance
--    by guessing or knowing their UUID. Re-running the revokes here is
--    idempotent and safe regardless of why they drifted (a function
--    replaced outside these files, a run that skipped the revoke line,
--    etc) -- run this immediately.
--
-- 2. The rest of the "SECURITY DEFINER executable by authenticated" lint
--    entries (the other 100+ rows) were spot-checked and are all
--    intentional: every one either checks fa_is_site_admin() /
--    fa_is_logistics_or_admin() / fa_is_plot_or_admin(), the
--    character_staff app_metadata claim, or scopes its query to auth.uid()
--    directly. That pattern (SECURITY DEFINER + an internal auth.uid()/
--    staff check) is how every write RPC on this site works, since RLS
--    alone can't express "you may write this row if X" for anything more
--    complex than row ownership -- no fix needed there.

revoke execute on function bank_balance(uuid) from public, authenticated, anon;
revoke execute on function xp_balance(uuid) from public, authenticated, anon;
revoke execute on function oc_balance(uuid) from public, authenticated, anon;
