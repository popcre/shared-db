# Plan: #770 production service credentials via pre-computed SCRAM verifiers

Issue: [popcre/shared-db#770](https://github.com/popcre/shared-db/issues/770). Owner instruction
(Albert, chat, 2026-10-12, verbatim: "yes, go ahead with the reviewer check").
Registered from the #770 successor handoff
[`HANDOFF.d/2026-10-12T0008Z-edge-dev3-codex-770-recovery-production.md`](HANDOFF.d/2026-10-12T0008Z-edge-dev3-codex-770-recovery-production.md) §6 step 3.

## STATUS

Revision 4. Revisions 1, 2 and 3 got DeepSeek plan-review REJECT (runs
20261012T181315-1768589-27011, 20261012T181704-2222882-23133 and
20261012T182121-2343611-840, all "method sound in
principle"); every finding is answered below. Nothing has been executed.

**Task classes.** Stage A runs in the private designflow-backend #770 worktree under
`ai-task-gates start --class private-evidence --base 8afda0edfae275b6c85e9827c67483fd180f711f`
(the class the v23 rehearsal used). Stage B redeclares at whatever class
`ai-task-gates explain` reports for the production action and passes
`ai-task-gates check --before production`; a refusal stops the work.

**Two-stage authority.** An APPROVE of *this plan* authorizes only stage A: writing the private
verifier/issuer script and running steps 1–3 (isolated, no production). Stage B (steps 4–8, the
production write) requires a **second** exact-input APPROVE whose packet binds this plan's
commit and the issuer script by SHA-256 (path, commit and digest recorded in this file's
STATUS before that review), then `ai-task-gates check --before production
--reviewer-approval <that report>`. The production action executes only the script bytes whose
digest matches.

## Problem and why SCRAM verifiers are the correct control

Four runtime roles exist in production `qsllyeztdwjgirsysgai`, all `rolcanlogin=true`:
`designflow_prod_{backend,item_master,tracking,data_sync}_runtime`. Their passwords were
classified NULL on 2026-10-08 by user `postgres`; that is history and is re-proved in step 4.
Read-only evidence 2026-10-12: `postgres` holds `SELECT` on `pg_catalog.pg_authid` and
`pg_shadow` (`has_table_privilege`), so pre- and post-state are directly provable.

Fresh read-only evidence (2026-10-12, between the revision 1 and revision 3 commits;
`pg_settings` via `supabase_read_only_user`): `log_statement=ddl`,
`log_min_error_statement=error`, `log_error_verbosity=default`, `log_duration=off`,
`log_min_duration_statement=-1`, `log_min_duration_sample=-1`,
`log_transaction_sample_rate=0`, `log_{statement,parser,planner,executor}_stats=off`,
`auto_explain.log_min_duration=10000`, `pgaudit` preloaded but `pgaudit.log=none` and extension
not created, `pg_stat_statements.track=top` with `track_utility=on`,
`password_encryption=scram-sha-256`, PostgreSQL 17.6. Statement-text sinks are therefore: the
server log (`log_statement`, `log_min_error_statement`), `pg_stat_statements`, and the
transient `pg_stat_activity.query` of the issuing session (visible only to `postgres` and
`pg_read_all_stats` members while the statement runs). The Management API is not used for
this action, so it is not a sink. Every sink can only ever contain what was sent: verifiers.

`log_statement=ddl` logs the full text of every successful `ALTER ROLE`, and
`log_min_error_statement=error` logs the text of every failing one. PostgreSQL never redacts a
password literal in either path. So a plaintext `ALTER ROLE ... PASSWORD 'x'` would be logged
**whether or not it fails**; the earlier sessions' target control (`log_error_verbosity`) does
not govern the `log_statement=ddl` success-path line (TERSE only drops some failure-context
detail), so it could never have made plaintext issuance safe. The only
way to keep a usable secret out of provider logs on this platform is to never send one: send a
pre-computed SCRAM-SHA-256 verifier. PostgreSQL documents that a password string already in
SCRAM verifier format is stored as-is (docs: CREATE ROLE, "PASSWORD"; `password_encryption`).
**Decision requested of the reviewer (not assumed).** Codex Root sessions recorded "no ...
SCRAM verifier workaround" (`HANDOFF.d/2026-10-09T0400Z-...:66`,
`HANDOFF.d/2026-10-12T0008Z-...:71`). The same line states the gate that would satisfy them:
"provider-scoped fatal/error redaction or documented equivalent preserving native/audit/stats,
tested with DUMMY fatal/error proof, plus independent exact-plan APPROVE". This plan claims to be
that documented equivalent: logging, audit and statistics stay untouched (nothing is
reduced), and steps 3 and 7 are the DUMMY failure/success proofs on real PG17 and on
production. Whether that equivalence holds is the reviewer's explicit decision; the handoffs
stay immutable and the decision is recorded here and on #770.

## Goal (unchanged)

No plaintext password, and nothing that can be used to log in, ever appears in provider logs,
client logs, argv, transcripts or Git — on success or failure.

## Method

1. **Verifier tool** — new private script `scripts/cutover/scram_verifier.py` in the existing
   private #770 designflow-backend branch (never pushed): stdlib only
   (`hashlib.pbkdf2_hmac`, `hmac`, `secrets`), RFC 5802/7677, 4096 iterations, 16-byte salt,
   output `SCRAM-SHA-256$4096:<salt>$<StoredKey>:<ServerKey>` with **standard base64 (RFC 4648
   §4, `+/` and `=` padding)** for all three fields, which PostgreSQL's verifier parser
   requires. Reads the password only from an inherited file descriptor; never
   argv/env/stdout. Unit tests against the RFC 7677 test vector and libpq
   `PQencryptPasswordConn` output.
   **Guard tests (stage A deliverable):** accept the tool's own output; reject base64url
   alphabet, missing padding, wrong padding, non-canonical padding bits, salt not 16 bytes,
   key not 32 bytes, wrong iteration count, wrong prefix, tampered StoredKey/ServerKey,
   trailing whitespace/newline, and a raw password string; plus an end-to-end test proving a
   rejected verifier never opens a database connection (connection factory spy).
   **Fail-closed send guard:** immediately before step 5 every verifier must match
   `^SCRAM-SHA-256\$4096:[A-Za-z0-9+/]{22}==\$[A-Za-z0-9+/]{43}=:[A-Za-z0-9+/]{43}=$`, decode to
   16/32/32 bytes, and recompute byte-identical from the plaintext and decoded salt; any
   mismatch aborts before a connection opens (a malformed string would be hashed as plaintext
   and its literal logged).
2. **Password generation and custody** — 32 random bytes from `secrets`, encoded base64url
   (this is the password itself, not a verifier field), generated
   inside the same protected process, written to the existing staged 1Password items in vault
   `vibe_coding` through the 1Password SDK/`op` reading from stdin (never argv), serialized
   under the existing op-access lock. Read back and compare digest only.
3. **Isolated byte-equality proof (real PG17, superuser, network-isolated bwrap like the #770
   rehearsal)** — create a test role, `ALTER ROLE ... PASSWORD '<verifier>'`, read
   `pg_authid.rolpassword`, assert byte-equal to the verifier; then log in with the plaintext
   over SCRAM and succeed; log in with a wrong password and fail. Also capture the server log
   with `log_statement=ddl` and `log_min_error_statement=error` and prove only the verifier
   (never the plaintext) appears, for one success and one forced failure.
4. **Production issuer** — role `postgres` via the vault production admin item. Read-only
   evidence: `postgres` has `CREATEROLE` and `ADMIN OPTION` on all four runtime roles
   (`pg_auth_members`, 2026-10-12), which PostgreSQL 17 requires for `ALTER ROLE ... PASSWORD`.
   Before the write: prove target (`current_database`, pinned CA verify-full, project ref
   `qsllyeztdwjgirsysgai` assertion). **Pre-state proof:** a format-only query over
   `pg_authid` returning, per role, only `CASE WHEN rolpassword IS NULL THEN 'NULL' WHEN
   rolpassword LIKE 'SCRAM-SHA-256$%' THEN 'SCRAM' ELSE 'OTHER' END`. All four must be `NULL`;
   otherwise stop before any write (an existing credential would be overwritten
   irrecoverably). Because the pre-state is proved NULL, undo to NULL is an exact restore.
   **Log-access preflight:** before the write, read one recent window of provider Postgres
   logs through the supported Supabase log API and confirm entries are returned; if not, stop
   before the write.
5. **Production write** — one transaction: four `ALTER ROLE <role> PASSWORD '<verifier>'`
   statements for exactly those roles; commit. The only text that can reach logs is four
   verifiers.
6. **Production post-check** — (0) for each role read only
   `encode(sha256(convert_to(rolpassword,'UTF8')),'hex')` from `pg_authid` and assert it equals
   the locally computed SHA-256 of that role's verifier (proves verbatim storage without
   echoing the verifier); then (a) direct-port
   login with the plaintext over SCRAM succeeds; (b) wrong password fails; (c) **blocking
   gate:** login through Supavisor pooler port 6543 succeeds. The 2026-10-08
   `SUPAVISOR_AUTH_QUERY_SECRET_FORMAT` classification occurred when all four passwords were
   NULL; the inference (not proven) is that the auth query found no secret. This gate proves
   or disproves it. The pooler presents the same Supabase-rooted chain: the 2026-10-08
   credential-free probe completed TLS 1.3 verify-full against the pinned root on the pooler
   (`HANDOFF.d/2026-10-09T0400Z-...:60`), and each run of 6(c) uses verify-full with that
   pinned CA. Any failure = undo.
7. **Log proof on production** — fetch the **entire** provider Postgres log window from
   1 minute before the transaction to 5 minutes after (well inside retention) through the
   supported log API into protected custody, and scan it locally. **Positive control first:**
   exactly four `ALTER ROLE` statement lines for the four roles must be present (retry the
   fetch every 60 s for up to 15 minutes to absorb ingestion lag). Then: each plaintext occurs
   zero times; each of those lines contains its verifier and nothing password-like. Also read
   the `pg_stat_statements` row(s) for `ALTER ROLE`: at least one row must exist; record its
   stored text form (verbatim verifier or normalized `$1`) and scan it the same way. If the
   positive control is not met in 15 minutes, or the window cannot be fetched in full, the
   proof is failed: step 8 undo runs (fail closed), then stop.
8. **Undo** — `ALTER ROLE <role> PASSWORD NULL` for the four roles returns exactly to the
   step-4 proved pre-state (all NULL); runs automatically if any step-6 or step-7 gate fails,
   then the step-4 format-only `pg_authid` query must show all four `NULL` again.

## Why a logged verifier is not a usable secret

SCRAM login needs ClientKey; the verifier holds StoredKey = H(ClientKey) and ServerKey only.
Offline guessing of a 256-bit random password through 4096-iteration PBKDF2 is infeasible.
**Load-bearing residual:** someone holding StoredKey + ServerKey who can also act as the server
to a client (man-in-the-middle) can recover ClientKey from that client's proof and then log in.
So a logged verifier is safe only while every client verifies the server certificate. All four
services pin the Supabase root CA
with `rejectUnauthorized: true`, each in its own repository's `config/database-pool.js` line 54
(`popcre/designflow-backend` 9402a88f0, `popcre/designflow-item-master` 4aa6850c,
`popcre/designflow-tracking` e88793a0 — all `sandbox-albert`; `popcre/designflow-data-syncing`
c88a43d on `develop`), and each repository's `config/database-connection-contract.js`
refuses Supabase without `DB_SSL=true` (source verified at those commits on 2026-10-12).
**Stage B blocking gate:** re-verify this pinning in the exact image/commit each service will
run against Supabase, and refuse stage B if any service does not verify. (The
`fix_connection_pool.md` "SSL off" note describes the current private-VPC Cloud SQL path, not
the Supabase path.) The issuing and proof clients in this plan also use verify-full with the
pinned CA.

## Success check

All four roles authenticate directly and through Supavisor with their 1Password secrets; wrong
passwords fail; provider logs show only verifiers; logging settings unchanged; the separately
closed credential incident untouched.

## Not in scope

Cutover, PITR, writer fencing, app business acceptance, any logging change, any unsupported
API setter.

## Review findings answered (revision 1 → 2)

1. Byte-equality proved on real PG17 (step 3); production uses behavioural login proof (step 6).
2. Supavisor login is now a blocking gate with the prior observation explained (step 6c).
3. Plan now targets the correct controls (`log_statement=ddl`, `log_min_error_statement`) with
   fresh evidence, and the log proof covers success and failure (steps 3, 7).
4. TLS mode verified for all four services (section above).
5. Undo defined and automatic (step 8).
6. Issuer privilege proved read-only (step 4).
7. Assertion named: behavioural, because `pg_authid` is superuser-only (step 6).
8. Tool and custody specified, no argv exposure (steps 1–2).
9. Registered from the successor handoff; task class and gate stated (STATUS).
10. Prior reason engaged: plaintext issuance is unsafe under `log_statement=ddl` regardless of
    error verbosity (Problem section).
11. STATUS section added.

## Revision 2 → 3 findings answered

1. Pre-state no longer relied on; undo sets explicit NULL (step 4, step 8).
2. Whole-window local scan, retention bound, log-access preflight, fail-closed undo (steps 4, 7).
3. Fail-closed verifier grammar/round-trip guard before send (step 1).
4. Prohibition provenance and supersession authority stated (Problem section).
5. Stage B binds script by SHA-256 (STATUS).
6. Two-stage authority stated (STATUS).
7. TLS evidence cited per repository and commit.
8. All statement sinks enumerated, `pg_stat_statements` added to the proof.
9. `log_error_verbosity` wording corrected.
10. Base64 alphabets explicit.
11. Timestamps replaced by commit-relative provenance.
12. Supavisor cause labelled an inference.

## Revision 3 → 4 findings answered

H1/M2: `postgres` can read `pg_authid` (proved); pre-state NULL is required and proved, undo is
exact. H2: positive control with bounded retry. M3: guard tests listed. M1/L2: residual stated
precisely, pinning is a stage-B blocking gate, pooler TLS cited. M4: equivalence is now an
explicit reviewer decision. M5: task classes stated. L1: LOGIN flags proved. L3: row must
exist, stored form recorded. L4: registered in `docs/agents/active-contracts-and-plans.md`.
L5: `pg_stat_activity` and Management API addressed.

## Question for the reviewer

Decide explicitly whether this is the "documented equivalent" the handoff gate asks for.
Does this plan meet the privacy goal, and does it justify stage A (script + isolated steps
1–3 only)? APPROVE or name the specific remaining gap. Stage B is reviewed separately.

Posted by Claude chat 16164463-0b2e-4ea7-a039-2d3d59cd5d21 on edge-dev3
