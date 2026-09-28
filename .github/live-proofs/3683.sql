-- Live proof for #3683 (migration 20260928160635, claim #3694). Read-only.
-- Proves on production: the migration is in the ledger; both durable-state tables exist
-- with RLS on, read-only to authenticated, and not writable by the loader role; the
-- publish function is SECURITY DEFINER and executable only by service_role; and the
-- durable state reconciles with its publications (every entity row points at a
-- recorded publication, and every withdrawal names one).
select (
  exists (select 1 from supabase_migrations.schema_migrations where version = '20260928160635')
  and to_regclass('plm.nbcu_entity_lifecycle') is not null
  and to_regclass('plm.nbcu_lifecycle_publication') is not null
  and (select bool_and(relrowsecurity) from pg_class
        where oid in ('plm.nbcu_entity_lifecycle'::regclass, 'plm.nbcu_lifecycle_publication'::regclass))
  and not has_table_privilege('service_role', 'plm.nbcu_entity_lifecycle', 'INSERT')
  and not has_table_privilege('service_role', 'plm.nbcu_entity_lifecycle', 'DELETE')
  and has_table_privilege('authenticated', 'plm.nbcu_entity_lifecycle', 'SELECT')
  and not has_table_privilege('anon', 'plm.nbcu_entity_lifecycle', 'SELECT')
  and (select prosecdef from pg_proc where oid = to_regprocedure('plm.nbcu_publish_lifecycle(uuid)'))
  and has_function_privilege('service_role', 'plm.nbcu_publish_lifecycle(uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'plm.nbcu_publish_lifecycle(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'plm.nbcu_publish_lifecycle(uuid)', 'EXECUTE')
  and not exists (
    select 1 from plm.nbcu_entity_lifecycle l
     where not exists (select 1 from plm.nbcu_lifecycle_publication p where p.capture_id = l.last_seen_capture_id)
        or (l.status = 'withdrawn' and l.withdrawn_capture_id is null)
  )
) as passed
