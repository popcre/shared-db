# Plan: #770 production service credentials via pre-computed SCRAM verifiers

Issue: [popcre/shared-db#770](https://github.com/popcre/shared-db/issues/770). Owner instruction (Albert, chat, 2026-10-12): "yes, go ahead with the reviewer check".
Status: PROPOSAL FOR INDEPENDENT REVIEW. Nothing in this plan has been executed.

## Problem

Four DesignFlow runtime roles (backend, item-master, tracking, data-syncing) exist in production
Supabase with NULL passwords. Earlier sessions required that a password-setting statement can
never place a usable secret in provider PostgreSQL error/statement logs, and tried to satisfy that
by setting `log_error_verbosity` (and related controls) for the issuing session. On hosted
Supabase that control is outside the supautils allowlist, not grantable, and not in the
Management API configuration schema (proved read-only 2026-10-11 7:39 PM EDT). Those sessions
also listed "SCRAM workaround" as forbidden without recording a reason. This plan asks a reviewer
to judge the SCRAM verifier route on its merits against the actual goal.

## Goal (unchanged)

No plaintext password, and nothing that can be used to log in, ever appears in provider logs,
client logs, argv, transcripts or Git — even if the issuing statement fails.

## Proposed method

1. For each role, generate a fresh random password (>= 32 bytes from a CSPRNG) inside protected
   custody and store it in 1Password vault `vibe_coding` (existing staged service items).
2. Compute the PostgreSQL SCRAM-SHA-256 verifier locally from that password
   (`SCRAM-SHA-256$4096:<salt>$<StoredKey>:<ServerKey>`, RFC 5802/7677, same algorithm as libpq
   `PQencryptPasswordConn`). Only the verifier leaves custody.
3. In one guarded transaction against the proven production target (verified TLS, target ref
   assertion), run `ALTER ROLE <role> PASSWORD '<verifier>'` for exactly the four roles, assert
   4 rows changed in `pg_authid`-visible state (via `rolpassword IS NOT NULL` through the
   permitted view), commit.
4. PostgreSQL stores a string already in SCRAM verifier form verbatim; it is never treated as a
   plaintext password. Anything logged on success or failure is therefore the verifier only.

## Why a logged verifier is not a usable secret

- SCRAM login requires the client to prove knowledge of ClientKey; the verifier contains only
  StoredKey = H(ClientKey) and ServerKey. Neither lets an attacker log in.
- The residual is an offline guessing attack on the verifier (4096 PBKDF2 iterations). With a
  >= 256-bit random password this is computationally infeasible.
- ServerKey would let someone impersonate the *server* to a client; clients use verified TLS to
  the pinned Supabase CA, so server impersonation also requires breaking TLS.

## Proof before production (DUMMY test)

On the isolated rehearsal target (never production) and then once on production with a
throw-away role-free statement:
- Run an `ALTER ROLE` with a DUMMY verifier that is designed to fail (non-existent role), then
  read provider logs via the supported Supabase log API and show only the DUMMY verifier string
  appears, never a plaintext.
- Confirm Supavisor (pooler) authenticates a role whose password was set as a verifier
  (Supavisor's auth query reads the stored SCRAM secret).

## Success check

All four services authenticate through the pooler with their 1Password credentials; provider
log search for each plaintext returns zero hits; logging controls unchanged; no rotation of the
separately closed credential incident.

## Not in scope

Production cutover, PITR, writer fencing, app acceptance. No logging reduction, no unsupported
API setter, no change to the closed incident.

## Question for the reviewer

Does the SCRAM verifier method meet the stated privacy goal as well as or better than the
unavailable `log_error_verbosity` control? APPROVE only if yes and the DUMMY proof steps are
sufficient; otherwise state the specific gap.

Posted by Claude chat 16164463-0b2e-4ea7-a039-2d3d59cd5d21 on edge-dev3
