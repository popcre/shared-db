# Exact initial health-index activation packet — owner5622

## Status and authority

DRAFT activation source for the two admitted DAM operations only. The active policy
adds health-dam-errored-5622 and health-dam-write-5622, bound to actual source
PR5721. The SG health operation below remains an INACTIVE proposal; its policy
key is absent while foreign5681 table WRITE remains protected. Root exact source
review is required before merge/activation. Tooling5713 genuinely merged
 ee28beb2dc97265c9ad585cf4b54d5bb99e0ea58. Same5622/application706 remain open.
RPC5719/20261105160321 stays DRAFT until all three genuine owned production
receipts and catalogues prove prerequisites. No index ledger is forged. Complete
both DAM preview/production receipts before any later SG policy/source change.

## Exact definitions and claims

Fixed registry digest84a870f7ad2f9c1d0201a614f9964f386adf7dfc51e3048967d45ef69b5b9eaa.
Only the following names/definitions are admitted:

| Operation | Production canonical | Preview owned shadow | Owning table/dependency |
|---|---|---|---|
| health-dam-errored-5622 | dam_search_health_errored_idx | dam_search_health_errored_preview_5622 | public.dam_search_documents READ |
| health-dam-write-5622 | dam_search_health_last_write_idx | dam_search_health_last_write_preview_5622 | public.dam_search_documents READ |
| health-sg-write-5622 | sg_search_health_last_write_idx | sg_search_health_last_write_preview_5622 | public.style_guide_search_documents READ |

Definitions respectively: btree(entity_id) WHERE embedding_error IS NOT NULL;
btree(embedding_updated_at DESC) WHERE embedding_updated_at IS NOT NULL;
btree(embedding_updated_at DESC) WHERE is_active AND embedding_updated_at IS NOT NULL.

Each operation owns exactly its canonical+shadow index WRITEs and actual table
READ. The minimum existing5622 scope also retains its own health/reset RPC
objects. It declares no broad table WRITE. A foreign table WRITE conflicts with
our dependency READ; foreign index READ/WRITE conflicts with our index WRITE.
No foreign claim, OID, receipt, source policy or historical author lease is adopted.

Actual native admission11:26:03AM EST November5 admits both DAM operations and
refuses SG operation because real protected claim5681 owns its table WRITE.
All ten protected claims parsed after genuine own grammar repairs; no claim was
removed or ignored. Scope fingerprint653ec6714c782c6ca78d277e345b1f5af3ac1bfd270147e14327aa027348d53a.
This fingerprint is evidence of that snapshot, not authority to ignore later
scope changes. SG remains HOLD until its actual owner safely completes/releases
or canonically narrows its own claim. Fresh native admission is required for each
operation; no blocked entry is enabled speculatively to exhaust automatic retries.

## DAM activation entries and inactive SG proposal

Only the first two DAM entries are authored in the policy. The SG entry is
proposal-only and MUST stay absent until a separate admitted source release. Preserve every existing SG/foreign entry byte-for-byte; refresh the
current-main preimage instead of replaying an old full policy snapshot. The
hashes below are the native JSON-string definition digests, not raw-file hashes.

```json
{
  "health-dam-errored-5622": {
    "kind": "health-initial/v1",
    "source_pr": 5721,
    "work_issue": 5622,
    "claim_issue": 5622,
    "definition_sha256": "ef5b8aa4b781ce0427d5447dc8b62c7a7e84a8093f70629da44e28701a05adda",
    "lock_timeout_ms": 500,
    "statement_timeout_ms": 900000,
    "swap_timeout_ms": 2000,
    "total_timeout_s": 3600
  },
  "health-dam-write-5622": {
    "kind": "health-initial/v1",
    "source_pr": 5721,
    "work_issue": 5622,
    "claim_issue": 5622,
    "definition_sha256": "5fd72ff2aaf31bed0f380ed5301cd16dcfdd72b278a1a64fcc591417a5fc1ecc",
    "lock_timeout_ms": 500,
    "statement_timeout_ms": 900000,
    "swap_timeout_ms": 2000,
    "total_timeout_s": 3600
  },
  "health-sg-write-5622": {
    "kind": "health-initial/v1",
    "source_pr": 5721,
    "work_issue": 5622,
    "claim_issue": 5622,
    "definition_sha256": "4ea06d18a7c7beddea64999138c37b61a61f48b6c1b424bc9582157be67272da",
    "lock_timeout_ms": 500,
    "statement_timeout_ms": 900000,
    "swap_timeout_ms": 2000,
    "total_timeout_s": 3600
  }
}
```

Build statements remain nonblocking CREATE INDEX CONCURRENTLY with500ms lock,
at most900000ms statement and3600s total bounds. Metadata/owned-shadow cleanup
uses2000ms statements. Original health/reset migration and request ceilings are
not raised: fresh RPC DDL500ms/2500ms/3s; real health REST acceptance<=8seconds.

## Immutable proof and crash disposition

The exact merged source PR must contain the identical active entry. Current-main
head, policy digest, workflow bot identity/run/dispatch ref, target/project,
review hold, admitted owner scope and exclusive target generation are checked
at point of use. Preview and production never share interchangeable proof.

Preview proves original canonical index/table/OID/definition/owner/validity and
historical preview source ledger, then genuinely builds its fixed shadow. Only
this process's successful exact CREATE may immediately validate the created OID
and persist the immutable built receipt. Existing built-OID proof permits
bounded recovery; a crash between CREATE and built receipt leaves an ambiguous
object. Resumed exact-name/definition alone refuses and preserves it, never
adopts/drops it. Foreign preimages, changed table/OID/definition/owner, incomplete
builds, scope/target/source drift and lost fencing refuse safely. No manual
cleanup, foreign drop, receipt rewrite or ledger invention is authorized.

Preview cleans only its owned OID and rechecks the original canonical preimage.
Production requires that genuine successful preview run/receipt plus initial
absence and creates the canonical fixed index. Every completion must match its
actual successful workflow and ready/valid catalogue OID. Original SG receipt
history/default executor path list remain intact; new code cannot silently
relabel an old executor proof as current.

## Required release/acceptance sequence

- [ ] Root reviews exact tooling and this actual two-DAM source/current candidate; fresh native admission covers both active DAM operations. SG remains inactive until its own5681 collision is resolved by its owner, without claim adoption.
- [ ] Root authorizes only actually admitted entries; source PR authors identical policy, preserves foreign map, passes current native checks and merges with no active foreign source pin.
- [ ] Existing automatic selector serially produces genuine preview shadow build+cleanup and canonical production completion for every activated operation; current catalogues/OIDs/definitions/owners/validity and immutable run receipts match.
- [ ] After all three completed index receipts, root releases fresh RPC5719 normal preview/automatic production, preserving old preview history and retired pending production versions.
- [ ] Actual REST both-corpus count/latency accuracy, natural poller/render/T8 saves, real bounded reset, monitor alert/clear and timed acceptance remain open on5622/706. No full tagging/scan stop or restart is authorized.

## Fresh first-stage release packet

11:43:15 AM EST November5: actual native10-claim snapshot admits both DAM
operations with no conflicting/malformed claim; SG still refuses protected5681.
11:43:16 AM EST: approved correct-production bounded catalogue returns NO three
canonical health indexes and only the unchanged legacy reset overload. No new
health function is installed. 11:43:17 AM EST: current preview returns all three
canonical indexes valid/ready with expected definitions/owner and the exact
historical three health/reset bodies. Protected preimages retain full definitions,
ACLs and target identity; no shared data was mutated. At actual activation these
preimages and current exclusive lanes/source pins must be rechecked.

Local native19 ownership/crash tests and12 claim/fencing tests pass. Exact policy
assertion proves only the two DAM keys added, existing SG entry deep-equal to
current main, and health-sg-write-5622 ABSENT. This is source preparation, not
permission to merge or execute. Root reviews this concrete source before release.
