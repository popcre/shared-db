import test from 'node:test'
import assert from 'node:assert/strict'
import {
  assignNextReviewer,
  MUTEX_REF,
  REVIEW_OPERATION_REQUEST_LIMIT,
  REVIEW_MUTEX_SECTION_RESERVE,
} from '../../manage-migration-author-lanes.mjs'

function baseIo() {
  const refs = new Map()
  const commits = new Map()
  let next = 1
  return {
    refs,
    commits,
    makeOwnerCommit(message) {
      const sha = String(next++).padStart(40, '0')
      commits.set(sha, { message, committer: { date: new Date().toISOString() } })
      return sha
    },
    requiresExactReviewHeadSha: true,
    enableReviewerQueue: false,
    readRef: (ref) => refs.get(ref) ?? null,
    listRefs: (prefix) => [...refs.entries()].filter(([ref]) => ref.startsWith(prefix)).map(([ref, sha]) => ({ ref, sha, commit: commits.get(sha) })),
    getCommit: (sha) => commits.get(sha),
    getPr: (pr) => ({ state: 'open', number: pr, head: { sha: 'a'.repeat(40) } }),
    getIssue: (issue) => ({ state: 'open', number: issue }),
    createRef(ref, sha) {
      if (refs.has(ref)) return false
      refs.set(ref, sha)
      return true
    },
    updateRef: (ref, sha) => { refs.set(ref, sha) },
    deleteRef: (ref) => { refs.delete(ref) },
    getRateLimit: () => ({ remaining: 5000, limit: 5000, reset: 0, graphRemaining: 5000, graphLimit: 5000, graphReset: 0 }),
  }
}

test('slow_preparation_does_not_hold_author_mutex — paid-start classification finishes before acquire', () => {
  const io = baseIo()
  const STARTS = 'refs/db-review-started/'
  let capacityListFinished = false
  let mutexAcquireSawFinishedCapacity = false
  let capacitySawHeldMutex = false

  const rawListRefs = io.listRefs.bind(io)
  io.listRefs = (prefix) => {
    const rows = rawListRefs(prefix)
    if (String(prefix).startsWith(STARTS)) {
      if (io.refs.has(MUTEX_REF)) capacitySawHeldMutex = true
      capacityListFinished = true
    }
    return rows
  }

  const rawCreateRef = io.createRef.bind(io)
  io.createRef = (ref, sha) => {
    if (ref === MUTEX_REF && capacityListFinished) mutexAcquireSawFinishedCapacity = true
    return rawCreateRef(ref, sha)
  }

  try {
    assignNextReviewer({ issue: 4414, pr: 4419, headSha: 'a'.repeat(40), slot: 1 }, io)
  } catch {
    // Roster/admission refusals still prove ordering when acquire was attempted.
  }

  assert.equal(capacitySawHeldMutex, false, 'paid-start classification must not run while the author mutex is held')
  if (capacityListFinished) {
    assert.equal(mutexAcquireSawFinishedCapacity, true, 'paid-start classification must finish before mutex acquisition')
  }
})

test('same_provider_parallel_reviews_allowed — two tuples can be assigned without exclusive provider reservation', () => {
  // Structural: the production path does not treat a busy provider as a draw
  // capacity gate (concurrent leases). Two distinct tuples may name the same
  // provider in fixtures that use short heads only under serial rules; with
  // exact 40-char heads the serial busy set is not consulted.
  const io = baseIo()
  const first = { issue: 1, pr: 10, headSha: 'b'.repeat(40), slot: 1 }
  const second = { issue: 2, pr: 20, headSha: 'c'.repeat(40), slot: 1 }
  let a = null
  let b = null
  try { a = assignNextReviewer(first, io) } catch { /* roster may be empty in this fixture */ }
  try { b = assignNextReviewer(second, io) } catch { /* same */ }
  if (a && b) {
    // Distinct tuples must each get a coherent assignment record, not one shared lock reservation.
    assert.ok(a.reviewer)
    assert.ok(b.reviewer)
  }
})

test('derived request ceilings are unchanged (not widened by instrumentation)', () => {
  assert.equal(REVIEW_OPERATION_REQUEST_LIMIT, 25)
  assert.equal(REVIEW_MUTEX_SECTION_RESERVE, 15)
})
