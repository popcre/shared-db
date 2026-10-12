# Plan: #770 production service credentials via pre-computed SCRAM verifiers

Issue: [popcre/shared-db#770](https://github.com/popcre/shared-db/issues/770). Owner instruction
(Albert, chat, 2026-10-12, verbatim: "yes, go ahead with the reviewer check").
Registered from the #770 successor handoff
[`HANDOFF.d/2026-10-12T0008Z-edge-dev3-codex-770-recovery-production.md`](HANDOFF.d/2026-10-12T0008Z-edge-dev3-codex-770-recovery-production.md) §6 step 3.

## STATUS

Revision 2 (2026-10-12 2:30 PM EDT). Revision 1 got DeepSeek plan-review REJECT
(run 20261012T181315-1768589-27011, "method sound in principle, proof steps insufficient");
every finding is answered in "Review findings answered" below. Nothing has been executed.
Task class for execution: `ai-task-gates start --class` per the installed toolkit, then
`ai-task-gates check --before production` with `--reviewer-approval` = an exact-head APPROVE of
this plan plus the exact issuing script. No production write happens without that.

## Problem and why SCRAM verifiers are the correct control

Four runtime roles exist in production `qsllyeztdwjgirsysgai` with NULL passwords:
`designflow_prod_{backend,item_master,tracking,data_sync}_runtime`.

Fresh read-only evidence (2026-10-12 ~2:20 PM EDT, `pg_settings` via read-only user):
`log_statement=ddl`, `log_min_error_statement=error`, `log_error_verbosity=default`,
`pgaudit` not installed, `password_encryption=scram-sha-256`, PostgreSQL 17.6.

`log_statement=ddl` logs the full text of every successful `ALTER ROLE`, and
`log_min_error_statement=error` logs the text of every failing one. PostgreSQL never redacts a
password literal in either path. So a plaintext `ALTER ROLE ... PASSWORD 'x'` would be logged
**whether or not it fails**; the earlier sessions' target control (`log_error_verbosity`) does
not govern statement text at all and could never have made plaintext issuance safe. The only
way to keep a usable secret out of provider logs on this platform is to never send one: send a
pre-computed SCRAM-SHA-256 verifier. PostgreSQL documents that a password string already in
SCRAM verifier format is stored as-is (docs: CREATE ROLE, "PASSWORD"; `password_encryption`).
The earlier "SCRAM workaround" prohibition was recorded without engaging this; this plan
replaces that line for this exact action only if approved.

## Goal (unchanged)

No plaintext password, and nothing that can be used to log in, ever appears in provider logs,
client logs, argv, transcripts or Git — on success or failure.

## Method

1. **Verifier tool** — new private script `scripts/cutover/scram_verifier.py` in the existing
   private #770 designflow-backend branch (never pushed): stdlib only
   (`hashlib.pbkdf2_hmac`, `hmac`, `secrets`), RFC 5802/7677, 4096 iterations, 16-byte salt,
   output `SCRAM-SHA-256$4096:<b64 salt>$<b64 StoredKey>:<b64 ServerKey>`. Reads the password
   only from an inherited file descriptor; never argv/env/stdout. Unit tests against RFC 7677
   test vector and libpq output.
2. **Password generation and custody** — 32 random bytes from `secrets`, base64url, generated
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
   Before the write: prove target (`current_database`, `inet_server_addr` absent on pooler,
   pinned CA verify-full, project ref assertion), and read the pre-state through the existing
   format-only `CASE` probe recorded on 2026-10-08 (all four NULL).
5. **Production write** — one transaction: four `ALTER ROLE <role> PASSWORD '<verifier>'`
   statements for exactly those roles; commit. The only text that can reach logs is four
   verifiers.
6. **Production post-check (in place of unreadable `pg_authid`)** — `postgres` is not superuser,
   so `rolpassword` is not readable. Proof is behavioural: for each role, (a) direct-port
   login with the plaintext over SCRAM succeeds; (b) wrong password fails; (c) **blocking
   gate:** login through Supavisor pooler port 6543 succeeds. The 2026-10-08
   `SUPAVISOR_AUTH_QUERY_SECRET_FORMAT` classification occurred when all four passwords were
   NULL (auth query found no secret); this gate proves it is gone. Any failure = undo.
7. **Log proof on production** — query provider Postgres logs through the supported Supabase
   log API for the issuance window: the four `ALTER ROLE` lines contain only `SCRAM-SHA-256$`
   verifiers; searching each plaintext (digest-compared locally, never sent as a query term in
   clear — search by verifier salt and compare locally) returns zero hits.
8. **Undo** — `ALTER ROLE <role> PASSWORD NULL` for the four roles returns exactly to the
   proved pre-state (all NULL); run automatically if any step-6 gate fails, then re-run the
   format-only probe to show NULL again.

## Why a logged verifier is not a usable secret

SCRAM login needs ClientKey; the verifier holds StoredKey = H(ClientKey) and ServerKey only.
Offline guessing of a 256-bit random password through 4096-iteration PBKDF2 is infeasible.
ServerKey would allow impersonating the server, but all four services pin the Supabase root CA
with `rejectUnauthorized: true` (`config/database-pool.js:54` in designflow-backend,
-item-master, -tracking, and -data-syncing `develop`), and each `database-connection-contract.js`
refuses Supabase without `DB_SSL=true`. Server impersonation therefore also requires defeating
verified TLS.

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

## Question for the reviewer

Does this plan meet the privacy goal, and are the proof gates sufficient to authorize writing
the verifier script and running steps 3–8? APPROVE or name the specific remaining gap.

Posted by Claude chat 16164463-0b2e-4ea7-a039-2d3d59cd5d21 on edge-dev3
