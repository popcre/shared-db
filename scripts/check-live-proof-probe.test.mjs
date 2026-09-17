import test from 'node:test'
import assert from 'node:assert/strict'
import { evaluateProbe, ProbeCheckError, scopeField } from './check-live-proof-probe.mjs'

const scope = (returnTo) => `x\n\`\`\`db-work-scope\nwork_type: structural\napplication_return_to: ${returnTo}\nlive_assertion: a\n\`\`\`\n`
const contract = { work_type: 'structural', work_issue: 3043 }
const migration = ['supabase/migrations/20260916120643_x.sql', '.agent/contract.json']
const PROBE = 'select (count(*) = 1) as passed from plm.production_lane_canary;'
const never = () => { throw new Error('must not read') }

test('refuses a shared-db outcome migration without its probe', () => {
  assert.throws(() => evaluateProbe({ contract, changedFiles: migration, readIssueBody: () => scope('u2giants/shared-db'), readProbe: () => null }),
    (e) => e instanceof ProbeCheckError && /\.github\/live-proofs\/3043\.sql/.test(e.message))
})

test('accepts the probe carried in the pull request or already on main', () => {
  const seen = []
  const r = evaluateProbe({ contract, changedFiles: migration, readIssueBody: () => scope('u2giants/shared-db'), readProbe: (p) => { seen.push(p); return PROBE } })
  assert.equal(r.relevant, true)
  assert.deepEqual(seen, ['.github/live-proofs/3043.sql'])
})

test('refuses a probe that selects no passed column', () => {
  assert.throws(() => evaluateProbe({ contract, changedFiles: migration, readIssueBody: () => scope('u2giants/shared-db'), readProbe: () => '' }), /passed/)
})

test('application-return outcomes are not judged here', () => {
  const r = evaluateProbe({ contract, changedFiles: migration, readIssueBody: () => scope('u2giants/popdam3'), readProbe: never })
  assert.equal(r.relevant, false)
})

test('no migration, non-structural contract or code-truth restoration is not applicable', () => {
  assert.equal(evaluateProbe({ contract, changedFiles: ['docs/a.md'], readIssueBody: never, readProbe: never }).relevant, false)
  assert.equal(evaluateProbe({ contract: { work_type: 'repo-maintenance', work_issue: 1 }, changedFiles: migration, readIssueBody: never, readProbe: never }).relevant, false)
  assert.equal(evaluateProbe({ contract: null, changedFiles: migration, readIssueBody: never, readProbe: never, isCodeTruthRestoration: () => true }).relevant, false)
})

test('fails closed on a missing contract, work issue or return address', () => {
  assert.throws(() => evaluateProbe({ contract: null, changedFiles: migration, readIssueBody: never, readProbe: never }), ProbeCheckError)
  assert.throws(() => evaluateProbe({ contract: { work_type: 'structural' }, changedFiles: migration, readIssueBody: never, readProbe: never }), ProbeCheckError)
  assert.throws(() => evaluateProbe({ contract, changedFiles: migration, readIssueBody: () => '```db-work-scope\nwork_type: structural\n```', readProbe: never }), /application_return_to/)
  assert.throws(() => scopeField(scope('a/b') + scope('c/d'), 'application_return_to'), ProbeCheckError)
})

test('a transferred repository name and the historical name both count as this repository (#2530)', () => {
  for (const returnTo of ['popcre/shared-db', 'u2giants/shared-db']) {
    assert.throws(() => evaluateProbe({ contract, changedFiles: migration, readIssueBody: () => scope(returnTo), readProbe: () => null, repository: 'popcre/shared-db' }), ProbeCheckError)
  }
  const r = evaluateProbe({ contract, changedFiles: migration, readIssueBody: () => scope('popcre/popdam3'), readProbe: never, repository: 'popcre/shared-db' })
  assert.equal(r.relevant, false)
})
