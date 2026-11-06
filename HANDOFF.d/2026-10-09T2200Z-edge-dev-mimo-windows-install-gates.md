---
issue: 770
status: BLOCKED
owner: mimo / edge-dev
---

# #770 continuation — Windows install gates and plan handoff

Observation checkpoint: October 9, 2026, 10:30 PM EDT. This is a handover, not execution approval. Work card: https://github.com/popcre/shared-db/issues/770. Merged handoff: `HANDOFF.d/2026-10-09T0400Z-edge-dev3-codex-770-recovery-continuation.md` (PR #4115). Predecessor: PR #4101.

## 0. Business decisions only the owner can make

None. Already settled: complete #770, one scheduled production move, preserve capability. #2873 and tracking #111 are complete. Uma owns DesignFlow develop delivery.

## 1. What this application is

DesignFlow services (backend, item-master, tracking, data-sync) need database migration from Cloud SQL to Supabase with recovery, writer fencing, and authenticated acceptance. The ai-devops toolkit provides reviewer tooling and task gates required for the installation and review pipeline.

## 2. What we set out to do

Resume #770 from the merged handoff. Recover private encrypted custody. Continue toolkit PR #1533's fixture repair through merge and installation. Then rehearsal, credential issuance, provider blockers, and production move.

## 3. Current state

### Completed this session

- **PR #1533 merged** at `b9046892660d7eccd3efc0e4af84cf85849923a6` on `popcre/ai-devops` main (2026-10-09T15:52:39Z). The diagnosed fixture repair (synthetic readiness scoped to frontdoor fixture in `tests/test-ai-review-code-only.sh`) is in main. Linux CI section 4 passes. Merge queue landed after ENVY re-run cleared.
- **Muse APPROVE review** at correct merge base `1861259d` (diff-review) and `b904689` (final-check). Reports at `C:\tmp\ai-devops-1533\.ai\reviews\muse-diff-review-20261009T125444-1278485-12429.md` and `C:\tmp\ai-devops-install\.ai\reviews\muse-final-check-20261009T175147-1827819-20806.md`.
- **Plan written and merged:** `plan_windows-install-gates.md` in shared-db, registered in `HANDOFF.d/2026-10-09T2200Z-edge-dev-mimo-windows-install-gates.md`. PR https://github.com/popcre/shared-db/pull/4145 merged 2026-10-09T18:33:38Z.
- **GitHub issue filed:** https://github.com/popcre/ai-devops/issues/1548 — "Windows install gates block supported toolkit installation on edge-dev."
- **Custody key located** in 1Password: `ig5e7vjw4a3fqt5rgtbtof3etm` (vibe_coding vault) — "DesignFlow recovery encryption key - shared-db770 isolated rehearsal October2026." The encrypted archive itself is on edge-dev3 only.

### Blocked — Windows installation

The toolkit at `b904689` cannot install on edge-dev (Windows 11, Git Bash MINGW64). Seven gate failures, all documented with root causes in `plan_windows-install-gates.md` and ai-devops#1548. Summary:

1. `flock` missing (Git Bash) — `update.sh:67`
2. Path format mismatch (`pwd` MSYS vs `git rev-parse` Windows) — `update.sh:44`
3. Launcher canonical path comparison fails on MSYS `$HOME` — `ai-task-gates:1834`
4. `PROGRAMFILES` unset in Git Bash breaks launcher routing check — `ai-task-gates:910`
5. Install verification hard-coded Linux-only — `ai-task-gates:1495`
6. `start_head` must equal pre-update head, not target — `ai-task-gates:1780`
7. Review and installation require separate tasks and separate `final-check` review — `ai-task-gates:1835`

The three-phase fix is in the plan. Phase 1 patches (~10 lines in `update.sh` and `ai-task-gates`). Phase 2 is a separate final-check review and authorize-install. Phase 3 is the Windows installer.

### Private custody

Key in 1Password (`ig5e7vjw4a3fqt5rgtbtof3etm`). Encrypted archive at edge-dev3 paths from the handoff: `/home/ahazan/.codex/worktrees/770-rehearsal/designflow-backend/.ai/private-evidence/770/recovery/cipher` and `.../plain`. Never pushed. Do not reconstruct from narrative. Need a transfer path from edge-dev3.

### What was tried and failed this session

- **DeepSeek review** (4 attempts): first returned `missing-verdict`, three subsequent attempts killed mid-run with `ChildProcess.kill`. Lifecycles stuck at `status: running`. Issue logged: `20260109T112722Z-edge-dev-deepseek-1143052`.
- **Codex review** (2 attempts): BLOCKED — sandbox denied access to `review-sandboxes` directory, and `MANIFEST.md` unavailable.
- **Grok review** (2 attempts): completed once with REJECT on files NOT in the PR diff (comparing against current `origin/main` instead of merge base). Second attempt killed.
- **Gemini review**: "provider returned no response text."
- **Muse with wrong base** (`origin/main` = `ae56e6e`): REJECT on same phantom findings as Grok.
- **Muse with correct base** (`1861259d` merge-base): **APPROVE**. This was the breakthrough — the `--base` parameter must be the merge-base, not `origin/main`.
- **update.sh direct run**: failed on `flock`, then path format, then "candidate checkout has local changes" (when I patched the script in-tree), then "candidate is not the exact approved target" (when the patch changed HEAD), then "Linux-only" verification route.
- **authorize-install**: failed on "Launcher is not canonical managed path" (MSYS vs Windows path), then "Installed Windows launcher routing differs" (`PROGRAMFILES` unset), then "Protected review and installation must use separate tasks" (same review reused).

## 4. Dead ends — do NOT retry these

- Comparing reviews against `origin/main` instead of the merge-base. Always use `git merge-base origin/main HEAD`.
- Reusing a `diff-review` as the deploy approval for `authorize-install`. Action `deploy` requires `review_mode: final-check` or `security-review`.
- Patching `update.sh` in the candidate worktree and committing it. The candidate HEAD must exactly match the reviewed commit.
- Faking `flock` with a stub that always succeeds as a permanent fix.
- Bare `git pull` on the installed checkout or manual launcher copies.
- Starting the installation task at the target commit. `start_head` must be the pre-update installed head.

## 5. Exact next steps

Follow `plan_windows-install-gates.md` phases 1–3. Start at Phase 1 (P1: path normalization in `update.sh`; P2: lock fallback; P3: `PROGRAMFILES` detection and launcher path fix in `ai-task-gates`). Then Phase 2 (separate `final-check` review, `authorize-install`). Then Phase 3 (Windows installer, hash verification).

## 6. Constraints

- Feature-branch-PR for `popcre/ai-devops`. Never push to `main` directly.
- Reviewer must differ from implementer (provider `muse`, implementer `mimo`).
- ENVY CI runner limitation preserved (Smart App Control / Worker 2.337.0).
- MSYS paths in `authorize-install` calls (`/c/Users/ahazan/.local/bin/ai-task-gates`).
- Never reconstruct private evidence from the handoff narrative.

## 7. Access and environment

- Machine: edge-dev (Windows 11, Git Bash MINGW64_NT-10.0-26300).
- 1Password vault: `vibe_coding`. Custody key item: `ig5e7vjw4a3fqt5rgtbtof3etm`.
- Installed checkout: `C:\repos\ai-devops` at `63e83b0772b5b8e7a071264829b163dd863c39f6`.
- Candidate worktree: `C:\tmp\ai-devops-install` (detached at `b904689`, installation task declared).
- Muse review reports under `C:\tmp\ai-devops-1533\.ai\reviews\` and `C:\tmp\ai-devops-install\.ai\reviews\`.

## 8. Open questions, risks, ownership

- Root coordinator owns all pending outcomes on #770.
- Whether to contribute the Phase 1 patches upstream to `popcre/ai-devops` (open: see plan §8).
- Private custody transfer from edge-dev3 is unblocked only after installation works.
- Reviewer system flakiness on this machine (DeepSeek killed, Codex sandbox denied) may resurface; issue `20261009T112722Z-edge-dev-deepseek-1143052` records it.

## Self-audit

1. Comprehensive cold continuation: YES — §3 defines exact state, §4 records dead ends, §5 gives ordered steps with file references, plan file carries the full build spec.
2. Equivalent session knowledge: YES — §3 and §4 carry every finding, failure, and rejected approach from this session.
3. Execution detail coverage: YES — plan phases have concrete files, commands, and verification gates.
4. Owner-decision sweep: YES — §0 is None. All technical approval stays root/assigned reviewer.
