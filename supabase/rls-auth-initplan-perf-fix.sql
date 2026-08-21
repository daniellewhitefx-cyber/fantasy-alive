drop policy if exists "Members see only their own private notes" on member_private_notes;
create policy "Members see only their own private notes"
  on member_private_notes for select
  using (id = (select auth.uid()));

create policy "Auction items visible to everyone, staff also see drafts"
  on auction_items for select
  using (
    status in ('live', 'closed')
    or ((select auth.jwt()) -> 'app_metadata' ->> 'auction_staff')::boolean is true
    or fa_is_site_admin()
  );

drop policy if exists "Players and staff see backstory submissions" on character_backstories;
create policy "Players and staff see backstory submissions"
  on character_backstories for select
  using (player_id = (select auth.uid()) or fa_is_backstory_viewer());

drop policy if exists "Players and Lore see backstory submissions" on character_backstories;
create policy "Players and Lore see backstory submissions"
  on character_backstories for select
  using (player_id = (select auth.uid()) or fa_is_lore_or_admin());

drop policy if exists "Players see their own transactions" on bank_transactions;
create policy "Players see their own transactions"
  on bank_transactions for select
  using (
    player_id = (select auth.uid())
    or ((select auth.jwt()) -> 'app_metadata' ->> 'bank_staff')::boolean is true
    or fa_is_site_admin()
  );

drop policy if exists "Bills are visible to both parties" on bank_bills;
create policy "Bills are visible to both parties"
  on bank_bills for select
  using (from_player_id = (select auth.uid()) or to_player_id = (select auth.uid()));

drop policy if exists "Players see their own withdrawal requests, staff sees all" on bank_withdrawal_requests;
create policy "Players see their own withdrawal requests, staff sees all"
  on bank_withdrawal_requests for select
  using (
    player_id = (select auth.uid())
    or ((select auth.jwt()) -> 'app_metadata' ->> 'bank_staff')::boolean is true
    or fa_is_site_admin()
  );

drop policy if exists "Players create their own withdrawal requests" on bank_withdrawal_requests;
create policy "Players create their own withdrawal requests"
  on bank_withdrawal_requests for insert
  with check (player_id = (select auth.uid()));

drop policy if exists "Players can view their own bug reports" on bug_reports;
create policy "Players can view their own bug reports"
  on bug_reports for select
  using (player_id = (select auth.uid()) or fa_is_site_admin());

drop policy if exists "Players see their own characters" on characters;
create policy "Players see their own characters"
  on characters for select
  using (
    player_id = (select auth.uid())
    or ((select auth.jwt()) -> 'app_metadata' ->> 'remort_staff')::boolean is true
    or ((select auth.jwt()) -> 'app_metadata' ->> 'character_staff')::boolean is true
    or fa_is_site_admin()
  );

drop policy if exists "Players see their own character skills" on character_skills;
create policy "Players see their own character skills"
  on character_skills for select
  using (
    player_id = (select auth.uid())
    or ((select auth.jwt()) -> 'app_metadata' ->> 'character_staff')::boolean is true
    or fa_is_site_admin()
  );

drop policy if exists "Players and staff see XP transactions" on xp_transactions;
create policy "Players and staff see XP transactions"
  on xp_transactions for select
  using (
    player_id = (select auth.uid())
    or ((select auth.jwt()) -> 'app_metadata' ->> 'character_staff')::boolean is true
    or fa_is_site_admin()
  );

drop policy if exists "Players and staff see OC transactions" on oc_transactions;
create policy "Players and staff see OC transactions"
  on oc_transactions for select
  using (
    player_id = (select auth.uid())
    or ((select auth.jwt()) -> 'app_metadata' ->> 'character_staff')::boolean is true
    or fa_is_site_admin()
  );

drop policy if exists "Players and staff see item transfers" on character_item_transfers;
create policy "Players and staff see item transfers"
  on character_item_transfers for select
  using (
    exists (select 1 from characters c where c.id = from_character_id and c.player_id = (select auth.uid()))
    or exists (select 1 from characters c where c.id = to_character_id and c.player_id = (select auth.uid()))
    or fa_is_logistics_or_admin()
  );

create policy "Members can upload character portraits"
  on storage.objects for insert
  with check (bucket_id = 'character-portraits' and (select auth.uid()) is not null);

create policy "Members can delete character portraits"
  on storage.objects for delete
  using (bucket_id = 'character-portraits' and (select auth.uid()) is not null);

drop policy if exists "Players and staff see character status effects" on character_status_effects;
create policy "Players and staff see character status effects"
  on character_status_effects for select
  using (
    player_id = (select auth.uid())
    or ((select auth.jwt()) -> 'app_metadata' ->> 'character_staff')::boolean is true
    or fa_is_site_admin()
  );

drop policy if exists "Players see their own characters" on characters;
create policy "Players see their own characters"
  on characters for select
  using (
    player_id = (select auth.uid())
    or ((select auth.jwt()) -> 'app_metadata' ->> 'remort_staff')::boolean is true
    or ((select auth.jwt()) -> 'app_metadata' ->> 'character_staff')::boolean is true
    or fa_is_site_admin()
  );

drop policy if exists "Players see their own character skills" on character_skills;
create policy "Players see their own character skills"
  on character_skills for select
  using (
    player_id = (select auth.uid())
    or ((select auth.jwt()) -> 'app_metadata' ->> 'character_staff')::boolean is true
    or fa_is_site_admin()
  );

drop policy if exists "Players see their own crafting log" on crafting_log;
create policy "Players see their own crafting log"
  on crafting_log for select
  using (player_id = (select auth.uid()) or fa_is_logistics_or_admin());

drop policy if exists "Players see their own consumed materials" on crafting_materials_consumed;
create policy "Players see their own consumed materials"
  on crafting_materials_consumed for select
  using (
    exists (
      select 1 from crafting_log cl
      where cl.id = crafting_log_id and (cl.player_id = (select auth.uid()) or fa_is_logistics_or_admin())
    )
  );

drop policy if exists "Players see adjustments that affect them, staff see all" on event_log_hours_adjustments;
create policy "Players see adjustments that affect them, staff see all"
  on event_log_hours_adjustments for select
  using (
    character_id is null
    or exists (select 1 from characters c where c.id = character_id and c.player_id = (select auth.uid()))
    or fa_is_logistics_or_admin()
  );

drop policy if exists "Players see their own emergency contact form" on emergency_contact_forms;
create policy "Players see their own emergency contact form"
  on emergency_contact_forms for select
  using (player_id = (select auth.uid()) or fa_is_logistics_or_admin());

drop policy if exists "Players see their own allowance claims" on event_log_allowance_claims;
create policy "Players see their own allowance claims"
  on event_log_allowance_claims for select
  using (
    character_id in (select id from characters where player_id = (select auth.uid()))
    or fa_is_logistics_or_admin()
  );

drop policy if exists "Players see their own luxuries" on event_log_luxuries;
create policy "Players see their own luxuries"
  on event_log_luxuries for select
  using (player_id = (select auth.uid()) or fa_is_logistics_or_admin());

drop policy if exists "Players see their own OC spends" on event_log_oc_spends;
create policy "Players see their own OC spends"
  on event_log_oc_spends for select
  using (player_id = (select auth.uid()) or fa_is_logistics_or_admin());

drop policy if exists "Players and staff see their flex pass transactions" on flex_pass_transactions;
create policy "Players and staff see their flex pass transactions"
  on flex_pass_transactions for select
  using (
    player_id = (select auth.uid())
    or ((select auth.jwt()) -> 'app_metadata' ->> 'character_staff')::boolean is true
    or fa_is_site_admin()
  );

drop policy if exists "Players see their own friend rows" on character_friends;
create policy "Players see their own friend rows"
  on character_friends for select
  using (
    character_id in (select id from characters where player_id = (select auth.uid()))
    or friend_character_id in (select id from characters where player_id = (select auth.uid()))
    or fa_is_site_admin()
  );

drop policy if exists "Players send friend requests from their own characters" on character_friends;
create policy "Players send friend requests from their own characters"
  on character_friends for insert
  with check (
    character_id in (select id from characters where player_id = (select auth.uid()))
    and status = 'pending'
  );

drop policy if exists "Recipients accept friend requests" on character_friends;
create policy "Recipients accept friend requests"
  on character_friends for update
  using (
    friend_character_id in (select id from characters where player_id = (select auth.uid()))
    and status = 'pending'
  )
  with check (
    friend_character_id in (select id from characters where player_id = (select auth.uid()))
    and status = 'accepted'
  );

drop policy if exists "Either side can remove a request or friendship" on character_friends;
create policy "Either side can remove a request or friendship"
  on character_friends for delete
  using (
    character_id in (select id from characters where player_id = (select auth.uid()))
    or friend_character_id in (select id from characters where player_id = (select auth.uid()))
    or fa_is_site_admin()
  );

drop policy if exists "Players and staff see item grants" on staff_item_grants;
create policy "Players and staff see item grants"
  on staff_item_grants for select
  using (
    exists (select 1 from characters c where c.id = character_id and c.player_id = (select auth.uid()))
    or fa_is_logistics_or_admin()
  );

drop policy if exists "Players see their own tag requests" on character_tag_requests;
create policy "Players see their own tag requests"
  on character_tag_requests for select
  using (player_id = (select auth.uid()) or fa_is_logistics_or_admin());

drop policy if exists "Players see kudos they gave" on kudos;
create policy "Players see kudos they gave"
  on kudos for select
  using (from_player_id = (select auth.uid()) or fa_is_site_admin());

drop policy if exists "Players give kudos" on kudos;
create policy "Players give kudos"
  on kudos for insert
  with check (from_player_id = (select auth.uid()));

drop policy if exists "Players see their own liability waiver" on liability_waivers;
create policy "Players see their own liability waiver"
  on liability_waivers for select
  using (player_id = (select auth.uid()) or fa_is_logistics_or_admin());

drop policy if exists "Only lore editors can insert" on lore_entries;
create policy "Only lore editors can insert"
  on lore_entries for insert
  with check (((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'lore_editor' or fa_is_site_admin());

drop policy if exists "Only lore editors can update" on lore_entries;
create policy "Only lore editors can update"
  on lore_entries for update
  using (((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'lore_editor' or fa_is_site_admin());

drop policy if exists "Only lore editors can delete" on lore_entries;
create policy "Only lore editors can delete"
  on lore_entries for delete
  using (((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'lore_editor' or fa_is_site_admin());

create policy "Lore editors can upload images"
  on storage.objects for insert
  with check (bucket_id = 'lore-images' and (((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'lore_editor' or fa_is_site_admin()));

create policy "Lore editors can delete images"
  on storage.objects for delete
  using (bucket_id = 'lore-images' and (((select auth.jwt()) -> 'app_metadata' ->> 'role') = 'lore_editor' or fa_is_site_admin()));

drop policy if exists "Market listings visibility" on market_listings;
create policy "Market listings visibility"
  on market_listings for select
  using (
    listed_by = (select auth.uid())
    or exists (select 1 from characters c where c.id = buyer_character_id and c.player_id = (select auth.uid()))
    or fa_is_logistics_or_admin()
    or fa_is_plot_or_admin()
    or (status = 'active' and coalesce((select is_open from market_settings where id = true), false))
  );

drop policy if exists "Players see their own department memberships" on department_members;
create policy "Players see their own department memberships"
  on department_members for select
  using (player_id = (select auth.uid()) or fa_is_site_admin());

drop policy if exists "Players see messages they sent or can receive" on messages;
create policy "Players see messages they sent or can receive"
  on messages for select
  using (
    sender_id = (select auth.uid())
    or recipient_player_id = (select auth.uid())
    or exists (
      select 1 from department_members dm
      where dm.department_id = messages.recipient_department_id
        and dm.player_id = (select auth.uid())
    )
  );

drop policy if exists "Players see their own read receipts" on message_reads;
create policy "Players see their own read receipts"
  on message_reads for select
  using (player_id = (select auth.uid()));

drop policy if exists "Players see their own folders" on message_folders;
create policy "Players see their own folders"
  on message_folders for select
  using (player_id = (select auth.uid()));

drop policy if exists "Players see their own folder assignments" on message_folder_assignments;
create policy "Players see their own folder assignments"
  on message_folder_assignments for select
  using (player_id = (select auth.uid()));

drop policy if exists "Players see their own non-combat build skills" on character_noncombat_skills;
create policy "Players see their own non-combat build skills"
  on character_noncombat_skills for select
  using (
    player_id = (select auth.uid())
    or ((select auth.jwt()) -> 'app_metadata' ->> 'character_staff')::boolean is true
    or fa_is_site_admin()
  );

drop policy if exists "Players and staff see other task log" on event_log_other_tasks;
create policy "Players and staff see other task log"
  on event_log_other_tasks for select
  using (player_id = (select auth.uid()) or fa_is_logistics_or_admin());

drop policy if exists "Players see their own department memberships" on department_members;
create policy "Players see their own department memberships"
  on department_members for select
  using (player_id = (select auth.uid()) or fa_is_site_admin());

drop policy if exists "Players and staff see their own registration non-combat skills" on registration_noncombat_skills;
create policy "Players and staff see their own registration non-combat skills"
  on registration_noncombat_skills for select
  using (
    exists (
      select 1 from registrations r
      where r.id = registration_noncombat_skills.registration_id
        and (r.player_id = (select auth.uid()) or fa_is_logistics_or_admin())
    )
  );

drop policy if exists "Players and staff see registrations" on registrations;
create policy "Players and staff see registrations"
  on registrations for select
  using (player_id = (select auth.uid()) or fa_is_logistics_or_admin());

drop policy if exists "Players see their own characters" on characters;
create policy "Players see their own characters"
  on characters for select
  using (
    player_id = (select auth.uid())
    or ((select auth.jwt()) -> 'app_metadata' ->> 'remort_staff')::boolean is true
    or ((select auth.jwt()) -> 'app_metadata' ->> 'character_staff')::boolean is true
    or fa_is_site_admin()
  );

drop policy if exists "Players and staff see remort requests" on character_remort_requests;
create policy "Players and staff see remort requests"
  on character_remort_requests for select
  using (
    player_id = (select auth.uid())
    or ((select auth.jwt()) -> 'app_metadata' ->> 'remort_staff')::boolean is true
    or fa_is_logistics_or_admin()
  );

drop policy if exists "Players and staff see OC submissions" on oc_submission_requests;
create policy "Players and staff see OC submissions"
  on oc_submission_requests for select
  using (player_id = (select auth.uid()) or fa_is_logistics_or_admin());

drop policy if exists "Players see kudos about them" on kudos;
create policy "Players see kudos about them"
  on kudos for select
  using (
    from_player_id = (select auth.uid())
    or to_player_id = (select auth.uid())
    or to_character_id in (select id from characters where player_id = (select auth.uid()))
    or fa_is_logistics_or_admin()
  );

drop policy if exists "Players and staff see remort requests" on character_remort_requests;
create policy "Players and staff see remort requests"
  on character_remort_requests for select
  using (
    player_id = (select auth.uid())
    or ((select auth.jwt()) -> 'app_metadata' ->> 'remort_staff')::boolean is true
    or fa_is_logistics_or_admin()
  );

drop policy if exists "Players see their own shoppe purchases" on shoppe_purchases;
create policy "Players see their own shoppe purchases"
  on shoppe_purchases for select
  using (player_id = (select auth.uid()) or fa_is_logistics_or_admin());

drop policy if exists "Players see their own shopping trips" on event_log_shopping_trips;
create policy "Players see their own shopping trips"
  on event_log_shopping_trips for select
  using (
    character_id in (select id from characters where player_id = (select auth.uid()))
    or fa_is_logistics_or_admin()
  );

drop policy if exists "Players see their own shoppe sales" on shoppe_sales;
create policy "Players see their own shoppe sales"
  on shoppe_sales for select
  using (player_id = (select auth.uid()) or fa_is_logistics_or_admin());

create policy "Auction staff can upload auction images"
  on storage.objects for insert
  with check (
    bucket_id = 'auction-images'
    and (((select auth.jwt()) -> 'app_metadata' ->> 'auction_staff')::boolean is true or fa_is_site_admin())
  );

create policy "Auction staff can delete auction images"
  on storage.objects for delete
  using (
    bucket_id = 'auction-images'
    and (((select auth.jwt()) -> 'app_metadata' ->> 'auction_staff')::boolean is true or fa_is_site_admin())
  );

drop policy if exists "Players see their own known spells" on character_known_spells;
create policy "Players see their own known spells"
  on character_known_spells for select
  using (player_id = (select auth.uid()) or fa_is_site_admin());

drop policy if exists "Students and teachers see their own teach requests" on character_teach_requests;
create policy "Students and teachers see their own teach requests"
  on character_teach_requests for select
  using (student_player_id = (select auth.uid()) or teacher_player_id = (select auth.uid()) or fa_is_logistics_or_admin());

drop policy if exists "Players see their own training purchases" on event_log_training_purchases;
create policy "Players see their own training purchases"
  on event_log_training_purchases for select
  using (player_id = (select auth.uid()) or fa_is_logistics_or_admin());

drop policy if exists "Players see their own upkeep costs" on event_log_upkeep_costs;
create policy "Players see their own upkeep costs"
  on event_log_upkeep_costs for select
  using (player_id = (select auth.uid()) or fa_is_logistics_or_admin());

drop policy if exists "Players see their own working sessions" on event_log_working_sessions;
create policy "Players see their own working sessions"
  on event_log_working_sessions for select
  using (player_id = (select auth.uid()) or fa_is_logistics_or_admin());
