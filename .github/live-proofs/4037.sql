-- Live proof for #4037 (migration 20261007171252, successor of 20261007143431). Read-only.
-- Proves on production:
--   1. the successor (or original) migration is in production's ledger
--   2. app.handle_new_auth_user() grants app_access 'dam' (v_dam_app := 'dam')
select (
  exists (select 1 from supabase_migrations.schema_migrations
          where version in ('20261007171252', '20261007143431'))
  and position('v_dam_app app.app_name := ''dam''' in
               pg_get_functiondef('app.handle_new_auth_user()'::regprocedure)) > 0
) as passed;
