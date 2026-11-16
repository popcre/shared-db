# HANDOFF: Fix the shared-db production promotion pipeline jam

**Status:** open — plan written, not yet implemented
**Plan:** [docs/plan_promo-pipeline-fix.md](../../docs/plan_promo-pipeline-fix.md)
**Date:** 2026-11-16 ~5:30 PM EST

## What's happening

The shared-db production promotion pipeline is jammed. The `automatic-production-trigger.yml` concurrency group is cancelling queued runs before they execute (zero jobs started). This blocks all merged migrations from reaching production, including `20261115132055` and `20261116120000` (Disney property-suggestion, designflow-backend#408).

## What's done

- PR #6489 merged: timeout 10→30 min (necessary but not sufficient)
- Root cause identified: concurrency group cancelling runs, not timeout
- Plan written at `docs/plan_promo-pipeline-fix.md`

## What's next

Implement the plan: add early-exit guard to `automatic-production-trigger.yml`, verify queue drains, prove designflow-backend#408 live on sandbox.

## Key files

- `.github/workflows/automatic-production-trigger.yml` — the workflow to fix
- `scripts/automatic_promotion_candidates.py` — the selector (already has #6352 fix)
- `docs/plan_promo-pipeline-fix.md` — the full plan

Posted by MiMo chat ses_ffe5e29f41b39ffej7JEA7YF4w on win32
