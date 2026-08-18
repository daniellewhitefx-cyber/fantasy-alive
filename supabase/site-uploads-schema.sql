insert into storage.buckets (id, name, public)
values ('home-feed-images', 'home-feed-images', true)
on conflict (id) do nothing;

insert into storage.buckets (id, name, public)
values ('auction-images', 'auction-images', true)
on conflict (id) do nothing;

-- No SELECT policy: both buckets are public (public = true above), so
-- object bytes are already served at /storage/v1/object/public/... with
-- no RLS check at all. A SELECT policy here isn't needed for that and
-- only adds the ability to enumerate every file in the bucket via the
-- API, which Supabase's linter flags as unwanted (public_bucket_allows_listing).
drop policy if exists "Public read for home feed images" on storage.objects;

drop policy if exists "Site admins can upload home feed images" on storage.objects;
create policy "Site admins can upload home feed images"
  on storage.objects for insert
  with check (bucket_id = 'home-feed-images' and fa_is_site_admin());

drop policy if exists "Site admins can delete home feed images" on storage.objects;
create policy "Site admins can delete home feed images"
  on storage.objects for delete
  using (bucket_id = 'home-feed-images' and fa_is_site_admin());

drop policy if exists "Public read for auction images" on storage.objects;

drop policy if exists "Auction staff can upload auction images" on storage.objects;
create policy "Auction staff can upload auction images"
  on storage.objects for insert
  with check (
    bucket_id = 'auction-images'
    and ((auth.jwt() -> 'app_metadata' ->> 'auction_staff')::boolean is true or fa_is_site_admin())
  );

drop policy if exists "Auction staff can delete auction images" on storage.objects;
create policy "Auction staff can delete auction images"
  on storage.objects for delete
  using (
    bucket_id = 'auction-images'
    and ((auth.jwt() -> 'app_metadata' ->> 'auction_staff')::boolean is true or fa_is_site_admin())
  );
