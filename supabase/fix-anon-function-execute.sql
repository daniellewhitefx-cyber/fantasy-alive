revoke execute on all functions in schema public from public;
grant execute on all functions in schema public to authenticated, service_role;

alter default privileges in schema public revoke execute on functions from public;
alter default privileges in schema public grant execute on functions to authenticated, service_role;
