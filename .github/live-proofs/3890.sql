-- Shared production proof: the already-correct legacy table remains in dflow.
-- Sandbox proof is separately recorded from the sandbox-only bounded workflow.
SELECT (
  EXISTS (SELECT 1 FROM supabase_migrations.schema_migrations
    WHERE version = '20261007000937')
  AND to_regclass('dflow.properties_and_characters') IS NOT NULL
  AND to_regclass('core.properties_and_characters') IS NULL
  AND (SELECT count(*) FROM pg_attribute
    WHERE attrelid = to_regclass('dflow.properties_and_characters')
      AND attnum > 0 AND NOT attisdropped) = 8
) as passed;
