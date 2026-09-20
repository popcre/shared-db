import { createHash } from 'node:crypto'
import { isTrustedOperatorComment } from './repository-identity.mjs'

export const REQUIRED_STAGES = Object.freeze(['implementation-merged', 'database-applied', 'live-verified', 'application-accepted', 'complete'])
export const STAGE_FENCE = 'db-work-stage'
const SHA = /^[0-9a-f]{40}$/
const DIGEST = /^[0-9a-f]{64}$/
const REPOSITORY = /^[A-Za-z0-9_.-]+\/[A-Za-z0-9_.-]+$/

export function stageEventKey(event) {
  return createHash('sha256').update(JSON.stringify([
    event.repository, event.work_issue, event.stage, event.evidence_digest,
  ])).digest('hex')
}

export function validateStageEvent(event) {
  if (!event || Array.isArray(event) || event.schema_version !== 1) throw new Error('stage event schema_version must be 1')
  if (!REPOSITORY.test(event.repository ?? '')) throw new Error('stage event repository is required')
  if (!Number.isSafeInteger(event.work_issue) || event.work_issue <= 0) throw new Error('stage event work_issue must be positive')
  if (!REQUIRED_STAGES.includes(event.stage) || event.stage === 'complete') throw new Error('stage event must name an intermediate required stage; complete uses the final record')
  if (!Number.isSafeInteger(event.pr) || event.pr <= 0) throw new Error('stage event pr must be positive')
  for (const field of ['head_sha', 'merge_sha']) if (!SHA.test(event[field] ?? '')) throw new Error(`stage event ${field} must be an exact SHA`)
  if (!DIGEST.test(event.evidence_digest ?? '')) throw new Error('stage event evidence_digest must be sha256')
  if (typeof event.evidence_ref !== 'string' || !event.evidence_ref.trim()) throw new Error('stage event evidence_ref is required')
  if (event.event_id !== stageEventKey(event)) throw new Error('stage event id does not bind task, stage and evidence digest')
  return event
}

// Comments are transport, never proof. The trusted operator may publish an event,
// but current repository facts and stage-specific evidence must still verify it.
export function findStageEvents(comments) {
  const events = new Map()
  for (const comment of comments ?? []) {
    const matches = [...String(comment?.body ?? '').matchAll(/```db-work-stage\s*\n([\s\S]*?)```/g)]
    if (!matches.length) continue
    if (!isTrustedOperatorComment(comment)) throw new Error('stage event author is not the trusted repository operator')
    if (matches.length !== 1) throw new Error('a stage comment must contain exactly one event')
    const event = validateStageEvent(JSON.parse(matches[0][1]))
    const prior = events.get(event.event_id)
    if (prior && JSON.stringify(prior) !== JSON.stringify(event)) throw new Error('conflicting stage event reuses an immutable event id')
    events.set(event.event_id, event)
  }
  return [...events.values()]
}

/**
 * This reader performs no network IO. `verify` is a current-world verifier owned
 * by the caller, NOT a field accepted from the issue/comment. It must return all
 * named checks after fetching the exact repository/issue/PR and immutable evidence.
 * Missing verifier/checks never authorize readiness. No stage implies another.
 */
export function verifyAcceptedStage({ issue, stage, repository, comments, verify }) {
  if (!REPOSITORY.test(repository ?? '')) throw new Error('current repository identity is required')
  if (!REQUIRED_STAGES.includes(stage) || stage === 'complete') throw new Error('intermediate required stage is invalid')
  const events = findStageEvents(comments).filter(event => event.work_issue === issue && event.stage === stage)
  if (!events.length) return { satisfied: false, status: 'waiting', reason: `dependency #${issue} has no ${stage} event` }
  if (typeof verify !== 'function') throw new Error('current-world stage evidence verifier is unavailable')
  // Every claim for the selected stage must verify. A newer event cannot hide a
  // revoked/conflicting earlier claim; explicit repair is needed instead.
  for (const event of events) {
    if (event.repository !== repository) throw new Error('stage event repository does not match the current repository')
    const proof = verify(event)
    if (!proof || typeof proof.then === 'function') throw new Error('stage verifier must return completed evidence checks')
    const checks = ['repositoryMatches', 'issueLinked', 'prMerged', 'headMatches', 'mergeMatches', 'mergeInMain', 'evidenceDigestMatches', 'evidenceAuthorized', 'evidenceCurrent', 'notRevoked', 'stageAccepted']
    for (const check of checks) if (proof[check] !== true) throw new Error(`stage evidence did not prove ${check}`)
  }
  return { satisfied: true, status: 'accepted-stage', reason: `dependency #${issue} verified ${stage}; issue closure is administrative`, events }
}
