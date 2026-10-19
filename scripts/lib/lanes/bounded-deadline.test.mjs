import test from 'node:test'
import assert from 'node:assert/strict'
import {
  remainingDeadlineMs,
  assertDeadlineBudget,
  clampTimeoutToDeadline,
  assertCleanupReserve,
  CLEANUP_RESERVE_MS,
  reconcileAmbiguousWrite,
  recoveryForReconcile,
  cleanupMayDeleteMutex,
} from './bounded-deadline.mjs'

test('remainingDeadlineMs: unbounded when missing or invalid', () => {
  assert.equal(remainingDeadlineMs(null, 1000), null)
  assert.equal(remainingDeadlineMs(undefined, 1000), null)
  assert.equal(remainingDeadlineMs('nope', 1000), null)
})

test('remainingDeadlineMs: clamps past deadlines to zero, never negative', () => {
  assert.equal(remainingDeadlineMs(1000, 1000), 0)
  assert.equal(remainingDeadlineMs(1000, 2500), 0)
  assert.equal(remainingDeadlineMs(5000, 1000), 4000)
})

test('assertDeadlineBudget: refuses before launch when remaining < min', () => {
  assert.equal(assertDeadlineBudget(null, 1, 0), null)
  assert.equal(assertDeadlineBudget(5000, 100, 0), 5000)
  assert.throws(
    () => assertDeadlineBudget(50, 100, 0),
    (error) => error.code === 'DEADLINE_EXHAUSTED' && /refusing before launching/.test(error.message),
  )
  assert.throws(() => assertDeadlineBudget(1000, 1, 2000), /DEADLINE_EXHAUSTED|refusing before launching/)
})

test('assertDeadlineBudget: wrapError keeps the caller error type', () => {
  assert.throws(
    () => assertDeadlineBudget(1, 10, 0, (detail) => {
      const error = new Error(detail)
      error.name = 'LaneError'
      return error
    }),
    (error) => error.name === 'LaneError',
  )
})

test('clampTimeoutToDeadline: caps child timeout to remaining budget', () => {
  assert.equal(clampTimeoutToDeadline(120_000, null, 0), 120_000)
  assert.equal(clampTimeoutToDeadline(120_000, 30_000, 0), 30_000)
  assert.equal(clampTimeoutToDeadline(5_000, 30_000, 0), 5_000)
  assert.equal(clampTimeoutToDeadline(5_000, 1_000, 2_000), 0)
})

test('assertCleanupReserve: requires commit + reserve before commit', () => {
  assert.deepEqual(
    assertCleanupReserve(null, 1000, CLEANUP_RESERVE_MS, 0),
    { remaining: null, reserveMs: CLEANUP_RESERVE_MS, commitMs: 1000 },
  )
  assert.throws(
    () => assertCleanupReserve(5_000, 1_000, CLEANUP_RESERVE_MS, 0),
    (error) => error.code === 'DEADLINE_CLEANUP_RESERVE' && /cleanup reserve/.test(error.message),
  )
  const ok = assertCleanupReserve(60_000, 1_000, CLEANUP_RESERVE_MS, 0)
  assert.equal(ok.remaining, 60_000)
  assert.equal(ok.reserveMs, CLEANUP_RESERVE_MS)
})

test('reconcileAmbiguousWrite: committed keeps assignment, never redraws', () => {
  const result = reconcileAmbiguousWrite({
    desired: [{ ref: 'refs/db-review-active/1', sha: 'a'.repeat(40) }],
    prior: [{ ref: 'refs/db-review-active/1', sha: null }],
    readObserved: () => 'a'.repeat(40),
  })
  assert.equal(result.kind, 'committed')
  assert.equal(recoveryForReconcile(result), 'keep_assignment_no_redraw')
})

test('reconcileAmbiguousWrite: fully uncommitted is retryable no-write', () => {
  const result = reconcileAmbiguousWrite({
    desired: [
      { ref: 'refs/db-review-active/1', sha: 'a'.repeat(40) },
      { ref: 'refs/db-coordination/review-cursor', sha: 'b'.repeat(40) },
    ],
    prior: [
      { ref: 'refs/db-review-active/1', sha: null },
      { ref: 'refs/db-coordination/review-cursor', sha: 'c'.repeat(40) },
    ],
    readObserved: (ref) => (ref.includes('cursor') ? 'c'.repeat(40) : null),
  })
  assert.equal(result.kind, 'uncommitted')
  assert.equal(recoveryForReconcile(result), 'retryable_no_write')
})

test('reconcileAmbiguousWrite: partial and unknown require recovery', () => {
  const partial = reconcileAmbiguousWrite({
    desired: [
      { ref: 'a', sha: '1'.repeat(40) },
      { ref: 'b', sha: '2'.repeat(40) },
    ],
    prior: [
      { ref: 'a', sha: null },
      { ref: 'b', sha: null },
    ],
    readObserved: (ref) => (ref === 'a' ? '1'.repeat(40) : null),
  })
  assert.equal(partial.kind, 'partial')
  assert.equal(recoveryForReconcile(partial), 'recovery_required')

  const foreign = reconcileAmbiguousWrite({
    desired: [{ ref: 'a', sha: '1'.repeat(40) }],
    prior: [{ ref: 'a', sha: '9'.repeat(40) }],
    readObserved: () => 'f'.repeat(40),
  })
  assert.equal(foreign.kind, 'unknown')
  assert.equal(recoveryForReconcile(foreign), 'recovery_required')
})

test('reconcileAmbiguousWrite: read failure is unknown, not uncommitted', () => {
  const result = reconcileAmbiguousWrite({
    desired: [{ ref: 'a', sha: '1'.repeat(40) }],
    prior: [{ ref: 'a', sha: null }],
    readObserved: () => { throw new Error('timeout') },
  })
  assert.equal(result.kind, 'unknown')
  assert.equal(recoveryForReconcile(result), 'recovery_required')
})

test('cleanupMayDeleteMutex: successor owner is never ours', () => {
  const ours = 'a'.repeat(40)
  const successor = 'b'.repeat(40)
  assert.equal(cleanupMayDeleteMutex(ours, ours), true)
  assert.equal(cleanupMayDeleteMutex(successor, ours), false)
  assert.equal(cleanupMayDeleteMutex(null, ours), false)
  assert.equal(cleanupMayDeleteMutex(ours, null), false)
  assert.equal(cleanupMayDeleteMutex(ours, 'short'), false)
})

test('named gate: owned_git_and_gh_children_have_remaining_deadlines', () => {
  // Zero remaining refuses before launch — the named hostile case.
  assert.throws(() => assertDeadlineBudget(0, 1, 100), /refusing before launching/)
  assert.equal(clampTimeoutToDeadline(10_000, 100, 100), 0)
})

test('named gate: ambiguous_commit_recovers_same_assignment_without_redraw', () => {
  const result = reconcileAmbiguousWrite({
    desired: [{ ref: 'x', sha: 'a'.repeat(40) }],
    prior: [{ ref: 'x', sha: null }],
    readObserved: () => 'a'.repeat(40),
  })
  assert.equal(recoveryForReconcile(result), 'keep_assignment_no_redraw')
})

test('named gate: cleanup_never_deletes_successor_mutex', () => {
  assert.equal(cleanupMayDeleteMutex('b'.repeat(40), 'a'.repeat(40)), false)
})
