---
issue: 5986
status: OPEN
owner: next session (unassigned)
---

# HANDOFF — DesignFlow `database/production-ready` still not working (2026-11-10)

## 1. Goal
DesignFlow app releases to main must stop being blocked by the shared-db release observer
(workflow "DesignFlow database release readiness", id 393353405,
https://github.com/popcre/shared-db/blob/main/.github/workflows/designflow-db-release.yml, code https://github.com/popcre/shared-db/blob/main/scripts/designflow-db-release.mjs).
Albert reported on 2026-11-10 10:36 AM EST that it is "still not working". **He did not give the
details to the previous session.** He will paste them into the new session. Start from his details. Do not assume
it is one of the problems below.

## 2. Background: three problems already fixed (do not redo)
1. **item-master #184 (promote/pr-158-main → main) never got the status.** The observer publishes
   `database/production-ready` only on app `develop`/`main` heads, and a main source counts only when it comes
   from a merged `develop`→`main` PR (`sourceAllowed`). Fix: Uma opens main PRs from develop.
2. **shared-db PR #5910 (migration 20261106174810, work issue #5026) refused twice.** (a) The body lacked
   `Work issue #5026`. That was fixed by editing the body. (b) "evidence is inherited; exactly one PR-owned complete
   pair is required": there was no `.agent/work/<issue>/<gen>/` pair. Fixed by reissue PR
   https://github.com/popcre/shared-db/pull/5944 (new version 20261108135128, merged 2026-11-08 9:31 AM EST),
   plus item-master manifest PR https://github.com/popcre/designflow-item-master/pull/185.
3. **"Source content is absent or exceeds the bounded file size"** (frontend #558, tracking #189;
   requirement work issue #3869, source PR #4735). An older current-live certificate (commit 0cbc97f6) lacked the
   newer trusted file `scripts/lib/production-apply-artifact-name.mjs`. `content()` threw and aborted the scan.
   Fix: `trustedPathsMatch()` skips such stale certificates. https://github.com/popcre/shared-db/pull/5987
   (issue #5986), merged 2026-11-09 ~12:05 PM EST. Because `scripts/designflow-db-release.mjs` is itself in
   `CURRENT_LIVE_TRUSTED_PATHS`, **every change to the observer makes all certificates stale**. That needs one
   current-live recovery run (the command is printed in the observer's `recovery_command` / step summary).
   That recovery was run (run 42661874107, success). Observer run 42662145659 then reported all six apps
   `ready`. Frontend #558 and tracking #189 have since MERGED.
   Self-service notes for app devs: section "Common database/production-ready blocks" in
   https://github.com/popcre/shared-db/blob/main/docs/designflow-db-release.md

## 3. Current state (verified 2026-11-10 10:36 AM EST)
- Observer runs today: 42834838058 success (9:30 AM EST), 42841654416 success (10:10 AM EST),
  42841663636 **failure** (10:10 AM EST). The failure was in the pre-observe unit tests: test 97
  (`scripts/lib/designflow-db-catalog.test.mjs:137`) could not reach the synthetic PostgreSQL socket
  (`/var/run/postgresql/.s.PGSQL.5432`). That looks like container-start flakiness, because a parallel run at the same time passed.
  Not yet investigated. It may or may not be what Albert means.
- https://github.com/popcre/shared-db/pull/5992 (deletes the previous #5986 handoff file) is open and CLEAN, with auto-merge on.
- The previous session holds no shared-db claims (closeout check ok).

## 4. Likely causes to check first
- Recurring stale certificate: any new merge touching a `CURRENT_LIVE_TRUSTED_PATHS` file
  (`scripts/lib/production-catalog-recovery.mjs:83`) makes certificates stale again. Look for
  `current-live-reverification-required` in the latest observer log and run its `recovery_command`.
  This is a design weakness: every observer change forces a manual recovery. Consider automating it.
- A flaky synthetic Postgres in the workflow's test step (item 3 above).
- A new app PR from a non-develop branch (item 2.1).
- A new migration source PR without `Work issue #N` or without an evidence pair (item 2.2).

## 5. Next actions
1. Read Albert's details. Identify the app, PR, and exact observer reason:
   `gh run list -R popcre/shared-db -w 393353405 -L 5`, then `gh run view <id> --log | grep -E '"repository"|"status"|"reason"|recovery_command'`.
2. Fix through the normal shared-db PR flow (`docs/agents/merge-protocol.md`). Never edit app repos' main directly.
   DesignFlow app PRs go to `develop` and are merged by Uma.
3. Verify: a fresh observer run reports the affected app `ready`, and the app PR's `database/production-ready` status is success.

## 6. Constraints
- Albert is non-technical. Never ask him to approve, merge, or run commands. Ask only business questions.
- Times in EST. Sign GitHub posts with $AI_GH_SIGNATURE.
- Don't use bare `sleep` loops over PR reads (a hook blocks them). Use `ai-pr-wait`.

## 7. Risks
A recovery run binds to current main. Run it only after any observer-related merge has landed, or it goes stale again.

## 8. Evidence
Runs: 42637565705 (old failure), 42661874107 (recovery), 42662145659 (all ready), 42841663636 (today's failure).

## 9. Self-audit
Could a stranger continue? Yes for background and diagnosis (sections 2–5). The one known gap is Albert's
undisclosed symptom, which he will supply.
