-- Version: 20261104214917
-- derived-from: none
-- Issue: popcre/shared-db#4437 (app u2giants/popdam3#706).
-- The claim walks idx_sg_search_documents_claim_pending in queue order, so every
-- embedded row leaves a dead entry exactly where the next claim starts. At the
-- default 20% threshold (~47k dead rows) that walk exceeded the 8s PostgREST
-- limit: 57014 ended the backfill on 2026-10-28. Live proof 2026-11-04: 44,887
-- heap fetches and 5.4s for a 100-row walk, 360 and 0.9s once entries were cleared.
-- Vacuum this table about every 2,000 updates so the walk stays short.
alter table public.style_guide_search_documents set (
  autovacuum_vacuum_scale_factor = 0,
  autovacuum_vacuum_threshold = 2000,
  autovacuum_analyze_scale_factor = 0.02
);
