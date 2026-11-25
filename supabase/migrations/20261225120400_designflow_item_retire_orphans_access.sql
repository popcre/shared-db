-- #4707: retire copied DesignFlow items whose source row was deleted at the
-- owner's request (EP001, designflow-data-syncing#207). The Data Syncing
-- runtime may delete only an unlinked, history-free copied item whose
-- dflow_prod."itemHeader" row no longer exists and whose delete before-image
-- is already recorded, and may re-insert such an item only from that
-- before-image, so a retirement run rolls back.
-- derived-from: none

begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

-- Copied items were never deletable before this migration, so no copied-item
-- delete before-image can exist yet. Refuse otherwise: such an image was
-- written under the old unchecked insert rule and must not authorize a restore.
do $$
begin
  lock table plm.designflow_reconcile_before_image in share row exclusive mode;
  if exists (select from plm.designflow_reconcile_before_image
             where target_table = 'designflow_item' and operation = 'delete') then
    raise exception '#4707: unverified copied-item delete before-images exist; refuse';
  end if;
end
$$;

-- Row security hides non-DesignFlow licensing rows from the runtime, so the
-- history check runs as the owner and returns only a boolean.
create function plm.designflow_item_has_licensing_history(p_legacy_item_id integer)
returns boolean
language sql
stable
security definer
set search_path = ''
as $$
  select exists (select from plm.licensing_status s where s.designflow_item_id = p_legacy_item_id)
$$;
revoke all on function plm.designflow_item_has_licensing_history(integer) from public, anon, authenticated;
grant execute on function plm.designflow_item_has_licensing_history(integer) to designflow_prod_data_sync_grants;

grant delete on plm.designflow_item to designflow_prod_data_sync_grants;

create policy designflow_item_retire_orphan_delete on plm.designflow_item
  for delete to designflow_prod_data_sync_grants using (
    canonical_item_id is null
    and not exists (select from dflow_prod."itemHeader" h where h.item_id_pk = legacy_item_id)
    and not plm.designflow_item_has_licensing_history(legacy_item_id)
    and exists (
      select from plm.designflow_reconcile_before_image b
      where b.target_table = 'designflow_item' and b.operation = 'delete'
        and b.target_key->>'legacy_item_id' = legacy_item_id::text
        and b.before_row = to_jsonb(designflow_item)
    )
  );

create policy designflow_item_retire_orphan_restore on plm.designflow_item
  for insert to designflow_prod_data_sync_grants with check (
    canonical_item_id is null
    and not exists (select from dflow_prod."itemHeader" h where h.item_id_pk = legacy_item_id)
    and exists (
      select from plm.designflow_reconcile_before_image b
      where b.target_table = 'designflow_item' and b.operation = 'delete'
        and b.target_key->>'legacy_item_id' = legacy_item_id::text
        and b.before_row = to_jsonb(designflow_item)
    )
  );

-- A delete before-image of a copied item must be the exact current row, so a
-- restore can only bring back a row that existed. Other before-images keep the
-- existing append-only rule.
drop policy designflow_reconcile_before_image_insert on plm.designflow_reconcile_before_image;
create policy designflow_reconcile_before_image_insert on plm.designflow_reconcile_before_image
  for insert to designflow_prod_data_sync_grants with check (
    not (target_table = 'designflow_item' and operation = 'delete')
    or exists (
      select from plm.designflow_item d
      where d.legacy_item_id::text = target_key->>'legacy_item_id' and to_jsonb(d) = before_row
    )
  );

commit;
