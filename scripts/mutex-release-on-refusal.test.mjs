// Issue #3791: Shared Supabase Migrations run 36506351098 took the author mutex for
// an admission, was refused by an exhausted API quota, and its finally's own
// owner-check read was refused too -- the mutex was never released.
import test from 'node:test'
import assert from 'node:assert/strict'
import { withAuthorMutex, releaseMutexOnExit, releaseRefOverGit, MUTEX_REF } from './manage-migration-author-lanes.mjs'

const rateLimited = () => { const e = new Error('GitHub command failed: GitHub API rate limit exceeded (host-wide latch; no request sent)'); e.rateLimitExhausted = true; return e }

function fakeIo({ gitRelease = true } = {}) {
  const refs = new Map()
  let quotaGone = false
  const io = {
    refs, gitCalls: [],
    exhaust() { quotaGone = true },
    makeOwnerCommit: () => 'a'.repeat(40),
    readRef(ref) { if (quotaGone) throw rateLimited(); return refs.get(ref) ?? null },
    createRef(ref, sha) { if (quotaGone) throw rateLimited(); if (refs.has(ref)) return false; refs.set(ref, sha); return true },
    deleteRef(ref) { if (quotaGone) throw rateLimited(); refs.delete(ref) },
    wait: () => {},
  }
  if (gitRelease) io.releaseRefOverGit = (ref, sha) => { io.gitCalls.push([ref, sha]); if (refs.get(ref) !== sha) return false; refs.delete(ref); return true }
  return io
}

test('a rate-limit refusal mid-admission still releases the author mutex (over git)', () => {
  const io = fakeIo()
  assert.throws(() => withAuthorMutex('admission', io, { requestId: 'r' }, () => {
    assert.equal(io.refs.get(MUTEX_REF), 'a'.repeat(40), 'the mutex is held inside the operation')
    io.exhaust()
    throw rateLimited()
  }), /rate limit/, 'the ORIGINAL refusal still reaches the caller')
  assert.equal(io.refs.has(MUTEX_REF), false, 'the mutex was released')
  assert.deepEqual(io.gitCalls, [[MUTEX_REF, 'a'.repeat(40)]])
})

test('the healthy path releases over the API and never touches git', () => {
  const io = fakeIo()
  assert.equal(withAuthorMutex('admission', io, { requestId: 'r' }, () => 7), 7)
  assert.equal(io.refs.has(MUTEX_REF), false)
  assert.deepEqual(io.gitCalls, [])
})

test('a successor-owned mutex is never deleted by the git fallback', () => {
  const io = fakeIo(); io.refs.set(MUTEX_REF, 'b'.repeat(40)); io.exhaust()
  releaseMutexOnExit('a'.repeat(40), io)
  assert.equal(io.refs.get(MUTEX_REF), 'b'.repeat(40))
})

test('when both releases fail, the error names the held SHA and the recovery command', () => {
  const io = fakeIo({ gitRelease: false }); io.releaseRefOverGit = () => { throw new Error('push refused') }
  io.refs.set(MUTEX_REF, 'a'.repeat(40)); io.exhaust()
  assert.throws(() => releaseMutexOnExit('a'.repeat(40), io), /may still be held by a{40}.*--recover-author-mutex/)
})

test('releaseRefOverGit deletes only with a lease on our exact SHA', () => {
  const calls = []; let current = 'a'.repeat(40)
  const listRefs = () => new Map(current ? [[MUTEX_REF, current]] : [])
  const run = (bin, args) => { calls.push([bin, ...args]); current = null; return '' }
  assert.equal(releaseRefOverGit(MUTEX_REF, 'a'.repeat(40), { run, listRefs }), true)
  assert.deepEqual(calls[0], ['git', 'push', '--porcelain', `--force-with-lease=${MUTEX_REF}:${'a'.repeat(40)}`, 'origin', `:${MUTEX_REF}`])
  current = 'b'.repeat(40); calls.length = 0
  assert.equal(releaseRefOverGit(MUTEX_REF, 'a'.repeat(40), { run, listRefs }), false)
  assert.equal(calls.length, 0, 'another owner: no push at all')
})
