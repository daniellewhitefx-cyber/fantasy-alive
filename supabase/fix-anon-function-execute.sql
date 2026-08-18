-- Supabase grants EXECUTE on every new function in the public schema to
-- both the anon and authenticated roles by default. Every function in
-- this project is meant to be called by a signed-in player or staff
-- member (most already raise an exception if auth.uid() is null, or
-- check a staff flag from the JWT), so there's no legitimate reason for
-- the anon (signed-out) role to be able to call any of them. Supabase's
-- linter flags this as "Public Can Execute SECURITY DEFINER Function".
--
-- This revokes EXECUTE from anon on every existing function, and updates
-- the default privileges so future functions created the same way (via
-- the Supabase SQL editor, as the postgres role) don't get an anon grant
-- either. authenticated keeps EXECUTE, since that's the intended caller
-- for virtually everything here.
revoke execute on all functions in schema public from anon;
alter default privileges in schema public revoke execute on functions from anon;
