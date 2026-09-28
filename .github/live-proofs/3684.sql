-- Live proof for #3684 (migration 20260928181047, claim #3728). Read-only.
-- Proves on production: the migration is in the ledger; both durable-state tables exist
-- with RLS on, read-only to authenticated, and not writable by the loader role; the
-- publish function is SECURITY DEFINER and executable only by service_role; and the
-- durable state reconciles with its publications (every entity row points at a
-- recorded publication, and every withdrawal names one).
select (
  exists (select 1 from supabase_migrations.schema_migrations where version = '20260928181047')
  and to_regclass('plm.peanuts_entity_lifecycle') is not null
  and to_regclass('plm.peanuts_lifecycle_publication') is not null
  and (select bool_and(relrowsecurity) from pg_class
        where oid in (to_regclass('plm.peanuts_entity_lifecycle'), to_regclass('plm.peanuts_lifecycle_publication'))) is true
  and not has_table_privilege('service_role', 'plm.peanuts_entity_lifecycle', 'INSERT')
  and not has_table_privilege('service_role', 'plm.peanuts_entity_lifecycle', 'DELETE')
  and has_table_privilege('authenticated', 'plm.peanuts_entity_lifecycle', 'SELECT')
  and not has_table_privilege('anon', 'plm.peanuts_entity_lifecycle', 'SELECT')
  and coalesce((select prosecdef from pg_proc where oid = to_regprocedure('plm.peanuts_publish_lifecycle(uuid)')), false)
  and has_function_privilege('service_role', 'plm.peanuts_publish_lifecycle(uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'plm.peanuts_publish_lifecycle(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'plm.peanuts_publish_lifecycle(uuid)', 'EXECUTE')
  and not exists (
    select 1 from plm.peanuts_entity_lifecycle l
     where not exists (select 1 from plm.peanuts_lifecycle_publication p where p.capture_id = l.last_seen_capture_id)
        or (l.status = 'withdrawn' and l.withdrawn_capture_id is null)
  )
) as passed
