---
summary: "Fixed issue 5609 statement-capacity staging profile: preview first, preserve observations, no restart capability."
kind: ops
status: current
read-when: "reviewing or delivering the fixed statement-capacity staging-only profile for issue 5609"
---

# Fixed statement-capacity staging for issue 5609

Owner: the coordinator of [issue 5609](https://github.com/popcre/shared-db/issues/5609).
Statement-entry eviction invalidated complete acceptance observations. This
profile stages a larger future capacity without activating it or disturbing the
index-observation interval on issue 5610. It does not establish either issue's
acceptance. Retire the profile after effective capacity is independently verified
and issue 5609 is accepted.

## Scope and authority

The committed `config/pgss-capacity-stage.json` authorizes only
`pg-stat-statements-capacity-stage/v1`, `pg_stat_statements.max = 40000`.
Its source PR must be replaced with the actual positive PR number before release;
the initial `null` placeholder is deliberately refused. The existing issue must
remain open. Original candidate indexes are read and protected, never changed.

The dedicated `stage-pgss-capacity.yml` workflow is main-only manual dispatch
with exactly issue 5609 and an expected main SHA. It checks out that SHA, proves
main freshness in a separate step without the Supabase credential, and performs
preview first. Production advances automatically only after a successful
same-run, same-attempt, same-source, same-plan preview receipt. This new profile
uses existing native preview-maintenance and production exclusive refs,
mutexes, generation fencing and owned release. It does not use the migration
apply lane, create an author claim, reserve a migration version, or invent a
replacement lock. The toolkit's separately governed admission must explicitly
recognize the exact committed staging profile before dispatch.

No restart is authorized, exposed or implemented. No SQL DDL/DML, statistics
reset, arbitrary setting, target, value, decrease, endpoint or caller payload is
accepted. Effective capacity remains unchanged during staging; any observed
restart, reset, identity change or runtime-capacity change refuses success.

## Vendor request and preservation

The [vendor update implementation](https://github.com/supabase/cli/blob/v2.118.0/apps/cli/src/commands/postgres-config/update/update.handler.ts)
fetches current overrides and sends their complete merged object. The vendor's
`--no-restart` behavior explicitly adds the JSON boolean
`restart_database: false`; omitting this control cannot establish staging-only
semantics. The profile therefore copies every recognized existing override,
changes only the fixed capacity key, and adds that fixed false control. Unknown
keys/types, floating-point numbers and duplicate JSON keys are refused.

The [Management API](https://supabase.com/docs/reference/api/v1-update-postgres-config)
permits a maximum capacity of 45000; this profile fixes 40000. The control field
is a request instruction, not a persisted configuration override. Returned
configuration must omit it and preserve every other prior key exactly. Nothing
silently strips an unexpected returned field.

Under the owned native fence, an exact protected-target GET runs first. A final
configuration GET must then equal the original snapshot, and its verified
contents supply the merged PUT with no intervening remote call. Native fencing
serializes cooperating governed writers. The vendor offers no compare-and-swap
contract; this does not exclude unrelated, uncoordinated control-plane clients
changing configuration after that last GET. There is one PUT at most. An
uncertain response is a failure, never an
automatic replay or stale restoration. A later independent retry re-reads state
and is idempotent if the fixed value is already stored.

## Proof and privacy

Canonical production identity is read as one literal assignment using Python
AST from `scripts/shared_db_live_proof.py`, without executing that module or
copying its protected identifier. Preview identity comes only from the current
repository variable and must differ from production. TLS uses the fixed vendor
host, redirects and environment proxies are disabled, and tokens exist only in
the staging step environment. Main-freshness steps have no Supabase token.

A fixed read-only catalog query before and after qualifies the approved read
role, transaction, database, setting context, runtime value, postmaster and
reset identities, plus four original candidate index identities. Production
must still match their November 6 OIDs/definitions. Preview must preserve its
own exact pre/post identities. All candidates must remain valid and ready.
`pending_restart` is recorded but need not be true: storage can precede reload.
The profile never activates the setting.

Only source/plan/program hashes, target fingerprints and bounded numeric/boolean
facts are written to receipts. Full configuration, API errors, tokens, project
identifiers, SQL responses and application data are not printed. The receipt is
proof of staging only; it cannot close live acceptance or authorize a restart.

## Verification

Mocked HTTP tests exercise the actual request bodies, full override preservation,
fixed false control, concurrent change refusal, target identity, role/context,
original indexes, post-state changes, unknown outcome without retry, idempotence,
receipt binding, redirect/proxy refusal and redacted errors. Native-adapter tests
cover exact merged source, main freshness, foreign ownership, expired leases and
fixed-profile refusal. No test calls a hosted service or mutates a real lock.
