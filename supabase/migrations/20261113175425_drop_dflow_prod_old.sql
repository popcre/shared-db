-- shared-db issue #6265 - drop the empty leftover landing schema dflow_prod_old.
-- Successor to version 20261113150753 (merged in PR #6240, never applied to
-- production): that lane's preview evidence predates a scripts/production_migration_guard.py
-- change on main, so the automatic promotion refused its producer pin. This
-- version re-states the identical idempotent drop from current main.
-- Owner authorization (Albert Hazan, chat 2026-11-13, verbatim: "drop the empty shelf").
-- Evidence: popcre/designflow-data-syncing#126 - zero readers; 127 empty tables,
-- 0 rows. Backup: gs://designflow-storage/backups/dflow-stale-cleanup-2026-11-12/prod_dflow_prod_old_schema.dump
--
-- CASCADE is required and safe here: RESTRICT refuses to drop a schema that still
-- CONTAINS objects (the 127 empty tables), and CASCADE can only reach outside
-- dependents - the 2026-11-13 audit proved there are none (review finding #6241).

drop schema if exists dflow_prod_old cascade;
