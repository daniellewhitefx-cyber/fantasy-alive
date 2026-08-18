-- Postgres grants EXECUTE on every new function to the PUBLIC pseudo-role
-- by default, which every actual role (including anon) inherits from
-- regardless of any role-specific grant or revoke. The previous version
-- of this file revoked EXECUTE from anon specifically, which had no
-- effect: PUBLIC's blanket grant meant anon could still call everything.
--
-- This revokes EXECUTE from PUBLIC instead (which does take it away from
-- anon, since anon has no other source of the privilege), then explicitly
-- re-grants it to authenticated and service_role, since those roles were
-- also only getting EXECUTE via the PUBLIC default, not an explicit grant
-- of their own, and revoking PUBLIC's grant would otherwise break every
-- RPC call in the app for signed-in users too. Also updates default
-- privileges so future functions created the same way (via the Supabase
-- SQL editor, as the postgres role) follow the same pattern.
revoke execute on all functions in schema public from public;
grant execute on all functions in schema public to authenticated, service_role;

alter default privileges in schema public revoke execute on functions from public;
alter default privileges in schema public grant execute on functions to authenticated, service_role;
