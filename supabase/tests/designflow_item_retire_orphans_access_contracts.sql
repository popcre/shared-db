-- #4707: the Data Syncing runtime may delete a copied DesignFlow item only when
-- it is unlinked, has no licensing history and its source row is gone, and may
-- re-insert one only from a recorded delete before-image. No other runtime
-- gains a delete on plm.designflow_item.
do $test$
declare
  p record;
begin
  if to_regclass('plm.designflow_item') is null
     or to_regrole('designflow_prod_data_sync_grants') is null then
    return;
  end if;
  if not has_table_privilege('designflow_prod_data_sync_grants', 'plm.designflow_item', 'DELETE') then
    raise exception 'data sync cannot retire orphaned items';
  end if;
  if to_regrole('designflow_prod_backend_grants') is not null
     and has_table_privilege('designflow_prod_backend_grants', 'plm.designflow_item', 'DELETE') then
    raise exception 'backend gained a delete on plm.designflow_item';
  end if;
  select qual into p from pg_policies
    where schemaname = 'plm' and tablename = 'designflow_item'
      and policyname = 'designflow_item_retire_orphan_delete' and cmd = 'DELETE';
  if p is null or p.qual not like '%canonical_item_id IS NULL%'
     or p.qual not like '%itemHeader%' or p.qual not like '%licensing_status%' then
    raise exception 'orphan delete policy is missing or broader than the retirement rule';
  end if;
  if not exists (select from pg_policies where schemaname = 'plm' and tablename = 'designflow_item'
      and policyname = 'designflow_item_retire_orphan_restore' and cmd = 'INSERT'
      and with_check like '%designflow_reconcile_before_image%') then
    raise exception 'orphan restore policy is missing';
  end if;
end
$test$;
