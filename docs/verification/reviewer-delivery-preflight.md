# Reviewer delivery preflight for repository maintenance

Issue #3624 makes the existing delivery preflight mandatory for every new reviewer assignment. The record and its registered evidence bundle must name the same issue, pull request, and exact review head. Missing, blocked, mismatched, or unreadable evidence refuses before the reviewer allocator reads GitHub or spends a slot. Existing assignments and replacement operations are not retroactively described as preflight proven.

For a PR with no database migration, create the bundle in a clean, exact-head worktree with input shaped as follows. Include every changed implementation file in `focusedFiles` and the supporting tests in `verificationFiles`; the lists are content hashed. Use real issue, PR, base-main, and head values. Omit `claim` and database object claims. The builder sets the empty migration-order digest and `metadata.claim: null`.

```json
{
  "workType": "repo-maintenance",
  "migrations": [],
  "focusedFiles": ["scripts/example.mjs"],
  "verificationFiles": ["scripts/example.test.mjs"],
  "writes": [],
  "reads": [],
  "issue": 1,
  "pr": 2,
  "baseMainSha": "<40-hex main commit>",
  "integrationSha": "<40-hex PR head>"
}
```

```bash
node scripts/orchestrator-flow/evidence-bundle.mjs --input bundle-input.json > bundle.json
```

Prepare the nine preflight checks from current, durable evidence. For `sidecars` and `producers`, set `DELIVERY_EVIDENCE_REGISTRY_ROOT` to an absolute local directory and use `scripts/orchestrator-flow/sidecar-registry-evidence.mjs --issue <issue> --pr <pr> --head-sha <head>` in the clean exact-head worktree. Copy its two checks into the preflight input; keep their registration files under that trusted root. Supply evidence-backed `PASS` or `BLOCKED` for `route`, `work_contract`, `object_collision`, `dependencies`, `migration_order`, `reviewer_capacity`, and `runner_capacity`. A `PASS` string without its actual evidence is not proof.

```bash
node scripts/manage-migration-author-lanes.mjs --delivery-preflight --evidence-bundle bundle.json --preflight-input preflight-input.json --changed-files-file changed-files.json > gate.json
```

The preflight input names the exact issue, PR, head, and all nine checks. `changed-files.json` is the PR's actual changed-file array; the routine rebuild check runs if it contains a migration. Extract `gate.json`'s `record` and registered `bundle` into separate JSON files. Pass both files, the same registry-root environment, exact head, and changed-file list to `--assign-reviewer` or `--replace-failed-reviewer`. The allocator verifies registry readback and the record/bundle/head binding before either reviewer draw. A later head requires a fresh preflight unless the existing integration-refresh carry proof passes.

Migration PRs continue to require at least one versioned migration, a positive claim number, and the existing object and ordering evidence. The zero-migration path rejects migration files, database claims, and bundles with no focused or verification file.
