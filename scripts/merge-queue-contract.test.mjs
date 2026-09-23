import test from 'node:test'
import assert from 'node:assert/strict'
import {
  MergeQueueError,
  MergeQueueModeUnknown,
  PREVIEW_REHEARSAL_CONTEXT,
  QUEUE_RULE,
  RULESET_NAME,
  assertOldestMigration,
  awaitPreviewRehearsal,
  baseNeedsPreview,
  checkQueueOrder,
  migrationVersions,
  pullRequestFromQueueRef,
  queueMode,
  queueRulesetMatches,
  readOpenPullRequests,
  readPullRequestFiles,
  rehearsalState,
  verifyQueuePullRequest,
} from './merge-queue-contract.mjs'

const REPO = 'acme/widgets'

test('extracts exactly one PR from a GitHub merge queue ref', () => {
  assert.equal(pullRequestFromQueueRef('refs/heads/gh-readonly-queue/main/pr-1435-deadbeef'), 1435)
  assert.equal(pullRequestFromQueueRef('gh-readonly-queue/main/pr-3267-0123abcd'), 3267)
  assert.throws(() => pullRequestFromQueueRef('refs/heads/main'), /expected exactly one pull request/)
  assert.throws(() => pullRequestFromQueueRef(''), /expected exactly one pull request/)
  assert.throws(() => pullRequestFromQueueRef('gh-readonly-queue/main/pr-12-aaa/pr-34-bbb'), /expected exactly one pull request/)
})

test('queue-ref PR identity is independently verified against live PR shape', () => {
  const row = { number: 1435, state: 'OPEN', baseRefName: 'main', headRefOid: 'a'.repeat(40) }
  assert.equal(verifyQueuePullRequest(1435, row), 1435)
  assert.throws(() => verifyQueuePullRequest(1436, row), /different pull request/)
  assert.throws(() => verifyQueuePullRequest(1435, { ...row, state: 'MERGED' }), /not open/)
  assert.throws(() => verifyQueuePullRequest(1435, { ...row, baseRefName: 'develop' }), /base is not main/)
  assert.throws(() => verifyQueuePullRequest(1435, { ...row, headRefOid: 'xyz' }), /head SHA is unreadable/)
})

test('REST pagination is slurped and flattened without a 100-row window', () => {
  const read = (args) => {
    assert.ok(args.includes('--slurp'))
    if (args.at(-1).includes('/files?')) return [[{ filename: 'README.md' }], [{ filename: 'docs/x.md' }]]
    return [[{ number: 1, draft: false }], [{ number: 2, draft: true }]]
  }
  assert.deepEqual(readPullRequestFiles(1, { repo: REPO, read }), ['README.md', 'docs/x.md'])
  assert.deepEqual(readOpenPullRequests({ repo: REPO, read }), [
    { number: 1, isDraft: false, files: ['README.md', 'docs/x.md'] },
    { number: 2, isDraft: true, files: ['README.md', 'docs/x.md'] },
  ])
})

test('a malformed page shape is refused, never flattened away', () => {
  const bad = () => ({ unexpected: true })
  assert.throws(() => readPullRequestFiles(1, { repo: REPO, read: bad }), /pagination is unreadable/)
  assert.throws(() => readOpenPullRequests({ repo: REPO, read: bad }), /pagination is unreadable/)
})

test('the 3,000-file coverage ceiling is a refusal, not a complete list', () => {
  const files = Array.from({ length: 3000 }, (_, i) => ({ filename: `f${i}.sql` }))
  const read = () => [files]
  assert.throws(() => readPullRequestFiles(1, { repo: REPO, read }), /3000-file coverage limit/)
})

test('migration versions are exact, unique, and ordered', () => {
  assert.deepEqual(migrationVersions([
    'supabase/migrations/20260825120001_b.sql',
    'docs/x.md',
    'supabase/migrations/20260825120000_a.sql',
    'supabase/migrations/not-a-version.sql',
  ]), ['20260825120000', '20260825120001'])
})

test('oldest open migration PR must enter first', () => {
  const candidate = ['supabase/migrations/20260825120002_candidate.sql']
  assert.throws(() => assertOldestMigration(20, candidate, [
    { number: 19, isDraft: false, files: ['supabase/migrations/20260825120001_older.sql'] },
  ]), /behind open PR #19/)
  assert.equal(assertOldestMigration(20, candidate, [
    { number: 19, isDraft: true, files: ['supabase/migrations/20260825120001_older.sql'] },
    { number: 21, isDraft: false, files: ['supabase/migrations/20260825120003_newer.sql'] },
  ]).relevant, true)
  // The candidate never blocks itself.
  assert.equal(assertOldestMigration(20, candidate, [
    { number: 20, isDraft: false, files: candidate },
  ]).relevant, true)
})

test('non-migration PRs do not participate and migration merges require preview', () => {
  assert.equal(assertOldestMigration(20, ['README.md'], []).relevant, false)
  assert.equal(baseNeedsPreview(['README.md']), false)
  assert.equal(baseNeedsPreview(['supabase/migrations/20260825120000_x.sql']), true)
})

test('checkQueueOrder wires candidate files and open PRs through the reader', () => {
  const read = (args) => {
    const target = args.at(-1)
    if (target.includes('pulls?state=open')) return [[{ number: 9, draft: false }]]
    if (target.includes('pulls/9/files')) return [[{ filename: 'supabase/migrations/20260825120001_old.sql' }]]
    return [[{ filename: 'supabase/migrations/20260825120002_new.sql' }]]
  }
  assert.throws(() => checkQueueOrder(10, { repo: REPO, read }), /behind open PR #9/)
})

// ---------------------------------------------------------------------------
// Queue-mode detection
// ---------------------------------------------------------------------------

const approvedDetail = {
  name: RULESET_NAME,
  target: 'branch',
  enforcement: 'active',
  conditions: { ref_name: { include: ['refs/heads/main'], exclude: [] } },
  rules: [{ type: 'merge_queue', parameters: { ...QUEUE_RULE.parameters } }],
}

test('the approved rule is exactly one all-green PR built and merged at a time', () => {
  assert.deepEqual(QUEUE_RULE.parameters, {
    check_response_timeout_minutes: 30,
    grouping_strategy: 'ALLGREEN',
    max_entries_to_build: 1,
    max_entries_to_merge: 1,
    merge_method: 'MERGE',
    min_entries_to_merge: 1,
    min_entries_to_merge_wait_minutes: 0,
  })
  assert.equal(queueRulesetMatches(approvedDetail), true)
  assert.equal(queueRulesetMatches({ ...approvedDetail, enforcement: 'evaluate' }), false)
  assert.equal(queueRulesetMatches({ ...approvedDetail, conditions: { ref_name: { include: ['refs/heads/develop'] } } }), false)
  assert.equal(queueRulesetMatches({ ...approvedDetail, rules: [{ type: 'merge_queue', parameters: { ...QUEUE_RULE.parameters, max_entries_to_build: 2 } }] }), false)
})

test('queue mode: active only for the exact approved ruleset', () => {
  const read = (args) => {
    const target = args.at(-1)
    if (target.endsWith('includes_parents=false')) return [{ id: 42, name: RULESET_NAME, enforcement: 'active' }]
    if (target.endsWith('rulesets/42')) return approvedDetail
    throw new Error(`unexpected read ${target}`)
  }
  assert.equal(queueMode({ repo: REPO, read }), 'active')
})

test('queue mode: inactive when no rulesets exist or the named one is disabled', () => {
  assert.equal(queueMode({ repo: REPO, read: () => [] }), 'inactive')
  const read = (args) => {
    const target = args.at(-1)
    if (target.endsWith('includes_parents=false')) return [{ id: 42, name: RULESET_NAME, enforcement: 'disabled' }]
    if (target.endsWith('rulesets/42')) return { ...approvedDetail, enforcement: 'disabled' }
    throw new Error(`unexpected read ${target}`)
  }
  assert.equal(queueMode({ repo: REPO, read }), 'inactive')
})

test('queue mode: unknown, never guessed, on duplicates, foreign queues, or shape drift', () => {
  const dup = () => [{ id: 1, name: RULESET_NAME, enforcement: 'active' }, { id: 2, name: RULESET_NAME, enforcement: 'active' }]
  assert.throws(() => queueMode({ repo: REPO, read: dup }), MergeQueueModeUnknown)

  const foreign = (args) => {
    const target = args.at(-1)
    if (target.endsWith('includes_parents=false')) return [{ id: 7, name: 'someone elses queue', enforcement: 'active' }]
    if (target.endsWith('rulesets/7')) {
      return { name: 'someone elses queue', enforcement: 'active', conditions: { ref_name: { include: ['~ALL'] } }, rules: [{ type: 'merge_queue' }] }
    }
    throw new Error(`unexpected read ${target}`)
  }
  assert.throws(() => queueMode({ repo: REPO, read: foreign }), /DIFFERENT active ruleset/)

  const drifted = (args) => {
    const target = args.at(-1)
    if (target.endsWith('includes_parents=false')) return [{ id: 42, name: RULESET_NAME, enforcement: 'active' }]
    if (target.endsWith('rulesets/42')) return { ...approvedDetail, rules: [{ type: 'merge_queue', parameters: { ...QUEUE_RULE.parameters, grouping_strategy: 'HEADGREEN' } }] }
    throw new Error(`unexpected read ${target}`)
  }
  assert.throws(() => queueMode({ repo: REPO, read: drifted }), /not the exact approved one-PR queue/)
})

// ---------------------------------------------------------------------------
// Shared-preview hold
// ---------------------------------------------------------------------------

const SHA = 'b'.repeat(40)

test('rehearsal state is the LATEST status for the exact context', () => {
  assert.equal(rehearsalState([]), null)
  assert.equal(rehearsalState([
    { context: PREVIEW_REHEARSAL_CONTEXT, state: 'failure', updated_at: '2026-09-18T00:00:00Z' },
    { context: PREVIEW_REHEARSAL_CONTEXT, state: 'success', updated_at: '2026-09-18T01:00:00Z' },
    { context: 'unrelated', state: 'failure', updated_at: '2026-09-18T02:00:00Z' },
  ]), 'success')
})

test('the hold releases on success, waits on pending, and refuses failure', async () => {
  const noSleep = async () => {}
  assert.equal((await awaitPreviewRehearsal({ sha: SHA, budgetMs: 1000, readStatuses: async () => [{ context: PREVIEW_REHEARSAL_CONTEXT, state: 'success' }], sleep: noSleep })).state, 'success')

  let polls = 0
  const pendingThenSuccess = async () => (++polls === 3 ? [{ context: PREVIEW_REHEARSAL_CONTEXT, state: 'success' }] : [])
  assert.equal((await awaitPreviewRehearsal({ sha: SHA, budgetMs: 100000, intervalMs: 1, readStatuses: pendingThenSuccess, sleep: noSleep })).state, 'success')
  assert.equal(polls, 3)

  await assert.rejects(
    awaitPreviewRehearsal({ sha: SHA, budgetMs: 1000, readStatuses: async () => [{ context: PREVIEW_REHEARSAL_CONTEXT, state: 'failure' }], sleep: noSleep }),
    /is failure; recover preview/,
  )
  await assert.rejects(
    awaitPreviewRehearsal({ sha: SHA, budgetMs: 10, intervalMs: 100, readStatuses: async () => [], sleep: noSleep }),
    /did not complete a successful post-merge preview rehearsal/,
  )
  await assert.rejects(
    awaitPreviewRehearsal({ sha: 'not-a-sha', budgetMs: 10, readStatuses: async () => [], sleep: noSleep }),
    MergeQueueError,
  )
})
