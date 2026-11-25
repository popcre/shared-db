-- #4707: retire copied DesignFlow items whose source row was deleted at the
-- owner's request (EP001, designflow-data-syncing#207). The Data Syncing
-- runtime may delete only an unlinked, history-free copied item whose
-- dflow_prod."itemHeader" row no longer exists, and may re-insert such an item
-- only from its own recorded before-image, so a retirement run rolls back.
-- derived-from: none

begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

grant delete on plm.designflow_item to designflow_prod_data_sync_grants;

create policy designflow_item_retire_orphan_delete on plm.designflow_item
  for delete to designflow_prod_data_sync_grants using (
    canonical_item_id is null
    and not exists (select from dflow_prod."itemHeader" h where h.item_id_pk = legacy_item_id)
    and not exists (select from plm.licensing_status s where s.designflow_item_id = legacy_item_id)
  );

create policy designflow_item_retire_orphan_restore on plm.designflow_item
  for insert to designflow_prod_data_sync_grants with check (
    canonical_item_id is null
    and not exists (select from dflow_prod."itemHeader" h where h.item_id_pk = legacy_item_id)
    and exists (
      select from plm.designflow_reconcile_before_image b
      where b.target_table = 'designflow_item' and b.operation = 'delete'
        and b.target_key->>'legacy_item_id' = legacy_item_id::text
    )
  );

commit;
