---
summary: "Issue 5609 first predeclared November 17 measurement: complete 226-entry vector, unchanged criteria, full-day acceptance pending."
kind: proof
status: open
read-when: "continuing the November 17 assets trigger acceptance window or verifying its source and counter bindings"
---

# November 17 first complete observation opening

Owner: Codex coordinator 01a1eb75 on [#5609](https://github.com/popcre/shared-db/issues/5609). This is an observation opening, not completed acceptance. The same issue retains its unchecked live-proof item.

## Selection and actual live qualification

The coordinator [predeclared the first complete selection](https://github.com/popcre/shared-db/issues/5609#issuecomment-6962109907) before capture: after actual delivery of the metadata-selector correction and independent source/functional verification, use the first complete unfiltered snapshot, without selecting on favorable cost or traffic. No performance-based recapture occurred.

[PR #6617](https://github.com/popcre/shared-db/pull/6617) actually merged as `924d24a14dac7e563ad2b2e0b5ba3c7315847765`. Freshly fetched main's probe SHA256 matched the reviewed correction, `4ebc6ddcacbb3b2e1ae885472a2c6659405a2ffdd4e23137d6e83de4c0239a9e`. A target-proved production functional SELECT using its exact CTEs/predicates returned three matching metadata records, all original exact trigger/image/read-access checks true, and zero primary-thumbnail mismatches at **November 17, 2026, 5:15:40.628397 PM EST**. Those records precede this opening and are not the required future three post-opening samples.

The FIRST complete capture was **November 17, 2026, 5:16:02.552460 PM EST**. Conditional earliest full-day eligibility is **November 18, 2026, 5:16:02.552460 PM EST**. Elapsed time alone cannot pass: authentic calls, costs, current metadata, counter/identity continuity and all other original conditions still must pass. The separate #5610 fourteen-day observation remains unchanged.

The protected configured identity was compared with the fresh connected production identity immediately before each read. Reader: `supabase_read_only_user`. Only catalog/statistics and aggregate boolean correctness observations were collected. No application row export, DDL/DML, statistics reset, synthetic workload, fixture, application deployment or configuration change occurred in this opening. Earlier fixture disclosure remains in the [diagnosis](20261117-current-diagnosis.md).

## Lossless snapshot and source binding

[Capture SQL](20261117-opening-capture.sql) is one SELECT over the complete original prefix, with no role/database/top-level restrictions or LIMIT. Numeric counters are text-valued in JSON. [Exact opening JSON](20261117-new-opening.json) contains all 226 tuples, table counters, reset identities and read role. Its SHA256 is `82b328601d52d99c3525bb171e12d116b18b5ae4fd657b900e7ab5c5760f3450`.

- Family count: **226**; typed sorted MD5: **8431240c38706c96991024f40198899c**.
- Postmaster: November 6, 2026, **11:20:19.434455 AM EST**; statement reset: **11:20:19.263334 AM EST**; database reset NULL; statement deallocation **74**.
- Assets OID **17809**, update counter **668116**; search documents OID **713489**, update counter **1271402**.

Python's lossless decoder and an independent isolated PostgreSQL 17 VALUES-only query reproduced the same 226-entry typed hash. No production fixture was used for that verification. The generator now quotes the signed bigint query identifier, fixing its demonstrated minimum-bigint cast overflow without changing any numeric value or hash. The existing minimum-value fixture now compiles in PostgreSQL and matches Python's typed hash.

The proposed active probe SHA256 is `f588afb03d66cd7fdb369f5f9fb385df641a310b54162814b3a4ca5dfb72ab6d`. Its entire `query_stats`-through-final acceptance suffix is byte-identical to #6617; all three PRE-reference lines are byte-identical. Only opening identity/counter values and the complete family vector changed. Twelve Python tests and isolated PostgreSQL selector 2/2, family 26/26, trigger 19/19 and metadata 104/104 cases pass. The qualified repository read-only lexer accepts it. Actual target-proved execution before a full day returned `passed=false`, correctly. No official successful production live-proof artifact is claimed.

## Preserved failure and exact completion contract

The November 6 window remains INVALID because observed deallocation reached 74 against its pinned zero. Its selector-corrected exact source is archived as [5609-third-failed-window-corrected.sql](5609-third-failed-window-corrected.sql), SHA256 `4ebc6ddcacbb3b2e1ae885472a2c6659405a2ffdd4e23137d6e83de4c0239a9e`. Its earlier source and the first two failed windows remain preserved. This opening does not repair, re-label or average away those failures.

The authentic original PRE references remain frozen and their stricter LEAST remains binding: weighted mean runtime strictly below **81.80826627638924305 ms/call**, WAL strictly below **29548.5825136248835 bytes/call**, and document-update rate below **8829/5050.846546 per second**. At least 24 real hours and 100 genuine calls across the COMPLETE original prefix family are required, with every opening tuple, query hash/start/counter and table identity intact, unchanged postmaster/reset/deallocation, and valid genuinely new tuple timing. Three current post-opening metadata matches, ten exact bindings, original image/read access and zero thumbnail drift remain required. The hosted **33.08% versus required 50%** WAL deficit and all historical invalid/interim deficits remain unresolved.

At/after the conditional full-day time, the coordinator freshly verifies target/source, runs the exact committed probe through the existing Shared DB Live Proof workflow for issue 5609, and examines every failed predicate if it refuses. A successful functional fragment is insufficient. If continuity fails, retain the failure and diagnose it before explicitly selecting any successor. If genuine calls or savings remain insufficient, keep the same issue open and investigate actual attributable workload; never generate traffic, change thresholds, or take a favorable subset. Current deployed relevant ingestion/licensing files were independently source-hash verified on [the same issue](https://github.com/popcre/shared-db/issues/5609#issuecomment-6962080787); no additional producer repair was proved.
