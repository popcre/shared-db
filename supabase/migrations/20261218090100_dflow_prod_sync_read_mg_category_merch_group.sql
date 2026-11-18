-- derived-from: none
-- Claim popcre/shared-db#6728. App contract popcre/designflow-data-syncing#103 (PR 161).
-- Production merch-group repair preview reads category links from
-- core.mg_category_merch_group as designflow_prod_data_sync_grants and gets
-- permission denied. Grant SELECT only. Role exists only in production;
-- elsewhere this is a no-op. Rollback: revoke select.
begin;
set local lock_timeout = '5s';
do $$
begin
  if exists (select 1 from pg_roles where rolname = 'designflow_prod_data_sync_grants') then
    grant select on table core.mg_category_merch_group to designflow_prod_data_sync_grants;
  end if;
end
$$;
commit;
