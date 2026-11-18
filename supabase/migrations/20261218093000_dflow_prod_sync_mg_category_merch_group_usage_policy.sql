-- derived-from: 20260818203751, 20261218092000
-- Claim popcre/shared-db#6728; fixes review finding #6731 on PR #6729.
-- The sync runtime inherits the table SELECT grant from its grants role.
-- Schema USAGE permits name resolution; other relations still require their
-- own privileges. The policy permits reads on this table only.
-- Rollback: drop dflow_prod_data_sync_read from this table. Revoke core USAGE
-- only after confirming the grant was introduced here and no other access uses it.
begin;
set local lock_timeout = '5s';

do $$
begin
  if not has_table_privilege(
    'designflow_prod_data_sync_grants',
    'core.mg_category_merch_group',
    'SELECT'
  ) then
    raise exception 'Expected sync SELECT grant from migration 20261218092000';
  end if;
end
$$;

grant usage on schema core to designflow_prod_data_sync_grants;
create policy dflow_prod_data_sync_read on core.mg_category_merch_group
  for select to designflow_prod_data_sync_runtime
  using (true);

set local role designflow_prod_data_sync_runtime;
do $$
begin
  if not row_security_active('core.mg_category_merch_group') then
    raise exception 'Expected row security to apply to the sync runtime';
  end if;
  perform count(*) from core.mg_category_merch_group;
end
$$;
reset role;

commit;
