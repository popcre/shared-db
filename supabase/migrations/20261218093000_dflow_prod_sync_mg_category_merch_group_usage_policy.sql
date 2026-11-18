-- derived-from: none
-- Claim popcre/shared-db#6728; fixes review finding #6731 on PR #6729.
-- 20261218092000 granted SELECT on core.mg_category_merch_group to
-- designflow_prod_data_sync_grants, but the role has no USAGE on schema core
-- and the table has row security with policies only for authenticated, so the
-- runtime (nobypassrls) would still be denied or see zero rows.
-- Adds schema usage (same as designflow_prod_item_master_grants in
-- 20261106174810) and a read-only policy for this role. No write access.
-- Rollback: drop the policy; revoke usage on schema core.
begin;
set local lock_timeout = '5s';
grant usage on schema core to designflow_prod_data_sync_grants;
drop policy if exists dflow_prod_data_sync_read on core.mg_category_merch_group;
create policy dflow_prod_data_sync_read on core.mg_category_merch_group
  for select to designflow_prod_data_sync_grants
  using (true);
commit;
