
alter table characters add column if not exists portrait_url text;

create or replace function character_set_portrait(p_character_id uuid, p_url text)
returns void language plpgsql security definer
set search_path = public
as $$
declare
  v_player uuid := auth.uid();
begin
  if v_player is null then raise exception 'Not signed in'; end if;

  update characters set portrait_url = nullif(trim(coalesce(p_url, '')), '')
    where id = p_character_id
      and (
        player_id = v_player
        or (auth.jwt() -> 'app_metadata' ->> 'character_staff')::boolean is true
        or fa_is_site_admin()
      );

  if not found then raise exception 'Character not found'; end if;
end;
$$;

insert into storage.buckets (id, name, public)
values ('character-portraits', 'character-portraits', true)
on conflict (id) do nothing;

drop policy if exists "Members can upload character portraits" on storage.objects;
create policy "Members can upload character portraits"
  on storage.objects for insert
  with check (bucket_id = 'character-portraits' and auth.uid() is not null);

drop policy if exists "Members can delete character portraits" on storage.objects;
create policy "Members can delete character portraits"
  on storage.objects for delete
  using (bucket_id = 'character-portraits' and auth.uid() is not null);
