-- Live proof for #3683 (migration 20260929011044, claim #3694). Read-only.
-- Proves on production: the migration is in the ledger; both durable-state tables exist
-- with RLS on, read-only to authenticated, and not writable by the loader role; the
-- withdrawal index leads with last_seen_capture_id; each table has exactly its one
-- reviewed read policy; the publish function is SECURITY DEFINER, VOLATILE, has its
-- pinned search_path and is executable only by service_role; and the durable state
-- agrees with its publications on values no foreign key enforces (every sighting and
-- withdrawal time equals the source_captured_at of the publication it names, and no
-- entity row names a withdrawal while active).
select (
  exists (select 1 from supabase_migrations.schema_migrations where version = '20260929011044')
  and to_regclass('plm.nbcu_entity_lifecycle') is not null
  and to_regclass('plm.nbcu_lifecycle_publication') is not null
  and (select bool_and(relrowsecurity) from pg_class
        where oid in (to_regclass('plm.nbcu_entity_lifecycle'), to_regclass('plm.nbcu_lifecycle_publication'))) is true
  and not has_table_privilege('service_role', 'plm.nbcu_entity_lifecycle', 'INSERT')
  and not has_table_privilege('service_role', 'plm.nbcu_entity_lifecycle', 'DELETE')
  and not has_table_privilege('service_role', 'plm.nbcu_entity_lifecycle', 'UPDATE')
  and not has_table_privilege('service_role', 'plm.nbcu_lifecycle_publication', 'INSERT')
  and not has_table_privilege('service_role', 'plm.nbcu_lifecycle_publication', 'UPDATE')
  and not has_table_privilege('service_role', 'plm.nbcu_lifecycle_publication', 'DELETE')
  and has_table_privilege('authenticated', 'plm.nbcu_entity_lifecycle', 'SELECT')
  and not has_table_privilege('anon', 'plm.nbcu_entity_lifecycle', 'SELECT')
  and coalesce((select pg_get_indexdef(to_regclass('plm.nbcu_entity_lifecycle_kind_last_seen_idx'))), '')
      = 'CREATE INDEX nbcu_entity_lifecycle_kind_last_seen_idx ON plm.nbcu_entity_lifecycle USING btree (last_seen_capture_id, entity_kind, status)'
  and (select count(*) from pg_policies where schemaname = 'plm'
        and (tablename, policyname) in (('nbcu_entity_lifecycle', 'nbcu_entity_lifecycle_plm_read'),
                                        ('nbcu_lifecycle_publication', 'nbcu_lifecycle_publication_plm_read'))
        and cmd = 'SELECT' and roles = array['authenticated']::name[]) = 2
  and (select count(*) from pg_policies where schemaname = 'plm'
        and tablename in ('nbcu_entity_lifecycle', 'nbcu_lifecycle_publication')) = 2
  and coalesce((select prosecdef and provolatile = 'v'
                       and proconfig = array['search_path=pg_catalog, pg_temp']
                  from pg_proc where oid = to_regprocedure('plm.nbcu_publish_lifecycle(uuid)')), false)
  and has_function_privilege('service_role', 'plm.nbcu_publish_lifecycle(uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'plm.nbcu_publish_lifecycle(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'plm.nbcu_publish_lifecycle(uuid)', 'EXECUTE')
  and not exists (
    select 1 from plm.nbcu_entity_lifecycle l
      join plm.nbcu_lifecycle_publication ls on ls.capture_id = l.last_seen_capture_id
      join plm.nbcu_lifecycle_publication fs on fs.capture_id = l.first_seen_capture_id
      left join plm.nbcu_lifecycle_publication w on w.capture_id = l.withdrawn_capture_id
     where l.last_seen_at <> ls.source_captured_at
        or l.first_seen_at <> fs.source_captured_at
        or (l.status = 'withdrawn' and l.withdrawn_at is distinct from w.source_captured_at)
        or (l.status = 'active' and l.withdrawn_capture_id is not null)
  )
) as passed
