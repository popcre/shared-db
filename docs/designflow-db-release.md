# DesignFlow database release readiness

Work issue: #4655. Application outcome: popcre/designflow-backend#232.

This implementation is not activated or proven merely because its files exist.
The six application manifests must reach their default branches, canonical source
must pass independent review and guarded merge, and the centrally controlled
main merge protection must pass a live negative test (or a centrally controlled
deployment gate must be proven if native protection is unavailable). Until those facts are
recorded on #4655, no automatic release or enforced deployment hold is claimed.

## Release identity and source custody

Each application records `.release/database.json` with its exact canonical source
PRs/issues, migration paths/content hashes, and bounded table/column/runtime-role
contracts. The parser accepts only six named applications, the configured
production project, bounded identifiers, known fields, and fixed privilege names.
No manifest SQL, shell, repository code, or arbitrary endpoint is executed.

`config/designflow-db-releases.json` is the reviewed central policy. It pins each
application's contract fingerprint, minimum baseline source requirements, schemas
and runtime roles. Empty or weakened application requirements cannot erase that
baseline. Database changes must update the canonical migration, this policy and
the consuming application's manifest together. Agent/app workflow guidance must
retain that requirement; automatic promotion does not capture ad-hoc sandbox SQL.

Before accepting a requirement, the observer proves its PR is merged into canonical
main, links exclusively to its work issue, declares exactly its authored migration
set, and has the same migration bytes at its author head and current main. Changed,
omitted, rewritten, forked or unmerged sources refuse. The current archive metadata
correction remains blocked until its authentic preserved-source route is resolved;
do not weaken content validation to conceal that correction.

## Existing promotion only

The central five-minute observer checks develop and main snapshots. Only develop
can initiate promotion. It asks the existing native preview selector for a stored
`merged_rehearsal` instruction and accepts only the exact required source PR,
versions and current canonical main. Existing guards, reviewer evidence, claimed
source custody, risk assessment and preview/production locks remain authoritative.

Dry-run and apply are sequenced across bounded observer runs. Each native dispatch
is preserved before its single API write. The migration workflow's deterministic
run name uses its existing inputs; no 26th input or alternative SQL apply path is
introduced. A missing, ambiguous, failed or uncertain dispatch requires authentic
reconciliation. A timed-out write is never replayed as if it had not happened.

Successful native production evidence is verified by the existing exact-source
artifact verifier plus archive-byte digest, exact migration-content hashes,
enforced catalog results and successful canonical producer jobs. Before expiring
Actions artifacts can make an old prerequisite unverifiable, the observer preserves
a compact create-only receipt under `refs/designflow-db-apply-receipts/`. Its owner
is #4655's canonical release process; one record binds each required source head.
Each reuse rechecks canonical source/producer ancestry and fresh SHA256 fingerprints
of the production migration ledger. A changed ledger or source refuses. These
receipts contain metadata/hashes, not business rows or credentials. Retain them
while any application policy references that source; retirement requires a scoped
review after every consumer has removed the dependency, never age-based deletion.
Current read-only production catalogs independently check the
declared columns, schema access and runtime privileges. Already applied source is
idempotent success only after both checks. No application data is queried or copied.

The existing central `SYNC_TOKEN` authenticates canonical operator effects and
cross-repository source reads. A separate short-lived token from the existing
`pop-ai-watchers` App (ID5112061), limited to the six application repositories,
publishes statuses with status-write and content-read permissions. The publisher
refuses another identity or a missing token; there is no PAT fallback for statuses.
The existing central Supabase credential performs read-only catalog inspection.
Neither credential is distributed to applications. Repeated source/evidence reads
are cached within one observer run, and the observer preserves an API reserve.

## Readiness is separate from release enforcement

Statuses and a digest-bearing Actions artifact bind each result to an exact app
commit and manifest. Main readiness additionally requires an actual merged PR
from that repository's develop branch and an identical source tree. A main snapshot
with missing production requirements waits; it never initiates a belated apply.
Application acceptance and business acceptance remain separate from database
readiness. A failed or waiting result is never reported as ready.

The initial audit found GitHub Free and private protection queries returned an
upgrade restriction. Albert authorized GitHub Team for two seats up to $8/month
before tax; checkout confirmed that amount. Record actual purchase, protection
configuration and enforcement proof on #4655 before claiming the gate is active.

After Team is active, the preferred enforcement is native main protection for the
six apps: require the `database/production-ready` status specifically from App
ID5112061, require an up-to-date pull request, enforce for administrators, and permit
no bypass, forced update or deletion. Preserve any stricter existing protections.
Prove a missing/failed/wrong-App check cannot permit a main merge. Keep the existing
six production triggers on main, and retain Uma's application merge authority.
The process does not automatically merge application code.

This native main gate can satisfy the requested pre-main protection without adding
a new Cloud Build wrapper or mutating production infrastructure. Such a wrapper was
proposed while private main protection was unavailable; it is not an activated
capability. The infrastructure repository's production-forbidden policy remains
intact. If native protection proves insufficient, return to a reviewed supported
infrastructure route rather than changing triggers ad hoc.

Statuses record a verified snapshot. GitHub does not give commit statuses an
application-defined expiration time; the central observer rechecks the current
heads every five minutes. Do not describe a cached green status as continuous
production proof or general application acceptance. Database changes continue
through the existing consumer-safety, rehearsal and production checks.

The observer checks out the exact workflow producer SHA and refuses checkout
source drift. A pinned App identity prevents a user token or application workflow
from supplying the required central readiness status. It does not prevent an
organization owner from deliberately changing protection settings.

## Verification and recovery

Tests cover strict source/manifest validation, role/policy weakening, absent evidence,
exact-commit drift, fail-closed statuses, idempotency and bounded preview identity.
Synthetic PostgreSQL tests prove actual query behavior for positive column grants,
schema/table/column/role denials, write privileges, empty contracts and read-only
transaction enforcement. These are not production or application acceptance.

Recover uncertain native operations through their existing issue and immutable
records, never by deleting dispatch custody or releasing another author's claim.
Roll back defective observer source through the guarded repository route; retain
the last valid application runtime while readiness is unavailable. Structural
rollback remains a new reviewed forward migration.
