# IMPLEMENTATION PLAN — review recovery (#4297, October 14, 2026 EDT)

## 1. Ultimate goal
Failed review services must not prevent healthy independent reviewers from reviewing unchanged work. Spending stays bounded and rejected work still needs repair. If any step conflicts with this goal, the goal wins — stop and flag it.

## 2. Application
Canonical popcre/shared-db tooling coordinates shared schema review. This is zero-database repository maintenance in a dedicated current-upstream worktree. Node.js modules, GitHub immutable refs, allocator mutex and guarded merge are existing capabilities.

## 3. Trigger
PR4206 head aa9c8a3d8d9066e93ed9c1b6185f56c18bbd9fea refuses after two counted paid starts; slot2 cannot draw without slot1. Owner authorizes implementing sensible recovery and explicitly requests parallel agents. Do not mutate that PR or its structural claims.

## 4. Scope
Budget accounting, out-of-order assignments, automatic verified terminal releases, policy documentation, adversarial tests. NOT migrations, production/database writes, historical proof fabrication, reviewer roster changes, removing gates, paid automatic retry loops or changes to another session's PR4294.

## 5. Current state
Base 9595a63fcc0c, branch codex/review-recovery-4297. Contract published refs/db-contracts/4297/1 before implementation. Circuit breaker refunds only two verified failures globally. Peer resolver demands slot1. Runner records starts and reports terminal reroute but leaves release to caller. PR4294 independently changes owner-quoted slot2 allowlist widening; preserve its separate ownership.

## 6. Findings
scripts/lib/lanes/review-circuit-breaker.mjs assertPaidReviewCapacity: two conservative starts plus global two refunds. scripts/lib/lanes/review-assignment.mjs resolvePeerSlots: mandatory slot1 and all peer discovery. scripts/manage-migration-author-lanes.mjs assignment/replacement: inherit only slotOne, candidates selected under mutex with engine exclusions. scripts/run-governed-review.mjs runGovernedReview: terminal_non_verdict lifecycle event without automatic durable release.

## 7. Rejected approaches
No unlimited retries, deleting history, dummy source edits, refunding REJECT/REVISE, freeing unknown starts, reducing review count or bypassing current gate to land its own replacement. A larger global failure cap just recreates the same dead end. Do not import PR4294 without exact comparison and review.

## 8. Locked decisions
A. Keep two conservative review-round starts per unchanged content/slot. Starts with no verified verdict-less infrastructure proof consume that allowance. Four recognized failure codes stay unchanged.
B. Every exact-bound verified infrastructure failure is accounted separately, regardless of total. At TWO such failures for a reviewer on unchanged content/slot, exclude that reviewer from NEW draws. Other healthy eligible reviewers retain capacity. Finite registered roster bounds new starts by 2 plus 2 per reviewer. No clock/head refresh reset. Supported provider-recovery extension is outside this change; all exhausted providers yield a precise blocked state, never pointless source-edit advice.
C. Either slot may be first. Resolve every peer and keep under-mutex revalidation. Earliest assigned live peer sequence anchors initial task allowlist. Same-slot durable assignment/replacement policy remains authoritative; conflicting requested allowlists refuse. Preserve existing widening restrictions, final exact-head review count and independence.
D. Runner auto-releases only a paid-started recognized terminal failure with no parseable verdict anywhere in stdout/stderr, using existing releaseFailedReviewer with exact held sequence, slot, reviewer, issue and head, confirmNoVerdict/confirmNoArtifact and existing CAS checks. No paid retry is launched. Release failure is reported with original error and preserved diagnostics, never treated as successful recovery. Unknown or malformed output remains conservatively counted.
E. Coordinator owns all policy, security, integration, commits, review and merge decisions. Workers implement mechanical edits only within assigned files.

## 9. Steps and gates
1. Budget module: replace global refund ceiling with separate exact-bound failure totals per reviewer; return failedReviewers/exhaustedReviewers and reinstated count plus existing paidAttempts/remaining. Preserve every provenance and scope validation; filter issue as well as PR/slot. Tests cover >2 failures across different reviewers,2 failures one reviewer exhausted,unknown starts exhausted,substantive change distinction,head refresh no reset,tampering. Gate node --test scripts/lib/lanes/review-circuit-breaker.test.mjs.
2. Peer resolver: remove mandatory slot1, return policyPeer from earliest live assigned peer including slot1; retain all peer discovery, returns filtering, malformed-history refusal and wire-read budget. Coordinator edits assignment/replacement callers and tests to inherit policyPeer while own policy dominates; candidate filtering incorporates exhaustedReviewers from step1 in EVERY ordinary/replacement/fallback/reuse branch. Gate node --test scripts/manage-migration-author-lanes.test.mjs.
3. Runner: add guarded automatic terminal release seam to injected deps and production deps; preserve exact sequence from held assignment/start evidence, not caller guess. Gate node --test scripts/run-governed-review.test.mjs. Workers must flag any missing bound sequence seam before editing wider modules.
4. Documentation and integration: record finite budgets, service recovery vs substantive rejection, independent assignment, all-pool exhaustion and historical proof limits. Run all three gates centrally and applicable full offline checks. Compare High and Extra High through actual findings, errors and coordinator corrections, explicitly no controlled performance claim.
5. Commit implementation then completion evidence alone; push, open PR, draw independent code reviewer under existing rules while CI runs, batch corrections. Guarded merge only after required approval/checks. Merged-source runtime verification must exercise actual supported tooling without DB write or paid loop. Leave original licensing PR status unchanged unless separately authorized proof succeeds.

### Adversarial cases
| Input | Hostile case | Required test |
| failure ref | wrong issue/PR/head/slot/sequence/reviewer | exact-binding refund refusal |
| failure record | verdict exists or unsupported code | no refund or automatic release |
| historical starts | main refresh,empty commit,revert | capacity cannot reset |
| historical starts | repeated failures one reviewer | exhausted reviewer never selected |
| assignment peers | slot2 then slot1 and 3 then2 | distinct providers all orders |
| task allowlist | different first-peer policy | refuse mismatch both orders |
| failure release | moved head,concurrent verdict,stolen lease | existing CAS refuses and diagnostic retained |
| runner output | quoted/stray REJECT/REVISE/APPROVE | no automated verdict-less claim |
| failure accounting | unknown running starts | count conservatively |

## 10. Tests
All three commands above. Preserve current circuit-breaker Git provenance tests, request-cost tests, independent final approval tests, engine exclusion tests, release/CAS tests and runner source receipts. Add behavior assertions, not implementation-mirroring assertions. No paid provider calls from test fixtures.

## 11. Constraints
Dedicated worktree only; no structural claim; declared reviewer-safety class and action gates. Publish immutable scope before edits. Centralize shared manager edits. Do not alter current PR4294 or its files in another checkout. No secrets or reviewer credentials during formal review. Sign GitHub posts.

## 12. Access
Authenticated gh read/write exists. Supported installed ai-task-gates. Node tests local. No secret needed for code/tests; official reviewer wrapper preflight determines runtime availability. Long output goes to session TMPDIR.

## 13. Definition of done and risks
Published contract, bounded implementation, adversarial checks passing, exact-head independent APPROVE, required CI passing, guarded merge, merged-source runtime proof, documented limits and evidence-based model comparison. Unknown historical starts may remain blocked; never invent terminal evidence. Risk: independent draws could inherit inconsistent policy; adversarial tests and mutex revalidation must prove safe. Rollback is reviewed revert preserving immutable records. No HANDOFF needed while work remains active; if externally blocked, preserve on issue4297 and write required handoff. No business questions remain.
