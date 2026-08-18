-- Every SECURITY DEFINER function in the schema was missing an explicit
-- search_path, which Supabase's linter flags as "Function Search Path
-- Mutable": since the function runs with the privileges of whoever
-- created it (not the caller), a mutable/inherited search_path lets a
-- malicious user shadow expected objects (tables, other functions) by
-- creating same-named objects earlier in their own search_path, tricking
-- the function into operating on attacker-controlled objects.
--
-- The corresponding create-or-replace statements in every other schema
-- file have also been updated to set search_path = public going forward,
-- so this file exists only to patch the functions that already exist in
-- production without needing to re-run every schema file. It finds every
-- security definer function in the public schema that doesn't already
-- have a search_path configured and sets one, using each function's
-- actual signature from the catalog rather than guessing.

do $$
declare
  r record;
begin
  for r in
    select p.oid
    from pg_proc p
    join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'public'
      and p.prosecdef = true
      and not exists (
        select 1 from unnest(coalesce(p.proconfig, '{}')) cfg
        where cfg like 'search_path=%'
      )
  loop
    execute format('alter function %s set search_path = public', r.oid::regprocedure);
  end loop;
end $$;
