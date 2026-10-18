-- Issue #4464. Version reserved by migration-author claim #4467.
-- derived-from: none
-- Stage Catalog production access for DesignFlow tracking
-- (popcre/designflow-tracking#124; coordinator decision #4475 comment 6255045042).
--
-- Privileges go on designflow_prod_tracking_grants, the NOLOGIN grant role that the
-- #2873 identity contract (20261008014009) gives, INHERIT, to the tracking LOGIN role
-- designflow_prod_tracking_runtime. This file changes no role membership. Production
-- benefits once popcre-tracking-prod logs in as designflow_prod_tracking_runtime
-- (separate work, #4475); until then the grant is additive and unused.
--
-- Grant matrix, confirmed against designflow-tracking (sandbox-albert):
--   * USAGE on schema plm only (no CREATE).
--   * SELECT on the seven catalog tables.
--   * INSERT, UPDATE, DELETE on the five tables the maintainer editor writes
--     (models/stage-catalog.model.js): stage_list, stage, stage_duration,
--     stage_dependency, licensor_stage_option.
--   * INSERT, UPDATE on prod_stage_progress and prod_stage_option: the tracker tick and
--     Linesheet option (routes/stage-progress.router.js) do SELECT ... FOR UPDATE and
--     INSERT ... ON CONFLICT DO UPDATE. No DELETE: the code never deletes there.
--   * INSERT on dflow_prod."AuditLog": both paths write an audit row (same grant the
--     item-master role holds in 20261008014009).
--   * EXECUTE on plm.stage_catalog_bump_version(), the SECURITY INVOKER version trigger
--     the editor writes fire.
--   Identity columns need no sequence grant (the contract test inserts as the role).
-- RLS stays enabled on the catalog. The role is NOBYPASSRLS, so each catalog table gets
-- one policy scoped TO designflow_prod_tracking_grants only (row authority is the tracking
-- API's maintainer check, as for service_role). No privilege goes to anon or authenticated.
-- No application rows change. USAGE on plm also reaches plm functions already EXECUTE-able
-- by PUBLIC; that pre-existing exposure is tracked in #4474 and is not widened here.
-- Rollback: drop the seven policies; revoke the table, function and schema privileges
-- from designflow_prod_tracking_grants.

do $pre$
begin
  if not exists (select 1 from pg_roles where rolname = 'designflow_prod_tracking_grants' and not rolcanlogin and not rolbypassrls)
  then raise exception '#4464: designflow_prod_tracking_grants missing or not a NOLOGIN NOBYPASSRLS role'; end if;
  if (select count(*) from pg_tables where schemaname = 'plm' and tablename in
      ('stage_list','stage','stage_duration','stage_dependency','licensor_stage_option','prod_stage_progress','prod_stage_option')) <> 7
  then raise exception '#4464: stage catalog tables are missing'; end if;
  if to_regclass('dflow_prod."AuditLog"') is null
  then raise exception '#4464: dflow_prod."AuditLog" is missing'; end if;
end
$pre$;

grant usage on schema plm to designflow_prod_tracking_grants;

grant select on table plm.stage_list, plm.stage, plm.stage_duration, plm.stage_dependency,
  plm.licensor_stage_option, plm.prod_stage_progress, plm.prod_stage_option
  to designflow_prod_tracking_grants;

grant insert, update, delete on table plm.stage_list, plm.stage, plm.stage_duration,
  plm.stage_dependency, plm.licensor_stage_option
  to designflow_prod_tracking_grants;

grant insert, update on table plm.prod_stage_progress, plm.prod_stage_option
  to designflow_prod_tracking_grants;

grant insert on table dflow_prod."AuditLog" to designflow_prod_tracking_grants;

grant execute on function plm.stage_catalog_bump_version() to designflow_prod_tracking_grants;

create policy stage_list_dflow_prod_tracking on plm.stage_list
  for all to designflow_prod_tracking_grants using (true) with check (true);
create policy stage_dflow_prod_tracking on plm.stage
  for all to designflow_prod_tracking_grants using (true) with check (true);
create policy stage_duration_dflow_prod_tracking on plm.stage_duration
  for all to designflow_prod_tracking_grants using (true) with check (true);
create policy stage_dependency_dflow_prod_tracking on plm.stage_dependency
  for all to designflow_prod_tracking_grants using (true) with check (true);
create policy licensor_stage_option_dflow_prod_tracking on plm.licensor_stage_option
  for all to designflow_prod_tracking_grants using (true) with check (true);
create policy prod_stage_progress_dflow_prod_tracking on plm.prod_stage_progress
  for all to designflow_prod_tracking_grants using (true) with check (true);
create policy prod_stage_option_dflow_prod_tracking on plm.prod_stage_option
  for all to designflow_prod_tracking_grants using (true) with check (true);

do $post$
declare v_bad text;
begin
  select string_agg(t || ':' || p, ', ') into v_bad
  from unnest(array['stage_list','stage','stage_duration','stage_dependency','licensor_stage_option','prod_stage_progress','prod_stage_option']) t
  cross join unnest(array['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER']) p
  where has_table_privilege('designflow_prod_tracking_grants', 'plm.' || t, p)
        is distinct from (p in ('SELECT','INSERT','UPDATE')
                          or (p = 'DELETE' and t not in ('prod_stage_progress','prod_stage_option')));
  if v_bad is not null then raise exception '#4464: privilege matrix differs: %', v_bad; end if;
  if not has_table_privilege('designflow_prod_tracking_grants', 'dflow_prod."AuditLog"', 'INSERT')
  then raise exception '#4464: INSERT on dflow_prod."AuditLog" missing'; end if;
  if has_schema_privilege('designflow_prod_tracking_grants', 'plm', 'CREATE')
  then raise exception '#4464: CREATE on plm must not be granted'; end if;
  if not has_function_privilege('designflow_prod_tracking_grants', 'plm.stage_catalog_bump_version()', 'EXECUTE')
  then raise exception '#4464: EXECUTE on plm.stage_catalog_bump_version() missing'; end if;
end
$post$;
