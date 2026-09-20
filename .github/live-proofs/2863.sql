-- Historical sample replay proof, recovered under issue 3302.
-- Counts come from transactional loader evidence, never fixed expected totals.
-- The prepack loader coalesces byte-identical responses to case-variant request
-- spellings; equal source counts and equal unique-row counts must both survive.
-- Its projector refuses conflicting source identities. No changed or removed
-- row may be hidden in the replay: every change_log entry disqualifies it.
WITH prepack_replay AS (
  SELECT r.id, r.company_code, r.rows_unchanged
  FROM coldlion.sync_run r
  WHERE r.endpoint = '/prepackDetail' AND r.status = 'succeeded'
    AND r.request_params->>'fullSnapshot' = 'true'
    AND r.rows_unchanged > 0 AND r.rows_inserted = 0 AND r.rows_updated = 0
    AND r.rows_fetched >= r.rows_unchanged
    AND r.finished_at >= r.started_at
    AND NOT EXISTS (SELECT 1 FROM coldlion.change_log c WHERE c.run_id = r.id)
    AND EXISTS (
      SELECT 1 FROM coldlion.sync_run prior
      WHERE prior.endpoint = r.endpoint AND prior.company_code = r.company_code
        AND prior.status = 'succeeded' AND prior.finished_at < r.started_at
        AND prior.request_params->>'fullSnapshot' = 'true'
        AND prior.request_params->'coveredKeys' = r.request_params->'coveredKeys'
        AND prior.rows_fetched = r.rows_fetched
        AND prior.rows_unchanged = r.rows_unchanged
        AND prior.rows_inserted = 0 AND prior.rows_updated = 0
        AND NOT EXISTS (SELECT 1 FROM coldlion.change_log c WHERE c.run_id = prior.id)
    )
    AND (SELECT count(*) FROM coldlion.prepack_detail d
         WHERE d.company_code = r.company_code AND d.run_id = r.id) = r.rows_unchanged
    AND (SELECT count(*) FROM coldlion.prepack_detail d
         WHERE d.company_code = r.company_code) = r.rows_unchanged
), prod_replay AS (
  SELECT r.id
  FROM coldlion.sync_run r
  WHERE r.endpoint = '/proddetails' AND r.status = 'succeeded'
    AND r.rows_fetched > 0 AND r.rows_fetched = r.rows_unchanged
    AND r.rows_inserted = 0 AND r.rows_updated = 0
    AND r.finished_at >= r.started_at
    AND NOT EXISTS (SELECT 1 FROM coldlion.change_log c WHERE c.run_id = r.id)
    AND EXISTS (
      SELECT 1 FROM coldlion.sync_run prior
      WHERE prior.endpoint = r.endpoint AND prior.company_code = r.company_code
        AND prior.status = 'succeeded' AND prior.finished_at < r.started_at
        AND prior.request_params->>'prodOrderNo' = r.request_params->>'prodOrderNo'
        AND prior.rows_fetched = r.rows_fetched
        AND prior.rows_fetched = prior.rows_inserted + prior.rows_updated + prior.rows_unchanged
    )
    AND (SELECT count(*) FROM coldlion.prod_detail d
         WHERE d.company_code = r.company_code
           AND d.prod_order_no::text = r.request_params->>'prodOrderNo') = r.rows_fetched
    AND (SELECT count(*) FROM coldlion.prod_detail d WHERE d.run_id = r.id) = r.rows_fetched
)
SELECT EXISTS (SELECT 1 FROM prepack_replay)
   AND EXISTS (SELECT 1 FROM prod_replay)
   AND (SELECT count(*) FROM pg_class c JOIN pg_namespace n ON n.oid = c.relnamespace
        WHERE n.nspname = 'coldlion' AND c.relname IN ('prepack_detail','prod_detail')
          AND c.relkind = 'r' AND c.relrowsecurity) = 2
   AND NOT EXISTS (
     SELECT 1 FROM (VALUES ('coldlion.prepack_detail'),('coldlion.prod_detail')) t(name)
     CROSS JOIN (VALUES ('anon'),('authenticated')) roles(name)
     WHERE has_table_privilege(roles.name, t.name, 'SELECT,INSERT,UPDATE,DELETE,TRUNCATE,REFERENCES,TRIGGER')
   )
   AND has_table_privilege('service_role','coldlion.prepack_detail','SELECT')
   AND has_table_privilege('service_role','coldlion.prod_detail','SELECT') AS passed;
