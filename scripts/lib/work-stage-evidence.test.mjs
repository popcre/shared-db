import test from 'node:test'
import assert from 'node:assert/strict'
import { stageEventKey, validateStageEvent, findStageEvents, verifyAcceptedStage } from './work-stage-evidence.mjs'
import { classifyDependency, classifyDependencies, parseDependencyDeclarations, validateDependencyDeclaration, findDependencyCycles } from './work-dependencies.mjs'
import { expectedOperatorAssociation } from './repository-identity.mjs'

const event = (over = {}) => {
  const value = { schema_version: 1, repository: 'popcre/shared-db', work_issue: 10, stage: 'implementation-merged', pr: 99, head_sha: 'a'.repeat(40), merge_sha: 'b'.repeat(40), evidence_digest: 'c'.repeat(64), evidence_ref: 'refs/evidence/10/1', ...over }
  return { ...value, event_id: stageEventKey(value) }
}
const comment = value => ({ body: '```db-work-stage\n' + JSON.stringify(value) + '\n```', author: 'u2giants', author_association: expectedOperatorAssociation() })
const verified = () => Object.fromEntries(['repositoryMatches', 'issueLinked', 'prMerged', 'headMatches', 'mergeMatches', 'mergeInMain', 'evidenceDigestMatches', 'evidenceAuthorized', 'evidenceCurrent', 'notRevoked', 'stageAccepted'].map(key => [key, true]))
const state = (over = {}) => ({ exists: true, open: true, repository: 'popcre/shared-db', comments: [comment(event())], verifyStageEvidence: verified, ...over })
const declaration = { issue: 10, required_stage: 'implementation-merged' }

test('explicit declarations preserve numeric legacy semantics and reject unknown stages', () => {
  assert.deepEqual(parseDependencyDeclarations('#10, 11@live-verified'), [10, { issue: 11, required_stage: 'live-verified' }])
  assert.deepEqual(parseDependencyDeclarations([10, declaration]), [10, declaration])
  for (const value of ['0', '-1', '1@done', '1.5', '1e2', '9007199254740992']) assert.throws(() => parseDependencyDeclarations(value))
  assert.throws(() => parseDependencyDeclarations([{ ...declaration, optional: true }]), /unknown fields/)
  assert.throws(() => validateDependencyDeclaration(10, [declaration]), /itself/)
  assert.throws(() => validateDependencyDeclaration(1, [10, declaration]), /duplicate/)
  assert.deepEqual(findDependencyCycles({ 1: [{ issue: 2, required_stage: 'live-verified' }], 2: [1] }), [[1, 2, 1]])
})

test('open with verified explicit stage releases but old dependencies still require closure', () => {
  assert.equal(classifyDependency(declaration, state()).satisfied, true)
  assert.equal(classifyDependency(10, state()).satisfied, false)
  assert.equal(classifyDependency({ issue: 10, required_stage: 'complete' }, state()).satisfied, false)
  assert.equal(classifyDependencies(1, [declaration], { 10: state() }).satisfied, true)
  assert.equal(classifyDependency(declaration, state({ open: false, comments: [] })).satisfied, false)
})

test('stage readiness requires every independently verified current-world check', () => {
  for (const field of Object.keys(verified())) {
    for (const value of [false, undefined]) {
      const result = classifyDependency(declaration, state({ verifyStageEvidence: () => ({ ...verified(), [field]: value }) }))
      assert.equal(result.satisfied, false, field)
      assert.match(result.reason, new RegExp(field))
    }
  }
  for (const verifyStageEvidence of [undefined, () => Promise.resolve(verified()), () => { throw new Error('HTTP 429') }]) {
    assert.equal(classifyDependency(declaration, state({ verifyStageEvidence })).satisfied, false)
  }
})

test('forged, wrong repository, wrong issue, wrong stage and unauthorized author cannot release', () => {
  for (const over of [{ repository: 'attacker/shared-db' }, { work_issue: 11 }, { stage: 'live-verified' }, { event_id: 'forged' }]) {
    const value = { ...event(), ...over }
    if (!over.event_id) value.event_id = stageEventKey(value)
    assert.equal(classifyDependency(declaration, state({ comments: [comment(value)] })).satisfied, false)
  }
  assert.equal(classifyDependency(declaration, state({ comments: [{ ...comment(event()), author: 'attacker' }] })).satisfied, false)
  assert.equal(classifyDependency(declaration, state({ repository: undefined })).satisfied, false)
})

test('duplicate delivery has one event identity; contradictory reuse blocks', () => {
  assert.equal(findStageEvents([comment(event()), comment(event())]).length, 1)
  assert.equal(classifyDependency(declaration, state({ comments: [comment(event()), comment(event())] })).events.length, 1)
  assert.throws(() => findStageEvents([comment(event()), comment(event({ pr: 100 }))]), /conflicting/)
  assert.throws(() => validateStageEvent(event({ stage: 'complete' })), /final record/)
})

test('no later stage implies earlier acceptance and no newer evidence hides revoked evidence', () => {
  assert.equal(classifyDependency({ issue: 10, required_stage: 'live-verified' }, state()).satisfied, false)
  const comments = [comment(event()), comment(event({ evidence_digest: 'd'.repeat(64) }))]
  const result = classifyDependency(declaration, state({ comments, verifyStageEvidence: value => ({ ...verified(), notRevoked: value.evidence_digest !== 'c'.repeat(64) }) }))
  assert.equal(result.satisfied, false)
})

test('immutable final record contradictions fail before stage acceptance', () => {
  const finalComment = record => ({ ...comment(event()), body: '```db-work-completion\n' + JSON.stringify(record) + '\n```' })
  for (const record of [
    { schema_version: 1, work_issue: 10, outcome: 'cancelled', reason: 'cancelled' },
    { schema_version: 1, work_issue: 11, outcome: 'merged', pr: 99, merge_sha: 'b'.repeat(40), migration_versions: [] },
    { schema_version: 1, work_issue: 10, outcome: 'merged', pr: 100, merge_sha: 'b'.repeat(40), migration_versions: [] },
    { schema_version: 1, work_issue: 10, outcome: 'merged', pr: 99, merge_sha: 'd'.repeat(40), migration_versions: [] },
  ]) assert.equal(classifyDependency(declaration, state({ comments: [comment(event()), finalComment(record)] })).satisfied, false)
})
