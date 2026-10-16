# Shared release holds — substantive Muse design debate

Scope: proposal/design only. No runtime safeguard changes or database actions.
Parent [implementation plan](../../plan_shared_release_hold_reduction.md), tracker
[#3779](https://github.com/popcre/shared-db/issues/3779); narrower-freeze integration
uses the existing [#4039 design](../../plan_narrow_promotion_freezes.md).
All four implementation outcomes and every STATUS implementation row remain open.

## October 16, 2026 EDT — first substantive critique

Muse reviewed published main `6669538515a8a5813887e9fa98eb422682f9ca4b` in persistent
session `shared-release-holds-plan-critique` (Muse Spark 1.3 Contributor).
The native completed report found six design blockers, ten meaningful improvements
and five polish findings. This was a design critique, not merely publication safety.
Earlier safe-to-publish approvals did not establish implementation feasibility.
Raw prompts/transcripts/provider reports remain private; the source-only dispositions
below carry everything a new implementing session needs.

| Finding | Accepted correction / explicit disagreement | Revised plan location |
|---|---|---|
| B1 overlapping reviewed design | Adopt #4039 strict mode and full caller matrix; no duplicate classifier. `.txt`, evidence, tests and instructions deny by default. | §4, step6 |
| B2 undefined quarantine | Quarantine is the existing exact lease retained after ambiguous write, not a new service; named catalog/preview recovery ceremony. | §8.1 B–C |
| B3 unchosen admission architecture | Revoke all, then strict fresh re-admission during EARLY freeze only. **Keep production-held blockade** as #4039 requires; do not silently broaden its prior review into a during-apply exception. | step6 |
| B4 infeasible assumed fence | 8a independently buildable identity/release fixes; 8b isolated writer/pooler/unlock/termination experiment; 8c takeover only after GO. No claim that an opaque CLI can share a coordinator connection. | step8 |
| B5 release race / missing assertions | All five release paths use the shared mutex and bound identity; acquisition outputs passed to every actual mutating path. Old/new CLI compatibility and activation drain specified. | step8a, §8.1 F |
| B6 no durable receipt contract | Choose existing Git coordination transport with immutable prepared/write-intent/terminal/report-complete receipts; strict schema/provenance, bounded retries, failure and absent-receipt reconstruction. **Do not claim full reconstruction if preimage/provenance remains unknowable.** | §8.1 A–C |
| M1 producer closure/staged modules | Reuse risk producer/runtime closure, target manifest helpers and reconcile #3781/staged exclusive-policy. | step6 |
| M2 conflicting inert classifiers | One strict `promotionProseTail` predicate; ordinary CI/document classifiers retain only their original roles. | step6 |
| M3 admitted but no jobs | Exact group/run-start observation, bounded alert, one owner-qualified normal requeue and verification; no overrides or credential expansion. | §8.1 E, step9 |
| M4 mixed versions | Compatible readers/release adapter first; all callers next; no old active writer before enabling recovery/strict routes. | §8.1 F, step8a |
| M5 checkout drift/starvation | Refuse before write, owner-qualified release; at most one fresh redispatch, second drift stops and records competing source. | §8.1 D |
| M6 nonexistent merge prep | Name actual checkout/setup/preflights/quota work; no fictional long-test or packet stage, no transferable prep authority. Step3 independent of receipt schema. | step3 |
| M7 stall signal/host | Existing read-only queue-hygiene collector/schedule, run/job/attempt + acquisition/step timing; formatter/router roles corrected. | step7 |
| M8 rollback | Disable optional routes, reconcile active work, drain/revalidate groups, consumers before schemas; retain safety fixes and immutable evidence. | §8.1 F |
| M9 trains omitted | Complete caller matrix plus two-sided train/candidate exclusion and complete backend histories; no concurrent SQL. | step6 |
| M10 cancellation outcomes | Explicit state→release/retain/obligation table, including lost receipt, successor ownership, reporting/restoration errors. | §8.1 C |
| P1 reviewer waiting already pre-lock | Treat approval evidence re-verification as live checks; no invented reviewer wait stage. | step4 / actual step inventory |
| P2 freeze timing | Freeze checked on acquisition; production interlock preserves critical protection. | step6 / baseline |
| P3 duplicate module | No `release-independence.mjs`; reuse strict freshness module per #4039. | step6 |
| P4 release time source | Use actual Actions step/acquire/release timing, not an assumed durable ref-delete timestamp. | step1 |
| P5 tool version | Record the installed psql version in preparation as tool identity; no unexpected install under hold. | step4 |

## Debate positions sent for follow-up

1. Re-admission must not override the production-held blockade. #4039's prior
review explicitly keeps it. The useful narrower scope is inert prose during the
long early qualification freeze; actual database critical work remains serialized.
2. Minimal immutable operation receipts are justified for crash reconstruction
and early release; they do not introduce a second promotion approval/snapshot
service. They are not self-authenticating authority: validate trusted producer,
identity, current revocations and necessary live state. Cannot recover from an
unknown preimage by declaration.
3. Identity assertions and mutex-safe cleanup are valuable independently; they
cannot be advertised as fencing in-flight SQL. The experiment must qualify all
writer connections before takeover automation. If it cannot, mark that outcome
open instead of changing engines or granting new production access implicitly.
4. The admission incident establishes a liveness signature, not a definitive
provider-token root cause. One ordinary exact-head, approved requeue is the
bounded operational repair; permanent identity changes need their own reviewed
configuration inputs, not a guessed new credential.

Follow-up debate outcome is not yet recorded. The next entry must report Muse's
actual response, disagreement/concession and exact revised source identity; no
approval is implied by this draft ledger.

Posted by Codex chat 01a144d8-b318-7ed0-af97-e852be49d231 on hetz
