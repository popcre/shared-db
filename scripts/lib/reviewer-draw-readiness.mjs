// ISSUE #2998 — pre-draw handoff readiness.
//
// The defect this module exists to remove: every pre-condition of a successful
// reviewer handoff used to be checked AFTER the expensive step. A draft PR, a
// conflicted branch, a stale brief, a broken evidence pair, a pull request that
// is not current with main, or a cross-PR collision were each discovered only
// after the draw had consumed reviewer capacity -- so the cost of the bad
// handoff was a wasted reviewer slot and a stalled lane instead of a fast,
// named error.
//
// Everything here is SIDE-EFFECT-FREE. Reads only: local file reads for the
// carried brief, and GitHub reads that the draw already needed. No cursor, no
// assignment, no ref, no comment is written by anything in this file, and the
// orchestrating caller runs it BEFORE any of those mutations on both draw
// paths (--assign-reviewer and --replace-failed-reviewer).
//
// FAIL DIRECTION, matching the existing assertReviewerDrawReadiness doctrine:
// a definite bad fact refuses by name; an unreadable input PROCEEDS, because a
// transport fault must never silently convert into a reviewer refusal. A
// refusal here is a refusal -- it never contains an approval and never reads
// as a recorded decision.
import { readFileSync } from 'node:fs'
import { contractHash, contractRef, reconcileReportWithContract, validateCompletionReport, validateContract, validatePullRequestCompletion } from '../agent-work-contract.mjs'
import { validateCompletionRecord } from './work-dependencies.mjs'
import { resolveEvidencePair } from './agent-evidence-paths.mjs'
import { gather as gatherSourceSnapshot, openProtectedCollisions, PROTECTED_SOURCE_PATHS } from '../check-pr-source-collisions.mjs'
import { findCollisions, gatherSources as gatherObjectSources } from '../check-pr-object-collisions.mjs'

export class DrawReadinessError extends Error {}

const SHA = /^[0-9a-f]{40}$/
const MIGRATION_FILE = /^supabase\/migrations\/\d{14}_[^/]+\.sql$/
const NO_DRAW = 'No reviewer was drawn and no reviewer capacity was spent'

function refuse(message) {
  throw new DrawReadinessError(`${message}. ${NO_DRAW}.`)
}

// ---------------------------------------------------------------------------
// 1. The carried prompt, validated BEFORE the draw.
//
// Issue #2998 fix 1: the outbound reviewer prompt must carry the terminal
// `VERDICT: <DECISION> <head>` contract before the reviewer draw is consumed.
// The governed runner still injects and checks that contract before it starts
// a provider (its guard is unchanged and remains the backstop), but the runner
// runs AFTER the draw -- so a handoff that carries a brief now has that brief
// validated here, before anything is consumed.
//
// The prompt arguments are OPTIONAL. The documented flow and
// refresh-code-pr-branch re-draw without a brief, and the codex wrapper takes
// no prompt by design (#2244), so absence is not a failure; a brief that IS
// carried must be readable, non-empty, and must not bind a decision line to a
// different head than this draw is for.
// ---------------------------------------------------------------------------
export function assertDrawPromptContract({ prompt, promptFile, headSha } = {}, { readFile = readFileSync } = {}) {
  if (prompt === undefined && promptFile === undefined) return { carried: false }
  let text
  if (promptFile !== undefined) {
    try {
      text = readFile(String(promptFile), 'utf8')
    } catch (error) {
      refuse(`the carried review brief --prompt-file ${promptFile} is not readable (${String(error?.message ?? error)})`)
    }
  } else {
    text = String(prompt)
  }
  if (!String(text).trim()) refuse('the carried review brief is empty')
  const head = String(headSha ?? '').toLowerCase()
  if (SHA.test(head)) {
    // Same stale-head rule the runner enforces at start time (promptHeadContract):
    // a decision line naming any other head means the brief was written for a
    // different commit than the one this draw would bind.
    for (const match of String(text).matchAll(/VERDICT:\s*[A-Z_]+[ \t]+([0-9a-f]{7,40})\b/gi)) {
      const named = match[1].toLowerCase()
      if (!head.startsWith(named)) {
        refuse(`the carried review brief binds a decision line to head ${named}, but this draw is for head ${head}`)
      }
    }
  }
  // Confirmed for this head: the runner will bind the terminal instruction to
  // the live head when it starts, which is exactly the contract the draw just
  // proved the brief can carry.
  return { carried: true, headClean: true }
}

// ---------------------------------------------------------------------------
// 2. The contract/completion evidence pair, validated BEFORE the draw.
//
// Issue #2998 fix 3: "the evidence pair is valid". The classification is the
// repository's own resolver, and a `current` pair is validated exactly like
// the CI gate judges it -- schema, reconciliation against the published
// immutable contract, and (for an open pull request) the pull-request binding.
// `inherited` proceeds: a pull request that changes no evidence file makes no
// evidence claim here, and the enforced CI gate -- grandfathering and
// documents-only exemptions included -- remains the authority on whether a
// pair is required at all. `partial` and `conflicted` are definite bad facts.
// ---------------------------------------------------------------------------
export function evidencePairReadiness({ rows, pr, headSha, prState, io } = {}) {
  if (!Array.isArray(rows)) return { state: 'unreadable' }
  const filenames = rows.map((row) => String(row?.filename ?? ''))
  const pair = resolveEvidencePair(filenames)
  if (pair.state === 'partial') {
    const present = [pair.contract, pair.completion].filter((file) => filenames.includes(file))
    refuse(`this pull request changes only one half of its agent evidence pair (${present.join(', ')}); a contract and its completion report travel together`)
  }
  if (pair.state === 'conflicted') refuse(`this pull request carries more than one agent evidence pair (${pair.key}); exactly one pair may be present (#2708)`)
  if (pair.state === 'inherited') return pair
  // `current` -- deep validation. Open pull requests get the full judgment;
  // a non-open pull request keeps classification plus content checks only, so
  // a merged-pull-request draw (#2915) can never be refused by a check that
  // the CI gate would have applied before the merge happened.
  if (prState !== 'open') return { ...pair, validated: false, reason: 'not an open pull request' }
  if (!SHA.test(String(headSha ?? ''))) return { ...pair, validated: false, reason: 'no exact head to read the pair at' }
  if (typeof io?.getFileAt !== 'function') {
    return { ...pair, validated: false, reason: 'this io cannot read evidence files' }
  }
  let contractText, reportText
  try {
    contractText = io.getFileAt(pair.contract, headSha)
    reportText = io.getFileAt(pair.completion, headSha)
  } catch {
    return { ...pair, validated: false, reason: 'the evidence pair could not be read (transport)' }
  }
  let contract, report
  try {
    contract = JSON.parse(String(contractText))
    report = JSON.parse(String(reportText))
  } catch (error) {
    refuse(`the agent evidence pair on this pull request is not readable JSON (${String(error?.message ?? error)})`)
  }
  try {
    validateContract(contract)
    validateCompletionReport(report, { validateCompletionRecord })
  } catch (error) {
    refuse(`the agent evidence pair on this pull request does not validate (${String(error?.message ?? error)})`)
  }
  const expectedRef = contractRef(contract.work_issue, contract.generation ?? 1)
  if (report.contract_ref !== expectedRef) {
    refuse(`the completion report names contract ref ${report.contract_ref}, but its contract lives at ${expectedRef}`)
  }
  const reconciled = reconcileReportWithContract(report, contract)
  if (!reconciled.satisfied) refuse(`the completion report does not satisfy its contract (${reconciled.problems.join('; ')})`)
  if (prState === 'open') {
    try {
      validatePullRequestCompletion(report, { pr: Number(pr), headSha })
    } catch (error) {
      refuse(`the completion report does not bind this pull request (${String(error?.message ?? error)})`)
    }
  }
  // The keystone: the checked-in contract must be the immutable publication.
  if (typeof io?.readRef !== 'function' || typeof io?.readCommitMessage !== 'function') {
    return { ...pair, validated: false, reason: 'this io cannot read the published contract' }
  }
  let publishedSha
  try {
    publishedSha = io.readRef(report.contract_ref)
  } catch {
    return { ...pair, validated: false, reason: 'the published contract ref could not be read (transport)' }
  }
  if (publishedSha === null) refuse(`no immutable contract is published at ${report.contract_ref}, so the checked-in pair was never authorised`)
  let message
  try {
    message = io.readCommitMessage(publishedSha)
  } catch {
    return { ...pair, validated: false, reason: 'the published contract commit could not be read (transport)' }
  }
  if (message === null) return { ...pair, validated: false, reason: 'the published contract commit could not be read (transport)' }
  let published
  try {
    published = JSON.parse(String(message).split('\n').slice(2).join('\n').trim())
  } catch (error) {
    refuse(`${report.contract_ref} does not carry a readable immutable contract (${String(error?.message ?? error)})`)
  }
  if (contractHash(published) !== contractHash(contract)) {
    refuse('the checked-in contract does not match the immutable contract published before the work')
  }
  return { ...pair, validated: true }
}

// ---------------------------------------------------------------------------
// 3. Current-with-main readiness, BEFORE the draw.
//
// Issue #2998 fix 3: "the branch is current with main". GitHub computes
// mergeable_state asynchronously, exactly like mergeable, so only a definite
// `behind` refuses; an absent or unknown value proceeds, and the guarded merge
// lane still refuses a real conflict later. Gated to open pull requests: a
// merged pull request is already in main's history.
// ---------------------------------------------------------------------------
export function currentMainReadiness(live, pr) {
  if (!live || typeof live !== 'object') return { state: 'unknown' }
  if (String(live.state ?? '').toLowerCase() !== 'open') return { state: 'not-open' }
  if (live.mergeable_state === 'behind') {
    refuse(`PR #${pr} is not current with main (GitHub reports mergeable_state=behind); refresh the branch onto main first`)
  }
  return { state: live.mergeable_state ?? 'unknown' }
}

// ---------------------------------------------------------------------------
// 4a. Cross-PR protected-source collision, BEFORE the draw.
//
// The guard the governed review of PR #3338 hit at merge time -- "another
// ready open pull request edits the same protected coordination source" --
// checked after the review. Gathering is skipped entirely (zero API calls)
// unless THIS pull request actually edits a protected source, so ordinary
// draws pay nothing.
// ---------------------------------------------------------------------------
export function collectProtectedSourceCollisions({ repo, pr, rows, gather = gatherSourceSnapshot, env = process.env } = {}) {
  if (!Array.isArray(rows)) return []
  const paths = rows.flatMap((row) => [String(row?.filename ?? ''), String(row?.previous_filename ?? '')]).filter(Boolean)
  if (!paths.some((path) => PROTECTED_SOURCE_PATHS.has(path))) return []
  const scanEnv = { ...env, GITHUB_REPOSITORY: repo, PR_NUMBER: String(pr) }
  let input
  try {
    input = gather(scanEnv)
  } catch {
    return [] // transport: unreadable must never become a reviewer refusal
  }
  return openProtectedCollisions(input.current, input.others)
}

// ---------------------------------------------------------------------------
// 4b. Cross-PR object collision, BEFORE the draw.
//
// Reuses the repository's own cross-PR object collision guard (the check that
// found four migrations silently erasing each other on 2026-07-31), reduced to
// the question this draw asks: does ANY collision involve THIS pull request?
// Gathered only when this pull request adds or modifies a migration file, so
// repository-maintenance draws pay nothing.
// ---------------------------------------------------------------------------
export function collectCrossPrObjectCollisions({ repo, pr, rows, gatherSources = gatherObjectSources, env = process.env } = {}) {
  if (!Array.isArray(rows)) return []
  const migrations = rows.filter((row) => MIGRATION_FILE.test(String(row?.filename ?? '')) && String(row?.status ?? '').toLowerCase() !== 'removed')
  if (!migrations.length) return []
  const scanEnv = { ...env, GITHUB_REPOSITORY: repo, PR_NUMBER: String(pr) }
  // The event payload, when set, describes whichever pull request triggered a
  // workflow -- not necessarily this one -- so it must not supply head facts.
  delete scanEnv.GITHUB_EVENT_PATH
  let sources
  try {
    sources = gatherSources(scanEnv)
  } catch {
    return []
  }
  if (!Array.isArray(sources) || !sources.length) return []
  const { collisions } = findCollisions(sources, sources[0].label)
  return collisions
}

// ---------------------------------------------------------------------------
// The one readiness result. Every criterion runs side-effect-free; the first
// definite bad fact refuses by name; anything unreadable proceeds.
// ---------------------------------------------------------------------------
export function preDrawHandoffChecks({ pr, headSha, rows, live }, io) {
  const state = live && typeof live === 'object' ? String(live.state ?? '').toLowerCase() : ''
  const evidence = evidencePairReadiness({ rows, pr, headSha, prState: state, io })
  const currentMain = currentMainReadiness(live, pr)
  let sourceCollisions = []
  let objectCollisions = []
  if (state === 'open' && Array.isArray(rows)) {
    if (typeof io?.protectedSourceCollisions === 'function') {
      try {
        sourceCollisions = io.protectedSourceCollisions(pr, rows) ?? []
      } catch {
        sourceCollisions = []
      }
    }
    if (typeof io?.crossPrObjectCollisions === 'function') {
      try {
        objectCollisions = io.crossPrObjectCollisions(pr, rows) ?? []
      } catch {
        objectCollisions = []
      }
    }
  }
  if (sourceCollisions.length) {
    const others = sourceCollisions.map((row) => `PR #${row.pr}`).join(', ')
    refuse(`another ready open pull request edits the same protected coordination source as PR #${pr} (${others}); merge or close the other pull request first`)
  }
  if (objectCollisions.length) {
    const objects = objectCollisions.map((row) => row.object).join(', ')
    const others = objectCollisions.flatMap((row) => (row.sources ?? []).map((source) => source.label)).filter((label) => !/^PR #\d+ \(this PR\)$/.test(label)).join(', ')
    refuse(`PR #${pr} collides with another open pull request on ${objects}${others ? ` (${others})` : ''}; serialize the pull requests before drawing`)
  }
  return { evidence, currentMain, sourceCollisions, objectCollisions }
}
