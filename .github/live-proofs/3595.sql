-- #3595: read-only production proof that the plm final homes carry the four
-- source lookup indexes (exact definitions) and append-only triggers, that the
-- guard functions pin search_path and are not executable by API roles, and that
-- both tables stay deny-by-default (RLS on, no policies, no API-role access).
-- Retire or re-baseline this probe when DesignFlow grants plm access or adds
-- indexes to these tables (#3595 follow-ups, #118 cutover).
SELECT (
  EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '20261011212008')
  AND (
    SELECT count(*) FROM (VALUES
      ('item_user_assignment_active_lookup',
       'CREATE INDEX item_user_assignment_active_lookup ON plm.item_user_assignment USING btree (rfq_item_id, function_key, effective_from, id) INCLUDE (user_id) WHERE (effective_to IS NULL)'),
      ('item_workflow_action_item_time',
       'CREATE INDEX item_workflow_action_item_time ON plm.item_workflow_action USING btree (rfq_item_id, occurred_at, id)'),
      ('item_workflow_action_open_handoff_lookup',
       'CREATE INDEX item_workflow_action_open_handoff_lookup ON plm.item_workflow_action USING btree (rfq_item_id, occurred_at DESC, id DESC) INCLUDE (actor_user_id)'),
      ('item_workflow_action_admin_review',
       'CREATE INDEX item_workflow_action_admin_review ON plm.item_workflow_action USING btree (rfq_item_id, occurred_at) WHERE requires_admin_review')
    ) AS e(name, def)
    JOIN pg_catalog.pg_index i ON i.indexrelid = pg_catalog.to_regclass('plm.' || e.name)
    WHERE i.indisvalid AND i.indisready AND i.indislive
      AND pg_catalog.pg_get_indexdef(i.indexrelid) = e.def
  ) = 4
  AND (
    SELECT count(*) FROM pg_catalog.pg_trigger t
     WHERE NOT t.tgisinternal AND t.tgenabled = 'O' AND t.tgtype = 27
       AND ((t.tgrelid = 'plm.item_user_assignment'::regclass
             AND t.tgname = 'item_user_assignment_immutable_history'
             AND t.tgfoid = 'plm.reject_item_assignment_history_rewrite()'::regprocedure)
         OR (t.tgrelid = 'plm.item_workflow_action'::regclass
             AND t.tgname = 'item_workflow_action_immutable'
             AND t.tgfoid = 'plm.reject_item_workflow_action_rewrite()'::regprocedure))
  ) = 2
  AND (
    SELECT count(*) FROM pg_catalog.pg_proc
     WHERE oid IN ('plm.reject_item_assignment_history_rewrite()'::regprocedure,
                   'plm.reject_item_workflow_action_rewrite()'::regprocedure)
       AND proconfig @> ARRAY['search_path=pg_catalog, plm']
  ) = 2
  AND NOT EXISTS (
    SELECT 1 FROM unnest(ARRAY['anon','authenticated','service_role']) AS r(role_name)
    CROSS JOIN unnest(ARRAY['plm.reject_item_assignment_history_rewrite()',
                            'plm.reject_item_workflow_action_rewrite()']) AS f(sig)
    WHERE pg_catalog.has_function_privilege(r.role_name, f.sig, 'EXECUTE')
  )
  AND (
    SELECT count(*) FROM pg_catalog.pg_class
     WHERE oid IN ('plm.item_user_assignment'::regclass, 'plm.item_workflow_action'::regclass)
       AND relkind = 'r' AND relrowsecurity
  ) = 2
  AND NOT EXISTS (
    SELECT 1 FROM pg_catalog.pg_policies
     WHERE schemaname = 'plm' AND tablename IN ('item_user_assignment', 'item_workflow_action')
  )
  AND NOT EXISTS (
    SELECT 1 FROM unnest(ARRAY['anon','authenticated','service_role']) AS r(role_name)
    CROSS JOIN unnest(ARRAY['plm.item_user_assignment','plm.item_workflow_action']) AS t(rel)
    CROSS JOIN unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE','REFERENCES','TRIGGER']) AS p(priv)
    WHERE pg_catalog.has_table_privilege(r.role_name, t.rel, p.priv)
  )
) as passed;
