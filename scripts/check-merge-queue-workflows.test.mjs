// Merge-queue workflow coverage (issue #2530 Phase C Step 7;
// plan_shared_db_popcre_transfer_merge_queue.md).
//
// WHY THIS TEST EXISTS. A required status context that no workflow reports for
// `merge_group` leaves every merge group pending forever — GitHub waits for a
// context that never arrives. So the mapping below is the authority tying every
// required context to the workflow and job that emits it, and proving that
// emission happens for BOTH `pull_request` and `merge_group` events.
//
// The context list is derived from TWO sources and must cover both:
//   1. the committed mirror docs/verification/main-required-status-checks.json
//      (the list the guarded merge pre-flight enforces);
//   2. KNOWN_LIVE_ADDITIONS below — contexts already live but not yet mirrored.
// The mirror must never shrink this coverage, and this test fails the moment a
// mirrored context has no mapped merge-group-capable emitter.
import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'

const readWorkflow = (name) => readFileSync(new URL(`../.github/workflows/${name}`, import.meta.url), 'utf8').replace(/\r\n/g, '\n')
const MIRROR = JSON.parse(readFileSync(new URL('../docs/verification/main-required-status-checks.json', import.meta.url), 'utf8'))

// Live on main but not yet in the committed mirror. The mirror is rewritten by
// scripts/update-required-checks.mjs from the live read-back at activation; an
// entry here must then move OUT of this list only by the mirror catching up.
const KNOWN_LIVE_ADDITIONS = ['Queue-sensitive checks (aggregate)']

// context -> emitter. kind 'check-run': the workflow job named `job` reports
// the context on whatever commit it runs on, so merge_group coverage means the
// workflow triggers on merge_group. kind 'commit-status': a status is POSTed to
// an explicit SHA — by the guarded merge lane on the reviewed PR head, and by
// the queue gate on the synthetic group SHA.
const CONTEXT_MAP = {
  'Agent work contract': { workflow: 'agent-work-contract.yml', kind: 'check-run', job: 'Agent work contract' },
  'Cancelled work guard': { workflow: 'cancelled-work-guard.yml', kind: 'check-run', job: 'Cancelled work guard' },
  'Cross-PR object collision': { workflow: 'pr-object-collision.yml', kind: 'check-run', job: 'Cross-PR object collision' },
  'Domain ownership': { workflow: 'domain-ownership.yml', kind: 'check-run', job: 'Domain ownership' },
  'Handoff contract': { workflow: 'handoff-contract-guard.yml', kind: 'check-run', job: 'Handoff contract' },
  'Intake pointer guard': { workflow: 'intake-pointer-guard.yml', kind: 'check-run', job: 'Intake pointer guard' },
  'Migration author lease': { workflow: 'migration-author-lease.yml', kind: 'check-run', job: 'Migration author lease' },
  'Migration guarded merge authorization': { kind: 'commit-status' },
  'Orchestrator marker guard': { workflow: 'orchestrator-marker-guard.yml', kind: 'check-run', job: 'Orchestrator marker guard' },
  'Promotion contract tests (offline)': { workflow: 'coldlion-promotion-contract-tests.yml', kind: 'check-run', job: 'Promotion contract tests (offline)' },
  'Queue-sensitive checks (aggregate)': { workflow: 'queue-sensitive-aggregate.yml', kind: 'check-run', job: 'Queue-sensitive checks (aggregate)' },
  'SQL migration guards': { workflow: 'shared-supabase-migrations.yml', kind: 'check-run', job: 'SQL migration guards' },
  'Tools offline tests': { workflow: 'tools-offline-tests.yml', kind: 'check-run', job: 'Tools offline tests' },
  'Merge queue gate': { workflow: 'merge-queue-gate.yml', kind: 'check-run', job: 'Merge queue gate' },
}

test('every mirrored or known-live required context has a mapped emitter', () => {
  const mirrored = MIRROR.contexts
  assert.ok(Array.isArray(mirrored) && mirrored.length > 0, 'the committed mirror carries no contexts; the required list is unknown')
  for (const context of [...mirrored, ...KNOWN_LIVE_ADDITIONS, 'Merge queue gate']) {
    assert.ok(CONTEXT_MAP[context], `no merge-group-capable emitter is mapped for required context "${context}"`)
  }
})

test('every check-run emitter triggers on pull_request AND merge_group checks_requested', () => {
  for (const [context, spec] of Object.entries(CONTEXT_MAP)) {
    if (spec.kind !== 'check-run') continue
    const text = readWorkflow(spec.workflow)
    assert.match(text, /^ {2}pull_request:$/m, `${spec.workflow} (${context}) lost its pull_request trigger`)
    assert.match(text, /^ {2}merge_group:$/m, `${spec.workflow} (${context}) does not trigger for merge_group`)
    assert.match(text, /^ {4}types: \[checks_requested\]$/m, `${spec.workflow} (${context}) does not pin merge_group checks_requested`)
    // Lane-capable jobs emit the context through a name EXPRESSION whose default
    // branch is the exact context string; asserting the string is present covers both.
    assert.ok(text.includes(spec.job), `${spec.workflow} does not emit a job named "${spec.job}"`)
  }
})

test('no required-context workflow is path-filtered (a filtered required check stays pending forever)', () => {
  for (const [context, spec] of Object.entries(CONTEXT_MAP)) {
    if (spec.kind !== 'check-run') continue
    const text = readWorkflow(spec.workflow)
    const onBlock = /^on:\n([\s\S]*?)^\w/m.exec(text)?.[1] ?? ''
    assert.ok(!/^ {4}paths(-ignore)?:/m.test(onBlock), `${spec.workflow} (${context}) has a paths filter on a required context`)
  }
})

test('no queue check is cancelled in progress: a re-requested group must never kill its own run', () => {
  for (const [context, spec] of Object.entries(CONTEXT_MAP)) {
    if (spec.kind !== 'check-run') continue
    const text = readWorkflow(spec.workflow)
    const line = /^ {2}cancel-in-progress: (.*)$/m.exec(text)?.[1]?.trim()
    assert.ok(line !== undefined, `${spec.workflow} (${context}) declares no concurrency cancel-in-progress policy`)
    assert.ok(
      line === 'false' || line.includes("!= 'merge_group'") || line.includes("== 'pull_request'"),
      `${spec.workflow} (${context}) may cancel an in-progress merge_group run: cancel-in-progress: ${line}`,
    )
  }
})

test('PR-payload steps defer or re-resolve on merge_group (the payload does not exist there)', () => {
  for (const name of ['pr-object-collision.yml', 'handoff-contract-guard.yml', 'migration-author-lease.yml', 'agent-work-contract.yml']) {
    const text = readWorkflow(name)
    const usesPayload = /github\.event\.pull_request\.|github\.base_ref|GITHUB_BASE_REF/.test(text)
    if (!usesPayload) continue
    const defended =
      /if: github\.event_name != 'merge_group'/.test(text) ||
      /merge-queue-contract\.mjs --resolve-queue-pr/.test(text) ||
      /github\.base_ref \|\| 'main'/.test(text)
    assert.ok(defended, `${name} consumes pull_request payload fields with no merge_group defence`)
  }
})

test('the queue gate: one-PR identity, ancestry proof, authorization, preview hold, group-SHA status', () => {
  const text = readWorkflow('merge-queue-gate.yml')
  assert.match(text, /^ {2}pull_request:$/m)
  assert.match(text, /^ {2}merge_group:$/m)
  assert.match(text, /name: Merge queue gate/)
  assert.match(text, /^ {2}statuses: write$/m)
  assert.match(text, /MERGE_GROUP_REF: \$\{\{ github\.event\.merge_group\.head_ref \}\}/)
  assert.ok(text.includes('merge-queue-contract.mjs --resolve-queue-pr'), 'the gate does not resolve the queued PR through the contract')
  assert.ok(text.includes('git merge-base --is-ancestor'), 'the gate does not prove the reviewed head is an ancestor of the group commit')
  assert.ok(text.includes('--require-preview-rehearsal'), 'the gate does not hold for the exact-SHA preview rehearsal')
  // The commit status is published on the GROUP sha, never the PR head here.
  assert.ok(text.includes('statuses/$MERGE_GROUP_SHA'), 'the gate does not publish authorization on the merge-group SHA')
  assert.ok(text.includes("context='Migration guarded merge authorization'"), 'the gate does not publish the guarded authorization context')
  assert.match(text, /^ {2}cancel-in-progress: false$/m)
})

test('the guarded merge lane is dual-mode and never uses --admin', () => {
  const text = readWorkflow('guarded-migration-merge.yml')
  assert.ok(text.includes('--queue-mode'), 'the guarded lane does not read live queue state')
  assert.ok(!text.includes('--admin'), 'the guarded lane must never bypass with --admin')
  assert.ok(text.includes('--match-head-commit'), 'the guarded lane dropped exact-head matching')
})

test('the preview rehearsal publishes the exact rehearsed main SHA, and only on success', () => {
  const text = readWorkflow('shared-supabase-migrations.yml')
  const preview = /^ {2}preview:\n([\s\S]*?)^ {2}[a-z]/m.exec(text)?.[1] ?? ''
  assert.ok(preview, 'the preview job was not found in shared-supabase-migrations.yml')
  assert.match(preview, /^ {6}statuses: write$/m, 'the preview job cannot publish commit statuses')
  assert.ok(preview.includes("context='Post-merge preview rehearsal'"), 'the preview job does not publish the rehearsal status')
  assert.ok(preview.includes('if: success() &&'), 'the rehearsal status is not gated on success() — a failure must never post success')
})
