-- Live proof for #3684 (migration 20260928181047, claim #3728). Read-only.
-- Proves on production: the migration is in the ledger; both durable-state tables exist
-- with RLS on, their read policy, and serving indexes, read-only to authenticated, and not
-- writable by the loader role; the publish function is VOLATILE SECURITY DEFINER with a pinned search_path, and executable only by service_role; and the
-- durable state reconciles with its publications (every entity row points at a
-- recorded publication, and every withdrawal names one).
select (
  exists (select 1 from supabase_migrations.schema_migrations where version = '20260928181047')
  and to_regclass('plm.peanuts_entity_lifecycle') is not null
  and to_regclass('plm.peanuts_lifecycle_publication') is not null
  and (select bool_and(relrowsecurity) from pg_class
        where oid in (to_regclass('plm.peanuts_entity_lifecycle'), to_regclass('plm.peanuts_lifecycle_publication'))) is true
  and (select bool_and(
         has_table_privilege('authenticated', t, 'SELECT')
         and not has_table_privilege('authenticated', t, 'INSERT')
         and not has_table_privilege('anon', t, 'SELECT')
         and not has_table_privilege('service_role', t, 'INSERT')
         and not has_table_privilege('service_role', t, 'UPDATE')
         and not has_table_privilege('service_role', t, 'DELETE'))
       from unnest(array['plm.peanuts_entity_lifecycle', 'plm.peanuts_lifecycle_publication']) t) is true
  and (select count(*) from pg_policies where schemaname = 'plm' and cmd = 'SELECT'
        and roles = '{authenticated}'::name[] and policyname = tablename || '_plm_read'
        and tablename in ('peanuts_entity_lifecycle', 'peanuts_lifecycle_publication')) = 2
  and (select count(*) from pg_indexes where schemaname = 'plm' and indexname in (
        'idx_peanuts_entity_lifecycle_last_seen', 'idx_peanuts_entity_lifecycle_first_seen',
        'idx_peanuts_entity_lifecycle_last_changed', 'idx_peanuts_entity_lifecycle_withdrawn_capture',
        'idx_peanuts_lifecycle_publication_baseline', 'idx_peanuts_lifecycle_publication_latest')) = 6
  and coalesce((select prosecdef and provolatile = 'v'
                       and proconfig = array['search_path=pg_catalog, pg_temp']
                  from pg_proc where oid = to_regprocedure('plm.peanuts_publish_lifecycle(uuid)')), false)
  and has_function_privilege('service_role', 'plm.peanuts_publish_lifecycle(uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'plm.peanuts_publish_lifecycle(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'plm.peanuts_publish_lifecycle(uuid)', 'EXECUTE')
  and not exists (
    select 1 from plm.peanuts_entity_lifecycle l
     where not exists (select 1 from plm.peanuts_lifecycle_publication p where p.capture_id = l.last_seen_capture_id)
        or (l.status = 'withdrawn' and l.withdrawn_capture_id is null)
  )
) as passed
