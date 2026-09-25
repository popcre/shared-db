import test from 'node:test'
import assert from 'node:assert/strict'
import {
  DrawReadinessError,
  promptCarriesVerdictContract,
  assertPromptContractBeforeDraw,
  assertEvidencePairBeforeDraw,
  assertBranchCurrentWithMain,
  assertNoProtectedSourceCollision,
  assertReviewerDrawPreparedness,
} from './lib/reviewer-draw-readiness.mjs'
import { main } from './manage-migration-author-lanes.mjs'

const HEAD = 'd'.repeat(40)
const OTHER_HEAD = 'e'.repeat(40)

function noDrawIo(live = { draft: false, mergeable: true, state: 'open', base: { ref: 'main' }, head: { sha: HEAD } }) {
  let drew = false
  const io = {
    pullRequestFiles() { return [{ filename: 'scripts/something-else.mjs' }] },
    getPr() { return live },
    getFileAt() { throw new Error('no evidence files') },
    openPulls() { return [] },
    listIssues() { drew = true; throw new Error('the reviewer draw must not be reached') },
    makeOwnerCommit() { drew = true; throw new Error('no owner commit must be made') },
  }
  return { io, drew: () => drew }
}

// ---------------------------------------------------------------------------
// Item 1 pre-draw half — the carried prompt must end in a recordable VERDICT.
// ---------------------------------------------------------------------------

test('#2998-1 promptCarriesVerdictContract accepts only a head-bound VERDICT line', () => {
  assert.equal(promptCarriesVerdictContract(`brief\nVERDICT: APPROVE ${HEAD}`, HEAD), true)
  assert.equal(promptCarriesVerdictContract(`brief\nVERDICT: REVISE ${HEAD}`, HEAD), true)
  assert.equal(promptCarriesVerdictContract(`brief\nVERDICT: REJECT ${HEAD}`, HEAD), true)
  // A bare verdict with no head is the observed unrecordable failure.
  assert.equal(promptCarriesVerdictContract('brief\nVERDICT: APPROVE', HEAD), false)
  // A verdict naming a different head is refused, never accepted.
  assert.equal(promptCarriesVerdictContract(`brief\nVERDICT: APPROVE ${OTHER_HEAD}`, HEAD), false)
  assert.equal(promptCarriesVerdictContract('', HEAD), false)
  assert.equal(promptCarriesVerdictContract(null, HEAD), false)
})

test('#2998-1 a carried prompt without a recordable VERDICT refuses before the draw', () => {
  assert.throws(
    () => assertPromptContractBeforeDraw({ prompt: 'just a brief', headSha: HEAD }),
    (error) => {
      assert.ok(error instanceof DrawReadinessError)
      assert.match(error.message, /no reviewer was drawn and no reviewer capacity was spent/)
      assert.match(error.message, /does not end in a recordable terminal VERDICT/)
      // The refusal is a refusal. It never stands in for an approval.
      assert.ok(!/^VERDICT: APPROVE/m.test(error.message))
      return true
    },
  )
  // Absence of a carried prompt is NOT a failure: the runner still validates.
  assert.equal(assertPromptContractBeforeDraw({ prompt: null, headSha: HEAD }), null)
  assert.equal(assertPromptContractBeforeDraw({ prompt: undefined, headSha: HEAD }), null)
  assert.deepEqual(assertPromptContractBeforeDraw({ prompt: `ok\nVERDICT: APPROVE ${HEAD}`, headSha: HEAD }), { promptContract: 'present' })
})

// ---------------------------------------------------------------------------
// Item 3 — evidence pair is valid before the draw.
// ---------------------------------------------------------------------------

test('#2998-3 a conflicted or partial evidence pair refuses before the draw', () => {
  const conflicted = {
    pullRequestFiles() {
      return [
        { filename: '.agent/contract.json' },
        { filename: '.agent/completion.json' },
        { filename: '.agent/work/2998/1/contract.json' },
        { filename: '.agent/work/2998/1/completion.json' },
      ]
    },
    getFileAt() { throw new Error('unreadable') },
    getPr() { return { head: { sha: HEAD } } },
  }
  assert.throws(() => assertEvidencePairBeforeDraw(1, conflicted), /more than one evidence pair/)
  const partial = {
    pullRequestFiles() { return [{ filename: '.agent/contract.json' }] },
    getFileAt() { throw new Error('unreadable') },
    getPr() { return { head: { sha: HEAD } } },
  }
  assert.throws(() => assertEvidencePairBeforeDraw(1, partial), /incomplete evidence pair/)
})

test('#2998-3 a completion report without a 40-character head_sha refuses before the draw', () => {
  const io = {
    pullRequestFiles() { return [{ filename: '.agent/contract.json' }, { filename: '.agent/completion.json' }] },
    getFileAt(file) {
      if (String(file).includes('completion')) return JSON.stringify({ head_sha: 'short', work_issue: 2998 })
      return '{}'
    },
    getPr() { return { head: { sha: HEAD } } },
  }
  assert.throws(() => assertEvidencePairBeforeDraw(1, io), /not an exact 40-character implementation SHA/)
})

test('#2998-3 a complete evidence pair with a 40-character head_sha proceeds', () => {
  const io = {
    pullRequestFiles() { return [{ filename: '.agent/contract.json' }, { filename: '.agent/completion.json' }] },
    getFileAt(file) {
      if (String(file).includes('completion')) return JSON.stringify({ head_sha: HEAD, work_issue: 2998, files_changed: [] })
      return '{}'
    },
    getPr() { return { head: { sha: HEAD } } },
  }
  assert.deepEqual(assertEvidencePairBeforeDraw(1, io), { evidence: 'current', head_sha: HEAD, key: 'legacy' })
})

test('#2998-3 a PR carrying no evidence paths proceeds, and unreadable inputs never refuse', () => {
  assert.deepEqual(assertEvidencePairBeforeDraw(1, { pullRequestFiles() { return [{ filename: 'scripts/foo.mjs' }] } }), { evidence: 'inherited' })
  assert.equal(assertEvidencePairBeforeDraw(1, { pullRequestFiles() { throw new Error('boom') } }), null)
  assert.equal(assertEvidencePairBeforeDraw(1, {}), null)
})

// ---------------------------------------------------------------------------
// Item 3 — the branch is current with main before the draw.
// ---------------------------------------------------------------------------

test('#2998-3 a pull request that does not target main refuses before the draw', () => {
  assert.throws(() => assertBranchCurrentWithMain(1, { getPr() { return { base: { ref: 'develop' } } } }), /not current with main/)
  assert.deepEqual(assertBranchCurrentWithMain(1, { getPr() { return { base: { ref: 'main' } } } }), { base: 'main', current: true })
  assert.equal(assertBranchCurrentWithMain(1, {}), null)
  assert.equal(assertBranchCurrentWithMain(1, { getPr() { throw new Error('boom') } }), null)
})

// ---------------------------------------------------------------------------
// Item 3 — no cross-PR protected-source collision before the draw.
// ---------------------------------------------------------------------------

test('#2998-3 a protected-source collision with an earlier ready PR refuses before the draw', () => {
  const io = {
    pullRequestFiles(number) {
      return [{ filename: 'scripts/manage-migration-author-lanes.mjs' }]
    },
    getPr() { return { created_at: '2026-09-10T00:00:00Z', head: { sha: HEAD } } },
    openPulls() {
      // The other PR activated earlier, so it precedes this one in the queue.
      return [{ number: 2, title: 'earlier', draft: false, created_at: '2026-09-01T00:00:00Z' }]
    },
  }
  assert.throws(
    () => assertNoProtectedSourceCollision(1, io),
    /edits a protected coordination source/,
  )
})

test('#2998-3 a PR with no protected path proceeds without gathering other pulls', () => {
  let gathered = false
  const io = {
    pullRequestFiles() { return [{ filename: 'scripts/unrelated.mjs' }] },
    openPulls() { gathered = true; return [] },
  }
  assert.deepEqual(assertNoProtectedSourceCollision(1, io), { collision: 'none' })
  assert.equal(gathered, false)
  // Unreadable transport never refuses.
  assert.equal(assertNoProtectedSourceCollision(1, { pullRequestFiles() { throw new Error('boom') }, openPulls() { return [] } }), null)
  assert.equal(assertNoProtectedSourceCollision(1, {}), null)
})

// ---------------------------------------------------------------------------
// The combined result, and the CLI wiring: no draw, no cursor, no owner commit.
// ---------------------------------------------------------------------------

test('#2998 combined preparedness is side-effect-free and reports every check', () => {
  const { io, drew } = noDrawIo()
  const result = assertReviewerDrawPreparedness({ pr: 1, headSha: HEAD, issue: 2998, prompt: null }, io)
  assert.equal(result.current, true)
  assert.equal(result.collision, 'none')
  assert.equal(result.evidence, 'inherited')
  assert.equal(drew(), false)
})

test('#2998-3 the CLI --assign-reviewer path refuses the new criteria before any draw', () => {
  const { io, drew } = noDrawIo({ draft: false, mergeable: true, state: 'open', base: { ref: 'develop' }, head: { sha: HEAD } })
  const errors = [], original = console.error
  console.error = (message) => errors.push(String(message))
  let code
  try { code = main(['--assign-reviewer', '--issue', '2998', '--pr', '2112', '--head-sha', HEAD], new Date(), io) }
  finally { console.error = original }
  assert.equal(code, 2)
  assert.match(errors.join('\n'), /not current with main/)
  assert.match(errors.join('\n'), /no reviewer was drawn and no reviewer capacity was spent/)
  assert.equal(drew(), false)
  assert.ok(!/APPROVE/.test(errors.join('\n')))
})

test('#2998-3 the CLI --replace-failed-reviewer path refuses the new criteria before any draw', () => {
  const { io, drew } = noDrawIo({ draft: false, mergeable: true, state: 'open', base: { ref: 'develop' }, head: { sha: HEAD } })
  const errors = [], original = console.error
  console.error = (message) => errors.push(String(message))
  let code
  try {
    code = main(['--replace-failed-reviewer', '--issue', '2998', '--pr', '2112', '--head-sha', HEAD, '--reviewer', 'muse-spark-1.3-contributor', '--reason', 'x', '--failed-sequence', '1', '--failure-code', 'reviewer_cannot_emit_governed_verdict', '--confirm-no-verdict', '--confirm-no-artifact'], new Date(), io)
  } finally { console.error = original }
  assert.equal(code, 2)
  assert.match(errors.join('\n'), /not current with main/)
  assert.equal(drew(), false)
})

test('#2998-1 the CLI --assign-reviewer path refuses a carried prompt with no recordable VERDICT', () => {
  const { io, drew } = noDrawIo()
  const errors = [], original = console.error
  console.error = (message) => errors.push(String(message))
  let code
  try {
    code = main(['--assign-reviewer', '--issue', '2998', '--pr', '2112', '--head-sha', HEAD, '--prompt', 'a brief with no verdict line'], new Date(), io)
  } finally { console.error = original }
  assert.equal(code, 2)
  assert.match(errors.join('\n'), /does not end in a recordable terminal VERDICT/)
  assert.equal(drew(), false)
})

test('#2998 a valid positive case clears every new check', () => {
  const { io } = noDrawIo()
  const errors = [], original = console.error
  console.error = (message) => errors.push(String(message))
  let code
  try {
    code = main(['--assign-reviewer', '--issue', '2998', '--pr', '2112', '--head-sha', HEAD, '--prompt', `brief\nVERDICT: APPROVE ${HEAD}`], new Date(), io)
  } finally { console.error = original }
  // Readiness itself must not have refused. A later assignment failure (the
  // stub io is not a full GitHub) is unrelated and must not look like readiness.
  const text = errors.join('\n')
  assert.ok(!/not current with main|recordable terminal VERDICT|evidence pair|protected coordination source|still a DRAFT|conflicts with its base/.test(text), text)
  assert.equal(typeof code, 'number')
})
