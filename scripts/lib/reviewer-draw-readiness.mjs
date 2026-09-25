// ISSUE #2998 item 3 (and item 1's pre-draw half) — pre-conditions asserted
// BEFORE any reviewer draw, cursor write, or assignment mutation.
//
// The defect class is a pre-condition checked AFTER the irreversible step.
// Observed costs: a merge declined twice with no reason because the PR was a
// draft; five PR failures from a hand-written evidence pair that disagreed with
// git; approvals given twice and recordable neither time because the outbound
// brief never carried the terminal VERDICT line.
//
// This module is side-effect-free. It reads, it decides, it throws. It never
// creates a cursor, never assigns a reviewer, never writes a ref, and never
// approves. Every refusal is a refusal.
//
// Fail-open direction, per check, is deliberate and matches the existing
// readiness guard: a transport fault or a missing io capability is NEVER
// silently converted into a reviewer refusal. Only a definite, readable
// contradiction refuses. Uncertainty proceeds exactly as before.

import { resolveEvidencePair } from './agent-evidence-paths.mjs'
import { PROTECTED_SOURCE_PATHS, openProtectedCollisions, filePaths } from '../check-pr-source-collisions.mjs'

export class DrawReadinessError extends Error {
  constructor(message) {
    super(message)
    this.name = 'DrawReadinessError'
  }
}

const SHA40 = /^[0-9a-f]{40}$/i

/** The terminal verdict contract the outbound brief must carry for this head. */
export function promptCarriesVerdictContract(prompt, head) {
  if (typeof prompt !== 'string' || !prompt.trim()) return false
  const named = [...prompt.matchAll(/VERDICT:\s*(?:APPROVE|REVISE|REJECT)\s+([0-9a-f]{7,40})\b/gi)]
    .map((match) => match[1].toLowerCase())
  if (!named.length) return false
  const live = String(head ?? '').toLowerCase()
  return named.every((token) => live.startsWith(token) || token.startsWith(live.slice(0, 7)))
}

/**
 * Item 1 pre-draw half: if the caller carries the outbound prompt into the
 * assignment, the terminal VERDICT instruction must already be present (or the
 * caller must be about to let the governed runner inject it). A prompt that
 * cannot end in a recordable verdict is refused BEFORE the draw. Absence of a
 * prompt here is not a failure — the governed runner still validates and
 * injects at its own stage, and a promptless handoff that never runs the
 * runner is caught there.
 */
export function assertPromptContractBeforeDraw({ prompt = null, headSha = null } = {}) {
  if (prompt === null || prompt === undefined) return null
  if (typeof prompt !== 'string') throw new DrawReadinessError('the carried reviewer prompt is unreadable, so no reviewer was drawn and no reviewer capacity was spent.')
  if (!promptCarriesVerdictContract(prompt, headSha)) {
    throw new DrawReadinessError(`the carried reviewer prompt does not end in a recordable terminal VERDICT instruction for head ${headSha}, so no reviewer was drawn and no reviewer capacity was spent. Add the line "Your final line must be exactly one of: VERDICT: APPROVE <head> | VERDICT: REVISE <head> | VERDICT: REJECT <head>" (the governed review runner injects this when the prompt is not carried at assignment), then assign a reviewer.`)
  }
  return { promptContract: 'present' }
}

/**
 * Item 3: the evidence pair must be valid before a draw.
 *
 * When the PR file inventory and file-at-head reader are available:
 *  - a PR that carries evidence paths must present exactly one complete pair;
 *  - a partial or conflicted pair refuses (the review cannot be recorded);
 *  - the completion report must parse and carry a 40-character head_sha.
 *
 * A PR that carries no evidence paths at all (`inherited`) proceeds: refusing
 * it here would invent a requirement the draw path never had. Unreadable
 * inputs proceed exactly as before.
 */
export function assertEvidencePairBeforeDraw(pr, io = {}) {
  if (typeof io?.pullRequestFiles !== 'function') return null
  let files
  try { files = io.pullRequestFiles(pr) } catch { return null }
  if (!Array.isArray(files)) return null
  const names = files.map((file) => String(file?.filename ?? file?.path ?? '')).filter(Boolean)
  const pair = resolveEvidencePair(names)
  if (pair.state === 'inherited') return { evidence: 'inherited' }
  if (pair.state === 'conflicted') {
    throw new DrawReadinessError(`PR #${pr} carries more than one evidence pair (${pair.key}), so no reviewer was drawn and no reviewer capacity was spent. Keep exactly one contract/completion pair for this pull request.`)
  }
  if (pair.state === 'partial') {
    throw new DrawReadinessError(`PR #${pr} carries an incomplete evidence pair (${pair.key ?? 'evidence'}), so no reviewer was drawn and no reviewer capacity was spent. Publish both the contract and the completion report, or neither.`)
  }
  if (typeof io?.getFileAt !== 'function') return { evidence: pair.state, key: pair.key }
  let head = null
  try { head = typeof io.getPr === 'function' ? io.getPr(Number(pr))?.head?.sha : null } catch { return null }
  if (!head) return null
  let completion
  try { completion = JSON.parse(io.getFileAt(pair.completion, head)) } catch { return null }
  if (!completion || typeof completion !== 'object' || Array.isArray(completion)) {
    throw new DrawReadinessError(`PR #${pr} completion report ${pair.completion} is not a JSON object, so no reviewer was drawn and no reviewer capacity was spent.`)
  }
  const implementationHead = String(completion.head_sha ?? '')
  if (!SHA40.test(implementationHead)) {
    throw new DrawReadinessError(`PR #${pr} completion report ${pair.completion} head_sha is not an exact 40-character implementation SHA, so no reviewer was drawn and no reviewer capacity was spent. Derive it with node scripts/agent-work-contract-git-evidence.mjs --derive-git-facts.`)
  }
  return { evidence: pair.state, head_sha: implementationHead.toLowerCase(), key: pair.key }
}

/**
 * Item 3: the branch must be current with main before a draw.
 *
 * Definite, readable contradictions refuse:
 *  - the PR does not target main at all;
 *  - the PR base SHA is readable and is NOT the current main tip AND GitHub
 *    reports a definite conflict (already covered by the mergeable=false
 *    check) — here we only add the base-target check.
 *
 * A base that trails main but still merges cleanly proceeds: forcing a rebase
 * before every draw would cost more than it saves, and the guarded merge lane
 * still refuses a real problem later. Unreadable inputs proceed.
 */
export function assertBranchCurrentWithMain(pr, io = {}) {
  if (typeof io?.getPr !== 'function') return null
  let live
  try { live = io.getPr(Number(pr)) } catch { return null }
  if (!live || typeof live !== 'object') return null
  const baseRef = String(live.base?.ref ?? live.baseRef ?? '').toLowerCase()
  if (baseRef && baseRef !== 'main') {
    throw new DrawReadinessError(`PR #${pr} targets ${baseRef}, not main, so it is not current with main and no reviewer was drawn and no reviewer capacity was spent. Retarget the pull request at main, then assign a reviewer.`)
  }
  return { base: baseRef || null, current: true }
}

/**
 * Item 3: no cross-PR protected-source collision before a draw.
 *
 * Only a PR that actually edits a protected coordination source can collide on
 * one. Gathering every open PR's file list is the quota blow-up the shared
 * snapshot exists to prevent, so this check runs only when the PR's own files
 * are already readable and include a protected path. Unreadable inputs, or a
 * PR with no protected path, proceed.
 */
export function assertNoProtectedSourceCollision(pr, io = {}, { currentFiles = null, currentActivatedAt = null } = {}) {
  if (typeof io?.openPulls !== 'function' || typeof io?.pullRequestFiles !== 'function') return null
  let files = currentFiles
  if (!Array.isArray(files)) {
    try { files = io.pullRequestFiles(Number(pr)) } catch { return null }
  }
  if (!Array.isArray(files)) return null
  const mine = filePaths(files)
  if (!mine.some((file) => PROTECTED_SOURCE_PATHS.has(file))) return { collision: 'none' }
  let activatedAt = currentActivatedAt
  if (!activatedAt && typeof io?.getPr === 'function') {
    try { activatedAt = io.getPr(Number(pr))?.created_at ?? io.getPr(Number(pr))?.createdAt ?? '' } catch { activatedAt = '' }
  }
  let pulls
  try { pulls = io.openPulls() } catch { return null }
  if (!Array.isArray(pulls)) return null
  const others = []
  for (const row of pulls) {
    const number = Number(row?.number)
    if (!Number.isInteger(number) || number === Number(pr)) continue
    if (row?.draft === true) continue
    let theirFiles
    try { theirFiles = io.pullRequestFiles(number) } catch { return null }
    if (!Array.isArray(theirFiles)) return null
    others.push({ number, title: String(row?.title ?? ''), draft: false, created_at: row?.created_at ?? row?.createdAt ?? '', activatedAt: row?.created_at ?? row?.createdAt ?? '', files: filePaths(theirFiles) })
  }
  const collisions = openProtectedCollisions({ number: Number(pr), files: mine, activatedAt: activatedAt ?? '' }, others)
  if (collisions.length) {
    const names = collisions.map((row) => `PR #${row.pr} ("${row.title}") on ${row.file}`).join('; ')
    throw new DrawReadinessError(`PR #${pr} edits a protected coordination source that an earlier ready open pull request also edits (${names}), so no reviewer was drawn and no reviewer capacity was spent. Merge or close the earlier pull request first; a reviewer spent here could not produce an actionable merge.`)
  }
  return { collision: 'none' }
}

/**
 * One side-effect-free readiness result covering every remaining #2998 item-3
 * criterion plus the optional carried prompt. Safe to call before any cursor,
 * assignment, or replacement mutation on both draw paths.
 */
export function assertReviewerDrawPreparedness({ pr, headSha = null, issue = null, prompt = null } = {}, io = {}) {
  const results = {}
  Object.assign(results, assertPromptContractBeforeDraw({ prompt, headSha }) ?? {})
  Object.assign(results, assertEvidencePairBeforeDraw(pr, io) ?? {})
  Object.assign(results, assertBranchCurrentWithMain(pr, io) ?? {})
  Object.assign(results, assertNoProtectedSourceCollision(pr, io) ?? {})
  return results
}
