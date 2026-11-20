-- derived-from: none
-- Claim popcre/shared-db#6728. App contract popcre/designflow-data-syncing#103
-- (production preview HTTP 500 "permission denied for table art_piece",
-- 2026-11-20). The merch-group repair in-use scan reads dflow_prod.art_piece
-- and the artists.art_source_id merchandise-group reference.
-- Rollback: revoke SELECT on art_piece and SELECT (art_source_id) on artists.
begin;
set local lock_timeout = '5s';
lock table dflow_prod.art_piece, dflow_prod.artists in access share mode;
do $check$
begin
  if exists (
    select 1 from pg_class
    where oid in ('dflow_prod.art_piece'::regclass, 'dflow_prod.artists'::regclass)
      and (relrowsecurity or relforcerowsecurity)
  ) then
    raise exception 'sync read grants require row security disabled on dflow_prod.art_piece and artists';
  end if;
end $check$;

grant select on table dflow_prod.art_piece to designflow_prod_data_sync_grants;
grant select (art_source_id) on table dflow_prod.artists to designflow_prod_data_sync_grants;

do $check$
begin
  if not has_table_privilege('designflow_prod_data_sync_runtime', 'dflow_prod.art_piece', 'select')
     or not has_column_privilege('designflow_prod_data_sync_runtime', 'dflow_prod.artists', 'art_source_id', 'select')
     or has_column_privilege('designflow_prod_data_sync_runtime', 'dflow_prod.artists', 'email', 'select') then
    raise exception 'runtime art_piece / artists read privileges differ from the sync contract';
  end if;
end $check$;
commit;
