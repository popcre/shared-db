-- Live proof for issue #2336: hash-pinned licensing consolidation engine is present
-- with immutable plan table, plan/apply functions, correct grants, RLS, and the
-- immutability trigger. No client write path; authenticated read only.
SELECT
  (to_regclass('plm.licensing_consolidation_plan') IS NOT NULL
   AND to_regprocedure('plm.plan_licensing_consolidation(text,uuid,text)') IS NOT NULL
   AND to_regprocedure('plm.apply_licensing_consolidation(uuid,text)') IS NOT NULL
   AND has_table_privilege('authenticated', to_regclass('plm.licensing_consolidation_plan'), 'select')
   AND NOT has_table_privilege('anon', to_regclass('plm.licensing_consolidation_plan'), 'select')
   AND NOT has_table_privilege('authenticated', to_regclass('plm.licensing_consolidation_plan'), 'insert')
   AND NOT has_table_privilege('authenticated', to_regclass('plm.licensing_consolidation_plan'), 'update')
   AND NOT has_table_privilege('authenticated', to_regclass('plm.licensing_consolidation_plan'), 'delete')
   AND NOT has_table_privilege('service_role', to_regclass('plm.licensing_consolidation_plan'), 'insert')
   AND NOT has_table_privilege('service_role', to_regclass('plm.licensing_consolidation_plan'), 'delete')
   AND has_function_privilege('authenticated', to_regprocedure('plm.plan_licensing_consolidation(text,uuid,text)'), 'execute')
   AND has_function_privilege('authenticated', to_regprocedure('plm.apply_licensing_consolidation(uuid,text)'), 'execute')
   AND NOT has_function_privilege('anon', to_regprocedure('plm.plan_licensing_consolidation(text,uuid,text)'), 'execute')
   AND NOT has_function_privilege('anon', to_regprocedure('plm.apply_licensing_consolidation(uuid,text)'), 'execute')
   AND (SELECT relrowsecurity FROM pg_class WHERE oid = to_regclass('plm.licensing_consolidation_plan'))
   AND (SELECT count(*) FROM pg_trigger
        WHERE tgrelid = to_regclass('plm.licensing_consolidation_plan')
          AND tgname = 'licensing_consolidation_plan_immutable_trg'
          AND tgisenabled) = 1
   AND (SELECT count(*) FROM pg_constraint
        WHERE conrelid = to_regclass('plm.licensing_consolidation_plan')
          AND conname = 'licensing_consolidation_plan_hash_chk') = 1
   AND (SELECT count(*) FROM pg_constraint
        WHERE conrelid = to_regclass('plm.licensing_consolidation_plan')
          AND conname = 'licensing_consolidation_plan_identity_uq') = 1
   AND (SELECT count(*) FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'plm' AND p.proname = 'plan_licensing_consolidation') >= 1
   AND (SELECT count(*) FROM pg_proc p
        JOIN pg_namespace n ON n.oid = p.pronamespace
        WHERE n.nspname = 'plm' AND p.proname = 'apply_licensing_consolidation') >= 1) as passed
