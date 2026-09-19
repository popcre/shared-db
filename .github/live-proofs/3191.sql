-- Live proof for #3191 (migration 20260918180012, PR #3277). Read-only.
-- Proves on production:
--   1. the migration is in production's ledger
--   2. supabase_read_only_user now holds EXECUTE on plm.prepack_role(text, text, text)
--   3. anon still does not hold it
select (
  exists (select 1 from supabase_migrations.schema_migrations where version = '20260918180012')
  and has_function_privilege('supabase_read_only_user', 'plm.prepack_role(text,text,text)', 'EXECUTE')
  and not has_function_privilege('anon', 'plm.prepack_role(text,text,text)', 'EXECUTE')
) as passed
