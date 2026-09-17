-- Live proof for #2794 (migration 20260917081021). Read-only.
-- Proves: the migration is in production's ledger; plm.import_master_data(jsonb,jsonb)
-- no longer exists; the licensing write guard it must not disturb is intact.
select (
  exists (select 1 from supabase_migrations.schema_migrations where version = '20260917081021')
  and to_regprocedure('plm.import_master_data(jsonb,jsonb)') is null
  and not exists (
    select 1 from pg_proc p join pg_namespace n on n.oid = p.pronamespace
    where n.nspname = 'plm' and p.proname = 'import_master_data'
  )
  and to_regclass('plm.licensing_write_authorization') is not null
  and to_regclass('plm.licensing_write_guard_audit') is not null
  and to_regprocedure('app.enforce_licensing_write_authority()') is not null
  and (select count(*) from pg_trigger
       where not tgisinternal
         and tgname in ('licensor_licensing_write_guard', 'property_licensing_write_guard')) >= 2
) as passed
