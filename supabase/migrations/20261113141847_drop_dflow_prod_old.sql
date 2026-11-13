-- shared-db issue #6239 - drop the empty leftover landing schema dflow_prod_old.
-- Owner authorization (Albert Hazan, chat 2026-11-13, verbatim: "drop the empty shelf").
-- Evidence: popcre/designflow-data-syncing#126 - zero readers; 127 tables, 0 rows,
-- measured 2026-11-13 through the pooler as postgres.qsllyeztdwjgirsysgai.
-- Backup: gs://designflow-storage/backups/dflow-stale-cleanup-2026-11-12/prod_dflow_prod_old_schema.dump
-- Default RESTRICT refuses the drop if anything outside the schema depends on it.

drop schema if exists dflow_prod_old;
