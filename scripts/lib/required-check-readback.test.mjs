import assert from 'node:assert/strict'
import test from 'node:test'
import { readRequiredCheckContexts } from './required-check-readback.mjs'

const checks = [{ context: 'A', app_id: 15368 }, { context: 'B', app_id: 15368 }]
const branch = () => ({ name: 'main', protected: true, commit: { sha: 'a'.repeat(40) }, protection: { enabled: true, required_status_checks: { contexts: ['A', 'B'], checks } } })
const repository = () => ({ id: 1275568548, full_name: 'popcre/shared-db' })
const branchRules = () => [[]]
const denied = () => { throw new Error('GitHub command failed: gh: Resource not accessible by integration (HTTP 403)') }
const read = (overrides = {}) => readRequiredCheckContexts({ protectedChecks: denied, branch, branchRules, repository, ...overrides })
const rule = (type, values = {}) => ({ type, ruleset_id: 24024180, ruleset_source: 'popcre/shared-db', ruleset_source_type: 'Repository', ...values })

test('falls back to the protected branch readback on the Actions token 403', () => {
  assert.deepEqual(read(), ['A', 'B'])
})

test('accepts active merge queue and reconciles required checks from active rulesets', () => {
  assert.deepEqual(read({ branchRules: () => [[rule('merge_queue')]] }), ['A', 'B'])
  assert.deepEqual(read({ branchRules: () => [[rule('required_status_checks', { parameters: { required_status_checks: [{ context: 'C', integration_id: 15368 }] } })]] }), ['A', 'B', 'C'])
  assert.throws(() => read({ branchRules: () => [[rule('required_status_checks', { parameters: { required_status_checks: [{ context: 'A', integration_id: 42 }] } })]] }), /ambiguous producer/)
})

test('compares both readable endpoints including producer identity', () => {
  assert.deepEqual(read({ protectedChecks: () => ({ contexts: ['B', 'A'], checks: [...checks].reverse() }) }), ['A', 'B'])
  assert.throws(() => read({ protectedChecks: () => ({ contexts: ['A', 'B'], checks: [{ context: 'A', app_id: 42 }, checks[1]] }) }), /identities disagree/)
})

test('refuses empty checks, extra check, wrong repository, and ambiguous rules', () => {
  assert.throws(() => read({ branch: () => ({ ...branch(), protection: { enabled: true, required_status_checks: { contexts: [], checks: [] } } }) }), /absent or disagree/)
  assert.throws(() => read({ branch: () => ({ ...branch(), protection: { enabled: true, required_status_checks: { contexts: ['A', 'B'], checks: [...checks, { context: 'C', app_id: 15368 }] } } }) }), /absent or disagree/)
  assert.throws(() => read({ repository: () => ({ id: 1, full_name: 'popcre/shared-db' }) }), /repository identity/)
  assert.throws(() => read({ branchRules: () => null }), /pagination/)
  assert.throws(() => read({ branchRules: () => [[{ type: 'merge_queue' }]] }), /source identity/)
  const fullPage = Array.from({ length: 100 }, () => rule('merge_queue'))
  assert.throws(() => read({ branchRules: () => [fullPage] }), /explicit end page/)
  assert.deepEqual(read({ branchRules: () => [fullPage], confirmRulesEnd: () => [] }), ['A', 'B'])
  assert.throws(() => read({ branch: () => ({ name: 'main', protected: true }) }), /absent or ambiguous/)
})

test('does not treat unrelated transport failures as an authority fallback', () => {
  assert.throws(() => read({ protectedChecks: () => { throw new Error('rate limit exceeded (HTTP 403)') } }), /rate limit exceeded/)
})
