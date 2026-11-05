# Publisher-backed missing characters — issue 5683

Application need: [PopDAM #680](https://github.com/u2giants/popdam3/issues/680). Governed canonical claim: [shared-db #5683](https://github.com/popcre/shared-db/issues/5683).

## STATUS

Authoring only. No preview, merge, automatic promotion or production release has been authorized for this packet. Reserved version 20261105125335 follows the coordinator's lower ordered train. Keep the existing lower-version verification repair and ordered migration dependencies visible; this source PR cannot leapfrog them. No canonical row or relink has been written by this task.

The packet inserts exactly Chase under the existing PP licensor and Cheer Bear under the existing CB licensor, plus one auditable source reference each. It creates no property edges, aliases or parents; it never updates a matched row. Codes remain NULL because the public roster supplies no business code. Existing unrelated Chase identities remain unchanged.

## Source admission

The coordinator independently admitted these two outside-source identities under the company licensing authority, for authoring only:

- [Paramount / Nickelodeon PAW Patrol character roster](https://www.paramountplus.com/sneak-peak/paw-patrol-characters-cast/) names Chase. Protected capture SHA-256: `aaa02545232ed4de09829b582f9e9c7396fcea13c8796ced112ccc08e0f8c08a`.
- [Official Care Bears roster](https://www.carebears.com/) names Cheer Bear. Protected capture SHA-256: `7f010a2a3750014f845eaf35709189358042c034a27e339942ceab875b251cdb`.

The `#chase` and `#cheer-bear` fragments in source-reference identities distinguish the named entry within its actual roster page; they do not assert that the publisher implements anchor navigation. The underlying URLs above are the captured sources. Raw HTML and source rows remain private. Publisher identity does not supply POP licensing ownership or a property edition. The existing active licensors were independently qualified by two ColdLion references each. Exact opaque hashes bind the unchanged full parent and its ColdLion witnesses; any change abstains the entire packet. DesignFlow-only property candidates have no authority here and are unused.

## Guards and isolated evidence

The existing curated SQL inspector is unchanged and accepts writes only to `core.character` and `core.taxonomy_source_ref`; reads are limited to core character/alias/licensor/source references. Every identity probe includes all statuses: scoped normalized names/codes, alias values, source names/codes, direct metadata source identities, global source identities and planned IDs. Any match/conflict aborts the complete transaction before either insert. No conflict update or partial fallback exists. A bounded live READ ONLY probe using the same conditions found both identities absent and both parent/authority witnesses unchanged.

`T2_CURATION_TEST_DATABASE_URL=postgres://postgres@127.0.0.1:PORT/t2_curation python3 scripts/tests/test_publisher_character_curation_5683.py` requires a dedicated disposable local PostgreSQL 17 database; it refuses any remote URL. Eight tests passed: exact two inserts and repeat abstention, inactive normalized-name collision, inactive code collision, alias collision, global source identity conflict, source-name/code/metadata identity conflicts, changed parent/source witness, and preservation of an unrelated same-name character. Every refusal compares complete before/after fixture state. Fictional parent/source rows replace only opaque authority hashes in the fixture; no private production rows are committed.

Four hash-bound native typed sidecar checks assert each exact character singleton and its exact source singleton. The sidecar integrity checker passed. These assertions prove the two admitted rows; they do not claim authenticated PopDAM relink delivery.

## Remaining delivery

- [ ] Coordinator review of exact source, source admission, identity guards and preserved authority.
- [ ] Qualified ordered preview and automatic promotion through the canonical workflow; no manual production SQL.
- [ ] Native production catalog proof: all four sidecar checks pass; parents, unrelated identities, aliases and property edges remain unchanged.
- [ ] Rebuild the bounded historical relink packet from current live canonical state using the actual application resolver; preserve genuine AI source, NULL models and original timestamps.
- [ ] Ordinary authenticated PopDAM examples show Chase and Cheer Bear, alongside Chucky, Michael Myers and Dwight on the same application issue. No model calls or blanket retagging establish that proof.
