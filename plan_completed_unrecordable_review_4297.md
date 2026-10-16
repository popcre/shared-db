# Owned completed-but-unrecordable review disposition — consumer design

## STATUS

IMPLEMENTATION AUTHORIZED after independent consumer-source-visible design APPROVE and coordinator GO. Actual reviewer allocation/start records and lease/disposition mutation remain NOT authorized. Implementer/dispatcher: Codex editor child chat 01a1424a-54cc-7302-8b0a-fdefa44ff789 on edge-dev3, acting for coordinator chat 01a14247-5120-71f0-a78d-b9d477b46304; original6603 owner remains that coordinator, never this child; branch `codex/4297-completed-unrecordable`, original current upstream `e241459ab805a1219b76534d425741e1f87fa44c`. Existing issue [#4297](https://github.com/popcre/shared-db/issues/4297), signed bounded successor note [6208906328](https://github.com/popcre/shared-db/issues/4297#issuecomment-6208906328).

OWN prospective contract was published BEFORE any consumer implementation: `refs/db-contracts/4297/33`, commit `dbe98e3fc930f082fac035836ca3884dbc3148e1`, canonical SHA256 `a1eafd58debde0dab92a8e48094d826652fc15937bcc494a3fff3d08adc6e1b0`. Generation32 is immutable historical lineage only, not adopted ownership/scope/completion. No old contract is rewritten. This design review is a non-authorizing standalone plan opinion; it does not allocate a shared-db code-review slot, create a review-start ref, dispose a lease, record a durable code verdict or replay a provider attempt. Those governed actions remain held. Independent consumer-source-visible design APPROVE and separate coordinator implementation GO are mandatory.

## 1. Ultimate goal

Preserve the real result and cost of a completed review which could not be recorded, safely end its exact owned assignment without pretending it failed or approved delivery, and permit one genuinely new normal review only when existing rules permit it. If a step conflicts with this goal, the goal wins — stop and flag it. This bounded repair does not close the wider4297 programme.

## 2. Application and route

Canonical `popcre/shared-db` supplies reviewer allocation, immutable prework/start/verdict history and guarded delivery for shared schema and maintenance work. This task is ZERO-DATABASE `repo-maintenance`/`reviewer-tooling`, not a structural author claim. Follow current `AGENTS.md`, `docs/agents/current-workflow.md`, `docs/agents/agent-work-contract-repo-maintenance-evidence.md`, normal guarded code PRs and native reviews. Do not run a migration, production operation or secret call.

## 3. Trigger and exact case

Coordinator case: issue4385/PR4387, OLD source head `901ee416b7557b205dc728e7c6ac199a70b8996c`, slot1, sequence6603, reviewer Muse Spark1.3 Contributor. Native final-check completed APPROVE, retained report/packet/lifecycle/spent start exist under coordinator custody, but the reserved original-source receipt `governed-source-44d122ce-bef5-46b9-b2ae-9459adb88e79.json` was absent and the governed runner refused recording. This plan has NOT inspected private completion proof or established qualification/remaining budget.

Existing same incident PR4346/sequence6598 belongs to Codex chat01a1425d-a395-77f2-812e-bbb8ff1facdc on hetz; last public incident note October15 at10:38 PM EDT. Its source/lease/receipt/reports remain untouched. Existing broader4297 owners retain their work. No approval import, fabricated receipt, no-verdict assertion, refund or replay is allowed.

## 4. Scope and collision boundary

IN: one explicit native non-authorizing disposition path, strict original prepublished dispatcher/native declared-session ownership, exact protected proof/source/lease matching, immutable public digests and atomic owned lease release, old-assignment admission/carry refusal, conserved paid starts and meaningful offline races/accounting tests.

OUT: new same-head successor assignment namespace, old assignment/start deletion, global claim authority grammar change, aliases/substring owners, cryptographic human authentication claims, retrospective verdict/receipt, failure/refund/reinstatement/provider pause, roster/round/capacity changes, synthetic source edits, private evidence disclosure, code before GO, foreign6598 and whole-programme closure.

Fresh open collision: PR4370 head `0c2f0726e3b959eb1dff055695ef7f16e84a5010`, branch `codex/4297-admission-comment-pages`, owns outcome-comment pagination in `scripts/manage-migration-author-lanes.mjs` and its test, generation28. Broader owner activity is not inferred from an open PR. Do not edit these shared files until coordinator reconciles source integration/functions; refresh open paths/current main before implementation. This prework writes only own contract, plan and handoff.

## 5. Current code (baseline e241459ab)

- `scripts/agent-work-contract.mjs`: `publishContract()` creates immutable ref then readback; header explicitly limits authority to ordering/non-overwrite, NOT cryptographic identity or proof of private work start. `validateContract()`/lineage reject malformed predecessor/unknown fields. `agent-work-contract-git-evidence.mjs` provides existing publication/source evidence checks; reuse its actual contract-pair binding rather than new owner prose.
- `scripts/lib/session-authority.mjs`: `resolveSessionAuthority()` uses exact DECLARED `SHARED_DB_SESSION_ID`. Existing claim owner label grammar accepts `Codex chat…`/adoption labels, not `Codex coordinator chat…`. It must stay unchanged.
- `scripts/run-governed-review.mjs`: `reserveReviewReceipt()` and `validateSourceReceipt()` bind original physical source/head/base/digest; `recordReviewStart()` at917–939 records exact tuple, sequence and optional receipt-PATH SHA/source digest BEFORE spawn. Start contains no unique chat authentication. Governed native dispatch/receipt acceptance occurs around637–730. No receipt means no durable verdict, correctly.
- `scripts/manage-migration-author-lanes.mjs`: `reviewLeaseStillHeld()`1973 reads exact live assignment/sequence; `assignNextReviewerOperation()` same-head prior assignment branch2164–2200 can REACQUIRE the old lease. Just deleting lease would replay the old paid attempt. `atomicReviewRefs()`636 uses atomic push with expected old SHA for every ref; reuse under existing mutex/request budget, no unchecked deletes/fallback.
- `scripts/lib/lanes/review-assignment.mjs`: `findCarriedSlotOne()` can carry equivalent old assignment to a new head; terminal dispositions must not resurrect as live/approved. `resolvePeerSlots()` uses this policy.
- `scripts/lib/lanes/review-replacement.mjs`: failure release requires no-verdict/no-artifact; this completed case MUST NOT enter it. Do not change `TERMINAL_FAILURE_CODES` or `REINSTATABLE_FAILURE_CODES`.
- `scripts/lib/lanes/review-circuit-breaker.mjs`: `paidStart()` reads immutable starts. `assertPaidReviewCapacity()`541–628 charges same/unchanged starts; count>=2 refuses third. Unknown and any decision stay charged; only exact verdictless infrastructure failure can reinstate. Its runtime algorithm need not change.
- Actual production protocol uses `concurrentLeases=Boolean(io.requiresExactReviewHeadSha)` and `notTaken` around2250–2285; provider busyness is NOT a draw limit for exact full-head requests. Therefore old6603 does not itself establish a cross-PR Muse capacity block. Do not fabricate such a blocker; preserve current exact parallel-lease semantics and independent formal allocation. Separate mutex/read failures still refuse normally.

## 6. Root cause and known limits

Toolkit registered Muse path already receives ORIGINAL repository; its core final packet preparation intentionally withholds receipt, Muse consumes that packet directly, but final qualified core receipt publication was missing. Toolkit prospective repair is separate ai-devops work, now source5f9a085d (not claimed merged/installed here). Consumer correctly refuses absent final receipt. Consumer lacks a truthful completed-unrecordable disposition; existing failure/reclaim paths contradict the real completed decision.

Source/contract readback here is not evidence that private6603 proof qualifies. Original contract/session identity is the native self-declared trust model, not an external credential. Public commit/ref immutability does not cryptographically authenticate a chat or establish when private work began. Missing native binding/ordering proof is a refusal, never a new invented historical field.

## 7. Rejected approaches

Do not manufacture past receipts or register old APPROVE; reclassify completion as no-verdict/service failure/refund; release unrelated lease; change roster/caps; broaden claim aliases; infer owner from common Git credentials; create a fresh same-head namespace or overwrite assignment refs; invent a source commit to get another round; hide old starts with new generation/base. Do not run unreviewed consumer code to release the lease needed for its own review. Preserve negative REJECT facts.

## 8. Locked design

### 8.1 Inputs and native ownership

New CLI operation in existing lane entrypoint: `--dispose-completed-unrecordable-review`, DEFAULT READ-ONLY DRY RUN. Execution requires existing explicit `--apply-recovery`, valid only with this mode and full requalification. Exact tuple flags are issue, PR, full head, review-slot, sequence and reviewer. One `--completed-unrecordable-evidence-file` names a bounded protected JSON descriptor of ORIGINAL artifacts; not raw evidence in arguments. All other mode combinations/unknown flags refuse. No new permanent service/tool or runtime bypass env.

Descriptor is untrusted routing only, never authority: schema_version1 and exact allowed keys for original contract ref, source root, reserved receipt path, lifecycle/report/packet/native completion references. Values are privately resolved against original native identities and exact public refs. Unknown/duplicate keys, ambiguity, path escape, linked/unowned/unbounded inputs or custody outside approved private route refuse. Reuse existing custody/size rules without narrowing supported native artifact formats or rewriting/chmodding old evidence to make it fit. No arbitrary host search, decrypt route, provider credential access or billing query.

For6603 the ORIGINAL public contract is `refs/db-contracts/4385/1`, SHA `570ddbf67c16c06f66b670123e0e9d3401db2dbc`, canonical contract SHA256 `4053d3db32c69696cbd5fdeefccb4857172a07b2daaf7f6fd7997338be27e8ba`. Existing dispatcher exactly `Codex coordinator chat 01a14247-5120-71f0-a78d-b9d477b46304 on edge-dev3`, original physical worktree `/home/ahazan/.codex/worktrees/stage-preview-ledger-rename`. This session independently verified ref/hash; private proof remains unverified.

DISPOSITION-ONLY parser requires the WHOLE dispatcher string: `^Codex coordinator chat ([0-9a-f]{8}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{4}-[0-9a-f]{12}) on ([A-Za-z0-9][A-Za-z0-9._-]{0,119})$`. No trimming, fallback labels, aliases, substring extraction, alternate case, trailing newline/whitespace or multiple owners. Require current actual `SHARED_DB_SESSION_ID` equals that UUID and passes existing `resolveSessionAuthority()` with the validated UUID as exact owner value; leave helper/claim grammar UNCHANGED. If `CODEX_THREAD_ID` exists it must agree. Compare machine to native hostname, no override; compare original physical source root to contract and source identity, no alias. Emit `human_identity_authenticated:false` and declared session, never a cryptoauth claim.

Validate original immutable publication/source evidence through existing contract helpers: correct repo/ref/commit/canonical hash, native prepublication evidence before implementation AND original paid start, exact original PR/completion/contract lineage, branch/root/base/head/digest. A new contract/dispatcher/comment, common author, current path or matching supplied hash cannot replace it. Missing proof/unknown format/mismatch REFUSES `ownership-unproven`.

### 8.2 Original completion qualification

Read exact original immutable assignment/start and current lease tuple/provider/sequence/ref SHA; do not trust supplied pointers without deriving canonical refs. Read protected original native lifecycle/report/final packet and their existing hashes/custody, terminal complete state, actual full-head verdict, implementer independence, original physical source comparison/digest. The generic caller label (e.g. old pool default zcode) is not unique owner identity; do not invent one from it. Retained packet has a NEW custody seal and ORIGINAL consumed seal at marker line4; validate existing chain correctly. Require original report and stored packet match original native terminal references, not reconstructed JSON or a provider session ID alone. Use existing qualified completion evidence; do not invent a raw stream artifact absent from successful native retention. Missing required original terminal proof refuses rather than replaying.

Bind reserved receipt PATH hash to original start marker and original source ignored untracked reports directory. Require genuinely absent destination; wrong/conflicting/linked/late receipt refuses. Reprove unchanged OLD901 source immediately before action. Start marker itself is consumed paid-start evidence; no external billing/service call or refund inference. Exact private proof must be qualified by the actual tool; this plan is not execution approval.

### 8.3 Durable disposition and race safety

New distinct immutable namespace `refs/db-review-dispositions/<issue>-<pr>-<fullhead>-slot<slot>-seq<sequence>`, schema1 record, kind `completed-unrecordable-missing-source-receipt`. Record exact tuple, observed ACTUAL verdict, `authorizing:false`, `paid_attempt_consumed:true`, `human_identity_authenticated:false`, declared owner/machine, original contract/assignment/start/lease immutable refs+SHAs, source identity and proof digests. Public record has no raw provider body/prompt/private file paths/credentials. This is NOT verdict/failure/replacement/refund namespace.

Dry-run validates read-only and returns sanitized qualification/block reason. Execution repeats proofs fresh, under existing review mutex/request budget; batch read refs/commits where supported. REQUIRE existing `atomicReviewRefs` capability; no sequential write/delete fallback. Atomically assert still-owned mutex, create absent exact disposition and delete ONLY exact expected still-held lease. Preserve assignment/start refs and current cursor/spend. Read back all changed refs; if response uncertain, inspect exact immutable record/refs, never repeat allocation/provider call. If matching disposition already exists and exact old lease absent, return idempotent NON-AUTHORIZING result. If a new/foreign lease occupies the old location, do not remove it or claim new action. Atomic crash/race tests must cover before push, uncertain successful push, changed owner, receipt/source race and retry. No manual rollback or ref overwrite.

### 8.4 Admission, carry and accounting

Guard `assignNextReviewerOperation()` prior assignment/replacement/cursor adoption paths BEFORE reacquiring/returning disposed exact assignment. Guard governed `recordReviewStart()`/recording entry so no stale caller/continuation can replay or record old6603. `findCarriedSlotOne()` and peer policy must not resurrect a disposed latest assignment or fall back to an older assignment for that disposed head; preserve unrelated genuine other-slot verdicts and existing exact/carry rules. Add bounded exact disposition reads to relevant fresh batched inventory; malformed/unreadable/ambiguous records refuse, never mean absent. Keep historical original assignment/start refs readable as history, not live/approved state.

Do NOT change paid-start runtime counting. Disposition never creates a recognized failure/refund/ref reinstatement. Qualify/dry-run/dispose OLD901 BEFORE any branch refresh. Toolkit receipt fix must first be reviewed, genuinely merged and protected-installed; then this consumer repair must be independently reviewed/merged through normal gates. Only afterward may coordinator normally integrate ACTUAL fresh main into4387, preserving all owned changes and prospectively publishing its own real evidence generation/new source head. No synthetic commit/base/task reset.

Existing normal allocator may then draw ONE new sequence only if `assertPaidReviewCapacity()` still charges6603 and reports room under unchanged two-start allowance/slot/cost/rotation/independence. With two charged starts, third refuses even after genuine main integration/new contract generation. Real code/source projection tests must prove conservation, not mock remaining=1. No automatic allocation/provider launch in disposition mode. An observed REJECT remains negative and cannot gain fresh approval through toolkit repair, main refresh or generation change without genuinely correcting the rejected code; missing supported correction proof conservatively blocks.

## 9. Implementation steps (ALL HELD until separate GO)

1. Refresh current main/open PR4370/function overlap and original4297 owners; coordinator resolves integration. Own immutable33 prework already published. If scope needs another file, publish a new honest successor BEFORE touching it. Gate: exact source/collision ledger and valid native contract; no foreign edit.
2. Add `scripts/lib/lanes/review-completed-unrecordable.mjs`/matching test: strict untrusted descriptor and original dispatcher/contract proof, original native completion chain, exact disposition parser/ref, read-only qualification and atomic execution. Export pure validation plus I/O-bound orchestration following existing lane pattern; no duplicate source/contract/lease engine. Add ONLY new disposition constant in constants module. Gate: actual native validator and all adversarial tests below.
3. Wire one mutually-exclusive mode/descriptor flag in `scripts/manage-migration-author-lanes.mjs`, existing `--apply-recovery` explicit execute guard, mutex/budget/atomic I/O; expose needed bindings via existing pattern. Keep failure release, replacement and budget algorithm unchanged. Gate: dry-run performs ZERO mutating I/O/provider calls; exact atomic expected-ref transition and uncertain-result recovery.
4. Wire terminal guard into existing assignment/cursor return and carry/admission readers and `scripts/run-governed-review.mjs` before paid start/record. Preserve normal unrelated assignment behavior/parallel leases. Gate: old tuple cannot reacquire/continue/record, disposed head cannot carry, other slot unchanged, new true head uses ordinary allocator namespace.
5. Add real Git/source-projection accounting fixture: old started source; genuine upstream consumer repair merge; current source integration/new v2 evidence; old6603 remains one charged attempt; ordinary new draw/start consumes second; another refuses. Include two already charged, malformed lineage, old REJECT/no actual correction and uncertain proof conservative cases. No new runtime counter switch or force/cap reset. Gate: actual `assertPaidReviewCapacity` and normal allocator tests.
6. Run all named suites/required truthful code checks. Commit implementation then evidence-only completion per native contract gate. Normal PR/formal allocator-assigned exact-head review plus requested Muse code review, CI/guarded merge. Existing exact full-head concurrency means no invented cross-PR Muse busyness blocker; all real policy refusals remain binding. NO actual6603 operation under implementation authority. Gate: actual code approval/merged-source proof, not design opinion.
7. Coordinator owns protected toolkit installation acceptance, exact merged consumer source qualification, private original6603 dry-run/action, later actual main integration/evidence/new draw. Missing proof/ownership/capacity records BLOCKED on same4297, not new ticket. Gate: old result retained non-authorizing/consumed; one genuinely new native original-source receipt/durable verdict within existing rules; wider4297 not closed.

## 10. Tests and adversarial matrix

| Boundary | Hostile case | Named test |
|---|---|---|
| Descriptor | Duplicate/unknown keys, ambiguous paths, linked/unowned/outside/oversized proof | `disposition_descriptor_requires_existing_private_custody` |
| Dispatcher | Unknown prefix, substrings, two owners, trailing newline/space, wrong UUID/machine/root | `disposition_original_dispatcher_whole_match_only` |
| Native authority | Missing/malformed declared session; CODEX mismatch; claimed external/crypto identity | `disposition_preserves_declared_session_trust_model` |
| Original contract | Missing/late/new/rewritten publication, wrong canonical hash/PR lineage/root | `disposition_requires_original_prepublication` |
| Native completion | Partial/nonterminal/wrong head/provider/digest/report/packet hash; absent original proof | `disposition_requires_original_completed_artifacts` |
| Retained packet | Confuse new retained seal with original consumed seal; changed marker/parts | `disposition_preserves_native_retained_hash_chain` |
| Receipt | Exists unequal/equal/linked, wrong start PATH binding, late appearance | `disposition_only_absent_original_receipt` |
| Lease | Wrong issue/PR/fullhead/slot/provider/sequence/ref; foreign6598 | `disposition_exact_owned_tuple_only` |
| Atomicity | No atomic capability; mutex/ref owner changes; uncertain success; retry/new occupant | `disposition_atomic_exact_ref_races` |
| Outputs | Raw body/path/credential in public record; manual verdict/refund/replacement | `disposition_never_authorizes_or_discloses` |
| Replay | Old assignment/cursor/replacement/continuation/start/record, older fallback carry | `disposition_old_tuple_never_replays_or_carries` |
| Source counter | Genuine upstream merge+new evidence vs synthetic refresh; two charged/third draw | `disposition_actual_git_projection_conserves_paid_starts` |
| Negative decision | Old REJECT followed only by tooling/main/evidence change | `disposition_reject_requires_actual_rejected_code_correction` |
| Capability | Unrelated other slot/live parallel reviewer/failure release/current source review | `disposition_preserves_existing_reviewer_capabilities` |

Run new module tests; `scripts/run-governed-review.test.mjs`; `scripts/lib/lanes/review-circuit-breaker.test.mjs`; `scripts/manage-migration-author-lanes.test.mjs`; existing assignment/lease/contract/exact-head tests through supported router; contract validation, worktree freshness and diff check. No live DB/provider/write fixture. Root retains actual6603 custody; all fixtures synthetic. Source tests then independent native exact-head code review must precede delivery.

## 11. Constraints

Own33 scope only; no broader owner adoption or foreign worktree edits. Current task class reviewer-safety; recheck before paid review/stronger action. Existing AGENTS/guarded merge/immutable evidence/request budget/concurrency/counter/independence/native private custody are binding. No user technical permission request, provider substitution, lease deletion shortcut, new runtime bypass flag, secret call or production action. All human clock notes use EDT/EST; machine file timestamps may UTC. A failed assertion is diagnosed, not disabled.

## 12. Access and environment

Owned current-main worktree `muse-owned-disposition/shared-db`; node/git/ai-gh and installed task gate available. Native worktree freshness verified e241459ab. Existing public original contract/ref hashes read without credentials disclosure; private provider proof remains coordinator custody and is NOT read in this prework. No 1Password slot or cloud access required. Source-visible independent standalone plan review uses normal maintained wrapper; no formal shared-db assignment/start/durable verdict is recorded by that advisory design opinion. Future code PR uses actual native allocator.

## 13. Delivery and open acceptance

Design completion requires an independent reviewer to inspect actual local consumer code named above and assess ownership trust limits, final original artifact availability, old lease→atomic disposition, carry/replay semantics, paid conservation after genuine main/evidence integration, negative REJECT handling, request bounds and toolkit-first/consumer-next ordering. A technical design APPROVE authorizes neither code nor concrete6603 disposition.

- [ ] Independent consumer-source-visible design verdict and coordinator code GO.
- [ ] Reconcile PR4370 overlap; implement/test/review/guarded merge own bounded repair.
- [ ] Protected toolkit receipt fix installed/qualified; merged consumer source proved.
- [ ] Private6603 qualification or exact refusal; original/foreign history preserved.
- [ ] Actual owned non-authorizing disposition and ordinary new-head review only within conserved capacity.
- [ ] Same4297 live proof and remaining broader owners/acceptance retained; no programme closure claim.

## Prospective implementation correction

Generation33 and its design review remain immutable. Native fresh registry selected successor34 before code; dispatcher is the actual child implementer, distinct from original6603 coordinator. Successor required_checks contain executable commands only. Future formal code review, required CI, guarded merge and live proof remain checklist obligations, not shell commands. PR4370 OPEN0c2 owns ghPaginated/admission-comment helpers, githubIo.issueComments and three associated tests; this repair does not edit those regions. Fresh main/4370 collision readback is required before final review.

## Implementation qualification before publication

Successor34 was selected from the fresh native registry, validated and immutably published BEFORE implementation: ref `refs/db-contracts/4297/34`, commit `01cfadbc2c9d02d40a70937978698482238fb1f6`, canonical SHA256 `05ba8fc3d48fe2a89077221146ec5cd219eb5aafb44a414e0d78c4ee83bebf1a`. Actual child dispatcher is distinct from original6603 owner.33 and its independent design review remain intact;34 expressly covers the preexisting33 design/contract paths. Required checks are executable commands only.

Focused source evidence:37 module tests;912 lane tests;312 runner/counter passes plus one preexisting skip;94 contract/Git-evidence/session/policy tests. All pass. Real Git fixtures conserve old paid starts across main/evidence successors; a third unchanged-content round refuses. Real native adapter proof uses two combined remote reads and one immutable hydration with dispositions present or absent. Native-shaped isolated disposition uses14 counted API attempts, read-only dryrun5; unchanged25 ceiling and cleanup reserve. Existing assignment/slot2 exact25 cost assertions remain. An old unbatched history fixture truthfully costs23 versus22 previously, still bounded; adapters cannot skip guards or adopt disposed v2 history. Incomplete snapshots refuse. No runtime flag, budget increase or provider replay was introduced.

Fresh upstream remains `e241459ab805a1219b76534d425741e1f87fa44c`; PR4370 remains OPEN at `0c2f0726e3b959eb1dff055695ef7f16e84a5010`. Its pagination/admission-comment helpers, githubIo.issueComments and three owned tests are untouched. Own snapshots, CLI, carry/start/record guards and appended tests are disjoint. Fresh readback/integration remains required before final formal review if main moves.

Publication ordering selected by coordinator: ordinary implementation commit EXCLUDES the new34 pair; obtain standalone exact-head native Muse code opinion before publication; after coordinator source publication GO open normal draft refs4297 to get a real PR number, then add truthful34 contract/completion-only tail, verify native Git evidence and obtain a fresh source seal. Formal allocator review waits for installed toolkit receipt-fix qualification and coordinator GO. Never fabricate a PR number or import an old approval.

- [ ] Standalone exact-head native code review and coordinator source inspection.
- [ ] Normal draft/real PR number, truthful34 evidence-only pair, required CI/formal review/guarded merge.
- [ ] Toolkit protected installation independently qualified before any consumer recovery.
- [ ] Actual owned old901 qualification/disposition and normal new-head review within conserved capacity: coordinator retains action; no live proof is claimed here. Wider4297 remains open.

## Prospective superseded-prework retirement (coordinator authorized)

Native `resolveCurrentPair` rejected the actual branch diff with both tracked33 prework contract and prospective34 pair: “more than one evidence pair claims this work (4297/33, 4297/34).” Allowed-path coverage alone did not resolve that gate. Before the retirement, the coordinator explicitly authorized removing ONLY the superseded33 working-tree contract. Its published ref `refs/db-contracts/4297/33`, commit `dbe98e3fc930f082fac035836ca3884dbc3148e1`, canonical SHA256 `a1eafd58debde0dab92a8e48094d826652fc15937bcc494a3fff3d08adc6e1b0`, original source commit `4aae67e7bdf981beca8125fc5e9773a9cc4705f6` and independent design report remain immutable/reachable. There is no rewrite of33 or34, base reset, ancestry hiding, class lowering or retired runtime contributor. The existing immutable34 contract explicitly permits the33 path and binds its exact predecessor hash. The future truthful34 completion must disclose this prospective metadata retirement.

Correctness refinements preserve the reviewed design: existing native completion validator now binds the actual original PR/work issue/canonical head repository/source branch; complete bounded immutable paid-start inventory disambiguates the original source/provider interval. Malformed/invalid-time/duplicated candidate evidence refuses explicitly; only recognized native nonpaid tombstones are skipped. Historical Muse aliases share provider ambiguity. Caller labels retain native routing semantics and never establish ownership. No new lifecycle fields or raw-stream requirement is invented.

Updated module evidence:51 tests pass. The isolated native-shaped API count remains14 for apply and5 for read-only qualification; complete paid-start history adds one Git remote listing plus hash-bound hydration per qualification, separately from counted API attempts. Fixed original-ref snapshot is one Git listing/hydration per qualification; peer/admission snapshot proof still inventories dispositions in its same existing two remote reads/one hydration. No actual6603 private qualification, disposition, allocation or provider replay occurred.

Git-context qualification uses the repository's existing `sanitizePrDataEnv` for child toolchain variables and the existing read-only hook/fsmonitor disabling pattern. The new module first refuses conflicting ambient Git repository/index/object/config/ancestry overrides before PR/source reads, preserves supported credential/SSH/proxy settings, and checks actual Git top-level against original canonical physical root. This is a bounded module guard, not a new Git framework or host configuration change.63 module tests pass, including a real ambient GIT_DIR redirect and injected index/config/root refusals; default dryrun/apply API counts remain5/14.

## Prospective atomic-publication refinement selected before source commit

Coordinator source audit proved that unchanged SHA refspecs may be skipped by Git push; they are not server-side compare assertions. This refinement supersedes the earlier §76 mutex-assertion wording: original contract/assignment/start remain immutable provenance snapshots, not no-op CAS guards. Disposition atomically CREATES its absent record, DELETES the exact held v2 lease, and DELETES its exact owned mutex. Native v2 verdict publication atomically CREATES its absent verdict and DELETES that SAME exact lease. Only one transaction can consume the lease. Legacy provider-keyed verdict publication remains supported unchanged. Standing-artifact validation, lost-response evidence preservation and never-void-authoritative-findings behavior remain binding.

Qualification requires complete native verdict/failure/replacement inventory and refuses conflicts or incomplete evidence. The disposition readback accepts only readable confirmed lease absence, exact disposition and mutex no longer owned by this operation; a successor mutex is preserved. Existing result-preserving finalization is reused so held-mutex and cleanup bookkeeping always clear. Same-SHA source refspec assertions are removed. Actual bare-Git adapter tests cover both winning orders, stale mutex rejection and successor acquisition after successful deletion before readback; no mock-only atomicity claim.

This cannot retroactively fence an already-running pre-upgrade recorder. Actual6603 action remains HELD until the coordinator independently proves original wrapper terminal exit/no old recorder in flight and installed consumer qualification. No invented acknowledgment field, old verdict import or provider replay supplies that proof. Existing starts and counters remain charged, unchanged request ceiling25 and cleanup reserve remain intact. Updated isolated apply measurement is15 API attempts, default dryrun5; Git inventory/hydration costs are reported separately.

Final atomic-refinement focused evidence before implementation commit: module77PASS, lane915PASS, runner/counter312PASS with1preexisting skip, contract/Git-evidence/session/policy94PASS:1398PASS/0FAIL overall. Real bare-Git tests include both competing winner orders, stale mutex all-or-nothing refusal, successor acquisition after successful delete before readback, plus same-process ownership cleanup/subsequent operation. Complete native terminal inventory includes original and archived verdict namespaces, failures, replacements and retired verdicts; independently held other slots remain supported; malformed candidate names refuse. Native v2 is identified by actual active-v2 ref namespace, never an adapter flag exemption. The legacy provider-keyed publication path remains unchanged. Fresh main remains e241459ab805a1219b76534d425741e1f87fa44c; foreign4370 remains OPEN0c2f0726e3b959eb1dff055695ef7f16e84a5010 and its owned helpers/tests are untouched. Native34 validation, unfiltered projectedpair proof and diffcheck pass. These are source/offline facts, not formal code approval, deployment or actual6603 recovery.
