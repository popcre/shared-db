---
issue: 4858
application_issue: https://github.com/u2giants/popdam3/issues/527
status: BLOCKED
owner: codex-chat-01a17ac7-afdb-7331-8a2d-2ce2b8a4cea5@hetz
---

# ColdLion OrderList case packs: preserved work, corrected cancellation finding

## 0. Business decisions only the owner can make

**None — nothing currently needs Albert's decision.** Do not ask him for a
technical approval, a credential, a manual action, or the pack on an obsolete
cancelled line. If future source reconciliation genuinely needs business
meaning, consolidate those questions into one message before dependent writes.

Already settled, do not re-ask:

- Albert's assortment meaning, corrected October 27, 2026 (relaying Yuchen):
  **“It Should show the total total pieces in the whole carton.”** Every
  assortment component's Case Pack is the whole physical carton's piece count
  (parent ColdLion prepack quantity), the same on every member. This supersedes
  the October 26 reading ("Pieces of that design per carton").
- JamieLynn, relayed by Albert on October 27, clarified that the original
  three-piece order line was fully cancelled and replaced by the five-piece
  version, distinguished by Dim Code 5. A different, closely numbered style is
  the active nine-piece line. Her later explanation supersedes treating two
  same-style lines as two active unresolved orders.
- JamieLynn reports an EDI 860 dated July 31, 2026 corrected the other style.
  An EDI multiplier was her earlier tentative explanation, not a proven cause.
  Do not implement a multiplier formula or infer inners by division.

Canonical business meaning is in the unmerged [ERP topic update](https://github.com/popcre/shared-db/blob/codex/dim-code-business-meaning/docs/business-rules/erp-orders-and-source-meaning.md#dim-codes-pack-variants-and-possible-edi-multipliers).

## 1. What this application is

[PopDAM OrderList](https://dam.designflow.app/orders) is staff's order list in
an internal artwork application. [App source](https://github.com/u2giants/popdam3)
is React; [shared-db](https://github.com/popcre/shared-db) owns shared Supabase
structures and ColdLion landing/intake. Production is the shared Virginia
backend; resolve and re-prove its protected identity rather than copying an
identifier from this document. Consumer shared-db mirrors are read-only.

App acceptance stays on [PopDAM #527](https://github.com/u2giants/popdam3/issues/527).
Backend work stays on [shared-db #4858](https://github.com/popcre/shared-db/issues/4858).
Both remain open. Keep `- [ ] live proof` on the same application issue; create
no second ticket for unfinished acceptance. Root owns the outstanding work until
an actual successor accepts; this handoff alone transfers no reservation.

## 2. Goal, scope and acceptance

Albert asked to pull the latest repository, investigate Yuchen's missing
ColdLion case packs, close the gap, document Dim Code meaning through the
business-rules skill, recheck the API, and use a subagent for remaining fixes.
He then requested wrap-up. No new scope may start during closeout.

Success means correct saved whole-carton packs, a recurring import that preserves
that meaning, physical assortment cartons counted once, correct treatment of
cancelled/replacement lines, and signed-in live proof. A green build, a prepared
workflow, or a documentation PR is not delivery of those outcomes.

## 3. Current state and source custody

**Earlier partial live delivery:** 43 formerly blank packs were retained after
an isolated signed-in production read verified 43/43. Initially 106 were filled;
63 own assortment fills used the wrong standalone defaults and were restored
to their exact original NULLs. Other fields were verified unchanged. Never
report 106 fixed. These counts describe the earlier receipt, not a fresh census.

**Never applied:** the earlier 574 component-correction candidates (563 blank/
zero plus 11 proven old defaults). The follow-up subagent did not regenerate
those candidates. Their count, preimages and eligibility are historical;
regenerate everything before another write. Google/manual exceptions are held.
The earlier claim of two active direct-item exceptions is superseded by the
cancellation finding below and must not be replayed as a two-row repair.

**App proof capability merged:** [PR534](https://github.com/u2giants/popdam3/pull/534),
[merge commit](https://github.com/u2giants/popdam3/commit/743dc59b5b92c69f1561be3b2238bbff3314ac2e).
Its [run40432535235](https://github.com/u2giants/popdam3/actions/runs/40432535235)
correctly reported `NOT YET APPLIED` and wrote no live acceptance. The proof
compares actual view behavior; it is preparation only until the change exists.

**Backend preserved, not released:** [PR4859](https://github.com/popcre/shared-db/pull/4859)
is CLOSED and reopenable; branch `codex/coldlion-case-pack` is retained. Published
source is [c413638a62d2e4ba9900586a69f512ce186dfdb7](https://github.com/popcre/shared-db/commit/c413638a62d2e4ba9900586a69f512ce186dfdb7).
The subagent merged inspected upstream locally and committed
`446ff78d9e9539438c237734a20004c04511ccb5`, clean but **UNPUSHED** because the
ship gate requires an exact-head approval first. Its intended
[commit URL](https://github.com/popcre/shared-db/commit/446ff78d9e9539438c237734a20004c04511ccb5)
is not a published recovery source. A protected recovery patch and local Git
custody are indexed by the vault note in section 8. Do not discard them.
78 intake tests passed on that local head; no new row/schema writes occurred.

Published files: [intake writer](https://github.com/popcre/shared-db/blob/c413638a62d2e4ba9900586a69f512ce186dfdb7/tools/coldlion-landing/lib/order-intake-write.mjs),
[migration20261027010036](https://github.com/popcre/shared-db/blob/c413638a62d2e4ba9900586a69f512ce186dfdb7/supabase/migrations/20261027010036_coldlion_component_case_packs.sql),
[rollback fixture](https://github.com/popcre/shared-db/blob/c413638a62d2e4ba9900586a69f512ce186dfdb7/supabase/tests/coldlion_component_case_packs.sql),
[generation3 prospective contract](https://github.com/popcre/shared-db/blob/c413638a62d2e4ba9900586a69f512ce186dfdb7/.agent/work/4858/3/contract.json).
The old version is now behind main and must not be reused. Native version
supersession/new custody and current prospective evidence are required.

**Documentation:** [canonical PR4915](https://github.com/popcre/shared-db/pull/4915)
contains business meaning, map routing, cancellation clarification and this
handoff; [app PR546](https://github.com/u2giants/popdam3/pull/546) contains the
[OrderList pointer](https://github.com/u2giants/popdam3/blob/codex/casepack-blocked-handoff/docs/ORDER_LIST.md#coldlion-pack-variant-reference).
Neither is merged. No frontend deployment is needed for these prose changes.

**Custody closed:** native park closed [claim4860](https://github.com/popcre/shared-db/issues/4860)
and PR4859 without deleting source. [Terminal receipt](https://github.com/popcre/shared-db/issues/4858#issuecomment-6447361740)
and [app receipt](https://github.com/u2giants/popdam3/issues/527#issuecomment-6447362207)
record the release. The final coordinator-native closeout check during wrap-up
SUCCEEDED: 14 open claims and 98 open issues inspected, all three stages read,
zero owned open claims and zero owned stages. JSON is retained privately.
Foreign sessions' reservations are not ours to remove. No preview schema apply,
merge-stage acquisition, or production schema apply happened for this change.

## 4. Failed attempts and dead ends

1. Standalone item defaults were wrongly used for some assortment members;
   exactly the 63 own fields were restored. Preserve receipts, do not repeat.
2. The first proof draft assumed a line-source hash not saved by the writer
   and confused sales line zero with assortment identity. The shipped proof
   uses actual component ordinals and saved component hash/SKU evidence.
3. A direct ledger read was rejected by the app guard. The proof now inspects
   actual view contracts and natural authenticated behavior; no guard bypass.
4. The original ephemeral failure was the unrelated issue4427 malformed-JWT
   assertion. PR4863 was closed; its successor [PR4866](https://github.com/popcre/shared-db/pull/4866)
   merged the repair. Do not keep treating that old failure as the current
   blocker or overwrite the other session's checkout.
5. The original GLM governed runner ended without a durable final receipt.
   Its pool record misleadingly remained active, with last progress long ago.
   This is not approval. Do not retry that failed/stale reviewer; incident3875
   and encrypted evidence were recorded through the existing reviewer tool.
6. Updated local source could not be pushed without exact-head approval.
   Native reviewer allocation refused a draft PR; a bounded ready/draw/redraft
   attempt met a foreign author mutex. No review or owned mutex was acquired,
   no paid review started, and our waiting process was stopped. PR was restored
   to draft and then natively parked. [Detailed blocker](https://github.com/popcre/shared-db/issues/4858#issuecomment-6447320145).
   Never mislabel a review of published c413 as approval of unpublished 446ff.
7. Local `ai-doc-safety` failed on existing tracked review artifacts,
   credential-shaped content, topology and project-shaped strings across both
   complete repositories. Markdown links passed: 523 canonical and 670 app
   files on the inspected heads. Those failures were not repaired or bypassed.
   Later handoff edits have not been claimed to pass this failed whole-tree
   gate. Entire Gates also asked for approval/up-to-date state on PR4915.
8. Earlier native final audits timed out in the shared GitHub throttle. During
   wrap-up the original installed checker succeeded without replacement,
   disabling, private state edits, or an invented zero-claims count.
9. Root missed a saved full-cancellation field and overstated two active
   same-style lines as ambiguous. That statement was corrected on
   [app issue527](https://github.com/u2giants/popdam3/issues/527#issuecomment-6449478550)
   and [backend issue4858](https://github.com/popcre/shared-db/issues/4858#issuecomment-6449479144).

## 5. Findings and governing meaning

For assortment members (owner correction 2026-10-27), Case Pack is the whole
carton's piece count: the parent line's prepack quantity, the same on every
component. Component order quantity is ordered units of that design. Cartons
are the parent line quantity divided by that total, counted once per physical
parent, never summed per design. Conflicting/missing totals remain unknown;
preserve Google rules. PR #4859 implements this.

Dim Code distinguishes reported variants, but its numeric text is not a
universal formula. The current [item-detail projection](https://github.com/popcre/shared-db/blob/c413638a62d2e4ba9900586a69f512ce186dfdb7/tools/coldlion-landing/lib/master-specs.mjs)
ignores Dim Code as a typed field (raw payload retains it). Production details
retain Dim Code and item identity. The proposed direct-item resolver safely
abstains on conflicting quantities; it does not yet select by Dim Code/itemPkey.
Do not silently expand the structural claim for a Dim Code column.

Direct API reads on October27 at 12:08/12:11 PM EDT confirmed a Dim Code5 record
with carton5 and a blank-code record currently carton9, both inner quantity1.
That proves the returned current master values, not historical line packs.
The saved order intake used in the earlier answer was fetched October23 at
12:42 AM EDT, after the reported July31 EDI860. It already showed the first
line fully cancelled, with zero shipped/invoiced and no pick/invoice reference;
active corrected styles had shipped/invoiced quantities and references. Saved
history also contains an older version of the cancelled line. Root did not
read an independent pick-ticket payload: its references came from order
history. Do not claim an independent ticket comparison or an API defect.
A current item-master update must not rewrite cancelled historical packs.

## 6. Exact next steps and success gates

1. Read both existing issues and this file, then reconcile current PRs, native
   custody, upstream and installed gates. First finish the normal prose-only
   publication path for PR4915 and PR546, resolving their required safety gate
   through its governed owner rather than deleting unrelated evidence. Gate:
   merged documentation or exact current refusal retained on the same issues.
2. Recover unpublished446ff from preserved Git/patch using the vault index.
   Resolve legitimate independent-review admission for that exact unpublished
   source; preserve the old reviewer failure and foreign mutex custody. Gate:
   an actual exact-head approval allows publication; no synthetic receipt or
   same-engine self-review. Never leave the backdated old PR ready in the queue.
3. Resume structure under the successor's actual identity: current native
   exact-object admission for the two views, a fresh valid version/reservation,
   bounded author check-in and prospective contract. Reopen/rebase the parked
   source through that native route. Re-derive from current view definitions,
   retain the later division-scoped intake changes. Gate: claim/version/contract
   and source guards pass; the old reservation is never reused.
4. Update the app proof's required migration/version reference through app
   source after the backend contract is settled. Obtain required exact-head
   independent review, full ephemeral checks/rehearsal, guarded merge and
   qualified automatic production promotion. Gate: installed view contract and
   passing release evidence, not green Railway status alone.
5. Before a row repair, freshly reconcile cancellations, replacements, exact
   item/Dim variants and source groups. Regenerate every candidate/preimage;
   exclude obsolete cancelled lines and uncertain/default/Google/manual cases.
   Apply only recoverable app-owned case-pack updates with immediate target
   proof and applicable gates. Gate: full exact readback, other fields unchanged.
6. Run the signed-in proof and independent source/carton comparison for current
   candidates and prior verified changes. Gate: actual saved values, physical
   cartons counted once, correct cancelled/replacement treatment and a real
   acceptance artifact rather than `NOT YET APPLIED`.
7. Close the same issues only after live acceptance. Retire this predecessor
   handoff only when its successor rules pass, release native custody and run
   final identity-bound closeout. Gate: zero owned claims/stages and no open
   acceptance obligation. No new business question is currently required.

## 7. Constraints, scope freeze and workspace

No app-side DDL, vendored-mirror edits, direct production schema commands,
whole-order replay, guessed variant, automated multiplier, or writes to
Google/manual exceptions. No reviewer bypass, foreign-lock takeover, broad
staging, forced push, or deletion of unique/unpublished work. The owner asked
for closure; no new feature/repair was started during wrap-up.

All own case-pack source/proof/documentation worktrees are intentionally
retained: the backend has unique unpublished source; documentation is unmerged;
proof work may be needed by a successor. Inspected trees were clean before this
handoff. Canonical checkouts have unrelated untracked session work; it is
protected and untouched. No branch or worktree was removed, no unrelated
handoff edited/deleted, no mystery own migration left untracked.

Housekeeping was report-only: it identified merged cleanup candidates and
successor-review handoffs, as well as live/unknown work. No candidate was treated
as deletion authority. Its detailed local report is retained with private
recovery evidence. No completion claim is made for another session's handoff.
The only new finding during wrap-up was that the original closeout checker now
works; no new implementation scope was undertaken.

## 8. Access, secrets and recovery

Use the existing authenticated GitHub and 1Password paths. The real native
closeout checker must run in the actual coordinator context; the child's
attempt correctly refused mismatched session identities. Use the supported
GitHub throttle; preserve foreign live state and never substitute an ad-hoc
claim counter for a failed native audit.

Vault `vibe_coding`: ColdLion credential item `zq6cjbz3ycj6psgkeae2devufm`, shared
DB password item `246sf23gymd64yudpmhswcnyle`, tester login item
`mbspkosvp2rf25qxhqufipxqca`. Secret values never belong in arguments, output,
source, issues or this document. Inject through protected existing references.
Session sweep: existing items cover every credential used; nothing new to store.
Scratch credential files contain only references and non-secret connection
settings, are mode0600, and remain outside Git.

Recovery Secure Note **PopDAM OrderList ColdLion case packs - issue 527 recovery
evidence (hetz, 2026-10-26)**, item `lfoua56qya4ui643qxty4jvgba`, gives the
protected host location. It indexes the original snapshots/restoration receipts,
43-line proof, historical component manifest/scripts, child blocked handover,
unpublished446ff recovery patch, park receipts and final closeout JSON.
Historical component preimage digest:
`1dbb17904d2e348d09e425459f771e6a9372f8b310c91a2542b0bc10fd878443`.
It is a recovery identifier, not authority to replay old data. Raw source rows
and authenticated traffic stay in private evidence, never public Git.

## 9. Open risks and self-audit

The remaining corrections are NOT delivered. Current source may need a fresh
re-derivation; historical counts/preimages and all old approvals can drift.
The cancellation error also means a current exception census must be rebuilt.
Documentation publication and review admission remain technical blockers owned
by the root workstream. The earlier RLS test failure is repaired, not the
current dependency. No business approval is owed by Albert.

Self-audit, read end-to-end before publication:

1. **Newcomer can continue: yes.** Sections1–3 identify the applications, same
   issues, published/unpublished custody and actual release state; section6
   gives ordered actions with explicit success gates.
2. **Can continue as effectively as root: yes.** Sections4–5 retain failed
   reviews, publication deadlock, source semantics, current-vs-historical packs,
   cancellation correction and the absent independent pick-ticket comparison.
3. **All execution evidence and safety limits: yes.** Sections3,6–8 name exact
   source, prospective evidence, native release/closeout, private recovery,
   credentials-by-ID, tests, workspace decisions and live-proof requirements.
   No local-only file reference or raw transaction row appears here.
4. **Owner-only view complete: yes.** A sentence-by-sentence sweep of sections1–9
   and both child blocks found no pending business choice. Section0 explicitly
   says none and records every settled answer. Review/access/publication work
   stays technical; no hidden request for Albert's approval is present.

## Part B. Subagent casepack_proof

Asked to add signed-in live acceptance coverage for backend issue4858. Produced
an isolated app proof implementation, corrected it after feedback and passed
27 tests. Root corrected remaining assumptions/schema selection and shipped
PR534. Child source was committed; the final shipped proof is the authority,
not every intermediate child assumption. The child completed and is not active.
Its clean worktree is retained with the unfinished acceptance work. It did not
apply schema, write production data or claim that the not-yet-applied proof was
acceptance. No native database claim/stage was acquired by that child.

## Part B. Subagent finish_orderlist

Albert explicitly requested a subagent finish remaining corrections. It
reconciled current source and the repaired test dependency, natively renewed
then parked the exact original claim, merged upstream into local446ff and
passed78 intake tests. No new paid review, schema apply or row repair occurred.
It exposed the unpublished-head review/publication deadlock, protected the
foreign reviewer mutex, preserved source/patch, posted the same-issue handover
and verified native park. It completed blocked, not active; no successor has
accepted custody. Root's successful final native check covers the closed root
claim and all three stages. Its implementation did not silently expand into a
Dim Code schema change or apply the old574 candidates.
