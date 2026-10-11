-- Live proof for issue #2336: hash-pinned licensing consolidation engine
SELECT
  ((SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'plm' AND p.proname IN ('plan_licensing_consolidation','apply_licensing_consolidation') AND p.prosecdef AND p.proconfig @> ARRAY['search_path=pg_catalog']) = 2
   AND (SELECT count(*) FROM pg_proc p JOIN pg_namespace n ON n.oid = p.pronamespace WHERE n.nspname = 'plm' AND p.proname = 'licensing_consolidation_plan_immutable') = 1
   AND (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'plm' AND c.relname = 'licensing_consolidation_plan' AND c.relkind = 'r') = 1
   AND (SELECT count(*) FROM pg_trigger t JOIN pg_class c ON c.oid = t.tgrelid JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'plm' AND c.relname = 'licensing_consolidation_plan' AND t.tgname = 'licensing_consolidation_plan_immutable' AND NOT t.tgisinternal) = 1
   AND (SELECT c.relrowsecurity FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace WHERE n.nspname = 'plm' AND c.relname = 'licensing_consolidation_plan') = true
  ) AS passed;