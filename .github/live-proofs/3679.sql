-- #3679 ColdLion order intake staging: read-only production shape and access proof.
-- Asserts OBJECTS, not names: the six new tables exist as tables; every
-- load-bearing constraint is bound to its PARENT TABLE and DEFINITION
-- (conrelid + pg_get_constraintdef — a right name on the wrong table, or a
-- right name with a weakened definition, fails); every required index is bound
-- to its parent (pg_index.indrelid) and key list (pg_get_indexdef) — the winner indexes
-- must carry last_seen_run DESC and the hash key); the sealed window_ledger is
-- untouched by the intake path via the last_run_id join (a bare count(*) could
-- not detect the in-place state updates the sealed failure recorder performs);
-- and the closed landing posture denies EVERY privilege (not just SELECT) to
-- public/anon/authenticated while service_role holds arwd and NOTHING of
-- truncate/references/trigger/maintain — arwd alone cannot detect TRUNCATE.
WITH expected_tables AS (
  SELECT * FROM (VALUES
    ('intake_window_state'), ('intake_order_line'), ('intake_order_component'),
    ('intake_new_order'), ('routing_code_map'), ('intake_quarantine')
  ) AS t(relname)
),
new_tables AS (
  SELECT count(*) AS present
  FROM expected_tables e
  JOIN pg_catalog.pg_class c
    ON c.relname = e.relname
   AND c.relnamespace = 'coldlion'::regnamespace
   AND c.relkind = 'r'
),
-- (constraint, parent table, two definition fragments) — both fragments must
-- appear in pg_get_constraintdef for the row to count. Fragments are chosen so
-- the exact identity columns, NULLS NOT DISTINCT, the EP001 expression, the
-- routing PK, and each FK parent survive the check and no weakening of them
-- does.
expected_constraints AS (
  SELECT * FROM (VALUES
    ('coldlion_intake_order_line_division_not_ep001', 'intake_order_line', 'division_code IS NULL', '''EP001''::text'),
    ('coldlion_intake_order_line_identity_unique', 'intake_order_line', 'NULLS NOT DISTINCT (sales_order_no, sales_order_line_no, master_item_no, line_source_hash)', 'UNIQUE'),
    ('coldlion_intake_order_component_identity_unique', 'intake_order_component', 'NULLS NOT DISTINCT (line_id, sub_item_no, sub_label_code, component_source_hash)', 'UNIQUE'),
    ('coldlion_routing_code_map_code_pkey', 'routing_code_map', 'PRIMARY KEY (code)', ''),
    ('coldlion_intake_order_line_first_seen_run_fkey', 'intake_order_line', 'FOREIGN KEY (first_seen_run)', 'REFERENCES coldlion.sync_run(id)'),
    ('coldlion_intake_order_line_last_seen_run_fkey', 'intake_order_line', 'FOREIGN KEY (last_seen_run)', 'REFERENCES coldlion.sync_run(id)'),
    ('coldlion_intake_order_component_first_seen_run_fkey', 'intake_order_component', 'FOREIGN KEY (first_seen_run)', 'REFERENCES coldlion.sync_run(id)'),
    ('coldlion_intake_order_component_last_seen_run_fkey', 'intake_order_component', 'FOREIGN KEY (last_seen_run)', 'REFERENCES coldlion.sync_run(id)'),
    ('coldlion_intake_order_component_line_fkey', 'intake_order_component', 'FOREIGN KEY (line_id)', 'REFERENCES coldlion.intake_order_line(id) ON DELETE CASCADE'),
    ('coldlion_intake_new_order_first_seen_run_fkey', 'intake_new_order', 'FOREIGN KEY (first_seen_run)', 'REFERENCES coldlion.sync_run(id)'),
    ('coldlion_intake_new_order_last_seen_run_fkey', 'intake_new_order', 'FOREIGN KEY (last_seen_run)', 'REFERENCES coldlion.sync_run(id)'),
    ('coldlion_intake_window_state_last_run_fkey', 'intake_window_state', 'FOREIGN KEY (last_run)', 'REFERENCES coldlion.sync_run(id)'),
    ('coldlion_intake_quarantine_first_seen_run_fkey', 'intake_quarantine', 'FOREIGN KEY (first_seen_run)', 'REFERENCES coldlion.sync_run(id)')
  ) AS c(conname, relname, fragment1, fragment2)
),
load_bearing_constraints AS (
  SELECT count(*) AS present
  FROM expected_constraints e
  JOIN pg_catalog.pg_constraint c
    ON c.conname = e.conname
   AND c.connamespace = 'coldlion'::regnamespace
   AND c.conrelid = ('coldlion.' || e.relname)::regclass
   AND position(e.fragment1 in pg_catalog.pg_get_constraintdef(c.oid)) > 0
   AND (e.fragment2 = '' OR position(e.fragment2 in pg_catalog.pg_get_constraintdef(c.oid)) > 0)
),
-- (index, parent table, key-list fragment) — the winner indexes must carry
-- last_seen_run DESC followed by the source hash, and the run-FK indexes must
-- lead with the FK column, on the exact staging tables.
expected_indexes AS (
  SELECT * FROM (VALUES
    ('coldlion_intake_order_line_winner_idx', 'intake_order_line', '(sales_order_no, sales_order_line_no, master_item_no, last_seen_run DESC, line_source_hash)'),
    ('coldlion_intake_order_line_first_seen_run_idx', 'intake_order_line', '(first_seen_run)'),
    ('coldlion_intake_order_line_last_seen_run_idx', 'intake_order_line', '(last_seen_run)'),
    ('coldlion_intake_order_component_winner_idx', 'intake_order_component', '(line_id, sub_item_no, sub_label_code, last_seen_run DESC, component_source_hash)'),
    ('coldlion_intake_order_component_first_seen_run_idx', 'intake_order_component', '(first_seen_run)'),
    ('coldlion_intake_order_component_last_seen_run_idx', 'intake_order_component', '(last_seen_run)')
  ) AS i(idxname, relname, keys)
),
required_indexes AS (
  -- pg_class carries no indrelid; the parent-table binding comes from pg_index
  -- (indexrelid -> the pg_class row, indrelid -> the indexed table), the
  -- 2357.sql / 3498.sql pattern.
  SELECT count(*) AS present
  FROM expected_indexes e
  JOIN pg_catalog.pg_class i
    ON i.relname = e.idxname
   AND i.relnamespace = 'coldlion'::regnamespace
   AND i.relkind = 'i'
  JOIN pg_catalog.pg_index x
    ON x.indexrelid = i.oid
   AND x.indrelid = ('coldlion.' || e.relname)::regclass
   AND position(e.keys in pg_catalog.pg_get_indexdef(i.oid)) > 0
),
seeded_vocabulary AS (
  -- The full observed 2026-09-17 routing vocabulary, exactly.
  SELECT count(*) = 16 AND bool_and(code IN (
    'FOB','POECA','POEGA','POEVA','POE','DDPNJ','DDPMD','DDPPA','DDPOH',
    'DDPNC','DDPCA','DDPGA','MDDP','DES001','ANT001','WMFC'
  )) AS complete
  FROM coldlion.routing_code_map
),
ledger_untouched AS (
  -- Content-untouched, not count-unchanged: window_ledger's run linkage is
  -- last_run_id (20260818232639:206), and the sealed failure recorder marks
  -- ledger rows state='failed' through it — this join catches that in-place
  -- mutation, which a bare count(*) cannot.
  SELECT NOT EXISTS (
    SELECT 1
    FROM coldlion.window_ledger w
    JOIN coldlion.sync_run r ON r.id = w.last_run_id
    WHERE r.requested_by = 'coldlion-order-intake'
  ) AS no_link
),
posture AS (
  -- EVERY privilege bit is denied to the three untrusted roles, not only
  -- SELECT; service_role holds arwd and none of the four maintenance bits.
  SELECT bool_and(
           NOT has_table_privilege(r.role_name, 'coldlion.' || e.relname, p.privilege_name)
         ) AS untrusted_denied_everything,
         bool_and(
           has_table_privilege('service_role', 'coldlion.' || e.relname,
                               'SELECT, INSERT, UPDATE, DELETE')
         ) AS service_arwd,
         bool_and(
           NOT has_table_privilege('service_role', 'coldlion.' || e.relname, 'TRUNCATE')
           AND NOT has_table_privilege('service_role', 'coldlion.' || e.relname, 'REFERENCES')
           AND NOT has_table_privilege('service_role', 'coldlion.' || e.relname, 'TRIGGER')
           AND NOT has_table_privilege('service_role', 'coldlion.' || e.relname, 'MAINTAIN')
         ) AS service_no_maintenance_bits,
         bool_and(c.relrowsecurity) AS rls_on
  FROM expected_tables e
  JOIN pg_catalog.pg_class c
    ON c.relname = e.relname
   AND c.relnamespace = 'coldlion'::regnamespace
   AND c.relkind = 'r'
  CROSS JOIN (VALUES
    ('public'), ('anon'), ('authenticated')
  ) AS r(role_name)
  CROSS JOIN (VALUES
    ('SELECT'), ('INSERT'), ('UPDATE'), ('DELETE'),
    ('TRUNCATE'), ('REFERENCES'), ('TRIGGER'), ('MAINTAIN')
  ) AS p(privilege_name)
)
SELECT (
  (SELECT present = 6 FROM new_tables)
  AND (SELECT present = 13 FROM load_bearing_constraints)
  AND (SELECT present = 6 FROM required_indexes)
  AND (SELECT complete FROM seeded_vocabulary)
  AND (SELECT no_link FROM ledger_untouched)
  AND (SELECT untrusted_denied_everything AND service_arwd
             AND service_no_maintenance_bits AND rls_on FROM posture)
) as passed;
