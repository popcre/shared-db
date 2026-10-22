# Handoff — #4578 sandbox dflow.sample.quantity_migration_state

Issue: https://github.com/popcre/shared-db/issues/4578 · Written 2026-10-22 4:35 AM EDT by Claude chat 034fa3d5-6be1-4136-b732-2b2e22056a1b on edge-dev3.

## 1. Goal and current state
Goal: the DesignFlow sandbox Supabase project (`xupnyeifmpsacrqahwwm`, used by https://alsand.designflow.app via Cloud Run `popcre-albert-tracking-sandbox`, us-east4, secrets `DB_*_SANDBOX`) gets `dflow.sample.quantity_migration_state`, so `GET /api/tracking/sample/list` returns 200 and the Sample Tracking grid loads. Then tick the live-proof box on #4578.
State: the fix migration is MERGED on main but NOT applied to the sandbox. The grid still fails. Live-proof box unticked.

## 2. What was done (merged through Guarded Merge)
- PR https://github.com/popcre/shared-db/pull/4607 (0abde12b): catalog contract `dflow_sample_quantity_state_v1` in https://github.com/popcre/shared-db/blob/main/scripts/production_catalog_verification.py
- PR https://github.com/popcre/shared-db/pull/4597 (c0c0a160): https://github.com/popcre/shared-db/blob/main/supabase/migrations/20261022071323_sample_quantity_state_sandbox_reapply.sql — idempotent copy of 20260722221200 (IF NOT EXISTS / guarded DO block); sidecar https://github.com/popcre/shared-db/blob/main/scripts/production-verification-sidecars/20261022071323.json. Reviewed APPROVE by DeepSeek (slot 1).
- Root cause of the gap: `designflow-sandbox-migrations.yml` only applies migrations a PR *added*; 20260722221200 reached main via a rename (PR #168), so it could never be dispatched to the sandbox.

## 3. Preview / production
No preview or production write was made by this session. The new migration is a no-op on production/preview (all objects already exist there); it will flow through normal promotion.

## 4. Half-finished
Sandbox apply. Dry-run run https://github.com/popcre/shared-db/actions/runs/39746607257 (commit c0c0a160, allowlist 20261022071323, source_pr 4597) BLOCKED in the whole-batch preflight of https://github.com/popcre/shared-db/blob/main/scripts/production_migration_guard.py#L2483: "references missing dflow.sample / dflow.sample_box … created by 20260721201500 which is not applied". The sandbox ledger lacks 20260721201500 (restore_dflow_sample_tracking_tables) even though the tables exist live (the app error is "column does not exist", not "relation does not exist").

## 5. Owned
Nothing. Claims #4583 and #4596 released; `ai-shared-db-closeout-check` returned ok (0 claims, 0 stages).

## 6. Next actions
1. Read-only: prove on the sandbox that the six tables created by https://github.com/popcre/shared-db/blob/main/supabase/migrations/20260721201500_restore_dflow_sample_tracking_tables.sql and its five FKs exist (connect with the `DB_*_SANDBOX` GCP secrets; psql is not installed on edge-dev3).
2. Pick ONE governed route (structural-safety class, needs exact-head APPROVE):
   a. add a sandbox "mark applied with catalog proof" path (today https://github.com/popcre/shared-db/blob/main/.github/workflows/sandbox-ledger-orphan-reconciliation.yml only DELETEs orphan rows), then record 20260721201500 as applied; or
   b. let the sandbox preflight (https://github.com/popcre/shared-db/blob/main/scripts/sandbox_migration_preflight.py) accept a live-catalog proof for referenced objects whose creator is unrecorded.
   Do NOT add 20260721201500 to the batch: its `ADD CONSTRAINT` statements are not idempotent and would abort on the sandbox.
3. Rerun `DesignFlow Sandbox Migrations` dry-run (mode dry-run, current main SHA, allowlist 20261022071323, source_pr 4597, confirmation "DRY-RUN <sha>"), then apply with `dry_run_run_id`.
4. Verify: open https://alsand.designflow.app → Sample Tracking; the grid loads and `/api/tracking/sample/list` is 200 (Cloud Run logs clean). Tick the box on #4578 and close it.
5. Reviewer note (StepFun, PR #4597): later sandbox views may also need other unapplied sample migrations (20260722221600, 20260723230000, 20260824150630, 20260824172136); check the sandbox ledger for them.

## 7. Blocked on
Missing governed route to reconcile the sandbox ledger for 20260721201500 (step 6.2).

## 8. What did NOT work, and why
- Dispatching 20260722221200 with source_pr 168 → refused "was not added by source PR" (rename).
- Claim lease labels must be `Claude chat <full-uuid> on <host>` and `SHARED_DB_SESSION_ID=<uuid>` exported, or check-in refuses. Issue writes must list index objects too.
- Contract added in the same PR as its sidecar fails guarded merge: trusted policy runs from main. Land the contract first.
- Appending a contract after `if __name__ == "__main__"` hides it from the CLI verifier.
- Two production merge freezes (PR #4603, #4608) and two later-numbered migrations forced re-versioning via `--reversion-active-claim`.

## 9. Possibly stale facts
Sandbox ledger contents and the alsand error were last observed 2026-10-22 ~4:20 AM EDT.
