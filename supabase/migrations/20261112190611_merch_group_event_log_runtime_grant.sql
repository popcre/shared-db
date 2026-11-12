-- Claim #6171 (successor of #5809 / #6128; popcre/designflow-data-syncing#117).
-- derived-from: none
-- The DesignFlow sync service connects as designflow_prod_backend_runtime
-- (no BYPASSRLS) and got "permission denied for table merch_group_event_log".
-- It inserts journal rows, reads them back by key/event_id, and updates
-- status/reason/rows_touched/processed_at. Grant exactly SELECT, INSERT,
-- column-scoped UPDATE (never DELETE), through the existing grants role.
-- id is uuid default gen_random_uuid(): no sequence to grant.
-- Fail closed if the runtime or its grants role has not been provisioned.

do $g$
begin
  if not exists (select 1 from pg_roles where rolname = 'designflow_prod_backend_runtime'
                 and not rolsuper and not rolbypassrls)
     or not exists (select 1 from pg_roles where rolname = 'designflow_prod_backend_grants'
                    and not rolcanlogin and not rolsuper and not rolbypassrls) then
    raise exception '#6171: backend runtime or safe grants role missing';
  end if;
  if not pg_has_role('designflow_prod_backend_runtime', 'designflow_prod_backend_grants', 'USAGE') then
    raise exception '#6171: backend runtime must inherit its grants role';
  end if;
  grant usage on schema coldlion to designflow_prod_backend_grants;
  grant select, insert on table coldlion.merch_group_event_log
    to designflow_prod_backend_grants;
  grant update (status, reason, rows_touched, processed_at)
    on table coldlion.merch_group_event_log to designflow_prod_backend_grants;

  if not exists (select 1 from pg_policies where schemaname = 'coldlion'
                 and tablename = 'merch_group_event_log'
                 and policyname = 'merch_group_event_log_runtime_select') then
    create policy merch_group_event_log_runtime_select on coldlion.merch_group_event_log
      for select to designflow_prod_backend_grants using (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'coldlion'
                 and tablename = 'merch_group_event_log'
                 and policyname = 'merch_group_event_log_runtime_insert') then
    create policy merch_group_event_log_runtime_insert on coldlion.merch_group_event_log
      for insert to designflow_prod_backend_grants with check (true);
  end if;
  if not exists (select 1 from pg_policies where schemaname = 'coldlion'
                 and tablename = 'merch_group_event_log'
                 and policyname = 'merch_group_event_log_runtime_update') then
    create policy merch_group_event_log_runtime_update on coldlion.merch_group_event_log
      for update to designflow_prod_backend_grants using (true) with check (true);
  end if;

  -- Post-check.
  if not (has_table_privilege('designflow_prod_backend_runtime', 'coldlion.merch_group_event_log', 'select')
      and has_table_privilege('designflow_prod_backend_runtime', 'coldlion.merch_group_event_log', 'insert')
      and has_schema_privilege('designflow_prod_backend_runtime', 'coldlion', 'usage')) then
    raise exception '#6171 post-check: runtime grants missing on coldlion.merch_group_event_log';
  end if;
  if exists (
    select 1 from pg_attribute
    where attrelid = 'coldlion.merch_group_event_log'::regclass
      and attnum > 0 and not attisdropped
      and has_column_privilege('designflow_prod_backend_runtime', attrelid, attnum, 'UPDATE')
          is distinct from (attname in ('status', 'reason', 'rows_touched', 'processed_at'))
  ) then
    raise exception '#6171 post-check: runtime UPDATE columns differ';
  end if;
  if has_table_privilege('designflow_prod_backend_runtime', 'coldlion.merch_group_event_log', 'delete') then
    raise exception '#6171 post-check: runtime role must not hold DELETE on coldlion.merch_group_event_log';
  end if;
end
$g$;
