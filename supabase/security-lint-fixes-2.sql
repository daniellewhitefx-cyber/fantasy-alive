
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
