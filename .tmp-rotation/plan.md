# Production DB password rotation plan — v10 (SIMPLE)

Incident: on 2026-10-02 a subagent URL-embedded the production database password
in a psql argv; the error printed it into a local transcript (machine edge-dev only;
swept: zero file hits, not on GitHub, not in chat). Standing rule: exposed =
compromised; the AI rotates it under the assigned AI reviewer's plan-review APPROVE
(owner rulings 2026-08-13 §0.0-B context, 2026-09-28 "never ask a human to approve").
Authority card: issue #3853 (non-orchestrator).

**Why v10 is deliberately small.** v9 (and its successors through 71 review rounds,
ended 2026-10-03 6:48 PM EST) tried to be a self-driving automation suite; the
document grew too complex to converge and no APPROVE ever closed. The recorded
lesson: a much simpler plan finishes this. This plan is executed by the coordinator
session step by step; it contains ONE eight-line helper for connection probes and
ONE for password generation, and every lesson from the 9 + 71 rounds is baked into
the steps below rather than re-litigated.

## 1. Inventory — verified live 2026-10-05 ~12:30 PM EST (re-verify at step 1; abort on drift)

- Supabase project (production): ref `qsllyeztdwjgirsysgai` ("shared POP database").
- 1Password vault `vibe_coding` (id `pimcaogmxxzoafh7lsluj6uxkq`, resolved live):
  - **Exposed credential**: item "Supabase DB Password - shared POP database", id
    `246sf23gymd64yudpmhswcnyle`, one concealed `password` field, notes empty
    (last updated 2026-09-09 — predates the incident, so the current value IS the
    exposed one).
  - PAT for the provider PATCH: item "Supabase CLI Personal Access Token", id
    `3t2xoqk5luyz7ffgdhj24gvtpq`, concealed field `SUPABASE_ACCESS_TOKEN`.
- GitHub secrets in popcre/shared-db that derive from the rotated value (BOTH must
  be re-set in the same operation): `SUPABASE_DB_PASSWORD_PRODUCTION` (password
  form), `SUPABASE_DB_URL_PRODUCTION` (pooler URL form embedding the same password).
  ENVIRONMENT-SCOPE CHECK (measured 2026-10-06 ≈5:40 AM EST; asserted again
  at step 1): `GET /repos/popcre/shared-db/environments/production/secrets`
  returns `{"total_count":0}` — the `production` environment defines NO
  secrets, so jobs with `environment: production` that read
  `secrets.SUPABASE_DB_PASSWORD_PRODUCTION` resolve the REPO-level secret
  (an environment secret shadows a repo secret only when defined; none is).
  Step 1 asserts every environment's secret list (production, preview,
  designflow-sandbox) is EMPTY; any entry naming a DB credential is a STOP —
  a shadow would survive the repo-secret rotation. The proofs 10a/10b
  therefore exercise the same credential those production jobs read.
  `SUPABASE_DB_PASSWORD_PREVIEW` is a DIFFERENT credential (preview project) and is
  NOT touched. `SUPABASE_ACCESS_TOKEN` (repo secret) is the PAT, not the DB
  password, and is NOT touched.
- Workflow files on current main that CONSUME either production secret (nine —
  the freeze list; a tenth file, `database-contract-tests.yml`, mentions
  `SUPABASE_DB_PASSWORD_PRODUCTION` only inside its own absence self-check at
  line 189 and is forbidden by design from touching any shared database, so it
  is NOT frozen): coldlion-history-backfill (URL×3), coldlion-landing-sync
  (URL×4), coldlion-licensor-property-production (PW×7),
  coldlion-order-intake (URL×4), coldlion-prepack-backfill (URL×3),
  coldlion-prod-detail-backfill (URL×3), production-catalog-verification-recovery
  (PW×1, real env mapping line 62), shared-db-live-proof (PW×1, real env mapping
  line 56), shared-supabase-migrations (PW×6).
- Consumer repos hold NO copy of this password (checked 2026-10-05 via gh api):
  u2giants/popdam3 (PAT + URL + service key only), popcrm-web (anon key),
  poppim-web (anon key), popcre/designflow-* (none).
- Tooling on this machine: `psql` 18.6 (scoop) — NOT used for mutations, only
  availability note; `pg` 8.23.0 at
  `C:/repos/dflow_plm/designflow-item-master/node_modules` (the v9 fallback
  checkout `designflow-backend/node_modules` no longer exists — this plan pins the
  item-master checkout and verifies it loads at step 2).
- Provider mutation endpoint (lesson 1, cost one review round in v9): Management
  API `PATCH https://api.supabase.com/v1/projects/qsllyeztdwjgirsysgai/database/password`
  (verb PATCH; v9 burned a round on PUT-vs-PATCH — do not re-derive the verb).

## 2. Preconditions (all must be true before step 3)

- P-1. Hardening PR #3938 is MERGED on main (PG* env transport; no credential in
  argv anywhere in the coldlion tools). No rotation step runs before this.
- P-2. This plan has an `ai-review codex plan-review --implementer zcode`
  APPROVE bound to the EXACT BYTES of the reviewed set: plan.md, gen.mjs,
  probe.mjs, closure.mjs, sanitize.mjs, and the side-car digests.txt (which lists each
  reviewed file's sha256 and nothing else — appending digests to the plan
  itself would be self-referential). THE BINDING IS CONTENT-ADDRESSED ON
  GITHUB (issue comments are EDITABLE, so a comment proves nothing about
  post-approval bytes): before the APPROVING round, the five files +
  digests.txt are COMMITTED to the branch `rotation-plan-v10` and pushed;
  the review round runs against THAT COMMIT's checked-out content; the
  commit SHA — the content's own address — is recorded in the APPROVE
  report and asserted by step 1 (`git rev-parse origin/rotation-plan-v10`
  unchanged; each file's sha256 equals its committed blob's). The branch is
  pushed BEFORE the APPROVING round and stays pushed: the reviewed bytes
  are the committed bytes (round 28's MANIFEST correctly saw untracked
  files — the branch rotation-plan-v10 IS pushed and its head at APPROVE time is the reviewed packet (a SHA recorded in its own text would be self-referential after any amend, exactly like digests.txt — so the binding SHA is quoted in the #3853 comment and the APPROVE report, which postdate the final push; the working files' digests must MATCH their committed blobs, verified now and re-verified at step 1).
- P-3. The pinned pg module at
  `C:/repos/dflow_plm/designflow-item-master/node_modules/pg` is BOTH loaded
  (`node -e "require(...)"` exits 0) and INTEGRITY-PINNED as a WHOLE PACKAGE:
  a deterministic recursive digest over every file under `node_modules/pg`
  AND its runtime dependency closure, resolved at execution by the closure
  script in the review packet by starting at `pg` and walking each INSTALLED
  package's own `dependencies` map transitively (visited set for cycles); the
  script exits nonzero naming any resolved dependency directory that does not
  exist, so the set is DERIVED from the installed tree, never hand-listed,
  and computed as
  `sha256(concat(sorted(relpath + ':' + sha256(file))))`. The EXPECTED digest
  is pre-recorded here and re-verified at step 2 before any secret reaches
  the library: **pg-closure-digest
  9f32c3cc7f48a67b8283189805648119ea901867e961d4f99e3cf3ea9e1470a0 over 138
  files, 14 packages (resolution via createRequire.resolve from inside pg —
  exports-mapped packages resolve their main entry and walk up to the named
  package root, so NESTED node_modules layouts hash exactly what require()
  loads; a nested+exports synthetic layout test PASSES: the nested 2.0.0
  copy resolves, not the hoisted 1.0.0; visits are keyed by RESOLVED
  DIRECTORY so same-named dependencies at different paths are all hashed;
  installed optionalDependencies are hashed, absent ones skipped — the one
  fail-open direction npm itself defines)** (computed 2026-10-05 8:24 PM EDT with the closure script whose
  bytes are in the review packet). Two-file pins do not cover the code a
  library actually executes.
- P-4. PAT liveness: `GET /v1/projects/qsllyeztdwjgirsysgai` with the PAT returns
  200 (also proves network + auth before any mutation).
- P-5. Old-value preflight proof: a probe connection with the CURRENT vault
  password succeeds, and the URL form is the ONE form the runbook documents
  (`docs/agents/runbooks-credentials-cli-and-gotchas.md:43-47`): the pooler
  `postgresql://postgres.<ref>:<pw>@aws-1-us-east-1.pooler.supabase.com:6543/postgres`.
  No direct-host or generic-user fallback is attempted; if the pooler form
  does not connect, that is a STOP condition (the secret's URL form must be
  re-derived from the vault evidence, not guessed). The form that connects is recorded (fingerprint only)
  and reused verbatim for the new secret. A deliberately-wrong password probe MUST
  return exactly error code `28P01` — this is the probe's self-test (it proves the
  classifier works before it is asked to classify the real rejection later).
- P-6. TLS: the Amazon RDS global CA bundle
  (`https://truststore.pki.rds.amazonaws.com/global/global-bundle.pem`) is
  downloaded once to `C:/Users/ahazan/.tmp-rotation/rds-global-bundle.pem`; its
  sha256-16 is recorded. Probes verify the server chain fully
  (`rejectUnauthorized: true`); a missing bundle fails closed (v9 review lesson:
  verification-off was rejected).
- P-7. Scratch-directory hygiene (Windows): the scratch dir
  `C:/Users/ahazan/.tmp-rotation/` is created by the plan (it does not pre-exist);
  `icacls` must show ONLY the owner, SYSTEM, and Administrators with access
  (inheritance from the user profile is fine; any other ACE → STOP). Cleanup
  (step 12) removes the EXACT named files this plan created — the ONE
  authoritative list is step 12's (conditional value-<label>.txt files;
  unconditional secret-bearing intermediates; success-only non-secrets) —
  never a wildcard `rm -rf` of anything shared.

## 3. Steps (in order; one mutation phase; never auto-retry a production action)

Step 0 (before ANY production mutation): run
`ai-task-gates start --class production` from the executing worktree and then
`ai-task-gates check --before production-database-password-rotation`; both
outputs are recorded with the evidence. If the gate reclassifies or refuses,
the plan stops there (AGENTS.md task-declaration rule; never worked around).

Secrets move ONLY through: 0600 files under `C:/Users/ahazan/.tmp-rotation/`
(NTFS: user-profile path; `chmod 600` is a no-op on Windows — the plan relies on
the user-profile ACL, and the files are deleted at step 12), process env, or
`op://` references. NEVER argv, never command text, never MCP tool parameters,
never chat. Fingerprints are sha256, first 16 hex chars, printed only.

1. **Re-inventory and scratch setup**: re-run the §1 scans (gh api secrets
   list; workflow-file grep on current main; vault item ids; AND the §1
   environment-scope check — every environment's secret list must be empty). Any drift from
   §1 → STOP, re-review, do not improvise. Then create the scratch directory
   and EXECUTE P-6 (download the RDS CA bundle, record its sha256-16) and P-7
   (icacls check) — they are conditions of this step, not background
   assumptions. The complete file set the plan will create is (the SAME list
   step 12 deletes, with the same conditions): value-<label>.txt files
   (conditional: deleted only when that value's death is 28P01-proven or a
   successor completes — a live value's file is the only recoverable copy
   and is retained-with-reason on any stop); ALWAYS deleted on every exit:
   patch-body.json, patch-response.json, auth-header.txt, secret-pw.txt,
   secret-url.txt, notes.txt, item-template.json, header-line.txt; deleted
   on success exits only: rds-global-bundle.pem, digests.txt.
2. **Preflight proofs and helper self-tests** (P-3 through P-7 above), then the
   helper self-tests: (a) gen.mjs — run it, verify the file is exactly 40 chars
   from the declared alphabet and its printed fingerprint equals an
   independently recomputed sha256-16 of the file content with the trailing
   newline stripped, then DELETE the generated file (this self-test must not
   leave a stray value); (b) probe.mjs — with no PG* env it must exit 4 with
   `ERR MISSING-ENV`, with PG* set but the CA bundle file absent it must exit 4
   with `ERR MISSING-CA`, and against an unreachable host it must exit 4 with a
   transport class code (never exit 0, never exit 3). Record: URL form, old
   fingerprint, self-test 28P01 result.
3. **Freeze the fleet, then DRAIN it**: FIRST — BEFORE any disable —
   RECORD THE BASELINE: fetch each workflow's state (`gh api
   repos/popcre/shared-db/actions/workflows` → name + state) and freeze
   THAT listing verbatim as the restore target (the §1 nine consumers are
   named for the freeze itself; the baseline covers ALL workflows so
   restore cannot preserve an accidentally-all-disabled fleet; recording
   it after disabling would capture the frozen state as normal). THEN:
   verify no OPEN pull request
   touches the SENSITIVE PATH SET — `.github/workflows/*` AND the executed
   code of the two proof workflows (`tools/coldlion-landing/**`, the
   `tools/coldlion-*` modules the intake workflow invokes,
   `scripts/shared_db_live_proof.py`, `.github/live-proofs/*`) — via
   `gh pr list --state open` + per-PR file list: §1's inventory and the
   proofs' behavior are only as good as neither moving under them; any open
   touching PR is recorded and the freeze waits for it to merge or close
   (the rotation window is minutes; waiting is free). PIN MAIN at this
   moment: record `git rev-parse origin/main` after the scan; at EVERY
   subsequent step boundary (before 5, 9, 10, 11) re-fetch and compare —
   ANY movement of main, whatever files it touched, trips the STOP rule and
   re-derives §1 from the new main before proceeding (this closes the
   open-PR race: a PR that opens and merges mid-window moves main, and a
   moved main is a drift even when the merge touched nothing sensitive). The scan+freeze reaches a FIXPOINT: after freezing the
   nine, §1 is re-derived against current main once more; any new consumer
   merged in the gap joins BOTH the freeze AND the same drain loop (it is
   disabled and its runs waited out under the identical rule), and the loop
   repeats until a re-derive changes nothing AND no run of ANY frozen
   workflow — the nine plus every fixpoint-discovered consumer — is `queued`
   or `in_progress`. Residual, recorded honestly: a merge completing in the
   seconds between the final fixpoint check and the PATCH can still add a
   running consumer — branch protection means every merge came from a PR the
   scan saw, the gap is minutes, and the step-11 re-scan catches any survivor
   DRIFT RULE (overrides everything else in this paragraph): a newly
   discovered consumer of the secret — any workflow file merged or changed
   mid-window — is a STOP-for-engineer condition, exactly like §1 drift at
   step 1: the fleet stays frozen, the drift is recorded on #3853, and this
   rotation does NOT proceed further (no ad-hoc proof dispatch, no enable, no
   exception). Integrating the new consumer is a NEW governed phase with its
   own review; resuming this rotation after it re-derives §1 and re-runs the
   freeze fixpoint. The step-11 re-scan therefore only ever VERIFIES zero
   drift — any drift it finds means the rotation never reached step 11 clean.
   HOLD RULE for the whole window (first disable through final restore):
   nothing re-enables or dispatches any frozen workflow except steps 10a/10b's
   two named proof dispatches — any other trigger (a schedule tick already
   drained, a manual dispatch, a merge-queued run) is refused by the freeze,
   and if one slips through the seconds-gap it fails closed on the dead
   credential exactly once. RESIDUAL, accepted and bounded: "exactly once"
   is not enforceable across job retries or live connections — the window
   between the final pre-PATCH pin check and the provider's password
   change is SECONDS wide, everything frozen cannot start, and the only
   possible casualty is one run of an un-frozen NEW consumer merged inside
   that window: it fails closed on the dead credential (no data risk), is
   detected by the step-11 re-scan, and trips the drift STOP. Eliminating
   even that requires locking branch protection repo-wide, which this plan
   deliberately does not do for a seconds-wide window. THEN for each of the §1 nine
   (only those
   currently `active`), `gh workflow disable`. Record the pre-rotation
   enabled/disabled set verbatim (`gh api repos/popcre/shared-db/actions/workflows`
   → name+state for the nine). Then WAIT until no run of any frozen workflow
   (the nine plus every fixpoint-discovered consumer) is `queued` or
   `in_progress` — `gh run list --workflow <name> --limit 100` for
   each (the full first page; a deeper backlog is paginated until no active run
   remains), poll up to 20 min: a job already running holds the old credential in
   its env for its whole lifetime, and a queued job of a disabled workflow can
   still start (disable prevents NEW triggers, not already-queued runs). If any
   run is still active after 20 minutes: record its URL on #3853, keep waiting
   out-of-band, and do NOT proceed to step 5 until the drain is complete.
   Scheduled consumers (coldlion-landing-sync's history windows,
   coldlion-licensor-property-production) MAY skip a scheduled tick during the
   freeze: landing-sync re-reads windowed history on its next run (self-healing)
   and phase6 is gated by `PHASE6_SCHEDULE_ENABLED`; if the freeze spans a
   scheduled trigger, its name and due time are recorded on #3853 and the next
   run after restore is verified green. coldlion-order-intake has no schedule yet
   (cron stays off until F1), so nothing scheduled is lost there;
   dispatch-triggered workflows are what we freeze.
4. **Generate value B**: `node gen.mjs <label>` → 40 chars from
   `[A-Za-z0-9._~-]` (URL-embeddable, no percent-encoding ever needed), written
   to `C:/Users/ahazan/.tmp-rotation/value-<label>.txt` (0600 intent, NO
   trailing newline — the file is exactly the 40 bytes, because every
   consumer reads the file bytes VERBATIM: the PATCH body is
   `{"password":"<40 bytes>"}` built by concatenation on the exact bytes;
   the vault template embeds the exact bytes; `gh secret set` receives the
   exact bytes on stdin; a newline in one destination but not another
   would send different passwords to provider vs secrets) — one
   file PER GENERATED VALUE, never overwritten: a fresh-value recovery writes
   value-<new-label>.txt and leaves the old file until step 7 has PROBED that
   value dead; only a proven-dead value's file is deleted (step 12 at the
   latest). An overwritten file cannot be probed — this is what makes "prove
   every superseded value dead" possible. Print only the fingerprint.
5. **PATCH the provider** (provider FIRST — lesson 8): the PAT never appears in
   argv either — the Authorization header is written to the 0600 file
   `C:/Users/ahazan/.tmp-rotation/auth-header.txt` (`Authorization: Bearer <PAT>`,
   built by piping `op read` output; curl reads it with `-H @<file>`), and the
   body is the 0600 file `patch-body.json` (`{"password":"..."}` built from
   value B) passed with `--data @<file>`. argv carries only the URL and file
   paths. Expect HTTP 200. RESPONSE HANDLING (the provider may echo
   connection material): the response body is written RAW to the 0600 file
   `patch-response.json` — never to stdout, transcript, or chat; a
   reviewed helper (`sanitize.mjs`, part of the packet and digests.txt-bound)
   prints ONLY the HTTP status and the body's `message` field: it
   WHITELIST-extracts `message` (fallback `"(none)"`), caps at 300 chars,
   drops every character outside printable ASCII, and collapses any run of
   20+ non-space characters to `[redacted]` — it cannot print what it does
   not extract.
   `patch-response.json` joins the step-1/step-12 exact-name cleanup list;
   this is the only path provider output ever reaches the record. On ANY
   non-200 or transport-level failure (timeout,
   connection reset, 5xx, 4xx) the PATCH's actual effect must be MEASURED, never
   assumed: run the dual-credential probe. If probe(B) succeeds → the PATCH
   landed; continue forward. If probe(old) still succeeds → the PATCH's
   effect is UNCONFIRMED-ABSENT, not absent: a transport-timeout PATCH can
   activate minutes later. STOP, record, and QUARANTINE: the fleet stays
   frozen for 30 minutes, then a FINAL probe(old) decides — dead means it
   landed late and the rotation continues forward from step 6; still alive
   means the PATCH genuinely never landed, but that is NOT a §5 definitive
   refusal, so the fleet is never restored on it: record on #3853 and STOP
   for an engineer with the fleet still frozen. No auto-retry in any branch.
   If neither works → provider propagation: re-poll BOTH probes at most 10
   times, 30 seconds apart (a 5-minute wall-clock deadline), then STOP and
   record. No auto-retry in any branch. Every other "bounded re-poll" in
   this plan uses the same numbers: 10 attempts, 30 s apart, 5-minute
   deadline.
   RESTORE RULE (one sentence, no exceptions): the fleet may be restored only
   after a DEFINITIVE refusal — HTTP 400 or 422 (the only definitive codes)
   WITH a response `message` naming request validation, confirmed by
   probe(old) still succeeding. Every transport-level outcome
   (timeout, reset, 5xx) is UNCONFIRMED and goes to the 30-minute quarantine
   above even if probe(old) still answers — a late-landing PATCH must never
   meet a restored fleet.
6. **Prove B works**: probe with value B → success. Poll up to 10 times, 15 s
   apart (provider propagation). Record run count + fingerprint match.
7. **Prove EVERY superseded value is dead**: probe each value this rotation
   superseded — the pre-rotation vault value AND any intermediate value from a
   failed attempt (each still on disk in its per-label file from step 4) →
   each MUST fail with error code exactly `28P01` (lesson 13: a TLS error, timeout, or DNS failure
   does NOT count — only the Postgres 28P01 authentication-failure code proves
   a credential was invalidated).
8. **Vault update (with fingerprinted readback)**: `op item edit
   246sf23gymd64yudpmhswcnyle --vault pimcaogmxxzoafh7lsluj6uxkq`
   with the new password supplied via a 0600 template file (lesson 6: never MCP
   item_edit — parameters land in transcripts). In the SAME edit, set notes from a
   0600 notes file documenting the contract: rotated 2026-10-05 after the
   2026-10-02 local-transcript exposure; BOTH popcre/shared-db secrets
   `SUPABASE_DB_PASSWORD_PRODUCTION` and `SUPABASE_DB_URL_PRODUCTION` derive from
   this value and must be re-set together; old fingerprint `…` is compromised and
   must never be reactivated.
   READBACK GATE (immediately after the edit, before step 9): pipe the item's
   password field back out (`op read '<item ref>/password>'`) through sha256
   in a process pipe — the value is never printed — and assert the sha256-16
   equals value B's recorded fingerprint. An update timestamp alone cannot
   prove the COMPLETE password was stored; the fingerprinted readback can. A
   mismatch is a STOP (vault write corrupted/truncated): fix forward by
   re-running the edit, never by proceeding.
9. **GitHub secrets**: FIRST re-run the open-PR workflow scan. ANY consumer
   merged during steps 5-8 trips the DRIFT RULE of step 3 (STOP-for-engineer:
   fleet frozen, recorded on #3853, no ad-hoc proofs, no secret changes) —
   this step only proceeds when the scan is clean. THEN build the two secret
   payloads in 0600 files (password form;
   pooler URL form using the exact form recorded at step 2 with value B embedded),
   then `gh secret set SUPABASE_DB_PASSWORD_PRODUCTION < file` and
   `gh secret set SUPABASE_DB_URL_PRODUCTION < file` (stdin, never argv).
10. **Dispatch proofs — one per secret**: the URL secret and the password secret
    have different consumers, so each gets its own one-shot proof (two different
    workflows, one dispatch each; never auto-retry a production dispatch). Each
    proof is bound to its EXACT run: the recorded run id is verified via gh api to
    match workflow path, event `workflow_dispatch`, the main-branch head SHA at
    dispatch, and the exact inputs (10a: limit=5, claim_only=true; 10b:
    work_issue=2478) — a green run that is not THE dispatched run (v9 lesson 11:
    "latest" grabs the wrong run) proves nothing and the gate fails.
    - ENABLE-WINDOW DISCIPLINE (applies to 10a and 10b): the vehicle is
    enabled seconds before ITS dispatch; immediately after dispatching,
    enumerate the vehicle's queued/in_progress runs. WRITE-SAFETY, honestly:
    (a) BEFORE enabling, the vehicle has zero queued/in_progress runs (a
    running dispatch would execute with default inputs); (b) the workflow's
    `concurrency: coldlion-order-intake, cancel-in-progress: false`
    SERIALIZES runs — ours first → a concurrent dispatch QUEUES (zero steps
    executed) and `gh run cancel` makes it never run; A NOT-OURS RUN THAT
    ENTERED FIRST (dispatched in the same seconds): it runs with default
    inputs (writer ON) — detection is guaranteed (the post-dispatch
    enumeration names it), containment follows: ours queues behind; its
    completion is awaited; the data-effect check counts DISTINCT
    sales_order_no touched by ITS sync_run UUIDs; ANY canonical effect →
    STOP, recorded on #3853 as an unintended-write incident (F1's
    reconciliation class, never silently accepted); zero effect → cancel
    remaining not-ours queued runs and proceed. Before re-disable at step
    11, drain is re-verified (zero queued/in_progress). RESTORE GATE gains the same check fleet-wide: no
    frozen workflow may have a queued or in_progress run when the first
    `gh workflow enable` executes.
    - DISPATCH PIN (10a and 10b): immediately BEFORE dispatching, re-fetch
    origin/main and assert it equals the step-1 pin (mismatch → drift STOP;
    the proofs never run changed code); immediately AFTER each run
    completes, assert its `head_sha` equals the pin (the run executed
    exactly the pinned bytes; a moved head mid-run voids that proof and
    trips the drift STOP).
    - ENABLE HYGIENE (10a/10b): a vehicle is enabled ONLY in its own
    dispatch-and-complete window — enable → pin-check → dispatch → await
    completion → enumeration/cancel → DISABLE — and the OTHER vehicle is
    never enabled during it; after 10a's window closes, intake is disabled
    again before 10b begins, so no vehicle stays enabled across steps and
    no later dispatch can queue behind a lingering enable.
    - 10a. URL secret: enable ONLY coldlion-order-intake, dispatch ONE run with
      EXPLICIT bounded inputs `limit=5, claim_only=true` (stages + decodes — real
      DB reads/writes to `coldlion.intake_*` staging only — and skips the
      canonical writer), verify conclusion `success`, record the run id. The
      The run API does not expose dispatch inputs, so input claims are
      proved this way and no further: (i) BOUNDS — proven by effect (below); the `limit=5`/`claim_only=true`
      input VALUES are evidenced by the command record, bound to the selected
      run by actor-and-time adjacency: the exact gh invocation plus a
      timestamp is posted to #3853 BEFORE dispatch; the run id is appended to
      the SAME comment once the run exists; the binding holds only if the
      run's `created_at` falls within 60 seconds after the comment's posted
      timestamp AND the triggering actor is the posting identity — runs
      failing the adjacency check are not this rotation's. This is evidence
      of what was SENT; the effects are what is PROVEN; (i) LIMIT — the budget
      unit is TOTAL ORDERS STAGED, inserts AND updates (the code's budget
      spends on every order whose rows are written, novel or re-observed:
      order-intake.mjs slices each window's projection to the remaining
      budget). Correlate by RUN IDENTITY, not wall-clock, and SUM ACROSS
      WINDOWS — the entry point writes ONE sync_run PER WINDOW: enumerate
      EVERY sync_run UUID with `requested_by = 'coldlion-order-intake'` whose
      `started_at` falls inside the GitHub run's window, then assert
      `count(DISTINCT sales_order_no) from coldlion.intake_order_line where
      last_seen_run IN (<those UUIDs>)` ≤ 5 — `last_seen_run` is stamped
      this-run on BOTH the insert and the update path, so every touched
      order counts and unlimited updates cannot pass. (ii) CLAIM-ONLY two ways:
      (a) STEP-SKIP LOG — the run's job log for the writer step must carry the
      workflow's own skipped-step marker (the `if:` gating at
      coldlion-order-intake.yml:115-120 emits GitHub's step-skipped annotation,
      readable via the run's jobs API); (b) DB EFFECT — read-only queries over
      `plm.production_order` (headers) AND `plm.production_order_line`
      (lines) for rows whose source-ref identity ties to the intake (the
      writer links `plm.production_order_source_ref` /
      `production_order_line_source_ref`, source_system 'coldlion',
      `coldlion:so:` ids) with created OR last-updated timestamps inside
      the proof window — BOTH counts MUST be zero (the writer UPDATES
      existing headers and lines as well as inserting; an inserts-only
      count would miss those mutations). Either signal alone is insufficient
      (zero rows can mean nothing-new-detected; a log line can be misread);
      both together prove the writer was skipped AND nothing canonical
      appeared.
    - 10b. Password secret: enable ONLY shared-db-live-proof, dispatch ONE run
      with `work_issue=2478` — the input IS provable for this workflow: its
      uploaded artifact is NAMED `shared-db-live-proof-<work_issue>-<sha>`,
      so the artifact name itself carries the dispatched input value, and a
      mismatch fails the gate. Its psycopg path maps
      `SUPABASE_DB_PASSWORD_PRODUCTION` (workflow line 56) and runs the pinned
      read-only force-rollback transaction probe, verify conclusion `success`,
      record the run id + inputs.
11. **Restore the fleet**: re-disable the two proof vehicles, RE-RUN the
    drift scan (the main-pin comparison from step 3 comes FIRST — any
    movement of main trips the STOP rule — then the FULL sensitive path set: `.github/workflows/*`
    plus the proof workflows' own executed code — `tools/coldlion-landing/**`
    and every `tools/coldlion-*` module the intake workflow invokes, and
    `scripts/shared_db_live_proof.py` + `.github/live-proofs/*` for the
    live-proof workflow — because a mid-window change to the SCRIPTS is as
    dangerous as one to the workflow files). ANY drift trips the same
    STOP-for-engineer rule as step 3: no restore, fleet stays frozen,
    recorded on #3853, integration happens as a NEW governed phase. When —
    and only when — the scan is clean: enable every workflow that was active
    in the step-3 pre-set and is not now. GATE: final enabled/disabled set ==
    pre-rotation set exactly, verified by a fresh gh api listing.
12. **Record and clean** (CLEANUP-ON-FAILURE, ONE rule for every exit —
   success, STOP, quarantine, drift stop, C-rotation pause): delete every
   scratch file EXCEPT the value files that are still LIVE (a value whose
   death has NOT been proven by a 28P01 probe is the ONLY recoverable copy
   while it is the provider's live password — deleting it locks the
   credential behind nothing but this transcript, which is exactly the
   exposure class this rotation exists to end; those files are retained,
   recorded on #3853 as retained-with-reason, and deleted the moment their
   death is proven or a successor completes). Files always deleted on any
   exit: patch-body.json, patch-response.json, auth-header.txt (the PAT
   header), secret-pw.txt, secret-url.txt (secret payloads — secrets live
   in GitHub now, not scratch), item-template.json, header-line.txt.
   digests.txt and rds-global-bundle.pem (non-secret) delete on SUCCESS
   exits only. The step-1 file list and this list are THE SAME list
   (value-<label>.txt… conditional; the rest unconditional). (fingerprints, run id, 28P01 proof, enabled-set equality, EST
    timestamps, ZCode signature); then execute the cleanup list ABOVE (the
    ONE list; no other list exists). Final proof: `ls` the scratch dir —
    SUCCESS exits: EMPTY; a STOP retaining live value files: EXACTLY those
    files (names+reasons already on #3853), nothing else. The transcript
    copy of the old value that started this incident is local-only and is
    superseded by this rotation.

## 4. Gates (all must pass before the rotation is declared done)

- G-1 old fingerprint ≠ new fingerprint (trivially true but asserted).
- G-2 probe(current value) success ≥ 1 after propagation poll; EVERY superseded value probes exactly 28P01.
- G-3 BOTH dispatch-proof runs conclude `success`, verified against their
  recorded run ids, workflow paths, events, and the main pin at dispatch.
  What G-3 claims — and no more: the SECURITY BOUNDS are PROVEN BY EFFECT
  (10a: ≤ 5 newly staged orders and ZERO canonical rows; 10b: the artifact
  name proves its `work_issue` input and the psycopg probe read only); the
  10a `limit`/`claim_only` input VALUES are EVIDENCED by the actor+time-bound
  command record, not independently proven — the run API does not expose
  dispatch inputs and this plan does not claim it does.
- G-4 final workflow enabled-set == pre-rotation enabled-set.
- G-5 vault item updated (notes carry the contract); both GitHub secrets'
  `updated_at` timestamps moved (gh api).
- Any gate failing → §5.

## 4a. Intermediate-state recovery table (every state between first mutation and done)

The provider PATCH is the point of no return (the old value dies there), so the
only directions after it are FORWARD or FRESH-VALUE, never back:

| State when a step fails | Old value | New value B | GitHub secrets | Fleet | Recovery |
|---|---|---|---|---|---|
| During step 3 (a disable or drain fails partway) | live | unused | old | PARTIALLY frozen | No password change has happened. Recovery: complete-the-freeze (retry the failed disables until the fixpoint holds — the freeze is idempotent); a persistently failing disable is a GitHub outage on a NON-secret operation → ABORT by restoring the step-1 BASELINE (recorded before any disable) and re-enabling exactly the baseline set; record on #3853. NEVER proceed to step 4 on a partial freeze. |
| Before step 5 (PATCH DEFINITIVELY refused) | live | unused | old | frozen | RESTORE requires ALL THREE: (a) HTTP 400 or 422 (the ONLY definitive codes — any other 4xx takes the transport row); (b) the response `message` names a REQUEST-validation error (password policy etc.) per the sanitized-response rule in step 5; (c) probe(old) still SUCCEEDS, proving no effect occurred. Anything else takes the transport row. No retry. |
| Before step 5 (PATCH transport-failed: timeout/reset/5xx — effect UNCONFIRMED) | unknown | unused | old | frozen | the step-5 dual probe decides: new works → landed, continue; old works → 30-min quarantine, final probe decides per the §5 rule — old dead → landed late, continue forward; old still alive or unclassifiable → STOP for engineer, fleet frozen; neither → bounded re-poll, STOP. NEVER restore on a transport-level outcome (only the table's definitive 400/422 row above restores). |
| Steps 6-7 (probe of B fails, or old not 28P01) | dead | unknown until classified | old | frozen | Bounded re-poll (10×30s/5min), then CLASSIFY per the §5 rule: B green + old non-28P01 → propagation lag, proceed and re-probe old at step 7; B green + old green → contradiction, STOP; B dead + old green → PATCH did not land, STOP (retry needs fresh review); both dead → provider fault, STOP. C is NEVER spawned here — only a later gate failing while B is PROVEN LIVE and old is 28P01-dead opens the C path. Never reactivate old. |
| Step 8 (vault edit fails) | dead | live (B proven by step 6) | old | frozen | Retry the idempotent vault edit; persistently failing → record on #3853 that the authoritative copy is MISSING (value exists only in the per-label file); fleet stays frozen; C stays closed until the vault is writable AND B's liveness re-proven — C never from an unknown state. |
| Step 9 (one `gh secret set` fails) | dead | live | PARTIAL | frozen | The two writes are independent and idempotent: retry the failed `gh secret set` (transport write, not a production dispatch). Persistently failing → keep fleet frozen, record exactly which secret is stale on #3853 with timestamps; do NOT enable anything, do NOT rotate C (rotating cannot fix a GitHub-write outage). |
| Step 10 (a proof run fails) | dead | live | new | two vehicles enabled | THE ONE DECISION TREE (this row is the single rule; §5 and §6 reference it and state no other): re-run BOTH local probes (not a dispatch). (1) Either probe FAILS → CLASSIFY FIRST: a probe failing with a CLASSIFIED verdict that contradicts health (the new-value probe returns 28P01, i.e. B is provider-rejected) is a credential fault → fleet STAYS FROZEN, fresh value C per §5's constants and role re-binding (steps 4-11). A probe failing UNCLASSIFIED (transport: ECONNREFUSED/TIMEOUT) is NOT a credential verdict → branch (3). (2) BOTH probes green AND BOTH secrets POSITIVELY validated — the SURVIVING proof's effect proves its secret, and the FAILED secret is proven well-formed by ITS OWN run's evidence before the failure point (10a's failed run must show the workflow read the URL secret and reached the database; 10b's failed run must show psycopg authenticated; a timestamp alone never counts) → workflow/tooling fault: record on #3853, restore the step-3 set, route the bug to its own issue. If the failed secret lacks that in-run evidence: branch (3). (3) Ambiguous or a secret malformed → STAY FROZEN + STOP for engineer; fix forward (re-set secret), never restore into auth failures. Never re-dispatch a proof to "see". |
| Step 11 (restore fails) | dead | live | new | partially enabled | This is a bookkeeping gap, not a credential risk: retry `gh workflow enable/disable` (idempotent). If GitHub is down, record the exact residual set on #3853 as BLOCKED; the rotation's credential work is complete and only fleet state is pending. |

In every state except the probes-green workflow-bug branch of step 10, the fleet
stays frozen until step 11 completes; nothing runs with a dead credential,
because the freeze happened before the PATCH and the drain before the freeze.
The step-10 exception restores only after BOTH local probes re-proved the
credential state (B works, old is 28P01-dead) AND both GitHub secrets were
proven well-formed (both `updated_at` moved; the 10a/10b effects proved the
URL and password forms usable); a malformed or empty secret keeps the fleet
frozen, the failure recorded on #3853, and the fix forward — re-set the
secret — never a restore.

## 5. Rollback / failure handling

§4a's table is the SINGLE source of truth for every failure state; this
section adds nothing and overrides nothing. Four constants it names:

- The compromised value is NEVER reactivated.
- A fresh value C is generated ONLY from the one opening state: a later gate
  failing while B is PROVEN LIVE (probe green) and old is 28P01-dead. Every
  unclassified, contradictory, or ambiguous state is STOP-for-engineer —
  never a second mutation (a delayed PATCH B could otherwise overwrite C).
- ROLE RE-BINDING for a C rotation: the §4a table applies recursively with
  the roles re-bound — "new value" = C, "prior superseded value" = B (which
  step 7 must prove 28P01-dead, from its per-label file, before C's PATCH).
  The original exposed value is dead since the first rotation.
- Restore eligibility is exactly the table's "Before step 5" row: HTTP
  400/422 with a validation `message` AND probe(old) still succeeding. No
  transport-level outcome ever restores. No auto-retry in any branch.

## 6. What this plan does NOT do (deliberately)

- No mega-orchestration script (v9's failure mode). The coordinator executes each
  step and records evidence; two ~10-line helpers exist (`gen.mjs`, `probe.mjs`)
  and are read by the reviewer as part of this plan.
- No preview-project changes; no PAT rotation (PAT was never exposed); no
  COLDLION_API_KEY changes; no consumer-repo changes (they hold no copy).
- No workflow file edits (the hardening PR already removed the argv leak class on
  main; this plan only toggles workflow enabled-state, which leaves no commit).
- **Round-4 Critical, measured and answered** (guard sibling forms): the
  reviewer notes `_redact_concurrency_queue_literals` redacts discriminator
  literals in reversed comparisons (`'x' == inputs.target`), `contains()`
  calls, or indexed properties — spellings where the literal is not preceded by
  `==`/`!=`. Measured against the LIVE expression
  (shared-supabase-migrations.yml:137): every one of those spellings differs
  from the landed `== 'production'` / `== 'pull_request'` forms in bytes
  OUTSIDE the quoted literals (parentheses, function calls, property indexes),
  so transitioning main's line to any of them changes the normal form and
  custody REFUSES — the bypass needs BOTH sides already in the sibling
  spelling, and no sibling spelling exists on main. The slot-2 reviewer of the
  merged fix measured exactly this limit and approved on it ("not reachable
  from the live line without a structural (refused) edit"; recorded verdict
  `refs/db-review-verdicts/3943-3945-4c6c22a4…-slot2`). A positive-position
  redactor (redact only format() arguments and && / || operands) would remove
  the class by construction and is recorded as the durable follow-up on
  #3943; it is hardening, not an open hole, and it is outside this rotation's
  scope.
- **Review boundary — CLOSED** (rounds 1-3 Critical): three plan-review rounds
  raised the same Critical against `production_business_risk_gate.py`'s
  concurrency-custody normalization. Per the escalation commitment below, the
  rotation paused and the guard defect was fixed FIRST as its own PR: #3945
  (two exact-head reviewer APPROVEs — muse + grok — at head 4c6c22a4) MERGED
  to main as `519a5626b` on 2026-10-05 2:32 PM EST, closing #3943. This
  plan-review round runs against that main; the full gate suite is 209 passed
  including the new per-run/merged-queue/discriminator-refusal tests.

## 7. Review-round provenance

- Round 1 report: `.ai/reviews/codex-plan-review-20261005T161643-438564-16683.md`
  (REJECT). Fixes applied: drain-after-freeze (High 1); explicit bounded inputs +
  a dedicated password-secret proof (High 2); the §4a recovery table (High 3);
  nine-workflow freeze list without database-contract-tests (Medium); Critical
  routed to #3943.
- Round 2 report: `.ai/reviews/codex-plan-review-20261005T163053-455807-25431.md`
  (REJECT). Fixes applied: full-page drain scan, limit 100 + pagination (High);
  unknown-outcome PATCH handling via dual-credential probe, never assume
  unchanged (High); runbook-conformant URL forms only, generic pooler `postgres`
  dropped (High); proof runs bound to exact run id/path/event/head/inputs (High);
  scratch-dir ACL check + named-file-only cleanup (Medium); scheduled-consumer
  skip handling recorded (Medium). The Critical repeat is answered by the
  escalation commitment above.
- Round 3 report: `.ai/reviews/codex-plan-review-20261005T164746-500391-19945.md`
  (REJECT). Fixes applied: the PAT now moves via a 0600 header file read by
  `curl -H @file` — never shell-expanded into argv (High); the §4a step-10
  restore exception is now explicitly gated on BOTH local probes re-proving the
  credential state, resolving the freeze contradiction (High); ANY non-200
  PATCH outcome is measured by the dual probe, the 4xx "unchanged" assumption
  is gone (High); cleanup wording unified to the P-7 named-file list (Medium).
  The "no current test execution" note referred to a stale scratch-worktree
  `.agent/` manifest, not this plan — the plan's executable content is the two
  helper files reviewed herewith and the command sequences in §3. The Critical
  was CLOSED, not waived: the guard fix (PR #3945) was reviewed to two
  exact-head APPROVEs and MERGED to main as `519a5626b` (209 gate tests
  green) before this round ran.
- Packet evidence, executed 2026-10-05 ≈6:25 PM EST against the reviewed
  checkout: `python -m pytest scripts/test_production_business_risk_gate.py
  -q` → **221 passed, 347 subtests passed** (the guard suites including all
  #3943 rounds, the distinctness-token PR #3949, and the 64-bit digest
  widening PR #3952 — the round-14 demonstrated 16-bit collision is refused
  by a dedicated test); the pg-closure digest above was computed in the same
  execution. Claimed helper self-outputs remain in §7.
- Round-15 update: round 14 demonstrated a REAL 16-bit collision in the
  #3949 token ('collision-62654' ≡ the production queue literal's 4-hex
  digest) — the exact digest-width follow-up both #3949 reviewers had
  flagged. CLOSED in code by PR #3952 (merged 2026-10-06 ≈3:25 AM EST,
  two durable APPROVEs grok+muse via replacement chains after deepseek
  quota-failed and qwen ran silent; token digest widened to 16 hex / 64
  bits; the demonstrated collision is a dedicated regression test; 221 gate
  tests green against the merged main 9b07fdf3).
- Round-13→14 update: the distinctness-token guard LANDED (PR #3949,
  merged 2026-10-05 ~10:04 PM EST, two APPROVEs, 220 gate tests) — queue-name
  literals now carry a 4-hex digest in their redaction token, so a
  preview↔production collision REFUSES and only byte-identical literals
  normalise equal. The formerly-recorded-open sibling class on #3943 is now
  CLOSED in code; this plan's packet evidence reflects the 220-test suite
  against the merged main.
- Round-12 ruling, standing: the `&&`/`||`/`format(` positive-position
  literal class is NOT closed and this plan no longer says so — it is
  RECORDED-OPEN on #3943 (twice-approved residual; the distinctness-preserving
  token follow-up — the token carries a 4-hex digest of the literal so a
  preview↔production collision refuses while arbitrary renames stay
  tolerated — is specified there and landing as the guard lane's next PR).
  This plan's scope is the rotation; the guard's remaining hardening lives on
  its own lane with its own reviews.
- Round-7/round-8 answers on record: (a) the #3946 normalizer finding — a
  value change of a `&&`/`||`-position literal IS the residual both #3946
  approvers recorded explicitly ("position-preserving same-count exchange
  among positive-position literals", verdicts
  `refs/db-review-verdicts/3943-3946-08392403…` slots 1 and 2); it is
  unreachable from the live expression without an accompanying structural
  change that refuses, and re-litigating a twice-approved recorded residual
  through this plan's review channel is the v9 spiral the plan exists to
  avoid — recorded, not waived. (b) gen.mjs now takes a label and REFUSES to
  overwrite an existing value file (self-tested: second call exits 2). (c)
  The input-proof reframing and the 10b artifact-name proof are in §3. (d)
  Mid-window workflow re-scans added at steps 9 and 11.
- Round 4 findings applied before round 6 (digest binding, dual dispatch
  proof, task-gate step 0, quarantine). Round 5 findings applied before
  round 7: pg module integrity pins, restore-only-after-definitive-refusal,
  bounds proved from the run's own sync_run records, open-workflow-PR check
  before the freeze, base reference updated to main `60133e2`.
- Helper self-tests EXECUTED 2026-10-05 (pre-review, no secrets touched),
  raw outputs verbatim: `probe.mjs` with no PG* env → stdout `ERR MISSING-ENV`,
  exit 4; `probe.mjs` with PG* set and the CA bundle absent → stdout `ERR MISSING-CA`, exit 4; `probe.mjs` against an unreachable host → stdout `ERR ECONNREFUSED`, exit 4 (transport class, never exit 0/3 — re-executed 2026-10-06 after the deadline rewrite); `gen.mjs` self-test → 40 chars from `[A-Za-z0-9._~-]`,
  printed fingerprint equals an independently recomputed sha256-16, generated
  file deleted after. pg spot pins (superseded by the whole-package digest at
  execution): package.json sha256 e42dd36cba6e9dd8..., lib/index.js sha256
  3fad6e6d3d976edb....

## 8. Helper files (reviewed with this plan; no secrets in either)

- `gen.mjs` — writes value B to the 0600 path, prints fingerprint only.
- `probe.mjs` — takes env vars PGHOST/PGPORT/PGUSER/PGDATABASE/PGPASSWORD
  (the same PG* transport the hardening PR landed), connects via the pinned pg
  8.23.0 with full RDS-CA TLS verification, prints `OK` on success or
  `ERR <code>` on failure (28P01 is the only auth-proof code), never prints the
  password, URL, or raw server message. ONE overall wall-clock deadline covers
  connect AND query AND shutdown: a Promise.race timer destroys the client
  after 20 s and exits 4 (`ERR TIMEOUT`) — a hung query or a hung end() is
  classified as a transport failure, never mistaken for a verdict, and never
  left running.
