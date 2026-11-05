# Style-group save path: avoid legacy provenance-only writes

## Status

Source preparation; not production acceptance. Same V-A owner and issue5665;
parent5634/stage3live5666 and PopDAM680 retain the actual customer need.

The one authorized T8 designer correction failed under lock500ms, statement2500ms
and transaction3s after stage3142040 genuinely installed. Its entire transaction
rolled back, including asset/group/search/vector/lease and backup preimages. No
retry or broader DML is authorized by this source work.

## Actual read-only evidence

At10:36–10:38AM EST November5, exact target group/primary asset both had canonical
legacy vectors without private image provenance. The current search keyword hash
recomputed exactly; business metadata and thumbnail matched; the vector was newer
than authoritative source modification. Input joins used the two primary-key
indexes, not a broad document scan. No document lock was observed.

The current upsert nevertheless writes new provenance into the otherwise identical
group document. That unnecessary write is proven; attributing the timeout to its
HNSW work remains an inference until the original real save succeeds after delivery.

## Minimal change

Fresh singleton20261105154021 changes only the existing group refresh function.
Before the original upsert it compares all original searchable fields and business
metadata, excluding private lease/image-provenance keys, and requires the existing
authoritative image-input match. Only an exact no-op returns early. It preserves
the complete legacy row, vector, queue age and lease instead of claiming verified
legacy provenance. Real text/metadata changes continue through the unchanged
upsert. Same-URL renders, source-size changes, wrong models and image revisions
still defeat the guard. Existing security/ACLs and source freshness behavior remain.

The applied74126 source is immutable. Its historical reservation remains; new
154021 uses its own permanent native reservation and exact both-target singleton
atomic policy. All other policy entries remain unchanged.

## Verification

Actual isolated PostgreSQL17 reproduces the original failure of the unchanged
legacy full-row/ctid assertion. The new eight-assertion contract passes with a real
HNSW index on its synthetic temporary documents, including zero document updates,
complete pending legacy lease preservation, real keyword and metadata refresh,
same-URL render invalidation, wrong-model rejection and the actual size trigger.
It runs under the original500ms/2500ms/3s ceilings. The original45-case contract
is byte-identical and passes against the replacement. These prove semantics, not
production save latency.

- [ ] Exact source/native CI and coordinator review.
- [ ] Normal preview and automatic production receipts, installed definition/ACL.
- [ ] Coordinator-authorized original one-asset save succeeds within unchanged budgets; independent T8 preimage/backup/search/vector/lease acceptance.
- [ ] Natural render/poller and remaining application acceptance stay open on5666/5634/706.
