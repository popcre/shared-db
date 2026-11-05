# Image input identity: Phase 1 Step 3

Owner: PopDAM coordinator V-A session. Tracking: shared-db #5634 and PopDAM #706. This package is separate from health/reset #5623 and must follow the coordinator's producer transition order. It does not edit #5609's existing asset triggers, the GPU poller, model selection, or full tagging run.

## Reproduced before repair

A private synthetic preview fixture invoking the production refresh definition reproduced all three failures: an unchanged-picture keyword update erased the image vector; a no-op refresh cleared an active lease; changing only the thumbnail URL retained the obsolete vector. No production data was modified.

## Resulting contract

Keyword generation and `content_sha256` remain exact full-text hashes. Image provenance is separate metadata: asset ID, current thumbnail URL, source modified time, source file size, last successful render completion, fixed uncropped-thumbnail transform, and current Google SigLIP2 model. Sampled `quick_hash` is never an identity. Timestamp serialization is UTC regardless of caller timezone.

Claim returns an immutable image-input hash through its existing `content_sha256` result. Existing poller callers already echo that opaque result, so their signatures remain unchanged. Completion and error require the original token, unexpired lease, and captured image hash. Text-only updates preserve vectors, error state, retry state, and active leases. Changed image provenance invalidates them and rejects late completion. New provenance jobs reject a different model.

A narrow render-completion trigger observes same-URL re-renders. A separate size-only trigger covers the revision case omitted by #5609 without replacing its owned triggers. Cached render watermarks survive render-queue retention. New nightly group IDs can reuse only the exact primary asset's uncropped search vector with matching provenance/model; the separate cropped image-similarity vectors are never reused.

## Historical adoption boundary

There is no historical thumbnail fingerprint column. Existing canonical vectors are retained when current thumbnail metadata matches and their vector timestamp is newer than the known source/render revision. Already-pruned historical render events cannot reconstruct the image originally embedded; this package does not claim to repair all historical stale vectors. It introduces durable provenance prospectively without scheduling a library-wide re-embedding. Missing authoritative provenance retains conservative legacy text-and-URL behavior.

## Verification

Seventeen isolated preview checks passed: keyword hash changes; text retains lease/vector; original claim completion/error after text changes; source revision and URL invalidation; same-URL render invalidation; stale/wrong-token/expired completion rejection; model rejection; render-history retention; exact asset-to-new-group reuse; group text preservation; bounded historical bootstrap; timezone stability.

The committed SQL contract invokes installed function definitions rebound only to synthetic temporary tables, including actual render and source-size trigger functions. Its additional automatic-trigger checks passed in the private preview rehearsal. Public asset, group, render, and search rows were never written. Temporary objects disappear when the connection closes.

The new render index and each subsequent migration have 500ms lock acquisition, 2500ms statement, and three-second transaction ceilings. An index too slow under production load must fail safely; no manual production bypass is authorized. This fixture proves behavior, not production index build time or RPC latency.

- [ ] Exact-head CI and independent contract review.
- [ ] Automatic preview and production receipts after producer transition.
- [ ] Live unchanged-image tagging update and same-URL render evidence, with tagging saves healthy.
- [ ] Full Step 3 plan acceptance; no premature #706 closure.
