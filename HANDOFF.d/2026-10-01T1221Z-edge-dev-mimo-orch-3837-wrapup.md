---
issue: 3837
status: OPEN
owner: mimo/orch-3837-wrapup
---

# Shared-db orchestrator #3837 wrap-up (MiMo chat ses_ffe5f0cb4d420ffeIsV74tLSR5, edge-dev)

All times America/New_York (EDT). Facts checked 8:21 AM EDT, 2026-10-01.

## 0. DECISIONS ONLY THE OWNER CAN MAKE

None blocking technical work. Standing holds:

- **#1941 Laura/Ilona licensed-property sign-off** — on hold until **2026-10-05** per Albert (~3:05 PM EDT 2026-09-28). Dependents #2601, #2541 stay parked. Do not re-ask before that date.
- **DeepSeek account out of credit** — top up at https://platform.deepseek.com/top_up then `ai-review-preflight clear deepseek`. Until then DeepSeek is not drawable (HTTP 402). Not an Albert decision unless he wants another reviewer family instead.

Already settled — do NOT re-ask:

- Never ask Albert to approve technical risk; independent AI reviewer / governed machine gate decides (owner ruling 2026-09-28 / 2026-09-30).
- Albert is not a technical reviewer. Process questions go to an AI reviewer (he said so 2026-10-01: "i am non-technical and not qualified to answer. ask a reviewer").
- 2026-10-01 Muse process opinion: a one-time deliberate `origin/main` merge into a ready PR is the supported §2758 path when Guarded Merge requires current-main base. The session rule "never auto-update PR branches from main" targets unattended churn, not that refresh. Qualification: main+PR file overlap voids content-preserving carry-forward and needs a fresh review.

## 1. What this application is

`popcre/shared-db` is the shared Supabase schema repo for POP Creations apps. Structure (DDL) is governed here via branch+PR+Guarded Merge. Production project ref `qsllyeztdwjgirsysgai`; preview `mvpkijzfmfcxhnzqogzs`.

## 2. What we set out to do this session

Successor shared-db orchestrator after marker #3832 closed (handover PR #3836, briefing `HANDOFF.d/2026-09-30T1651Z-edge-dev-mimo-orch-3832-wrapup.md`). Ordered queue from Albert:

1. #2176 consumer contracts (fresh claim; do not assume `plm.import_coldlion_vendors` exists)
2. #3683 NBCU — governed review at merged head `258f0319` on PR #3695
3. protected-file queue #3657 → #3808 → #3396 → #3787 → #3647 → DesignFlow
4. #3825 then #3828

## 3. Current state — what is true right now

**Main tip `5deadd0432d282b204b4702464867f472025c333` at 8:10 AM EDT 2026-10-01.** Max migration on main: **`20260929093750`** (ColdLion item_image_metadata). NBCU `20260929045102` is also on main (from #3695). Marker **#3837 OPEN** (`route_id: local_c2c4b8ff-e007-4b90-9326-e70e83c0ebcb`).

### Done this session

| Item | Result |
|---|---|
| Successor marker | **#3837** opened; `check-orchestrator-marker.mjs --resolve` prints own route_id |
| **#3683 NBCU** | **CLOSED live_verified.** Muse+Gemini APPROVE at `258f0319`. Preview apply run `36760422856`. Production apply run `36763793561` (v1 Production Apply Review Evidence `36763689442` after auto-v2 fail-closed on material_access_change). Migration `20260929045102` on production. |
| **#2176** | Admitted + claim **#3838** version **`20260930172952`**. Migration authored. **PR #3839** OPEN at `4b36ee6d105c51b72d89823d94944b25e679e74a`. CI green (contract + ephemeral tests). Writes match claim (17 objects). |
| **#3828** | **MERGED** `27307f5d6` at 2026-09-30T22:04:19Z (outside this stretch; present when rechecked). |
| **#3825** | Muse REVISE at `e678c850` fixed (H1 string-literal bypass, M1 evidence, M2 IMMUTABLE). Refreshed onto main `5deadd043` (content-preserving refused: main also touched the risk-gate files). New head `e924eebd6`. Muse REVISE again: **bare-name call whitelist shadowable** (H1/M1). Fix agent in flight at wrap-up. |
| Reviewer issues | `20260930T195000Z-edge-dev-grok-turnlimit-2176`, `20260930T195200Z-edge-dev-muse-wrapper-exit-2176` |
| Process opinion | Muse agreed one-time main-merge is supported §2758 path (session `ds-main-merge-policy`) |

### Half-done / not done

| Item | Exact state |
|---|---|
| **#3825 whitelist fix** | Agent `general-19` still running at wrap-up (shadowable bare-name whitelist in `_do_body_is_assertion_only` / `_immutable_body_is_safe`). Branch `fix-risk-gate-alter-function-do-3821`, worktree `C:/repos/shared-db/.ai/worktrees/risk-gate-3821-mimo`. After fix: re-review at new head, then Guarded Merge. |
| **#3839 reviews** | Slot 1: DeepSeek 4640 → Grok 4641 (turn_limit_cancelled, excluded terminal-unavailable). Further assign/replace refused (`reviewer release evidence is unreadable`). Slot 2: Qwen 4642 → Muse 4643 (wrapper exit 1). Card posted on PR. |
| **protected-file queue** | #3657 → #3808 → #3396 → #3787 → #3647 → DesignFlow. **Not started.** One open PR at a time on `manage-migration-author-lanes.mjs`. |
| Claim transfers | #2110 (#3378), #3175 (#3307), #2662 (#3294) — not started. |

### Preview / production

- Preview: `20260929045102` applied (run `36760422856`, digest `sha256:5957bd59239ce46b778b41c9e50312e406832e1fe6a0566a32ba0449a3a2f1d7`). Prior versions remain.
- Production: `20260929045102` **applied** (run `36763793561`). Catalog verification: no hard failure. `20260929093750` still on production from prior session.

## 4. Everything we tried that did NOT work

1. **`normalizeObject` on `function foo(jsonb)`** — collapses to `function ` and trips "duplicate object claims". Claims must use bare function names (no argument lists).
2. **`--admit-issue` on `run-governed-review.mjs`** — unknown option. Only `manage-migration-author-lanes.mjs` takes it.
3. **Doubled `-- --` before wrapper `new`** — second `--` becomes wrapper argv[0]; Muse/Grok refuse. Correct: `-- new <session> --prompt-file <file>`.
4. **Merged-PR review from shared checkout** — `C:/repos/shared-db` is ~1000 commits behind origin/main and its runner hard-requires open PRs. Use `.ai/worktrees/review-3830-de4e2769` (post-#3830) with `SHARED_DB_MERGED_PR_ISSUE_BINDING=3695:3683`.
5. **PR body without `Work issue #N`** — `verifyMergedPrIssueBinding` refuses `Closes #N` alone. Added literal `Work issue #3683` to PR #3695 body.
6. **auto-v2 production promotion** on `20260929045102` — fail-closed (`material_access_change`). Supported path: v1 `Production Apply Review Evidence` + dispatch with `source_pr` + `preview_artifact_digest`.
7. **Guarded Merge without current main tip** — REFUSED `pull request is not based on the current main tip`. Deliberate `origin/main` merge is the §2758 path (Muse process opinion). `refresh-code-pr-branch.mjs` refused here because completion carried non-standard check commands (unittest + truth-audit).
8. **Content-preserving refresh carry-forward** — refused when main also changed the PR's files (`production_business_risk_gate.py`). Fresh exact-head review required.
9. **Grok on large migration reviews** — recurring `turn_limit_cancelled` (1–2M tokens, no VERDICT). Excluded `terminal-unavailable` on PR #3839.
10. **DeepSeek second-opinion** — HTTP 402 `OUT OF CREDIT`. Rotate; do not retry.
11. **Author mutex stranded** at `cde4f6e6…` — recovered via `recover-author-mutex.yml` with `expected_sha` + `confirmation=RECOVER <sha>`.
12. **`ai-reviewer-issue record` hung** on this host — wrote `issue.json` + `details.redacted.txt` manually under `C:/repos/ai-devops-reviewer-install/.ai/reviewer-issues/`.
13. **Qwen keeps drawing from the round robin** despite being broken until ai-devops#1035 — replace with `provider_unavailable` each time.

## 5. Root causes and key findings

- Review evidence binds to exact head; any fix voids APPROVEs. Batch findings into one head.
- Function object claims must be bare names; `(jsonb)` breaks `normalizeObject`.
- Completion `files_changed` must equal Git-changed set **including the evidence pair paths**.
- `schema_version: 2` contracts need explicit `evidence_parent` (null for gen 1).
- `grant all on all tables in schema X` over-grants on mixed-posture schemas; use explicit DML grants.
- Muse needs a **clean worktree** for source digests on this repo (dirty checkout → `local_preparation_incomplete`).
- `ai-muse`/`ai-grok-review` need `AI_*_CALLER=mimo` and subcommand `new|ask` before `--prompt-file`.
- Prefer Muse+Grok/StepFun over DeepSeek for migration reviews (DeepSeek REVISE-loops; issue `20260929T203215Z-edge-dev-deepseek-7809`).

## 6. Exact next steps

1. **#3825**: collect `general-19` whitelist fix (or re-dispatch). Re-review at new head (Muse preferred). Guarded Merge at that head. Verify: `gh pr view 3825` MERGED.
2. **#3839 reviews**: repair slot-1 return/release evidence for head `4b36ee6d…`, draw Muse or Gemini (Grok excluded). Single `--` before wrapper `new`. Verify: 2-slot APPROVE + Guarded Merge.
3. **protected-file queue** one PR at a time: #3657 → #3808 → #3396 → #3787 → #3647 → DesignFlow.
4. Claim transfers #2110/#3175/#2662 via the #3620 tool.
5. Close leftover parked waits if any remain (#3833 already closed).

**Verification gates:** each step ends with `gh pr view` MERGED or `gh issue view` CLOSED + live-proof comment; `check-exact-head-approval` green before every conductor drive.

## 7. Constraints and gotchas in force

- Branch + PR + Guarded Merge; AI merges; never push to protected `main`.
- Preview / production / merge are one-at-a-time lanes.
- One-time deliberate main-merge into ready PRs is allowed (Muse 2026-10-01); unattended auto-update is not.
- Never ask Albert to approve technical risk.
- Qwen fails on edge-dev until ai-devops#1035; do not draw it.
- DeepSeek out of credit until topped up.
- Claude/MiMo must not review Claude/MiMo-orchestrated work.
- #1941 on hold until 2026-10-05.
- Times in EDT (America/New_York).
- Sign GitHub comments `Posted by MiMo chat ses_ffe5f0cb4d420ffeIsV74tLSR5 on edge-dev`.
- Keep GitHub API calls bounded; one merge conductor only (`conductor-3821`).

## 8. Access and environment

- Machine: **edge-dev** (Windows).
- `gh` authenticated as u2giants. Repo `popcre/shared-db`.
- 1Password vault `vibe_coding`. `Supabase CLI Personal Access Token` item id `3t2xoqk5luyz7ffgdhj24gvtpq`. Use `op run --env-file` with `op://` refs only.
- Preview env file: `C:\repos\shared-db\.ai\tmp-preview.env`.
- Reviewer wrappers under `C:\repos\ai-devops-reviewer-install\bin\`.
- Git Bash: `"C:\Program Files\Git\bin\bash.exe"`.
- Shared checkout `C:\repos\shared-db` is dirty and far behind origin/main — work in isolated worktrees only.

## 9. Open questions and risks

- **#3839** reviewer assignment graph is broken for that head (`reviewer release evidence is unreadable`). Needs a careful repair, not another blind assign.
- **DeepSeek OOC** reduces the review pool until topped up.
- **Protected-file serialization**: only one open PR may touch `manage-migration-author-lanes.mjs`.
- **Many pre-existing worktrees** under `.ai/worktrees/` — do not delete without `cleanup-worktree` audit.
- Max migration / main SHA go stale within the hour — re-verify at start.

---

# Part (b) — sub-agent work blocks

### Agent: general-1 / general-10 — #2176 unit 6 authoring
- **Asked to do:** Author ColdLion consumer-safe promotion contracts under claim #3838 / version `20260930172952`.
- **Actually did:** Migration `20260930172952_coldlion_unit6_consumer_contracts.sql` + tests + evidence pair gen 1. Writes match claim (17 objects). Then fixed CI (evidence_parent, files_changed, drop stale merch_group columns from item_detail view, narrow coldlion grants). Final pushed head `4b36ee6d1`.
- **Found:** `plm.import_coldlion_vendors` absent (dropped `20260722213000`). `comment on column` emits extra object keys. `grant all` over-grants on mixed schemas.
- **PR / branch:** PR **#3839** `feat/2176-consumer-contracts`.
- **Worktree:** `C:/repos/shared-db-wt-2176-unit6` — finished (safe to clean after PR merges).
- **Deliberately did NOT do:** merge (orchestrator owns it); invent `plm.import_coldlion_vendors`.

### Agent: general-2 / general-5 / general-6 / general-13 — #3683 reviews
- **Asked to do:** Governed exact-head reviews at merged head `258f0319` on PR #3695.
- **Actually did:** Muse slot 2 APPROVE; Gemini slot 1 APPROVE (2/2). Binding fixed via `Work issue #3683` in PR body. Ran from `review-3830-de4e2769` worktree.
- **Found:** Shared-checkout runner rejects merged PRs. Muse needs `new <session>`. `AI_GEMINI_CALLER=mimo` required.
- **PR / branch:** PR #3695 (already MERGED `8f0d320a`).
- **Worktree:** `C:/repos/shared-db-wt-review-3683-head` — finished (safe to clean).
- **Deliberately did NOT do:** production apply (orchestrator used v1 evidence path).

### Agent: general-3 — Gemini #3683 slot 1
- **Asked to do:** Governed review slot 1.
- **Actually did:** APPROVE at `258f0319` after runner/binding fixes. Artifact `refs/db-review-verdict-replacements/3683-3695-258f0319…-4537`.
- **Found:** `AI_GEMINI_CALLER=mimo`; runner injects `--governed-verdict`.
- **Worktree:** review worktree — finished.

### Agent: general-4 — #3825 evidence fix
- **Asked to do:** Fix Agent work contract FAILURE (files_changed).
- **Actually did:** Listed both evidence paths in `files_changed`; pair committed together. Head `e678c850`.
- **Found:** files_changed must include the evidence pair; contract hash is canonicalized (formatting-only rewrites legal).
- **PR / branch:** PR #3825 `fix-risk-gate-alter-function-do-3821`.
- **Worktree:** `C:/repos/shared-db-wt-fix-3825-evidence` — finished.

### Agent: general-14 / general-16 — #3825 Muse reviews
- **Asked to do:** Exact-head reviews at `e678c850` then `6ae551e4`.
- **Actually did:** REVISE at `e678c850` (H1 string-literal fail-open, M1/M2). APPROVE at `6ae551e4` after fixes. Then post-refresh REVISE at `e924eebd6` (bare-name whitelist shadowable).
- **Found:** Single `--` before wrapper `new`. Muse timeout needs >10 min. Stuck Muse sessions may need `ai-muse reconcile`.
- **Worktree:** `C:/repos/shared-db-wt-review-3825` — live if #3825 still open.
- **Deliberately did NOT do:** merge.

### Agent: general-15 — #3825 Muse REVISE fix (round 2)
- **Asked to do:** Fix H1 string-literal bypass, M1 evidence rebind, M2 IMMUTABLE body check.
- **Actually did:** String/comment-aware tokenizer; IMMUTABLE body checks; rebound evidence to `32c05b35e`. Tests 195+12 OK. Head `6ae551e4`.
- **Found:** PG U-strings use `''` doubling only; truth-audit catalogue survives nearby inserts.
- **PR / branch:** PR #3825.
- **Worktree:** finished.

### Agent: general-17 — Muse process second-opinion
- **Asked to do:** Judge one-time main-merge into ready PRs under §2758.
- **Actually did:** Agreed; high confidence; qualification on reviewer carry-forward (prefer `--no-assign` and re-prove with `check-exact-head-approval`).
- **Found:** `refresh-code-pr-branch.mjs` is the sanctioned helper. Muse needs a clean worktree.
- **PR / branch:** none.
- **Worktree:** `C:/repos/shared-db-wt-process-opinion-20261001` — finished (safe to clean).

### Agent: general-18 — #3825 post-merge review
- **Asked to do:** Review merged result at `e924eebd6`.
- **Actually did:** REVISE — bare-name call whitelist shadowable (H1/M1). Artifact `refs/db-review-verdicts/3826-3825-e924eebd6…`.
- **Found:** Content-preserving refresh refused when main also changed the PR files.
- **PR / branch:** PR #3825.

### Agent: general-19 — #3825 whitelist fix (IN FLIGHT at wrap-up)
- **Asked to do:** Fix shadowable bare-name whitelist in DO checker and `_immutable_body_is_safe`; add tests; rebind evidence.
- **Actually did:** Still running at 8:20 AM EDT 2026-10-01 (53+ turns). No final head recorded yet.
- **PR / branch:** PR #3825 `fix-risk-gate-alter-function-do-3821`.
- **Worktree:** `C:/repos/shared-db/.ai/worktrees/risk-gate-3821-mimo` — **LIVE**.
- **Deliberately did NOT do:** merge.

### Agent: general-7 / general-8 / general-11 / general-12 — #3839 reviews (failed delivery)
- **Asked to do:** Slot 1/2 governed reviews at `4b36ee6d1`.
- **Actually did:** No durable verdicts. Grok turn_limit_cancelled (excluded). Muse wrapper exit 1 / stale-source APPROVE non-authorizing. Assignment graph now unreadable for slot 1.
- **Found:** See §4 items 2–3, 9, 12.
- **PR / branch:** PR #3839.
- **Deliberately did NOT do:** self-replace, merge.

---

## Secrets / docs

- Secrets sweep: **no new credential created**. Used existing 1Password item `Supabase CLI Personal Access Token` (`3t2xoqk5luyz7ffgdhj24gvtpq`) via `op run` + `op://` env file only. DeepSeek OOC is an account balance issue, not a leaked secret.
- Docs pass: durable lessons live in §4–§5 of this handover. `AGENTS.md` still correct on never-ask-Albert-to-approve and evidence-pair rules. Nothing outside this handover is stale that this session proved wrong.

## Queue seed (REQUIRED)

Outstanding items already have open issues or PRs:

| Item | Issue / PR | Next |
|---|---|---|
| #2176 consumer contracts | #2176 OPEN / PR #3839 OPEN | Repair slot-1 review evidence; 2-slot APPROVE; merge |
| #3825 risk-gate | #3826 / PR #3825 OPEN | Finish whitelist fix (general-19); re-review; Guarded Merge |
| protected-file queue | #3657, #3808, #3396, #3787, #3647, DesignFlow | One PR at a time on lanes script |
| Claim transfers | #2110/#3175/#3175/#2662 | After #3620 tool |
| DeepSeek OOC | n/a (account) | Top up + `ai-review-preflight clear deepseek` |
| Reviewer issues | `20260930T195000Z-edge-dev-grok-turnlimit-2176`, `20260930T195200Z-edge-dev-muse-wrapper-exit-2176` | Maintenance sweep later |
| #1941 hold | #1941 | Wait until 2026-10-05 |

No new `db-work` issues required — all outstanding work is already queued.

Posted by MiMo chat ses_ffe5f0cb4d420ffeIsV74tLSR5 on edge-dev
