-- #4707: retire copied DesignFlow items whose source row was deleted at the
-- owner's request (EP001, designflow-data-syncing#207). The Data Syncing
-- runtime gets no delete right on plm.designflow_item. It may call one owner
-- function that, for the exact orphan list its verified plan reported, locks
-- the rows, refuses if any is linked to a canonical item or has licensing
-- history, saves each row as a before-image, then deletes it. The runtime may
-- re-insert such an item only as the exact row of a recorded before-image, so
-- rollback by run id restores it.
-- derived-from: none

begin;
set local lock_timeout = '5s';
set local statement_timeout = '30s';

-- Copied items were never deletable before this migration, so no copied-item
-- delete before-image can exist yet. Refuse otherwise: such an image was
-- written under the unchecked insert rule and must not authorize a restore.
lock table plm.designflow_reconcile_before_image in share row exclusive mode;
do $$
begin
  if exists (select from plm.designflow_reconcile_before_image
             where target_table = 'designflow_item' and operation = 'delete') then
    raise exception '#4707: unverified copied-item delete before-images exist; refuse';
  end if;
end
$$;

create function plm.designflow_retire_orphan_items(p_run_id uuid, p_expected integer[])
returns integer[]
language plpgsql
volatile
security definer
set search_path = ''
as $$
declare
  v_orphans integer[];
  v_deleted integer[];
begin
  if p_run_id is null or p_expected is null then
    raise exception 'designflow_retire_orphan_items: run id and expected list are required';
  end if;
  -- Lock first: a concurrent licensing insert needs a KEY SHARE lock on its
  -- item, so it waits for (or, already committed, is seen by) the check below.
  perform 1 from plm.designflow_item t
    where t.legacy_item_id = any (p_expected) for update;
  select coalesce(array_agg(t.legacy_item_id order by t.legacy_item_id), '{}') into v_orphans
    from plm.designflow_item t
    where not exists (select from dflow_prod."itemHeader" h where h.item_id_pk = t.legacy_item_id);
  if v_orphans is distinct from (select coalesce(array_agg(x order by x), '{}') from unnest(p_expected) x) then
    raise exception 'designflow_retire_orphan_items: orphan set differs from the verified plan'
      using errcode = 'P0001', hint = 'ITEM_RETIRE_ORPHAN_SET_CHANGED';
  end if;
  if exists (select from plm.designflow_item t where t.legacy_item_id = any (v_orphans)
             and (t.canonical_item_id is not null
                  or exists (select from plm.licensing_status s where s.designflow_item_id = t.legacy_item_id))) then
    raise exception 'designflow_retire_orphan_items: an orphan is linked or has licensing history'
      using errcode = 'P0001', hint = 'ITEM_RETIRE_ORPHAN_BLOCKED';
  end if;
  insert into plm.designflow_reconcile_before_image (run_id, target_table, operation, target_key, before_row)
    select p_run_id, 'designflow_item', 'delete', jsonb_build_object('legacy_item_id', t.legacy_item_id), to_jsonb(t)
    from plm.designflow_item t where t.legacy_item_id = any (v_orphans);
  with d as (delete from plm.designflow_item t where t.legacy_item_id = any (v_orphans) returning t.legacy_item_id)
    select coalesce(array_agg(legacy_item_id order by legacy_item_id), '{}') into v_deleted from d;
  return v_deleted;
end
$$;
revoke all on function plm.designflow_retire_orphan_items(uuid, integer[]) from public, anon, authenticated;
grant execute on function plm.designflow_retire_orphan_items(uuid, integer[]) to designflow_prod_data_sync_grants;

-- A delete before-image of a copied item written by the runtime must be the
-- exact current row, so a restore can only bring back a row that existed.
drop policy designflow_reconcile_before_image_insert on plm.designflow_reconcile_before_image;
create policy designflow_reconcile_before_image_insert on plm.designflow_reconcile_before_image
  for insert to designflow_prod_data_sync_grants with check (
    not (target_table = 'designflow_item' and operation = 'delete')
    or exists (
      select from plm.designflow_item d
      where d.legacy_item_id::text = target_key->>'legacy_item_id' and to_jsonb(d) = before_row
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

commit;
