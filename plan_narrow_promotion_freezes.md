# Proposed implementation: ordinary-prose merges during promotion review

**Proposal only — not authorization to change safeguards or production.** Investigation issue [#4039](https://github.com/popcre/shared-db/issues/4039). Source baseline `fee69a25ffd9b39c2b3accfde680dfbac3aa54f5`. Read [investigation and evidence](docs/investigations/narrow-promotion-freezes.md) first, then this STATUS table. Owner: Codex investigation workstream. October 7, 2026, 11:39 AM EDT.

| Step | Status | Evidence / gate |
|---|---|---|
| Independent design approval | APPROVED DESIGN | Allocator sequence 5638 Gemini APPROVE at 610e80cd; report §9 retains durable exact-source verdict |
| 1. Freshness, authority and inventory | OPEN | §9.1 below |
| 2. Immutable snapshot and strict delta validator | OPEN | §9.2 and §10 named tests |
| 3. Admission, queue and freeze generation fencing | OPEN | §9.3 |
| 4. Preview, qualification and production integration | OPEN | §9.4 |
| 5. Adversarial/concurrency verification | OPEN | §9.5 |
| 6. Reviewed rollout, measured acceptance and rollback | OPEN | §9.6; live proof remains on #4039 |

**Fresh-session starting point:** verify retained design verdict and live publication state. Do not start implementation without later authorization. This session was authorized only to investigate. Successor registration: [handoff](HANDOFF.d/2026-10-07T1545Z-edge-dev3-codex-narrow-promotion-freezes.md).

## 1. Ultimate goal

Allow harmless document work to finish while another approved database change is being reviewed for production, without risking the shared database or losing exact acceptance evidence. If a step conflicts with this goal, the goal wins — stop and flag it. Speed never replaces review, target proof, bounded application, collision protection or live application acceptance.

## 2. System and environment

Canonical repository [popcre/shared-db](https://github.com/popcre/shared-db) owns SQL migrations for one shared Supabase database consumed by POP applications (CRM, DAM, PIM and DesignFlow). GitHub is source authority; automatic workflows execute reviewed changes. This is repository tooling, not a database structure change. Implementation languages are Node ES modules, Python and GitHub workflow YAML. Production identity is guarded by existing policy; preview identity comes from repository variable `PREVIEW_PROJECT_REF`. Never infer target from a local config.

Work only in a dedicated current-upstream worktree. Never edit a consumer's mirrored `shared-db/` directory or another session's checkout. Read repository `AGENTS.md`, `docs/agents/current-workflow.md`, relevant merge/claim/standing rules and activated production policy. Current automatic policy is active in `config/production-risk-policy-activation.json`. Never manual-dispatch production to test this proposal.

## 3. Trigger and reproduction

Albert asked whether promotion freezes could avoid blocking all shared-db merges. The supplied investigation task expressly prohibits implementation/deployment. Original mechanism on #3919 intentionally protects main while a risk assessment is obtained. On October 7 the #2875/#3708 freeze blocked generic merge acquisition and document authorization. Reproduce offline using existing freeze tests in `scripts/manage-migration-author-lanes.test.mjs`; never create a production freeze as an experiment.

## 4. Scope

IN: single-source automatic promotion only, serialized mutual exclusion with outstanding migration-train authority, immutable promotion identity, strict harmless-prose tail classification, review-period prose admission, consistent caller checks, exact-generation cleanup, offline race tests, measured staged rollout after separately authorized implementation.

OUT: all new SQL/schema or data writes; generic disjoint-migration admission; snapshot promotion of migration trains; releasing existing locks; changing reviewer membership/approval semantics; reducing required checks; changing branch protection; new manual production lane; reopening retired orchestrator instructions; changing consumer deployment/acceptance rules; a new scheduling service. Do not fabricate a migration to get a reviewer.

Retain broad blocking during actual production ownership. This intentionally small first delivery offers meaningful review-period relief without a semantic SQL dependency engine.

## 5. Current code and delivery state

Nothing in this proposal is implemented, committed as code, deployed or live-accepted. Existing behavior and pinned references are fully mapped in report §§1–3. Entry points:

* `scripts/manage-migration-author-lanes.mjs:3943,3953,4043,4063–4158`: acquisition, freeze records and documents authorization.
* `scripts/lib/lanes/exclusive-policy.mjs:110–201` and `exclusive-locks.mjs`: extracted compatibility policy, must match orchestration.
* `scripts/lib/documents-only-change.mjs`, `scripts/check-documents-only-merge-authorization.mjs`: base-owned complete comparison/classification.
* `scripts/check-main-tip-freshness.mjs:64–109,121–243`: existing path-based production-inert exception, **not enough for new admission**.
* `.github/workflows/shared-supabase-migrations.yml:431,1173,1557,1800,1831,2159–2182`: preview, qualifier, apply and cleanup.
* `scripts/merge-queue-contract.mjs:233–276,436–468`, `.github/workflows/merge-queue-gate.yml`: final queue recheck.
* `scripts/production_business_risk_gate.py:596,1244,2229,3743`: runtime/provenance/source/risk chain.
* `scripts/production_migration_guard.py:1070,1543,2280,2511`: bounded ordered guards and fresh dry-run.

Line numbers are baseline locators, not permission to edit blindly after upstream movement. Re-read live code first. Existing production source review equivalence is preserved; tests do not become unreviewed implementation equivalence.

## 6. Findings and root cause

Exact-main protection is spread across several independent guards. One production freshness check already allows documentation/tests/evidence movement, but preview and qualification/lock still require literal equality. Removing only the freeze would make work fail later. Production-held merge blocking and status revocation are separate mechanisms.

Claims/version leases model named read/write overlap, not complete transitive SQL dependencies. Stored bodies, dynamic SQL, role/default privileges, FK/trigger/type dependencies and promotion code invalidate schema-only independence. Baseline cleanup is exact-delete within each operation but matches release by PR across attempts; an old same-PR cleanup can match a replacement freeze. See report §5 for fencing distinction.

## 7. Rejected approaches

Reject bare freeze release, schema/table-only comparison, blindly permitting `.md`, using only the existing production-inert predicate, candidate review transplanted to moving main, source-PR-only cleanup fencing, accepting an expired lock as abandoned, and weakening reviewer retention/parsers. Do not broaden reviewed-source equivalence to tests. Do not add a separate broker, scheduler or duplicate promotion implementation.

Generic migration tail admission is deferred, not approved by implication. A future plan must prove dependency closure, version barriers, changed live ledger and producer-code authority; this plan cannot pass its positive case.

## 8. Locked and open design decisions

**Locked safety requirements:** source approval exact head; risk assessment exact snapshot S and ordered V; bounded immutable migration bytes; target proof immediately before every write; fresh verified dry-run; exclusive production write lock; unchanged applied migrations; all current artifact/source/issue/activation proofs; fail closed for missing/unknown state; application acceptance on same issue. No human technical approval or manual work.

**Locked first-stage scope:** only inert ordinary prose during review/qualification; existing full pause while production ref held; no SQL or executable changes while a snapshot is active.

**Implementation choices with explicit criteria:** reuse the current trusted classifier and global-invalidator inventory; one shared strict comparison module must serve every caller. Extend existing `scripts/target-queue-identity.mjs` freshness/manifest primitives (lines 247–357) and `scripts/lib/lanes/exclusive-policy.mjs`; **do not create `scripts/lib/promotion-snapshot.mjs` or another snapshot subsystem**. Step 10 #3781 already owns this integration. Reconcile its live scope/owner and reuse accepted wiring once available; do not implement its shared-file scope a second time. Its October 6, 2026, 8:39:11 PM EDT comment proves policy-level merge only, not live queue acceptance or production acquisition integration. Reuse existing evidence schema/transport helpers. A versioned snapshot record must be immutable and supported by exact-ref ownership; choose the existing coordination namespace or a new documented one only if no existing compatible record exists. Register every new ref in snapshot/transfer/configuration inventories and recovery readers.

**Unsettled and implementation-blocking:** complete consumed-prose denylist, live revocation semantics, activation barrier over preauthorized groups, shared-preview baseline freshness. Resolve by source evidence, named negative tests and assigned review, never a business question for Albert.

## 9. Sequenced executable phases

### 9.1 Freshness, authority and inventory

After separate implementation authorization: declare task class matching actual safeguarded production tooling scope (`production` if it gates live production; never downgrade to prose). Re-read gate policy and branch policy. Use the truthful ready repository-maintenance tracking fields with `change_type: documentation` for this investigation review and `SHARED_DB_AUTHOR_ENGINE=codex`; delivery-preflight arguments are optional unless the live task route requires them, and supplied proof must be genuine. Fetch live main into a dedicated worktree, run freshness guard, inspect issue #4039 and active overlapping tooling PRs, claims, exclusive refs and supported mutex recovery status. Do not adopt #2875/#4037 ownership.

Re-read `plan_shared_db_workflow_refactor.md` Step 10 and live #3781/#4018; preserve its MiMo ownership and register only freeze-specific extension scope after supported overlap reconciliation. Do not message another chat without Albert's explicit authorization; read-only issue/state inspection is enough to detect a hold. Define inventory at exact base: every runtime imported file, workflow, policy/configuration, verification sidecar and prose/instruction resource used in promotion, including dynamically loaded resource paths. Compare `PREVIEW_PRODUCER_PATHS`, sidecar registry and `config/orchestrator-global-invalidators-v1.json`; unknown closure refuses. Record existing required-check list unchanged.

Gate: a versioned inventory with reproducible source references; no missing runtime resources; no overlapping owned change; baseline suites pass. If a dependency cannot be proven inert, exclude its entire class.

### 9.2 Snapshot authority and strict harmless delta

Use/reuse one versioned promotion snapshot: exact S, source PR/head/merge SHA, work issue/contract generation, ordered V and migration digests, runtime/policy closure digest, immutable preview/review evidence identities, freeze SHA/generation and intended run attempt. Create an immutable **candidate descriptor before risk review** once exact source/main/runtime/baseline identity is established under the activation barrier. It permits only proven inert-prose admission, never production. After actual-main preview/risk proofs, append a separate immutable **approved attestation** referencing the candidate digest and complete artifacts/verdict. Dispatch/apply requires the approved attestation; candidate-only, cancelled or superseded review always refuses. Missing artifact/approval fields are legal only in the explicitly candidate state and never a production request. Missing fields, duplicate keys, unknown version/fields and reordered V refuse. Stage-one candidate requires one source PR, no train identity and no outstanding authorized/dispatched/failed train. A complete read of latest immutable train generations is mandatory; unknown/partial listings refuse. Train authorization/dispatch and candidate activation/admission must share existing coordination mutex so a train cannot authorize after an earlier absence check while prose admission remains active. Do not close or cancel another train to make a candidate eligible.

Extend the existing `evaluateProductionFreshness`/manifest-binding primitives in `scripts/target-queue-identity.mjs` with a strict, explicit candidate/attestation validation mode, with a minimal Python adapter only where necessary (canonical JSON bridge, no duplicated policy). Prove S is a real protected-main ancestor of fresh T; read exact complete git tree comparison, not filename metadata alone. Require ordinary prose classification from trusted base code, regular files and allowed modes, exclude executable instructions/runtime-consumed prose/global invalidators; disallow unproved renames/deletions/symlinks. Verify unchanged V and runtime closure. Explicitly reject migration/tests/evidence/code/config changes in the **new exception**, regardless of older independent allowances.

Preserve legacy exact-main behavior for old records; versioned opt-in only. Fresh issue/assignment/activation/ledger state is not a cached snapshot assertion.

Gate: `snapshot_docs_advance_preserves_exact_identity`, all hostile record/delta cases in §10; old exact equality tests unchanged where no new authority exists.

### 9.3 Admission and cleanup fencing

Integrate validator into `authorizeRepositoryMaintenanceStatus` while holding existing mutex; re-read live snapshot/ref and exact PR state before success. Code/migration acquisition retains current refusal. Queue group path must recheck snapshot generation, complete group tree and source PR authorization at final success; refuse multi-member/mixed groups under current single-PR contract. Snapshot activation must not assume old merge lanes disappear: drain/prove merge lane absent or prove harmless completed advance and revalidate.

Modify freeze schema/acquire/release to carry exact attempt/generation/ref authority. Ordinary release by textual owner or PR is not sufficient to release a replacement; producer records exact acquired SHA, cleanup passes expected SHA and attempt, release refuses mismatch under mutex. Upgrade all workflow cleanup callers together. Keep recovery evidence strict for unreadable legacy records; do not broaden any-positive-PR recovery. Repeated exact cleanup is no-op. Production ref ownership stays exact owner SHA; it never expires automatically.

Gate: race tests with actual synchronized fake refs or local Git atomic updates, covering an old same-PR cleanup against a newer generation, simultaneous acquisition, stale group success and TTL while apply is held.

### 9.4 Promotion caller integration

Include `scripts/dispatch-production-apply.mjs:119–122`, `.github/workflows/production-apply-review-evidence.yml:39–49`, and `.github/workflows/production-catalog-verification-recovery.yml:27–33` in the caller matrix. Also inventory `scripts/lib/lanes/cli-train.mjs:29–38,49–63` and `scripts/orchestrator-flow/migration-train.mjs:32,95–99`. Preserve their current-main equality for this first stage, and add the synchronized train/candidate admission exclusion from §9.2. Do not pass a train dispatch through the single-source snapshot route. Recovery callers are recovery routes, not new ordinary authorization: consume exact approved attestation under the same validator, preserve original failed-apply evidence and never rerun already-applied SQL. Snapshot recovery must remain possible after admitted prose movement; unknown/code movement still refuses. Replace preview/qualification/production-acquire **only under verified versioned snapshot authority** with common harmless-delta proof; retain exact checkout S, risk `mainSha=S` and artifact digests. Caller code must never silently update S to T. Update extracted policy and workflow check branches consistently. Qualification before dispatch and production acquisition after global mutex both require fresh protected-main tail proof; main movement races either validate harmless prose or refuse.

Keep production lock acquired before final apply freshness check. Keep full source merge blocking/status revocation while production held; cleanup restores only this run's revocations. Never change bounded checkout, target proof, dry-run/apply order, ledger/catalog checks or application acceptance. Inspect whether any producer proof incorrectly switches comparison target to T; preserve exact pinned closure against S and separately verify T contains no invalidator. Live cancellations/revocations must stop old snapshots; TTL is no review authority.

Gate: end-to-end offline workflow qualification fixture where docs land before qualification and before production acquisition, exact S is executed and ordered V is unchanged; code/policy movement refuses before dispatch/write; all legacy production evidence suites pass.

### 9.5 Adversarial verification and assigned review

Run §10 suites and race corpus. Review full changed diff, all callers, negative-case traces and immutable packet with allocator-assigned independent reviewer; start review concurrently with required CI after exact head push. Batch all review/CI fixes into one head, then re-review exact changed head. Do not name the implementer in this plan or choose provider outside rotation.

Gate: durable exact-head APPROVE for actual safeguard implementation, all required checks green and unchanged required-check set. A docs proposal's publication is not such approval.

### 9.6 Rollout, acceptance, rollback

Ship with opt-in/default-off versioned policy; retain old path. First shadow-only classify historical events and current changes without granting merge authority or touching production. Compare proposed versus old refusals, require zero false allows across adversarial corpus. Then enable ordinary-prose admission only through normal reviewed repository route. The assigned reviewer must approve exact activated configuration and runtime closure; task gates precede any production-affecting activation.

Use the next independently authorized real promotion as canary: allow one eligible prose merge during review, record S/T/V/closure/artifact identities, qualifier result, production ownership times, target proof, dry-run/apply evidence and original application acceptance. Do not launch a promotion solely as this tooling experiment. Keep `- [ ] live proof` and acceptance evidence on #4039 until measured behavior is established; source application's own issue also retains its acceptance requirement.

Rollback: stop new snapshot admissions/default off through a reviewed fix/revert; never cancel an active SQL apply or delete its lock to roll back tooling. Let owned run finish/reconcile, preserve snapshots/ref generation evidence, restore conservative merge authorization through existing gates. Do not roll back database ledger or edit applied migrations. Resume normal exact-main path only after old snapshot attempt is terminal and source refs reconciled.

Gate: one real approved promotion with eligible prose advancement passes complete original acceptance, no unauthorized merge or broader SQL allowance, measured separated timings recorded and independently assessed. No promise of elapsed-time reduction if mutex/CI dominate. Natural cut points are after §§9.2, 9.4, 9.5; re-read downstream phases and live source at each cut.

## 10. Tests and adversarial input matrix

Implement tests in the existing nearest suites and extend existing `scripts/target-queue-identity.test.mjs`; no duplicate snapshot module. Test names below describe required observable assertions, not just return values.

| External input / race | Hostile case | Named test and expected evidence |
|---|---|---|
| Snapshot JSON | Duplicate key, unknown schema/field, malformed SHA, changed digest/V order | `snapshot_record_rejects_ambiguous_identity`; no dispatch/write |
| Protected-main delta | Rewritten/non-ancestor history, unreadable/empty unexplained diff | `snapshot_tail_requires_readable_protected_ancestry` |
| Exact files/modes | Renamed instruction, Markdown symlink, executable mode, runtime-consumed prose | `snapshot_prose_cannot_hide_runtime_change` |
| Train authority | Existing authorized/dispatched/failed train; authorization races candidate activation | `stage_one_train_authority_retains_global_freeze` and `train_candidate_activation_has_one_winner`; no stranded approved train |
| Train recovery | Retry after partial apply or stale snapshot | `train_partial_apply_recovery_stays_legacy_and_no_prose_exception`; applied prefix never replays |
| Candidate lifecycle | Before risk approval, missing final evidence | `candidate_docs_only_never_dispatches_or_writes`; final attestation required |
| Recovery callers | Docs advance after partial apply or before immutable recovery evidence | `snapshot_recovery_accepts_prose_but_preserves_original_attempt`; no replay |
| Pure docs | Regular inert prose advances T during review | `snapshot_docs_advance_preserves_exact_identity`; S/V/A unchanged |
| Migration/code tail | Apparently disjoint additive CREATE in another schema | `stage_one_disjoint_sql_still_refuses`; no approval implied |
| SQL dependencies | Shared role/grant/function, cross-schema FK, trigger, DO/dynamic SQL | `unknown_and_shared_dependencies_refuse`; no SQL parser certification |
| Version inventory | Earlier/later version, duplicate, edited applied, ledger hole | `snapshot_tail_cannot_change_migration_inventory`; preserve legacy guard refusals |
| Live database | Extra applied version absent from S or partial A/B batch | `snapshot_live_ledger_reconciliation_refuses_stale_baseline`; applied A never reruns |
| Artifact/run | Expired/cancelled/wrong producer, another run attempt or source issue | `snapshot_rechecks_live_provenance_and_authority` |
| Policy/runtime closure | Mid-review promotion workflow/config/sidecar/security revocation change | `snapshot_global_invalidator_stops_old_runtime` |
| Final admission | Main/group/head changes after earlier authorization | `queue_final_snapshot_generation_race`; success only for exact validated group |
| Activation | Merge lane already held when snapshot begins | `snapshot_activation_drains_or_revalidates_prior_merge` |
| Concurrent acquire | Two sessions | `snapshot_create_only_has_one_winner` |
| Cleanup | Old attempt same PR deletes newer generation | `cleanup_old_attempt_cannot_release_new_same_pr_freeze` |
| Retry cleanup | Already absent expected generation | `cleanup_repeated_exact_attempt_is_idempotent` |
| TTL | Expiry mid-review vs mid-apply | `expiry_does_not_authorize_stale_snapshot_or_release_production` |
| Batch queue | Mixed safe/unsafe members | `queue_multi_member_snapshot_refuses` |

Run existing `node --test scripts/target-queue-identity.test.mjs scripts/dispatch-production-apply.test.mjs scripts/orchestrator-flow/migration-train.test.mjs scripts/manage-migration-author-lanes.test.mjs scripts/check-main-tip-freshness.test.mjs scripts/merge-queue-contract.test.mjs scripts/check-merge-queue-workflows.test.mjs scripts/lib/documents-only-change.test.mjs scripts/lib/lanes/exclusive-policy.test.mjs`; discover any actual renamed files before execution. Run Python suites `scripts/test_production_business_risk_gate.py`, `scripts/test_production_apply_review_evidence.py`, migration guard and derivation suites using repository documented Python context. Run `bash scripts/check-sql.sh`, all required workflow checks and promotion-sidecar closure guard. For concurrency, control barriers around observed ref SHA/final authorization, and assert loser leaves winner's ref intact.

A later SQL extension must add a positive `disjoint_additive_tail_merge_preserves_order_and_live_baseline` test with independent dependency proof; it is **not stage-one done criteria** and remains a refusal here.

## 11. Constraints and traps

One parent issue for this application/tooling need, no leftover-proof ticket. No structural object claims for tooling. Use installed task gates and `ai-gh`; exact-head review, queue and normal branch protections remain. Current main might advance between every read; verification at prior head expires. Preserve production environment binding, workflow concurrency, complete target proof, immutable provenance, live acceptance and collision coverage. Human times are America/New_York with EDT/EST labels. Signature on all GitHub posts: `Posted by Codex chat <actual id> on <machine>`.

Report limitations honestly: docs-only validation is not independent design review; a passing scanner is not SQL safety; merged/deployed/catalog-proved/application-accepted are distinct; deleting a lock is not a repair. Do not install tooling or access 1Password during reviews. No secrets in artifacts/arguments/logs.

## 12. Access and evidence

Installed `ai-task-gates`, `ai-gh`, Node and Python3 were available; GitHub authenticated read and issue creation worked. `python` was absent; use supported `python3`, do not replace OS binaries. No database credentials were needed or read. If future authorized acceptance requires credentials, load existing secrets skill and supported provider procedure; vault `vibe_coding`, locate documented item title from current runbook, never embed values or invent titles.

Private raw captures from investigation are under `/tmp/narrow-freeze-evidence/`; ephemeral only, not future-session authority. Durable baseline, observed run IDs/status provenance and sanitized summaries are in the report. Re-fetch current owners/refs rather than relying on those captures. The exact-source independent verdict and durable provenance are retained in report §9.

## 13. Definition of done, risks and open ownership

Investigation done requires report, sequenced proposal, durable publication and allocator-assigned independent design verdict or an explicit capability blocker; an unreviewed report cannot satisfy the requested approved recommendation. Implementation done requires separately authorized scope, exact-head assigned review, tests/CI, normal commit/push/PR/merge, activated-code identity, real prose-during-review canary, complete production/application acceptance and measured cleanup. Update this STATUS as each phase changes; mark code-landed/live-unaccepted distinctly and keep same-issue checklist unticked. Retire linked handoff only when its work is truly complete.

Risks: wrongly inert classification, stale live safety policy, existing group crossing activation, same-PR cleanup replacement, ledger drift and shared-preview contamination. Each risk has a named negative test and rollout refusal. Until these and assigned review pass, default remains conservative global freeze. No human decision is needed. Codex investigation workstream owns publication; future authorized implementation workstream owns all open phase gates and must register itself on #4039 before work.

## Self-audit

1. Can a newcomer execute without chat? **Yes for the authorized next step and, after approval/authorization, the scoped implementation.** §§1–5 define purpose, system, scope and exact source; §§9–12 specify ordered changes, verification, access and traps. The supported maintenance assignment route has been verified; design review is complete; implementation exact-head review remains a separate stop condition.
2. Does it preserve background/rejections? **Yes:** §§3,6–8 and linked report preserve exact-main contradictions, claim limitations, historical timings, rejected table-only approach and same-PR cleanup race; §§10–13 retain uncertainty and rollback.
3. Is the ultimate goal decisive? **Yes:** §1 states business outcome and goal-wins instruction; locked §§4,8 forbid SQL expansion and weaker acceptance even if faster. All 13 required sections, named adversarial tests, status/evidence, scope, definitions, secrets boundary and bidirectional handoff are present. Supplemental REJECT findings on d853e087 were addressed by existing primitive/ownership reuse, full recovery callers, pre-review candidate lifecycle literal operating-router registration and train/candidate exclusion; allocator sequence 5638 approved the corrected design at 610e80cd. No implementation approval is claimed.
