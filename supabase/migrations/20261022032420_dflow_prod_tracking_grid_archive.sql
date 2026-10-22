-- Issue #4585. Version reserved by migration-author claim #4586.
-- derived-from: 20261022014315_dflow_tracking_grid_archive.sql (#4570, sandbox dflow copy)
-- Production table for DesignFlow Production Tracking / Licensing Tracking Archive and
-- Unarchive (application PR popcre/designflow-frontend#352).
--
-- Owner ruling (Albert, chat, verbatim): "an archived order disappears only
-- from those two tracking screens and stays unchanged everywhere else." and
-- "everything archived anywhere in the system must be restorable with
-- Unarchive."
--
-- popcre-tracking-prod runs SCHEMA=dflow_prod, so its table-schema map resolves
-- "dflow_prod"."tracking_grid_archive". Same shape as the sandbox table:
--   grid_type 'prod_tracking'      -> row_id = production order header id
--   grid_type 'licensing_tracking' -> row_id = itemHeader item_id_pk
-- row_id is deliberately NOT a foreign key. Unarchive deletes the row.
--
-- Grants: dflow_prod uses per-table grants and no RLS. The tracking service
-- (helpers/trackingArchive.js) runs SELECT, INSERT ... ON CONFLICT DO NOTHING and
-- DELETE, so those three go to designflow_prod_tracking_grants, the NOLOGIN role
-- designflow_prod_tracking_runtime inherits (#2873). No other role gains access.
-- Rollback: drop table dflow_prod.tracking_grid_archive.

set lock_timeout = '5s';
set statement_timeout = '2min';

do $pre$
begin
  if to_regnamespace('dflow_prod') is null
  then raise exception '#4585: schema dflow_prod is missing'; end if;
  if not exists (select 1 from pg_roles where rolname = 'designflow_prod_tracking_grants' and not rolcanlogin and not rolbypassrls)
  then raise exception '#4585: designflow_prod_tracking_grants missing or not a NOLOGIN NOBYPASSRLS role'; end if;
end
$pre$;

create table if not exists dflow_prod.tracking_grid_archive (
  grid_type text not null
    check (grid_type in ('prod_tracking', 'licensing_tracking')),
  row_id bigint not null,
  archived_at timestamptz not null default clock_timestamp(),
  archived_by_user_id integer,
  primary key (grid_type, row_id)
);

comment on table dflow_prod.tracking_grid_archive is
  'Rows hidden from the Production/Licensing Tracking grids by Archive; delete the row to Unarchive (#4585).';

grant select, insert, delete on table dflow_prod.tracking_grid_archive to designflow_prod_tracking_grants;

do $post$
declare v_bad text;
begin
  select string_agg(p, ',') into v_bad
  from unnest(array['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER']) p
  where has_table_privilege('designflow_prod_tracking_grants', 'dflow_prod.tracking_grid_archive', p)
        is distinct from (p in ('SELECT','INSERT','DELETE'));
  if v_bad is not null then raise exception '#4585: tracking privilege matrix differs: %', v_bad; end if;
  if to_regrole('designflow_prod_tracking_runtime') is not null
     and not has_table_privilege('designflow_prod_tracking_runtime', 'dflow_prod.tracking_grid_archive', 'SELECT,INSERT,DELETE')
  then raise exception '#4585: tracking runtime cannot reach dflow_prod.tracking_grid_archive'; end if;
end
$post$;
