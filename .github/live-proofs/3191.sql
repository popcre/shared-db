-- Live proof for #3191 (migration 20260918180012, PR #3277). Read-only.
-- Proves on production:
--   1. the migration is in production's ledger
--   2. supabase_read_only_user now holds EXECUTE on plm.prepack_role(text, text, text)
--   3. anon still does not hold it
--   4. the view the #2611 proof counts, plm.item_missing_attribution, is now
--      readable end to end by this probe's own identity (the count executes
--      prepack_role; before this grant it raised "permission denied")
select (
  exists (select 1 from supabase_migrations.schema_migrations where version = '20260918180012')
  and has_function_privilege('supabase_read_only_user', 'plm.prepack_role(text,text,text)', 'EXECUTE')
  and not has_function_privilege('anon', 'plm.prepack_role(text,text,text)', 'EXECUTE')
  and (select count(*) from plm.item_missing_attribution) >= 0
) as passed
