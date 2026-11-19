import test from 'node:test'
import assert from 'node:assert/strict'
import { allowanceLine, reportAllowances } from './report-token-allowance.mjs'

test('prints counts only, and unavailable for a missing, failing or malformed read', () => {
  assert.equal(allowanceLine('A', { resources: { core: { used: 3, limit: 5000 } } }), 'A used=3 limit=5000')
  assert.equal(allowanceLine('A', {}), 'A unavailable')
  const ok = (args) => { assert.deepEqual(args, ['api', 'rate_limit']); return { resources: { core: { used: 1, limit: 2 } } } }
  assert.deepEqual(reportAllowances(['A', 'B'], { env: { A: 'tok' }, read: ok }), ['A used=1 limit=2', 'B unavailable'])
  const fail = () => { throw new Error('refused') }
  assert.deepEqual(reportAllowances(['A'], { env: { A: 'tok' }, read: fail }), ['A unavailable'])
})
