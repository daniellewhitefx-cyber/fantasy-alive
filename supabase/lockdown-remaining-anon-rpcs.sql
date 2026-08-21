revoke all on function admin_character_sheets(uuid[], text) from public, anon;
grant execute on function admin_character_sheets(uuid[], text) to authenticated;

revoke all on function bug_report_mark_resolved(uuid) from public, anon;
grant execute on function bug_report_mark_resolved(uuid) to authenticated;

revoke all on function bug_report_submit(text, text) from public, anon;
grant execute on function bug_report_submit(text, text) to authenticated;

revoke all on function character_names() from public, anon;
grant execute on function character_names() to authenticated;

revoke all on function character_noncombat_build_save(uuid, jsonb) from public, anon;
grant execute on function character_noncombat_build_save(uuid, jsonb) to authenticated;

revoke all on function craft_item(text, uuid, integer, uuid, text, text, integer, integer, integer, jsonb, boolean, text) from public, anon;
grant execute on function craft_item(text, uuid, integer, uuid, text, text, integer, integer, integer, jsonb, boolean, text) to authenticated;

revoke all on function event_log_admin_adjust_hours(text, uuid, integer, text) from public, anon;
grant execute on function event_log_admin_adjust_hours(text, uuid, integer, text) to authenticated;

revoke all on function event_log_admin_remove_hours_adjustment(uuid) from public, anon;
grant execute on function event_log_admin_remove_hours_adjustment(uuid) to authenticated;

revoke all on function event_log_apply_repeating_upkeep(text, uuid) from public, anon;
grant execute on function event_log_apply_repeating_upkeep(text, uuid) to authenticated;

revoke all on function event_log_cancel_upkeep(uuid) from public, anon;
grant execute on function event_log_cancel_upkeep(uuid) to authenticated;

revoke all on function event_log_log_upkeep(text, uuid, text, numeric, boolean) from public, anon;
grant execute on function event_log_log_upkeep(text, uuid, text, numeric, boolean) to authenticated;

revoke all on function event_log_mark_upkeep_actioned(uuid) from public, anon;
grant execute on function event_log_mark_upkeep_actioned(uuid) to authenticated;

revoke all on function event_log_stop_upkeep_repeat(uuid) from public, anon;
grant execute on function event_log_stop_upkeep_repeat(uuid) to authenticated;

revoke all on function teach_request_approve(uuid) from public, anon;
grant execute on function teach_request_approve(uuid) to authenticated;

revoke all on function teach_request_cancel(uuid) from public, anon;
grant execute on function teach_request_cancel(uuid) to authenticated;

revoke all on function teach_request_create(text, uuid, uuid) from public, anon;
grant execute on function teach_request_create(text, uuid, uuid) to authenticated;

revoke all on function teach_request_decline(uuid) from public, anon;
grant execute on function teach_request_decline(uuid) to authenticated;

revoke all on function teachable_skills_directory() from public, anon;
grant execute on function teachable_skills_directory() to authenticated;

revoke all on function fa_has_approved_teacher(uuid, text, text, text, text) from public, anon, authenticated;
