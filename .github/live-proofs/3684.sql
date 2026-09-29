-- Live proof for #3684 (migration 20260928210932, claim #3728). Read-only.
-- Proves on production: the migration is in the ledger; both durable-state tables exist
-- with RLS on and read-only grants; each carries exactly its one read policy WITH the
-- stored predicate (review of #3730, M6); the serving index has its reviewed column order
-- and the FK-backing indexes exist by exact definition; the publish function is VOLATILE
-- SECURITY DEFINER plpgsql returning jsonb with a pinned search_path, executable only by
-- service_role; and the durable state reconciles with its publications on facts the
-- schema does NOT enforce (M4): every publication names a capture that is complete, each
-- entity's last_seen_at is its last-seen publication's capture time, and every withdrawal
-- was made by a comparable publication.
select (
  exists (select 1 from supabase_migrations.schema_migrations where version = '20260928210932')
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
  and (select count(*) from pg_policies where schemaname = 'plm'
        and tablename in ('peanuts_entity_lifecycle', 'peanuts_lifecycle_publication')) = 2
  and (select count(*) from pg_policies where schemaname = 'plm' and cmd = 'SELECT'
        and roles = '{authenticated}'::name[] and policyname = tablename || '_plm_read'
        and permissive = 'PERMISSIVE' and with_check is null
        and qual = '(app.has_app_access(''plm''::app.app_name) OR app.has_role(''administrator''::app.app_role) OR app.has_any_role(ARRAY[''sales''::app.app_role, ''licensing''::app.app_role]))'
        and tablename in ('peanuts_entity_lifecycle', 'peanuts_lifecycle_publication')) = 2
  and (select count(*) from pg_indexes where schemaname = 'plm' and indexdef in (
        'CREATE INDEX idx_peanuts_entity_lifecycle_last_seen ON plm.peanuts_entity_lifecycle USING btree (entity_kind, status, last_seen_capture_id)',
        'CREATE INDEX idx_peanuts_entity_lifecycle_first_seen ON plm.peanuts_entity_lifecycle USING btree (first_seen_capture_id)',
        'CREATE INDEX idx_peanuts_entity_lifecycle_last_changed ON plm.peanuts_entity_lifecycle USING btree (last_changed_capture_id)',
        'CREATE INDEX idx_peanuts_entity_lifecycle_withdrawn_capture ON plm.peanuts_entity_lifecycle USING btree (withdrawn_capture_id) WHERE (withdrawn_capture_id IS NOT NULL)',
        'CREATE INDEX idx_peanuts_lifecycle_publication_baseline ON plm.peanuts_lifecycle_publication USING btree (baseline_capture_id) WHERE (baseline_capture_id IS NOT NULL)',
        'CREATE INDEX idx_peanuts_lifecycle_publication_latest ON plm.peanuts_lifecycle_publication USING btree (source_captured_at DESC, published_at DESC, published_capture_id DESC)')) = 6
  and coalesce((select prosecdef and provolatile = 'v' and prorettype = 'jsonb'::regtype
                       and prolang = (select oid from pg_language where lanname = 'plpgsql')
                       and proconfig = array['search_path=pg_catalog, pg_temp']
                  from pg_proc where oid = to_regprocedure('plm.peanuts_publish_lifecycle(uuid)')), false)
  and has_function_privilege('service_role', 'plm.peanuts_publish_lifecycle(uuid)', 'EXECUTE')
  and not has_function_privilege('authenticated', 'plm.peanuts_publish_lifecycle(uuid)', 'EXECUTE')
  and not has_function_privilege('anon', 'plm.peanuts_publish_lifecycle(uuid)', 'EXECUTE')
  and not exists (select 1 from plm.peanuts_lifecycle_publication p
                   join plm.peanuts_capture c on c.id = p.published_capture_id
                  where c.status <> 'complete' or c.source_captured_at <> p.source_captured_at)
  and not exists (select 1 from plm.peanuts_entity_lifecycle l
                   join plm.peanuts_lifecycle_publication p on p.published_capture_id = l.last_seen_capture_id
                  where l.last_seen_at <> p.source_captured_at)
  and not exists (select 1 from plm.peanuts_entity_lifecycle l
                   join plm.peanuts_lifecycle_publication p on p.published_capture_id = l.withdrawn_capture_id
                  where p.mode <> 'comparable')
) as passed
