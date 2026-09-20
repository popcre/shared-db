import test from 'node:test'
import assert from 'node:assert/strict'
import { readEffectiveRequiredChecks } from './required-check-authority.mjs'
const sha = 'a'.repeat(40)
const rule = { id: 'BPR_1', requiresStatusChecks: true, requiresStrictStatusChecks: false, requiredStatusCheckContexts: ['required'], requiredStatusChecks: [{ context: 'required', app: { databaseId: 15368 } }] }
export function fixture(rules = [], mutate = () => {}) {
  const response = { data: { repository: { databaseId: 1, nameWithOwner: 'popcre/shared-db', ref: { name: 'main', target: { oid: sha }, branchProtectionRule: structuredClone(rule) } } } }
  mutate(response)
  return { repo: 'popcre/shared-db', read: (args) => args.includes('graphql') ? response : [rules] }
}
test('resolves classic protection and allowed producer from a fresh identified branch', () => {
  const result = readEffectiveRequiredChecks(fixture())
  assert.deepEqual(result.checks, [{ context: 'required', app_id: 15368 }])
  assert.equal(result.base_sha, sha)
  assert.match(result.revision, /^[a-f0-9]{64}$/)
})
test('new inherited ruleset changes effective revision even with a still-unexpired old snapshot', () => {
  const old = readEffectiveRequiredChecks(fixture())
  old.expires = '2099-01-01'
  const added = { type: 'required_status_checks', ruleset_id: 12, ruleset_source_type: 'Organization', ruleset_source: 'popcre', parameters: { required_status_checks: [{ context: 'new required', integration_id: 7 }] } }
  const current = readEffectiveRequiredChecks(fixture([added]))
  assert.notEqual(current.revision, old.revision)
  assert.equal(current.checks.length, 2)
})
test('refuses transport denial, partial GraphQL, malformed pagination, wrong repository and missing producer', () => {
  assert.throws(() => readEffectiveRequiredChecks({ repo: 'popcre/shared-db', read() { throw Error('403') } }), /403/)
  for (const mutation of [
    (r) => { r.errors = [{ message: 'denied' }] },
    (r) => { r.data.repository.databaseId = null },
    (r) => { r.data.repository.nameWithOwner = 'other/repo' },
    (r) => { r.data.repository.ref.branchProtectionRule.requiredStatusChecks[0].app = {} },
    (r) => { r.data.repository.ref.branchProtectionRule.requiredStatusCheckContexts.push('lost') },
  ]) assert.throws(() => readEffectiveRequiredChecks(fixture([], mutation)))
  const input = fixture(); const read = input.read
  input.read = (args) => args.includes('graphql') ? read(args) : []
  assert.throws(() => readEffectiveRequiredChecks(input), /incomplete/)
})
test('null classic protection requires a known effective ruleset and empty policy refuses', () => {
  assert.throws(() => readEffectiveRequiredChecks(fixture([], (r) => { r.data.repository.ref.branchProtectionRule = null })), /no checks/)
})
