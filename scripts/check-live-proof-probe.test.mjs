import test from 'node:test'
import assert from 'node:assert/strict'
import { evaluateProbe, ProbeCheckError, scopeField } from './check-live-proof-probe.mjs'

const scope = (returnTo) => `x\n\`\`\`db-work-scope\nwork_type: structural\napplication_return_to: ${returnTo}\nlive_assertion: a\n\`\`\`\n`
const contract = { work_type: 'structural', work_issue: 3043 }
const migration = ['supabase/migrations/20260916120643_x.sql', '.agent/contract.json']

test('refuses a shared-db outcome migration without its probe', () => {
  assert.throws(() => evaluateProbe({ contract, changedFiles: migration, readIssueBody: () => scope('u2giants/shared-db'), probeExists: () => false }),
    (e) => e instanceof ProbeCheckError && /\.github\/live-proofs\/3043\.sql/.test(e.message))
})

test('accepts the probe carried in the same pull request', () => {
  const seen = []
  const r = evaluateProbe({ contract, changedFiles: migration, readIssueBody: () => scope('u2giants/shared-db'), probeExists: (p) => { seen.push(p); return true } })
  assert.equal(r.relevant, true)
  assert.deepEqual(seen, ['.github/live-proofs/3043.sql'])
})

test('application-return outcomes are not judged here', () => {
  const r = evaluateProbe({ contract, changedFiles: migration, readIssueBody: () => scope('u2giants/popdam3'), probeExists: () => false })
  assert.equal(r.relevant, false)
})

test('no migration or non-structural contract is not applicable and reads nothing', () => {
  const never = () => { throw new Error('must not read') }
  assert.equal(evaluateProbe({ contract, changedFiles: ['docs/a.md'], readIssueBody: never, probeExists: never }).relevant, false)
  assert.equal(evaluateProbe({ contract: { work_type: 'repo-maintenance', work_issue: 1 }, changedFiles: migration, readIssueBody: never, probeExists: never }).relevant, false)
})

test('ambiguous scope refuses', () => {
  assert.throws(() => scopeField(scope('a/b') + scope('c/d'), 'application_return_to'), ProbeCheckError)
  assert.throws(() => evaluateProbe({ contract: { work_type: 'structural' }, changedFiles: migration, readIssueBody: () => '', probeExists: () => true }), ProbeCheckError)
})
