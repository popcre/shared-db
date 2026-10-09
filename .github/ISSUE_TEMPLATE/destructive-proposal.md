---
name: Destructive proposal (DROP, TRUNCATE, VACUUM FULL, bulk DELETE)
about: Propose removing data or objects. Every heading below is required (issue #2437).
title: "Destructive proposal: "
labels: destructive-proposal
---

<!--
Absence is not proof (issue #2437). A zero from a reset counter is identical to a
zero from a genuinely unused object. The Destructive Proposal Guard workflow fails
when this issue carries the `destructive-proposal` label and any heading below is
missing or left empty. Keep every heading exactly as written.
-->

## Proposed action

<!-- The exact DROP / TRUNCATE / VACUUM FULL / DELETE and its target objects. -->

## Observation window

<!-- Start and end of the window the measurement covers. For pg_stat readings,
paste the output of docs/sql-snippets/pg-stat-observation-window.md so the counter
is never quoted undated. Anything created after the window start has no usage history. -->

## Positive control

<!-- A case the SAME measurement did catch inside this window (for example a table
with known writes showing n_tup_ins > 0). Without one, the window is unproven. -->

## Second independent source

<!-- A second source that would fail differently (row timestamps, branches API,
merged tree). Re-running the same query is not corroboration. -->

## Evidence class

<!-- structural (provable from the catalog, may proceed now) or usage (counters,
must wait). Classify every candidate. -->

## Earliest action date

<!-- Measurement and deletion are separated in time. The action is authorised only
by a later, independent re-read on or after this date. -->
