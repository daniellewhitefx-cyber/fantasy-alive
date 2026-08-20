-- Redefines "unread" for the Messages badge as "needs your reply" rather
-- than "you haven't opened it yet" -- opening a thread to read it
-- currently clears the notification even if you never actually answer.
-- A thread now counts as needing attention when the most recent message
-- in it wasn't sent by you. A department thread counts as answered once
-- ANY member of that department has sent the latest message in it, not
-- just you personally, since department inboxes are shared.

create or replace function message_unread_count()
returns integer language sql stable security definer
set search_path = public
as $$
  select count(distinct m.thread_key)::integer
  from messages m
  where m.created_at = (select max(m2.created_at) from messages m2 where m2.thread_key = m.thread_key)
    and (
      m.recipient_player_id = auth.uid()
      or exists (
        select 1 from department_members dm
        where dm.department_id = m.recipient_department_id and dm.player_id = auth.uid()
      )
    )
    and m.sender_id != auth.uid()
    and not exists (
      select 1 from department_members dm2
      where dm2.department_id = m.recipient_department_id and dm2.player_id = m.sender_id
    );
$$;
