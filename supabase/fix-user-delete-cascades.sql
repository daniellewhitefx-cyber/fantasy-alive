
do $$
declare
  fixes text[][] := array[
    array['bank_transactions', 'player_id', 'cascade'],
    array['bank_transactions', 'counterparty_id', 'set null'],
    array['bank_transactions', 'created_by', 'set null'],
    array['bank_bills', 'from_player_id', 'cascade'],
    array['bank_bills', 'to_player_id', 'cascade'],
    array['bank_withdrawal_requests', 'player_id', 'cascade'],
    array['bank_withdrawal_requests', 'fulfilled_by', 'set null'],
    array['auction_items', 'created_by', 'set null'],
    array['auction_items', 'winner_player_id', 'set null'],
    array['auction_bids', 'player_id', 'cascade'],
    array['announcements', 'created_by', 'set null'],
    array['xp_transactions', 'created_by', 'set null'],
    array['oc_transactions', 'created_by', 'set null'],
    array['event_info_items', 'created_by', 'set null'],
    array['home_feed_items', 'created_by', 'set null'],
    array['lore_entries', 'created_by', 'set null'],
    array['character_remort_requests', 'decided_by', 'set null'],
    array['oc_submission_requests', 'reviewed_by', 'set null']
  ];
  i int;
  tbl text;
  col text;
  action text;
  cname text;
begin
  for i in 1 .. array_length(fixes, 1) loop
    tbl := fixes[i][1];
    col := fixes[i][2];
    action := fixes[i][3];

    if to_regclass(tbl) is null then
      continue;
    end if;

    select con.conname into cname
    from pg_constraint con
    join pg_attribute att
      on att.attrelid = con.conrelid and att.attnum = any(con.conkey)
    where con.contype = 'f'
      and con.conrelid = tbl::regclass
      and att.attname = col
      and con.confrelid = 'auth.users'::regclass
    limit 1;

    if cname is not null then
      execute format('alter table %I drop constraint %I', tbl, cname);
    end if;

    execute format(
      'alter table %I add constraint %I foreign key (%I) references auth.users(id) on delete %s',
      tbl, tbl || '_' || col || '_fkey', col, action
    );
  end loop;
end $$;
