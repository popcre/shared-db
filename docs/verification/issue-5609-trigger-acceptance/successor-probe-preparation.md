# #5609 successor read-only probe preparation — baseline unset

Owner: original #5608–#5610 coordinator; issue [#5609](https://github.com/popcre/shared-db/issues/5609). This receipt is preparation, not live acceptance or authority to activate a new baseline.

## Preserve the failed original window

The former `.github/live-proofs/5609.sql` is retained byte-for-byte as [5609-original-failed-window.sql](5609-original-failed-window.sql), SHA256 `4db994c5425617fe5c211f688b6d35dd520f2af5449ef80d7c7e0c96d6a0eb9f`. It preserves its original November 5, 2026, 12:36:57 AM EST post-apply baseline and all original measurements. The later restart invalidated that original elapsed-time window. The strict November 6 check returned false; [run 42229944388](https://github.com/popcre/shared-db/actions/runs/42229944388) failed without a failure artifact. The existing issue records the failure at comments 6686598557 and 6686926990. Neither this forward preparation nor a future successful window erases that result.

The successor's observed/reset/entry/postmaster identities and all five post-baseline counters are NULL. It must return false until the coordinator explicitly installs a newly captured, genuinely clean baseline after the separately owned cache repair. No repaired baseline, elapsed-time proof, passing production probe, or acceptance is claimed here.

Frozen PRE targets remain exactly 170.077045367033 ms, 59888.980667756245 WAL bytes/call, and 8829/5050.846546 document updates per second. The original full 24-hour requirement, at least 100 calls, strict 50% mean/WAL improvement, lower document-update rate, current metadata, and zero thumbnail-cache drift requirements are unchanged. The statement identity remains query ID `8695287796313115953`, user `16486`, database `5`, top-level true. The separately delivered changed-fields application update can change normal request shape; if the pinned statement no longer receives 100 real matching calls, acceptance remains blocked. Do not substitute an identity, fabricate traffic, or treat missing traffic as improvement; the coordinator must resolve any actual comparability conflict from measured evidence.

## Exact reviewed trigger renderings

[acceptance-trigger-prefixes.json](../../../supabase/tests/fixtures/5609/acceptance-trigger-prefixes.json) records the original and November 6 catalog prefixes for the ten managed triggers. The five UPDATE prefixes have the same ordered members and IS DISTINCT FROM/OR operations; only redundant parenthesis nesting changed. The five sibling prefixes are unchanged. Only these fifteen exact reviewed MD5 values are accepted, not general whitespace removal, expression normalization, regex membership or arbitrary future variants.

Original source: [production live receipt](../database-efficiency/20261105T033714Z/assets-trigger-scoping-production-live.md). Current source: the original coordinator's November 6 catalog diagnostic receipt. The event/function/name checks, enabled state, timing/cardinality, no arguments/column list, WHEN presence, internal/deferrable guards and separate image-enqueue trigger remain enforced. The exact original migration is not edited or reapplied.

## Legitimate provenance without ignoring metadata

The additional metadata contract comes from immutable migration `20261105074126_search_image_input_identity.sql`. The successor reconstructs the complete semantic metadata object, including `_embedding_input`; it never removes that key merely to make equality pass. Source identity uses the current asset, thumbnail, modified time and size, fixed model/version/transform, canonical UTC JSON timestamps and the recomputed SHA256. A retained completed-render timestamp is accepted under the source helper's queue-retention rule; malformed dates, invalid offsets/overflow, JSON-type changes, missing required keys, unknown keys or `invalid_previous` do not pass.

The probe does not invoke the service-only VOLATILE provenance helper or alter grants. It independently reads the same source/most-recent-completed-render inputs. Render-queue SELECT access is checked alongside the existing required access; no read identity is granted new privileges by this change.

The transient `_embedding_lease_input_sha256` must be a lower-case 64-hex string accompanied by an actual non-null lease token, nonblank owner and finite expiry. A finite expired lease remains legitimate pending reclaim. Without the corresponding lease, the transient key and leftover lease fields are rejected. Its claimed input can legitimately predate the current keyword/image hash: the source's coalesce/preservation rules retain that identity through permitted same-image changes. Therefore equality to the current content/input hash is deliberately not invented. Full metadata equality still rejects every other extra or changed key.

## Authentic cutover and unchanged legacy documents

The provenance migration did not bulk-backfill existing documents. Its authentic successful automatic production run is [42027222583](https://github.com/popcre/shared-db/actions/runs/42027222583), head `078f27ee625776c531439512eabe5820c3f49a26`. The apply step began November 5, 2026, **7:30:57 AM EST** and finished 7:31:09 AM EST. The start is the conservative fixed cutoff, not a guessed deployment completion time.

The actual production producer bodies match the immutable migration: `dam.search_embedding_image_provenance` SHA256 `5157949d56c3321fb06689a2b5b443e73b20556ab9a56ebeda9523e4676fe5f8`; `public.refresh_dam_search_asset_document` SHA256 `83e720b8e77743a3c4b309f152f6093ee1bea3c74943d67916846e2d5cca1f58`.

Three explicit outcomes preserve that contract. Present provenance must equal the full independently reconstructed identity/digest. When the authoritative helper has no derivable image/source identity, exact core-only metadata remains legitimate. Otherwise, absent provenance is accepted only for exact unchanged legacy metadata: both indexed/source-update times must strictly precede the cutoff, source modification must be NULL or no later than both, and the current latest completed render must be NULL or no later than both. Actual leases still need their validated transient key. Present JSON NULL/malformed provenance never takes the legacy route; post-cutover missing derivable provenance, unknown keys and core mutations fail. No documents or assets are rewritten to satisfy this test.

A target-proved production functional diagnostic on November 6, 2026, **9:47:22 AM EST** returned three exact metadata matches, ten matching bindings against fifteen accepted prefixes, valid image binding, zero thumbnail-cache drift, and required read-role access. Its artificial `now()-24 hours` sampling bound is diagnostic only: it supplies neither an actual baseline nor elapsed-time/performance acceptance. The checked-in baseline remains UNSET.

## Meaningful read-only tests

The Python fixture generator reuses the actual successor metadata CTEs and exact trigger-match predicate. Target-proved, VALUES-only SELECTs returned aggregate counts only, with no application/table rows, VOLATILE calls, writes or DDL:

- Metadata: **90/90** expected outcomes; failures `[]`. Cases cover legitimate retained/live-render input, no-image/no-source identity, every semantic core-key mutation/missing key, typed source identity/model/version/transform/size/hash mutations, invalid date/offset/overflow/number/NULL JSON, legitimate old claimed lease identity and expired finite lease, orphan/missing/invalid lease fields and unknown keys. All original 72 cases remain; 18 additional cases cover valid unchanged legacy/actual lease/render-only identity, each cutoff equality/after/NULL, source/render freshness, present NULL/malformed provenance, unknown/core-mutated legacy metadata and orphan legacy lease.
- Trigger match: **19/19** expected outcomes; failures `[]`. Original/current exact prefixes pass; member/operator/OR-to-AND mutations, missing/extra triggers, event/function/relation/WHEN/flags/arguments/column-list/NULL-definition changes fail.

The immutable original probe digest, exact reviewed prefix hashes/parenthesis-only equivalence, preserved access/reset/count/event/performance guards, unset successor and read-only probe shape are also checked offline. These synthetic tests establish predicate behavior, not the live application outcome. Root retains review, publication, baseline custody and eventual acceptance.
