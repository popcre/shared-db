# Standalone health/reset RPC successor — owner5622

## Status

Source only. No merge, activation, production write or application completion is
claimed. The existing health need is5622 and application706/663; no new need is
created. Index maintenance activation must precede this migration's merge.

Fresh native reservation20261105160321 is distinct from all four immutable old
health files. Original73854/73903/73911/73920 SQL, reservation refs, applied preview
ledger and every original rehearsal/failure artifact remain intact.

## Contract and prerequisites

The three published73920 function bodies are byte-identical. This file adds only
strict prerequisite/prestate checks, CREATE OR REPLACE compatibility, and a
transactional PostgREST schema-cache notification. Legacy reset(text,uuid[]) is
required to exist and is never replaced, revoked or rewritten.

All three canonical indexes must be valid/ready, owned by postgres and have the
exact complete fixed definitions. A same-name index on another table, reversed
ordering, changed predicate, missing or invalid index refuses before function
mutation. This database guard establishes catalog capability; it does not claim
ownership from a matching definition. Genuine immutable owned maintenance receipts
for each production index are a separate required release gate.

A target may have all three new RPC signatures absent, or all three must match
the exact historical preview body hashes, language, volatility, definer/invoker,
owner, search_path and ACL set. Mixed or divergent states refuse atomically.
ACL ordering is immaterial; unexpected privileges are not accepted. Final ACL
validation protects against unexpectedly broad default privileges. Exact
both-target singleton atomic policy preserves500ms lock/2500ms statement/3s
transaction budgets and commits all function/ACL effects and ledger together.

The file declares no old73920 production ledger dependency: its guarded standalone
definitions support absent production functions and exact existing preview
functions. It does not falsely assert that old73920 was installed in production.

## Evidence

Actual preview catalog11:01:18AM EST November5 showed all three exact body hashes,
the legacy overload and all three valid/ready indexes. The contemporaneous
production catalog reader failed its bounded client deadline and returned no
state; no production absence was inferred. Fresh correct-target production
catalog/receipt checks remain required at actual release.

Seven actual isolated PostgreSQL17 tests use the existing canonical policy/hash
loader and atomic SQL/ledger wrapper. They prove absent-target creation, exact
historical-preview adoption without body/ACL change, each missing index, wrong
exact-name definition, mixed or divergent body/ACL/definer refusal with unchanged
preimages, and real two-corpus counts/non-NULL results/bounded reset/active-lease
exclusion/access guards. Each fixture uses one newly owned localhost database;
existing Supabase roles are required, no new roles or administrative role privileges are introduced, and
cleanup targets only that database without FORCE or session termination. The
fixture uses the already installed pgcrypto package inside its disposable DB;
no hosted extension, credential or platform setting is changed.

The permanent named CI step is distinct from foreign HTS/browse/actor steps and
from the builder's health-index drill. Current native exact-head CI remains a
separate requirement. These are synthetic isolated proofs, not ordinary live
poller/render or production latency acceptance.

## Delivery and acceptance

- [ ] Root exact-source/claim review, current native checks and ordered reservation admission.
- [ ] Tooling5713 merged and separately reviewed activation packet genuinely builds all three indexes, with preview shadow cleanup and owned production OIDs/receipts.
- [ ] Normal singleton preview then automatic production; actual function hashes/ACL/legacy overload/ledger and PostgREST schema visibility match.
- [ ] Real REST health finishes within eight seconds, returns both corpora with non-NULL pending/error counts and matches independent bounded count truth.
- [ ] Ordinary tagging/poller/render proof, one authorized bounded real reset with actual available-thumbnail/persisted-vector evidence, monitor alert/clear, outside-hours poller drill and24h near-zero acceptance remain on5622/706.
