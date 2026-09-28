# Isolated destination for the #770 / #771 production-copy rehearsal (issue #3689)

Status: PLAN — awaiting one allocator-assigned AI reviewer APPROVE on this exact text.

## Choice

A disposable, local PostgreSQL **17** cluster on the machine `edge-dev3`.
No new cloud or production infrastructure is created: no Terraform, no `gcloud`
mutation, no Supabase project, no Cloud SQL instance.

Why 17: the source, Cloud SQL `creatiflow-database` (project `lithe-breaker-323913`),
runs PostgreSQL 17.9 (docs/verification/cloudsql-designflow-capture-2026-08-10).
A same-major destination keeps `pg_dump`/`pg_restore` timings representative.

Size: the source is ~580 MB of relations (#770, refreshed 2026-09-04); edge-dev3
has ~1.7 TB free. A `designflow`-schema copy needs no non-core extension; if the
restore reports a missing extension, that is recorded on #771 and the rehearsal
stops rather than widening this plan.

## Install route (project-owned, no system change)

- edge-dev3 is Ubuntu 26.04, which ships only PostgreSQL 18; there is no docker and no sudo.
- PostgreSQL 17 server binaries come from the official PostgreSQL project apt
  repository (apt.postgresql.org, PGDG), fetched as `.deb` files, verified
  against the PGDG signing key, and unpacked with `dpkg -x` into the
  user-owned directory `~/pg-rehearsal-3689/pg17/`. Nothing is installed
  system-wide and no OS binary is replaced.

## Isolation and visibility

- Listens on `127.0.0.1` only, port `55432`; Unix socket inside the private
  data directory; `pg_hba.conf` allows only `host all all 127.0.0.1/32
  scram-sha-256` and local-socket `scram-sha-256`.
- No production application, service account, or credential is configured to reach it,
  and it stores no production credentials. The rehearsal reads Cloud SQL with
  the existing read-only 1Password item and writes here.
- Who can read: only OS user `ahazan` on edge-dev3 (data directory mode 0700),
  i.e. AI sessions on edge-dev3 working #770/#771.

## Encryption at rest

The root disk is plain ext4, so the data directory lives inside a `gocryptfs`
encrypted directory (`~/pg-rehearsal-3689/cipher` mounted at
`~/pg-rehearsal-3689/plain`). The gocryptfs passphrase and the database
superuser password are generated into 1Password vault `vibe_coding` (item
"shared-db 3689 rehearsal destination edge-dev3") and move only through
pipes / `op_run`; they are never printed.

## Retention and deletion rule

Delete when the #770/#771 copy rehearsal records its result, and in any case
no later than **2026-10-31 11:59 PM EDT**. Deletion = stop the cluster,
unmount gocryptfs, `rm -rf ~/pg-rehearsal-3689`, archive the 1Password item,
and post proof (directory absent, port 55432 closed) on #3689 and #770.
No copy of the data may leave edge-dev3.

## Proof of creation (to post on #3689)

`pg_ctl status`, `SELECT version()` showing 17.x, `ss -ltn` showing only
127.0.0.1:55432, a create/insert/select/drop round-trip, and the mount line
showing the data directory on the gocryptfs mount.

Posted by Claude chat 1b699f56-bfb1-4801-a2b9-db91edbc98f6 on edge-dev3
