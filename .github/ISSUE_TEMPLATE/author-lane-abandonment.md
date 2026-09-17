---
name: Author lane abandonment audit
about: Record the evidence for an expired author lane before any lane is touched (issue #2301). Every heading below is required.
title: "Author lane abandonment audit: claim #"
labels: db-work
---

<!--
An expired lease is not an abandoned lane. Expiry proves only that nobody
renewed a claim; it never releases the object protection or the capacity slot,
and nothing may transition a claim because a clock ran out.

This issue is the durable record that a decision was made on evidence. Open it
BEFORE relinquishing capacity and before retiring anything. Keep every heading
exactly as written.

PRIVACY: record identifiers, not people. Machine and worktree go in as their
recorded identifiers only. Never paste personal filesystem paths, account names,
credentials, tokens, or the contents of any message into this issue.
-->

```db-work-scope
status: ready
work_type: repo-maintenance
route: repo-maintenance
change_type: repo-maintenance
priority: 100
depends_on:
writes:
reads:
```

<!-- writes: and reads: are empty on purpose. An abandonment audit claims no
database object; claiming one would collide with the very claim it is
investigating. It is repo-maintenance work, not orchestrator structural work:
it changes no database structure. -->

```abandonment-audit
claim: <claim issue number>
pr: <pull request number>
head_sha: <the full 40-character head SHA>
owner: <the claim's recorded owner>
```

<!-- The abandonment-audit fence is the machine-readable half of this record and
is REQUIRED. The reconciler that suggests the guarded relinquish command and the
guarded command that revalidates the evidence both read this one fence. Fill in
every field: a fence missing a field, or carrying one in the wrong shape, is
read as no evidence at all, the reconciler prints no command, and a relinquish
falls through to the ordinary-blocker path with none of the exact-tuple
revalidation this record exists to provide. The four values must match the live
claim exactly. Never hand-edit this fence after the decision is recorded. -->

## Claim

<!-- The claim issue number, its recorded owner, and its branch. -->

## Pull request and exact head

<!-- The pull request number and its full 40-character head SHA, or "none". -->

## Migration version

<!-- The reserved migration version, or "none". It can never be reissued. -->

## Last known worktree and machine

<!-- Their recorded identifiers only. -->

## Expiry

<!-- When the lease expired, and the audit run that observed it. -->

## Audit output

<!-- Paste the report from:
     node scripts/manage-migration-author-lanes.mjs --abandonment-audit
     and state its exit code: 0 clean, 2 expired, 3 unverifiable.
     A 3 concludes nothing. Do not proceed on a 3. -->

## Evidence the author is terminal or unreachable

<!-- What was actually observed, with dates. Silence is not evidence of
absence; name the checks that were run and what each returned. -->

## Observed worktree state

<!-- Exactly one of: clean / absent / dirty / remote / ambiguous, and how it
was observed. "ambiguous" is not a state: re-observe or stop. -->

## Decision and authority

<!-- Quarantine (recoverable) or terminal retirement.

The orchestrator may retire work on its own evidence where the worktree is
clean, or absent with its absence proven and its durable branch and pull-request
evidence complete.

Albert decides, and only Albert decides, whether potentially recoverable
uncommitted work may be abandoned — that is any worktree observed dirty or
remote. Quote his decision here, with the date. -->

## Recovery or successor references

<!-- Where the work went: the recovery evidence, the successor claim and its
fresh migration version, or the tombstone written by --release-claim. -->
