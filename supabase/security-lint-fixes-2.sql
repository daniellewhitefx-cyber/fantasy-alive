-- Fixes for the two new categories of real findings from Supabase's latest
-- Performance/Security Advisor report (the "authenticated_security_
-- definer_function_executable" category -- 131 rows -- was already spot-
-- checked and resolved in security-lint-fixes.sql; every one of those
-- checks fa_is_site_admin() / fa_is_logistics_or_admin() /
-- fa_is_plot_or_admin() / fa_is_lore_or_admin(), a character_staff/other
-- app_metadata claim, or scopes its query to auth.uid() directly, so no
-- further action there).
--
-- 1. anon_security_definer_function_executable (22 rows): these SECURITY
--    DEFINER functions are reachable over PostgREST by the `anon` Postgres
--    role, i.e. a request with no session at all. Every one of them is
--    meant to be used only by a signed-in player or staff member, and
--    each already checks auth.uid()/a staff flag internally and raises an
--    exception when it's null/false -- so this was never exploitable, but
--    it's still bad practice to let an unauthenticated request reach the
--    function body at all. The Supabase client always sends the `anon`
--    API key as a header, but once a player is logged in that request
--    executes as the Postgres `authenticated` role (from their JWT), not
--    `anon` -- so revoking from `anon` only does not affect any signed-in
--    player or staff action.
--
-- 2. function_search_path_mutable (4 rows): these functions don't pin
--    search_path, so a malicious search_path set on the calling session
--    could in principle redirect an unqualified identifier inside the
--    function body to an attacker-controlled object. None of them
--    reference unqualified tables/functions in a way that's actually
--    exploitable today, but pinning search_path is a one-line, zero-risk
--    hardening. ALTER FUNCTION ... SET search_path only touches the
--    function's config, not its body, so this is safe to run regardless
--    of which exact version of each function is currently live.

revoke execute on function character_ensure_tag_requests(uuid, text) from public, anon;
grant execute on function character_ensure_tag_requests(uuid, text) to authenticated;

revoke execute on function character_set_portrait(uuid, text) from public, anon;
grant execute on function character_set_portrait(uuid, text) to authenticated;

revoke execute on function event_log_cancel_other_task(uuid) from public, anon;
grant execute on function event_log_cancel_other_task(uuid) to authenticated;

revoke execute on function event_log_claim_allowance(text, uuid) from public, anon;
grant execute on function event_log_claim_allowance(text, uuid) to authenticated;

revoke execute on function event_log_log_other_task(text, uuid, text, integer, integer) from public, anon;
grant execute on function event_log_log_other_task(text, uuid, text, integer, integer) to authenticated;

revoke execute on function event_log_mark_other_task_actioned(uuid) from public, anon;
grant execute on function event_log_mark_other_task_actioned(uuid) to authenticated;

revoke execute on function event_log_toggle_luxury(text, uuid, integer, boolean) from public, anon;
grant execute on function event_log_toggle_luxury(text, uuid, integer, boolean) to authenticated;

revoke execute on function event_roster(text) from public, anon;
grant execute on function event_roster(text) to authenticated;

revoke execute on function fa_character_merchant_level(uuid) from public, anon;
grant execute on function fa_character_merchant_level(uuid) to authenticated;

revoke execute on function fa_charge_shopping_travel(uuid, text, text) from public, anon;
grant execute on function fa_charge_shopping_travel(uuid, text, text) to authenticated;

revoke execute on function flex_pass_my_balance() from public, anon;
grant execute on function flex_pass_my_balance() to authenticated;

revoke execute on function flex_pass_purchase_grant(text) from public, anon;
grant execute on function flex_pass_purchase_grant(text) to authenticated;

revoke execute on function flex_pass_redeem(text) from public, anon;
grant execute on function flex_pass_redeem(text) to authenticated;

revoke execute on function my_event_registration(text) from public, anon;
grant execute on function my_event_registration(text) to authenticated;

revoke execute on function register_for_event(text, text, uuid, text, text, text, integer, boolean, text, text[], text, integer, boolean, text, jsonb, integer, text, text, text) from public, anon;
grant execute on function register_for_event(text, text, uuid, text, text, text, integer, boolean, text, text[], text, integer, boolean, text, jsonb, integer, text, text, text) to authenticated;

revoke execute on function shoppe_buy_item(text, uuid, text, text, integer, integer, integer, integer) from public, anon;
grant execute on function shoppe_buy_item(text, uuid, text, text, integer, integer, integer, integer) to authenticated;

revoke execute on function shoppe_cancel_sale(uuid) from public, anon;
grant execute on function shoppe_cancel_sale(uuid) to authenticated;

revoke execute on function shoppe_sell_item(text, uuid, text, text, integer, integer, boolean, integer, integer) from public, anon;
grant execute on function shoppe_sell_item(text, uuid, text, text, integer, integer, boolean, integer, integer) to authenticated;

revoke execute on function staff_delete_registration(uuid) from public, anon;
grant execute on function staff_delete_registration(uuid) to authenticated;

revoke execute on function staff_event_registrations(text) from public, anon;
grant execute on function staff_event_registrations(text) to authenticated;

revoke execute on function staff_player_characters(uuid) from public, anon;
grant execute on function staff_player_characters(uuid) to authenticated;

revoke execute on function staff_update_registration(uuid, text, uuid, text, text, integer, text, text[], text, integer, text, jsonb, integer, text, text, text) from public, anon;
grant execute on function staff_update_registration(uuid, text, uuid, text, text, integer, text, text[], text, integer, text, jsonb, integer, text, text, text) to authenticated;

alter function skills_true_cost(text, text, integer, text) set search_path = public;
alter function fa_merchant_rarity_quota(integer, integer) set search_path = public;
alter function fa_merchant_price_pct(integer) set search_path = public;
alter function fa_flex_pass_catalog(text) set search_path = public;
