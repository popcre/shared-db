import test from 'node:test'
import assert from 'node:assert/strict'
import { ownerReviewerReuseAllowed, ownerReuseEntries } from './owner-reviewer-reuse.mjs'

const doc = (entries) => () => JSON.stringify({ schema: 'shared-db-owner-reviewer-reuse/v1', entries })
const entry = { pr: 4206, issue: 2336, reviewer: 'muse-spark-1.3-contributor', owner_quote: 'let Muse review twice' }

test('owner-listed PR allows reuse only for slot 2 or later', () => {
  assert.equal(ownerReviewerReuseAllowed({ pr: 4206, slot: 2 }, doc([entry])), true)
  assert.equal(ownerReviewerReuseAllowed({ pr: 4206, slot: 1 }, doc([entry])), false)
})
test('reviewer must match the owner-named reviewer when given', () => {
  assert.equal(ownerReviewerReuseAllowed({ pr: 4206, slot: 2, reviewer: 'muse-spark-1.3-contributor' }, doc([entry])), true)
  assert.equal(ownerReviewerReuseAllowed({ pr: 4206, slot: 2, reviewer: 'glm-5.3' }, doc([entry])), false)
})
test('unlisted PR, missing quote, bad schema or unreadable file grant nothing', () => {
  assert.equal(ownerReviewerReuseAllowed({ pr: 9999, slot: 2 }, doc([entry])), false)
  assert.equal(ownerReviewerReuseAllowed({ pr: 4206, slot: 2 }, doc([{ ...entry, owner_quote: ' ' }])), false)
  assert.equal(ownerReviewerReuseAllowed({ pr: 4206, slot: 2 }, () => JSON.stringify({ schema: 'x', entries: [entry] })), false)
  assert.equal(ownerReviewerReuseAllowed({ pr: 4206, slot: 2 }, () => { throw new Error('nope') }), false)
})
test('committed list names only PR 4206 with a verbatim quote', () => {
  const rows = ownerReuseEntries()
  assert.deepEqual(rows.map((r) => r.pr), [4206])
  assert.match(rows[0].owner_quote, /let Muse review twice/)
})
