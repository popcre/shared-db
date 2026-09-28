-- Live proof for #3685 (migration 20260928181124, claim #3729). Read-only.
-- Proves on production: the migration is in the ledger; both durable-state tables exist
-- with RLS on, read-only to authenticated, and not writable (insert, update, delete,
-- truncate) by the loader role; the serving indexes exist; the publish function is
-- SECURITY DEFINER with its pinned search_path and executable only by service_role; and
-- the durable state reconciles with its publications (every capture reference on an
-- entity row names a recorded publication, and every withdrawal names one).
select (
  exists (select 1 from supabase_migrations.schema_migrations where version = '20260928181124')
  and to_regclass('plm.wildbrain_entity_lifecycle') is not null
  and to_regclass('plm.wildbrain_lifecycle_publication') is not null
  and (select bool_and(relrowsecurity) from pg_class
        where oid in (to_regclass('plm.wildbrain_entity_lifecycle'), to_regclass('plm.wildbrain_lifecycle_publication'))) is true
  and (select bool_and(
         not has_table_privilege('service_role', t, 'INSERT')
         and not has_table_privilege('service_role', t, 'UPDATE')
         and not has_table_privilege('service_role', t, 'DELETE')
         and not has_table_privilege('service_role', t, 'TRUNCATE')
         and not has_table_privilege('authenticated', t, 'INSERT')
         and not has_table_privilege('authenticated', t, 'UPDATE')
         and not has_table_privilege('authenticated', t, 'DELETE')
         and not has_table_privilege('authenticated', t, 'TRUNCATE')
         and has_table_privilege('authenticated', t, 'SELECT')
         and not has_table_privilege('anon', t, 'SELECT'))
       from unnest(array['plm.wildbrain_entity_lifecycle', 'plm.wildbrain_lifecycle_publication']) t) is true
  and (select count(*) from pg_indexes where schemaname = 'plm' and indexname in (
         'wildbrain_lifecycle_publication_latest_idx', 'wildbrain_lifecycle_publication_baseline_idx',
         'wildbrain_entity_lifecycle_last_seen_idx', 'wildbrain_entity_lifecycle_first_seen_idx',
         'wildbrain_entity_lifecycle_last_changed_idx', 'wildbrain_entity_lifecycle_withdrawn_idx')) = 6
  and coalesce((select prosecdef and provolatile = 'v'
                       and proconfig = array['search_path=pg_catalog, pg_temp']
                  from pg_proc where oid = to_regprocedure('plm.wildbrain_publish_lifecycle(uuid)')), false)
  and has_function_privilege('service_role', 'plm.wildbrain_publish_lifecycle(uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'plm.wildbrain_publish_lifecycle(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'plm.wildbrain_publish_lifecycle(uuid)', 'EXECUTE')
  and not exists (
    select 1 from plm.wildbrain_entity_lifecycle l
     where exists (
             select 1 from unnest(array[l.first_seen_capture_id, l.last_seen_capture_id,
                                        l.last_changed_capture_id, l.withdrawn_capture_id]) r(id)
              where r.id is not null
                and not exists (select 1 from plm.wildbrain_lifecycle_publication p where p.capture_id = r.id))
        or (l.status = 'withdrawn' and l.withdrawn_capture_id is null)
  )
) as passed
