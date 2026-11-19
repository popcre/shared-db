-- shared-db#2358 (claim #4536) live proof (read-only): both canonical licensing merge
-- functions and the change-history table exist in production, and migration
-- 20261021134203 is in the ledger. Functions are matched by name in schema plm so the
-- probe does not depend on argument signatures.
select (
  (select count(*) >= 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'plm' and p.proname = 'plan_licensing_canonical_merge')
  and (select count(*) >= 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
     where n.nspname = 'plm' and p.proname = 'apply_licensing_canonical_merge')
  and to_regclass('plm.licensing_canonical_change_history') is not null
  and exists (select 1 from supabase_migrations.schema_migrations where version = '20261021134203')
) as passed;
