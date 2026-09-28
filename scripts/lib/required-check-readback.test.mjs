import assert from 'node:assert/strict'
import test from 'node:test'
import { readRequiredCheckContexts } from './required-check-readback.mjs'

const branch = () => ({ name: 'main', protected: true, protection: { enabled: true, required_status_checks: { contexts: ['A', 'B'], checks: [{ context: 'A', app_id: 15368 }, { context: 'B', app_id: 15368 }] } } })
const branchRules = () => []
const denied = () => { throw new Error('GitHub command failed: gh: Resource not accessible by integration (HTTP 403)') }

test('falls back to the protected branch readback on the Actions token 403', () => {
  assert.deepEqual(readRequiredCheckContexts({ protectedChecks: denied, branch, branchRules }), ['A', 'B'])
})

test('compares both readable endpoints and rejects disagreement', () => {
  assert.deepEqual(readRequiredCheckContexts({ protectedChecks: () => ({ contexts: ['B', 'A'], checks: [{ context: 'A' }, { context: 'B' }] }), branch, branchRules }), ['A', 'B'])
  assert.throws(() => readRequiredCheckContexts({ protectedChecks: () => ({ contexts: ['A'], checks: [{ context: 'A' }] }), branch, branchRules }), /disagree/)
})

test('refuses absent protection and ruleset ambiguity', () => {
  assert.throws(() => readRequiredCheckContexts({ protectedChecks: denied, branch: () => ({ name: 'main', protected: true }), branchRules }), /absent or ambiguous/)
  assert.throws(() => readRequiredCheckContexts({ protectedChecks: denied, branch, branchRules: () => [{ type: 'required_status_checks' }] }), /ruleset readback/)
  assert.throws(() => readRequiredCheckContexts({ protectedChecks: denied, branch, branchRules: () => null }), /ruleset readback/)
  assert.throws(() => readRequiredCheckContexts({ protectedChecks: denied, branch: () => ({ name: 'main', protected: true, protection: { enabled: true, required_status_checks: {} } }), branchRules }), /absent or malformed/)
  assert.throws(() => readRequiredCheckContexts({ protectedChecks: denied, branch: () => ({ name: 'main', protected: true, protection: { enabled: true, required_status_checks: { contexts: ['A'], checks: [{ context: 'A' }, { context: 'B' }] } } }), branchRules }), /identities disagree/)
})

test('does not treat unrelated transport failures as an authority fallback', () => {
  assert.throws(() => readRequiredCheckContexts({ protectedChecks: () => { throw new Error('rate limit exceeded (HTTP 403)') }, branch, branchRules }), /rate limit exceeded/)
})
