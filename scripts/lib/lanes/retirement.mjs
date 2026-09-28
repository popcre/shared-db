// Split from scripts/manage-migration-author-lanes.mjs (issue #3726). Behavior-preserving move:
// the entrypoint re-exports every public name defined here. Edit here, not there.
import { LaneError, parseAuthorLease } from './claims.mjs'
import { RETIRED_CLAIM_REF_PREFIX, RETIREMENT_DECISIONS, RETIREMENT_OWNER_DECISION_STATES, RETIREMENT_RECORD_PREFIX, RETIREMENT_SCHEMA_VERSION, WORKTREE_STATES } from './constants.mjs'
import { validateImmutableArtifactReference } from './claim-maintenance.mjs'
import { githubIo, resetRetirementSnapshot, retirementSnapshot } from '../../manage-migration-author-lanes.mjs'

// ISSUE #2448 — a close comment must state the cause that actually ran.
// Every path that closes a claim names its own mechanism; nothing claims an
// expiry sweep, because no expiry sweep exists (`--cleanup-stale` closes
// nothing). The legacy string is retained ONLY so historical recovery can still
// read claims that were closed before this repair.
export const LEGACY_GUARDED_CLEANUP_CLOSE_REASON = 'Expired migration-author lease closed by guarded cleanup. Its migration version remains unavailable.'
export const CLAIM_CLOSE_REASONS = {
  acquisitionRollback: 'Migration-author claim closed by acquisition rollback: the coordination mutex was lost before this newly created claim could be confirmed. No lease expired and no cleanup sweep ran. Its migration version remains unavailable.',
  explicitRelease: 'Migration-author claim closed by an explicit owner-confirmed release (--release-claim). No lease expired and no cleanup sweep ran. Its migration version remains unavailable.',
  duplicateRelease: 'Duplicate migration-author claim closed by an explicit owner-confirmed duplicate release (--release-duplicate-claim), proved against live GitHub state: another open claim on the same branch holds the migration version that the single open pull request on that branch actually uses. No lease expired and no cleanup sweep ran. Its migration version remains unavailable.',
}
// A closed claim may be recovered only when its close comment records a
// deliberate, owner-confirmed release (or the pre-repair legacy string that
// such releases used to post). A rollback close is not recoverable.
export const RECOVERABLE_CLAIM_CLOSE_REASONS = new Set([LEGACY_GUARDED_CLEANUP_CLOSE_REASON, CLAIM_CLOSE_REASONS.explicitRelease])
export function requireClaimCloseReason(reason) {
  if (typeof reason !== 'string' || !reason.trim()) throw new LaneError('closing a claim requires an exact stated reason')
  return reason
}

// ---------------------------------------------------------------------------
// Terminal retirement tombstones (issue #2301, Step 3)
// ---------------------------------------------------------------------------

export const RETIREMENT_CLOSE_REASON = 'Migration-author claim closed by an explicit owner-confirmed terminal retirement (--release-claim with retirement evidence). An immutable tombstone under refs/db-claims-retired records the decision. No lease expired and no cleanup sweep ran. Its migration version remains permanently unavailable and this claim can never be resumed, renewed, expanded, or merged.'

export function retiredClaimRef(version) {
  if (!/^\d{14}$/.test(String(version ?? ''))) throw new LaneError('retirement ref requires an exact 14-digit migration version')
  return `${RETIRED_CLAIM_REF_PREFIX}/${version}`
}

// Identity comparison for branch and worktree reuse. Windows worktree paths
// reach this file with either slash, sometimes with a trailing one, and Git
// branch names are compared exactly -- but a path that differs only in case or
// separator is the SAME directory, and treating it as a new one is exactly how
// a retired worktree gets resurrected under a cosmetically different spelling.
export function normalizeRetirementIdentity(value) {
  return String(value ?? '').trim().replace(/\\/g, '/').replace(/\/+$/, '').toLowerCase()
}

export const RETIREMENT_REQUIRED_FIELDS = Object.freeze(['schema_version', 'claim', 'pr', 'head_sha', 'branch', 'version', 'worktree', 'worktree_state', 'decision', 'evidence', 'successor_issue', 'created_at'])

/**
 * Validate a retirement record. EVERY field is required, including
 * `successor_issue` -- which is explicitly `null` when there is no successor.
 * An OPTIONAL successor field would make "no successor" and "the writer forgot"
 * the same record, and Step 3 requires a successor to be nameable.
 */
export function validateRetirementRecord(record) {
  if (record === null || typeof record !== 'object' || Array.isArray(record)) throw new LaneError('retirement record must be a JSON object')
  for (const field of RETIREMENT_REQUIRED_FIELDS) if (record[field] === undefined) throw new LaneError(`retirement record is missing ${field}`)
  // Unknown keys are refused for the same reason the work contract refuses them:
  // a typo silently drops a binding, and a dropped binding is indistinguishable
  // from one that was never required.
  for (const key of Object.keys(record)) if (!RETIREMENT_REQUIRED_FIELDS.includes(key) && key !== 'owner_decision') throw new LaneError(`retirement record has unknown field ${key}`)
  if (record.schema_version !== RETIREMENT_SCHEMA_VERSION) throw new LaneError(`retirement record schema_version must be ${RETIREMENT_SCHEMA_VERSION}`)
  if (!Number.isInteger(record.claim) || record.claim <= 0) throw new LaneError('retirement record claim must be a positive issue number')
  if (!Number.isInteger(record.pr) || record.pr <= 0) throw new LaneError('retirement record pr must be a positive pull request number')
  if (!/^[0-9a-f]{40}$/.test(String(record.head_sha))) throw new LaneError('retirement record head_sha must be an exact 40-character commit SHA')
  if (!/^\d{14}$/.test(String(record.version))) throw new LaneError('retirement record version must be exactly 14 digits')
  for (const field of ['branch', 'worktree', 'evidence']) {
    if (typeof record[field] !== 'string' || !record[field].trim()) throw new LaneError(`retirement record ${field} must be a non-empty string`)
  }
  if (!WORKTREE_STATES.includes(record.worktree_state)) throw new LaneError(`retirement record worktree_state must be one of ${WORKTREE_STATES.join(', ')}`)
  if (!RETIREMENT_DECISIONS.includes(record.decision)) throw new LaneError(`retirement record decision must be one of ${RETIREMENT_DECISIONS.join(', ')}`)
  if (record.successor_issue !== null && (!Number.isInteger(record.successor_issue) || record.successor_issue <= 0)) throw new LaneError('retirement record successor_issue must be a positive issue number or null')
  if (record.decision === 'superseded-by-successor' && record.successor_issue === null) throw new LaneError('a superseded-by-successor retirement must name its successor issue')
  if (Number.isNaN(Date.parse(String(record.created_at)))) throw new LaneError('retirement record created_at must be a valid ISO timestamp')
  // Unmerged work on a dirty or remote tree is destroyed by retirement, so the
  // decision must be durable and dereferenceable, never a sentence typed at the
  // command line.
  if (RETIREMENT_OWNER_DECISION_STATES.includes(record.worktree_state)) {
    if (!record.owner_decision) throw new LaneError(`terminal retirement from a ${record.worktree_state} worktree requires an owner-decision record`)
    validateImmutableArtifactReference(record.owner_decision, 'retirement owner_decision')
  } else if (record.owner_decision !== undefined) throw new LaneError('owner_decision is allowed only for a dirty or remote worktree retirement')
  return record
}

export function formatRetirementRecord(record) {
  return `${RETIREMENT_RECORD_PREFIX}${JSON.stringify(validateRetirementRecord(record))}`
}

/**
 * FAIL CLOSED. A ref that exists in this namespace but whose commit message is
 * unreadable, truncated, or not a retirement record is NOT treated as "no
 * retirement" -- that is the direction that lets a corrupted tombstone resurrect
 * a claim. It throws, and the operator repairs the record.
 */
export function parseRetirementRecord(message) {
  const text = String(message ?? '')
  if (!text.startsWith(RETIREMENT_RECORD_PREFIX)) throw new LaneError('retirement ref does not point to a retirement record')
  let payload
  try { payload = JSON.parse(text.slice(RETIREMENT_RECORD_PREFIX.length)) }
  catch { throw new LaneError('retirement record is not readable JSON') }
  return validateRetirementRecord(payload)
}

export function isVersionRetired(version, io = githubIo) {
  return retirementSnapshot(io).versions.has(String(version ?? ''))
}

export function readRetirementRecord(version, io = githubIo) {
  const sha = retirementSnapshot(io).versions.get(String(version ?? ''))
  if (!sha) return null
  const message = io.readCommitMessage(sha)
  // `readCommitMessage` returns null when the commit is unreadable. A retirement
  // ref whose target cannot be read is an UNKNOWN terminal state, not an absent
  // one, so it refuses rather than returning null.
  if (message === null || message === undefined) throw new LaneError(`retirement record for ${version} is unreadable; refusing rather than treating it as not retired`)
  return parseRetirementRecord(message)
}

/**
 * The single refusal every claim-reactivation path calls. `action` names the
 * command so the operator is told which mutation was refused and why, instead of
 * a generic "claim is closed".
 */
export function assertClaimNotRetired(version, action, io = githubIo) {
  if (!isVersionRetired(version, io)) return null
  const record = readRetirementRecord(version, io)
  const successor = record.successor_issue ? `; successor work is issue #${record.successor_issue}` : '; a successor needs a fresh claim, branch, worktree and migration version'
  throw new LaneError(`migration version ${version} was terminally retired (${record.decision}, claim #${record.claim}, PR #${record.pr}) and can never be ${action}${successor}`)
}

/**
 * Branch and worktree identities are never reused, whether the holder is a live
 * claim or a tombstone. Reusing a retired branch re-points a dead lane's name at
 * new work, and every later audit of that branch reads the retired record.
 */
export function assertRetirementIdentityAvailable({ branch, worktree }, io = githubIo) {
  const wantedBranch = normalizeRetirementIdentity(branch), wantedWorktree = normalizeRetirementIdentity(worktree)
  for (const version of retirementSnapshot(io).versions.keys()) {
    const record = readRetirementRecord(version, io)
    if (normalizeRetirementIdentity(record.branch) === wantedBranch) throw new LaneError(`branch ${branch} belongs to terminally retired claim #${record.claim} (version ${version}); a successor must use a fresh branch`)
    if (normalizeRetirementIdentity(record.worktree) === wantedWorktree) throw new LaneError(`worktree ${worktree} belongs to terminally retired claim #${record.claim} (version ${version}); a successor must use a fresh worktree`)
  }
}

/**
 * Create-only, idempotent on an IDENTICAL record, refusing on a conflicting one.
 * An identical retry is what a lost HTTP response looks like from here, and it
 * must not become a second refusal that strands a half-finished retirement.
 */
export function createRetirementTombstone(record, io = githubIo) {
  const validated = validateRetirementRecord(record)
  const ref = retiredClaimRef(validated.version)
  const existingSha = io.readRef(ref)
  if (existingSha) {
    const existing = parseRetirementRecord(io.readCommitMessage(existingSha))
    // Compare the canonical serialisation, not field-by-field: a difference in
    // ANY bound field is a conflicting retirement.
    if (JSON.stringify(existing) !== JSON.stringify(validated)) throw new LaneError(`version ${validated.version} already carries a conflicting retirement tombstone for claim #${existing.claim}; retirement records are immutable and are never replaced`)
    resetRetirementSnapshot()
    return { ref, sha: existingSha, idempotent: true }
  }
  const sha = io.makeOwnerCommit(formatRetirementRecord(validated))
  if (!io.createRef(ref, sha)) {
    // Lost the create race. Whoever won must have written the identical record
    // or this retirement is in conflict.
    const winner = io.readRef(ref)
    const existing = winner ? parseRetirementRecord(io.readCommitMessage(winner)) : null
    if (!existing || JSON.stringify(existing) !== JSON.stringify(validated)) throw new LaneError(`retirement tombstone for ${validated.version} was created concurrently with a different record; refusing`)
    resetRetirementSnapshot()
    return { ref, sha: winner, idempotent: true }
  }
  // Readback: the ref must point at exactly the commit we wrote.
  if (io.readRef(ref) !== sha) throw new LaneError(`retirement tombstone readback failed for ${validated.version}`)
  resetRetirementSnapshot()
  return { ref, sha, idempotent: false }
}

/**
 * RETIRED-REOPENED. An open claim whose version is tombstoned is a resurrection:
 * somebody reopened the issue after the terminal record was written. Every
 * mutation path already refuses it; this is what makes it VISIBLE in a report
 * instead of only failing when someone tries to use it.
 */
export function retiredReopenedClaims(claims, now = new Date(), io = githubIo) {
  const found = []
  for (const claim of claims ?? []) {
    let lease
    try { lease = parseAuthorLease(claim.body, now) } catch { continue }
    if (lease.legacy || !lease.version) continue
    if (!isVersionRetired(lease.version, io)) continue
    const record = readRetirementRecord(lease.version, io)
    found.push({ status: 'RETIRED-REOPENED', claim: Number(claim.number), version: lease.version, branch: lease.branch, decision: record.decision, retiredClaim: record.claim, successorIssue: record.successor_issue })
  }
  return found
}

export function matchesLiveProof(proof,evidence){
  return proof?.schema_version===1&&proof.work_issue===evidence.work_issue&&proof.application_commit_sha===evidence.application_commit_sha&&proof.live_assertion===evidence.live_assertion&&proof.environment===evidence.environment&&proof.result==='passed'&&proof.observed_at===evidence.verified_at&&!Number.isNaN(Date.parse(proof.observed_at))
}
export function matchesGeneratedTypesProof(proof,evidence){
  return proof?.schema_version===1&&proof.work_issue===evidence.work_issue&&proof.application_commit_sha===evidence.application_commit_sha&&proof.result==='passed'&&proof.generated_types_sha256===evidence.generated_types_output_digest
}
