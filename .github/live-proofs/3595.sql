-- #3595: read-only production proof that the plm final homes carry the four
-- source lookup indexes and append-only triggers, and stay deny-by-default.
SELECT (
  EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations WHERE version = '20261011203448')
  AND (
    SELECT count(*) FROM unnest(ARRAY[
      'item_user_assignment_active_lookup', 'item_workflow_action_item_time',
      'item_workflow_action_open_handoff_lookup', 'item_workflow_action_admin_review'
    ]) AS i(name)
    WHERE pg_catalog.to_regclass('plm.' || i.name) IS NOT NULL
      AND pg_catalog.pg_get_indexdef(pg_catalog.to_regclass('plm.' || i.name))
        = pg_catalog.replace(pg_catalog.pg_get_indexdef(pg_catalog.to_regclass('dflow.' || i.name)), ' ON dflow.', ' ON plm.')
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
  AND NOT EXISTS (
    SELECT 1 FROM unnest(ARRAY['anon','authenticated','service_role']) AS r(role_name)
    CROSS JOIN unnest(ARRAY['plm.item_user_assignment','plm.item_workflow_action']) AS t(rel)
    CROSS JOIN unnest(ARRAY['SELECT','INSERT','UPDATE','DELETE','TRUNCATE']) AS p(priv)
    WHERE pg_catalog.has_table_privilege(r.role_name, t.rel, p.priv)
  )
) as passed;
