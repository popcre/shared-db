# Exact initial health-index activation packet — owner5622

## Status and authority

DRAFT proposal only. No active policy entry is changed by this packet. Same
health need/claim5622 and application706 remain open. Tooling5713 must genuinely
merge and its exact native checks pass before any activation. RPC successor5719
(version20261105160321) stays DRAFT until all three owned production index
receipts and actual catalogues prove the prerequisites. No index ledger is forged.

The source PR containing this packet will be the exact future activation source;
its actual number replaces SELF_PR below before review. Only after root reviews
that concrete packet may this same PR author the identical three policy entries.
Normal protected merge and existing automatic maintenance selection then provide
preview/production delivery. This document alone cannot satisfy the runtime
source-policy authorship check.

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

## Inactive candidate entries

Merge only these owned entries into the actual current operations map after root
release. Preserve every existing SG/foreign entry byte-for-byte; refresh the
current-main preimage instead of replaying an old full policy snapshot. The
hashes below are the native JSON-string definition digests, not raw-file hashes.

CANDIDATE_ENTRIES

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

- [ ] Root reviews exact tooling and this actual source PR/current candidate; existing5681 ownership collision is resolved by its owner, without broad claim adoption.
- [ ] Root authorizes only actually admitted entries; source PR authors identical policy, preserves foreign map, passes current native checks and merges with no active foreign source pin.
- [ ] Existing automatic selector serially produces genuine preview shadow build+cleanup and canonical production completion for every activated operation; current catalogues/OIDs/definitions/owners/validity and immutable run receipts match.
- [ ] After all three completed index receipts, root releases fresh RPC5719 normal preview/automatic production, preserving old preview history and retired pending production versions.
- [ ] Actual REST both-corpus count/latency accuracy, natural poller/render/T8 saves, real bounded reset, monitor alert/clear and timed acceptance remain open on5622/706. No full tagging/scan stop or restart is authorized.
