-- Issue #4464. Version reserved by migration-author claim #4467.
-- derived-from: none
-- Stage Catalog production access for DesignFlow tracking
-- (popcre/designflow-tracking#124, plan comment 6253504575).
--
-- popcre-tracking-prod's DB_USER secret is designflow_prod_backend_runtime. In this
-- repository (20261008014009:244) that LOGIN role holds only designflow_prod_backend_grants,
-- but the live production catalogue, read 2026-10-18 3:30 PM EDT as that role
-- (pg_auth_members, BEGIN READ ONLY), already shows INHERIT TRUE / SET FALSE / ADMIN FALSE
-- membership, grantor postgres, in designflow_prod_tracking_grants. This file records that
-- membership idempotently (a no-op in production) so a database built from this repository
-- matches production, and puts privileges on the tracking grant role, never on a LOGIN role.
-- Today that role has no USAGE on plm, so the catalog
-- (20261015193344, 20261016210024) is unreadable in production.
--
-- Grant matrix (exactly what designflow-tracking's catalog code does):
--   * USAGE on schema plm only (no CREATE).
--   * SELECT on the seven catalog tables read by models/stage-catalog.model.js,
--     helpers/stageCatalogReader.js, helpers/stageCatalogTracker.js and
--     routes/stage-progress.router.js.
--   * INSERT, UPDATE, DELETE only on the five tables the maintainer editor writes
--     (models/stage-catalog.model.js): stage_list, stage, stage_duration,
--     stage_dependency, licensor_stage_option. Identity columns need no sequence grant.
--     prod_stage_progress and prod_stage_option stay read-only for this role: the
--     dispatched scope (designflow-tracking#124 plan) is the maintainer editor only.
--     The tracker tick/Linesheet writes (routes/stage-progress.router.js) need a
--     separate reviewed grant before STAGE_CATALOG_ENABLED is turned on in production.
--   * EXECUTE on plm.stage_catalog_bump_version(), the SECURITY INVOKER version
--     trigger those writes fire (same precedent as service_role in 20261015193344).
--   * RLS stays enabled. The role is NOBYPASSRLS, so each table gets one policy
--     scoped TO designflow_prod_tracking_grants only (row authority is the tracking
--     API's maintainer check, as for service_role). no privilege is granted to anon or authenticated (authenticated keeps its
--     pre-existing USAGE on plm from 20260720120000).
-- No application rows change. No other plm table is granted. USAGE on plm also lets
-- this role reach plm functions already EXECUTE-able by PUBLIC (two callable SECURITY
-- DEFINER functions, already reachable by anon and authenticated live); that pre-existing
-- exposure is tracked in #4474 and is not widened to any client role here.
-- Rollback: drop the seven policies below; revoke the table, function and schema
-- privileges from designflow_prod_tracking_grants.

do $pre$
begin
  if not exists (select 1 from pg_roles where rolname = 'designflow_prod_tracking_grants' and not rolcanlogin and not rolbypassrls)
  then raise exception '#4464: designflow_prod_tracking_grants missing or not a NOLOGIN NOBYPASSRLS role'; end if;
  if not exists (select 1 from pg_roles where rolname = 'designflow_prod_backend_runtime' and rolcanlogin and not rolsuper and not rolbypassrls)
  then raise exception '#4464: designflow_prod_backend_runtime missing or not a plain LOGIN role'; end if;
  if (select count(*) from pg_tables where schemaname = 'plm' and tablename in
      ('stage_list','stage','stage_duration','stage_dependency','licensor_stage_option','prod_stage_progress','prod_stage_option')) <> 7
  then raise exception '#4464: stage catalog tables are missing'; end if;
end
$pre$;

grant designflow_prod_tracking_grants to designflow_prod_backend_runtime
  with inherit true, set false, admin false;

grant usage on schema plm to designflow_prod_tracking_grants;

grant select on table plm.stage_list, plm.stage, plm.stage_duration, plm.stage_dependency,
  plm.licensor_stage_option, plm.prod_stage_progress, plm.prod_stage_option
  to designflow_prod_tracking_grants;

grant insert, update, delete on table plm.stage_list, plm.stage, plm.stage_duration,
  plm.stage_dependency, plm.licensor_stage_option
  to designflow_prod_tracking_grants;

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
create policy prod_stage_progress_dflow_prod_tracking_read on plm.prod_stage_progress
  for select to designflow_prod_tracking_grants using (true);
create policy prod_stage_option_dflow_prod_tracking_read on plm.prod_stage_option
  for select to designflow_prod_tracking_grants using (true);

do $post$
declare v_bad text;
begin
  select string_agg(t || ':' || p, ', ') into v_bad
  from unnest(array['stage_list','stage','stage_duration','stage_dependency','licensor_stage_option','prod_stage_progress','prod_stage_option']) t
  cross join unnest(array['SELECT','INSERT','UPDATE','DELETE']) p
  where has_table_privilege('designflow_prod_tracking_grants', 'plm.' || t, p)
        is distinct from (p = 'SELECT' or t not in ('prod_stage_progress','prod_stage_option'));
  if v_bad is not null then raise exception '#4464: privilege matrix differs: %', v_bad; end if;
  if has_schema_privilege('designflow_prod_tracking_grants', 'plm', 'CREATE')
  then raise exception '#4464: CREATE on plm must not be granted'; end if;
  if not exists (select 1 from pg_auth_members m
                 where m.roleid = 'designflow_prod_tracking_grants'::regrole and m.member = 'designflow_prod_backend_runtime'::regrole
                   and m.inherit_option and not m.set_option and not m.admin_option)
  then raise exception '#4464: production login is not an INHERIT-only member of designflow_prod_tracking_grants'; end if;
end
$post$;
