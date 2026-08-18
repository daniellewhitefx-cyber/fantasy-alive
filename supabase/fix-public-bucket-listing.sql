-- The lore-images, home-feed-images, and auction-images buckets are all
-- public (public = true), so their object bytes are already served at
-- /storage/v1/object/public/... with no RLS check at all. A broad SELECT
-- policy on storage.objects isn't needed for that, and only adds the
-- ability to enumerate every file in each bucket via the API, which
-- Supabase's linter flags as unwanted (public_bucket_allows_listing).
-- Nothing in the app calls storage.from(...).list() on these buckets, so
-- dropping the SELECT policy doesn't affect anything.
drop policy if exists "Public read for lore images" on storage.objects;
drop policy if exists "Public read for home feed images" on storage.objects;
drop policy if exists "Public read for auction images" on storage.objects;
