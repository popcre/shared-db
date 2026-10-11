-- Live proof for issue #2336: hash-pinned licensing consolidation engine is present
-- with immutable plan table, plan/apply functions, correct grants, RLS + policy,
-- immutability trigger, and exact constraint identities. Service-role-only execute;
-- no client write path. Single statement ending in `as passed`.
SELECT
  (to_regclass('plm.licensing_consolidation_plan') IS NOT NULL
   AND (SELECT relkind FROM pg_class WHERE oid = to_regclass('plm.licensing_consolidation_plan')) = 'r'
   AND to_regprocedure('plm.plan_licensing_consolidation(text,uuid,text)') IS NOT NULL
   AND to_regprocedure('plm.apply_licensing_consolidation(uuid,text)') IS NOT NULL
   AND coalesce(has_table_privilege('authenticated', to_regclass('plm.licensing_consolidation_plan'), 'select'), false)
   AND coalesce(has_table_privilege('service_role', to_regclass('plm.licensing_consolidation_plan'), 'select'), false)
   AND NOT coalesce(has_table_privilege('anon', to_regclass('plm.licensing_consolidation_plan'), 'select'), false)
   AND NOT coalesce(has_table_privilege('authenticated', to_regclass('plm.licensing_consolidation_plan'), 'insert'), false)
   AND NOT coalesce(has_table_privilege('authenticated', to_regclass('plm.licensing_consolidation_plan'), 'update'), false)
   AND NOT coalesce(has_table_privilege('authenticated', to_regclass('plm.licensing_consolidation_plan'), 'delete'), false)
   AND NOT coalesce(has_table_privilege('service_role', to_regclass('plm.licensing_consolidation_plan'), 'insert'), false)
   AND NOT coalesce(has_table_privilege('service_role', to_regclass('plm.licensing_consolidation_plan'), 'update'), false)
   AND NOT coalesce(has_table_privilege('service_role', to_regclass('plm.licensing_consolidation_plan'), 'delete'), false)
   AND NOT coalesce(has_function_privilege('authenticated', to_regprocedure('plm.plan_licensing_consolidation(text,uuid,text)'), 'execute'), false)
   AND NOT coalesce(has_function_privilege('anon', to_regprocedure('plm.plan_licensing_consolidation(text,uuid,text)'), 'execute'), false)
   AND coalesce(has_function_privilege('service_role', to_regprocedure('plm.plan_licensing_consolidation(text,uuid,text)'), 'execute'), false)
   AND NOT coalesce(has_function_privilege('authenticated', to_regprocedure('plm.apply_licensing_consolidation(uuid,text)'), 'execute'), false)
   AND NOT coalesce(has_function_privilege('anon', to_regprocedure('plm.apply_licensing_consolidation(uuid,text)'), 'execute'), false)
   AND coalesce(has_function_privilege('service_role', to_regprocedure('plm.apply_licensing_consolidation(uuid,text)'), 'execute'), false)
   AND (SELECT relrowsecurity FROM pg_class WHERE oid = to_regclass('plm.licensing_consolidation_plan'))
   AND (SELECT count(*) FROM pg_policy
        WHERE polrelid = to_regclass('plm.licensing_consolidation_plan')
          AND polname = 'licensing_consolidation_plan_authenticated_read'
          AND polcmd = 'r') = 1
   AND (SELECT count(*) FROM pg_trigger t
        WHERE t.tgrelid = to_regclass('plm.licensing_consolidation_plan')
          AND t.tgname = 'licensing_consolidation_plan_immutable_trg'
          AND NOT t.tgisinternal
          AND t.tgenabled = 'O'
          AND t.tgtype = 27) = 1
   AND (SELECT count(*) FROM pg_constraint
        WHERE conrelid = to_regclass('plm.licensing_consolidation_plan')
          AND conname = 'licensing_consolidation_plan_hash_chk'
          AND contype = 'c') = 1
   AND (SELECT count(*) FROM pg_constraint
        WHERE conrelid = to_regclass('plm.licensing_consolidation_plan')
          AND conname = 'licensing_consolidation_plan_identity_uq'
          AND contype = 'u') = 1) as passed
