-- Issue popcre/shared-db#2541: restore the 21 ColdLion property names that 20261112173641 renamed.
-- Owner (Albert Hazan, 2026-11-12): MG06 values in ColdLion were already curated from the scrape;
-- that migration must not change them. Restores each name from the previous_name it recorded.
-- Codes, statuses, links and the new code-less potential rows are left unchanged. Idempotent.
do $restore$
declare r record; v_rows integer;
begin
  for r in select id, metadata->'submission_canonical'->>'previous_name' prev from core.property
            where metadata->'submission_canonical'->>'migration' = '20261112173641'
              and name is distinct from metadata->'submission_canonical'->>'previous_name' loop
    insert into plm.licensing_write_authorization(backend_pid,transaction_id,target_table,write_kind,plan_id,plan_hash,actor,protected_columns,expires_at)
    values (pg_backend_pid(), txid_current(), 'core.property', 'scrape_consolidation', gen_random_uuid(),
      encode(extensions.digest('2541/restore/'||r.id::text,'sha256'),'hex'), 'shared-db migration 20261112195109',
      array['name'], clock_timestamp()+interval '1 minute');
    update core.property set name = r.prev,
      metadata = metadata || jsonb_build_object('submission_canonical_reverted', jsonb_build_object('migration','20261112195109','authorising_issue',2541))
     where id = r.id;
    get diagnostics v_rows = row_count;
    if v_rows <> 1 then raise exception '#2541 restore changed % rows', v_rows; end if;
  end loop;
  if exists (select 1 from core.property where metadata->'submission_canonical'->>'migration' = '20261112173641'
              and name is distinct from metadata->'submission_canonical'->>'previous_name') then
    raise exception '#2541 restore post-condition failed';
  end if;
end
$restore$;
