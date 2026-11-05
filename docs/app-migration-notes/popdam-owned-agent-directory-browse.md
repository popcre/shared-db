# PopDAM owned agent directory browsing (#5652 / PopDAM #468)

Status: prepared backend only. Production promotion and dependent edge/frontend
cutover remain with the coordinator. No existing global request/result row is
rewritten or removed by this migration. Never cut over a pending legacy request
until its actual owner has drained it and protected preimages are captured.

`dam.agent_directory_browse_requests` is private transient history. Only five
service-role RPCs expose its state. The authenticated admin edge API supplies the
verified actor; authenticated agent routing supplies the target agent identity.
Browser callers never receive direct table or RPC privileges.

- Admission takes agent UUID, client request UUID, verified actor UUID, and text
  path. Empty, Unicode and UNC paths remain supported. It returns `admitted`,
  `idempotent`, or `busy`. A retry is idempotent only for the identical tuple;
  UUID collisions raise `22023`. Busy never exposes another actor's details.
- Each supported bridge or Windows-render agent has at most one pending/claimed
  request. The unique partial index fences concurrent insertions. The absolute
  deadline is 120 seconds, independent of client polling.
- Claim returns the existing `{request_id,path}` wire object or null. A 30-second
  delivery lease allows the same authenticated agent to retry a lost delivery.
- Completion matches exact request and authenticated target, claimed state and
  absolute deadline. It preserves the stored original path and every valid
  entry/additional field. Entries must be objects with string `name` and boolean
  `is_dir`. Identical completion retries return true without changing first
  results; conflicting duplicates, wrong-agent and stale/cancelled reports fail.
- Result reads require the verified actor and normally an exact UUID. A null UUID
  is a cached-old-UI compatibility adapter returning ONLY that actor's newest
  request, deterministically ordered by requested time then UUID. No global
  fallback exists. Retire this adapter with T9 after coordinator verification
  that cached old clients have drained and ordinary UI callers all send UUIDs.
- Cancellation affects only the verified actor's exact pending/claimed request.
- Admission cleans at most 100 terminal rows older than 24 hours for its own
  agent, using the cleanup index. Agent unpair and user removal cascade transient
  history; no user or agent deletion is blocked by browse records.

Disposable tests include actual two-session overlapping transactions: one session
holds its inserted winner uncommitted, another waits on a real lock, then returns
busy after the winner commits. The test fails if no overlap is observed. Shared
or production databases must never be used for these fixtures. Normal invitation
signup triggers remain enabled; fixtures are rolled back or explicitly removed
on both success and error for cross-session committed fixtures.

No scan, render, tagging, asset or existing admin_config object changes. No agent
update is required. Backend promotion precedes dependent caller edits; production
acceptance remains open until ordinary selected-agent browsing is proved live.

Test-runner custody: the ordinary functional suite runs as the normal default
contract-test role, and explicitly exercises service_role, anon and authenticated.
Only the concurrency filename uses the workflow's existing disposable
`supabase_admin` whitelist. Default `postgres` refuses passwordless dblink with
“Non-superusers must provide a password in the connection string or send
 delegated GSSAPI credentials.” The existing disposable superuser route avoids
new passwords, role grants, `dblink_connect_u`, or any production/runtime change.
The extension is test-only. Both competitor sessions disconnect before committed
fixtures are removed, including the normally retained app.profile history and
its dependent access/role rows. Success and exception cleanup assert zero residue.


Forward version continuity: prior unapplied reservation `20261105065814` remains permanently preserved. Both current preview and production ledgers were checked before the atomic forward reservation `20261105151428`; previous exact-head CI remains historical evidence, while the renamed source requires fresh checks. No legacy payload cleanup or caller cutover is performed by this migration.
