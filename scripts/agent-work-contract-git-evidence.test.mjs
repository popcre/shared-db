import test from 'node:test'
import assert from 'node:assert/strict'
import { classifyEvidencePair, GitEvidenceError, main, prChangedFiles, readPublishedContractFromGit, verifyGitEvidence } from './agent-work-contract-git-evidence.mjs'
import { contractHash } from './agent-work-contract.mjs'

const base = 'a'.repeat(40)
const prBase = 'd'.repeat(40)
const implementation = 'b'.repeat(40)
const prHead = 'c'.repeat(40)
const contract = {
  schema_version: 1, work_issue: 42, generation: 1, work_type: 'repo-maintenance', route: 'repo-maintenance',
  goal: 'fix the guard', base_sha: base, dispatcher: 'repo-session', worker: 'codex', branch: 'codex/fix', worktree: 'worktrees/fix',
  allowed_paths: ['scripts/**'], file_writes: ['scripts/fix.mjs'], db_reads: [], db_writes: [], prohibited_actions: ['no database writes'],
  required_checks: ['node --test'], assumptions: [], stop_conditions: ['stop on scope change'],
}
const report = { head_sha: implementation, files_changed: ['scripts/fix.mjs'], contract_ref: 'refs/db-contracts/42/1', contract_sha256: contractHash(contract) }
// The merge base and the PR base agree on an un-refreshed branch, which is the
// state every legacy pull request is in.
const io = (over = {}) => ({
  isAncestor: () => true,
  changedFiles: (from) => from === base ? ['scripts/fix.mjs'] : ['.agent/contract.json', '.agent/completion.json'],
  mergeBase: () => base,
  readPublishedContract: () => contract,
  ...over,
})
const keyedPair = ['.agent/work/42/1/completion.json', '.agent/work/42/1/contract.json']

test('the implementation diff and evidence-only tail are accepted', () => {
  assert.equal(verifyGitEvidence({ contract, report, prBaseSha: prBase, prHeadSha: prHead }, io()), true)
})

test('a self-reported file list cannot hide a changed file', () => {
  assert.throws(() => verifyGitEvidence({ contract, report, prBaseSha: prBase, prHeadSha: prHead }, io({ changedFiles: (from) => from === base ? ['scripts/fix.mjs', 'scripts/hidden.mjs'] : ['.agent/contract.json', '.agent/completion.json'] })), /does not match Git/)
})

test('unchanged_implementation_needs_no_new_evidence_commit: a real post-fold layout is accepted with content proof', () => {
  // REAL fold shape from refresh(): report.head_sha stays the pre-fold
  // implementation head; the tip is a merge commit that carries the pair plus
  // whatever main contributed. The file list is compared at the IMMUTABLE
  // contract.base_sha, never at the author-written report.base_sha (H2).
  const oldBase = 'e'.repeat(40)
  const newBase = 'f'.repeat(40)
  const foldedReport = { ...report, head_sha: implementation, base_sha: oldBase }
  const foldedIo = io({
    mergeBase: () => newBase,
    isAncestor: (a, b) => {
      if (a === oldBase && b === newBase) return true
      if (a === newBase && b === implementation) return false
      return true
    },
    changedFiles: (from, to) => {
      if (from === base && to === implementation) return ['scripts/fix.mjs']
      if (from === implementation && to === prHead) return ['.agent/contract.json', '.agent/completion.json', 'base.txt']
      if (from === newBase && to === prHead) return ['scripts/fix.mjs', '.agent/contract.json', '.agent/completion.json', 'base.txt']
      return []
    },
    blobEquals: (from, to, file) => file === 'base.txt',
    isContentPreserving: () => ({ ok: true, reason: 'same head' }),
  })
  assert.equal(verifyGitEvidence({ contract, report: foldedReport, prBaseSha: prBase, prHeadSha: prHead }, foldedIo), true)
})

test('changed_implementation_invalidates_receipt: lagging base without content proof is refused', () => {
  const stale = { ...report, base_sha: 'e'.repeat(40) }
  const newBase = 'f'.repeat(40)
  assert.throws(() => verifyGitEvidence({ contract, report: stale, prBaseSha: prBase, prHeadSha: prHead }, io({
    mergeBase: () => newBase,
    isAncestor: (a, b) => !(a === newBase && b === implementation),
    changedFiles: (from) => (from === newBase || from === base ? ['scripts/fix.mjs'] : ['.agent/contract.json', '.agent/completion.json']),
    isContentPreserving: () => ({ ok: false, reason: 'the pull request\'s own diff changed' }),
  })), /superseded base|#2845|not an ancestor of the reported implementation head/)
})

test('H2: a self-bound report.base_sha cannot vacuously pass the fold skip', () => {
  // base_sha == head_sha and files_changed [] would make a naive comparison
  // empty. The skip requires the recorded base to be an ancestor of the live
  // merge base; a self-bind is not, so the fold path is not taken and the
  // pair/tail rules still refuse.
  const selfBound = { ...report, head_sha: implementation, base_sha: implementation, files_changed: [] }
  const newBase = 'f'.repeat(40)
  assert.throws(() => verifyGitEvidence({ contract, report: selfBound, prBaseSha: prBase, prHeadSha: prHead }, io({
    mergeBase: () => newBase,
    isAncestor: (a, b) => !(a === implementation && b === newBase),
    changedFiles: () => [],
    isContentPreserving: () => ({ ok: true, reason: 'same head' }),
  })), /superseded base|#2845|not an ancestor of the reported implementation head|only this pull request's own two evidence files/)
})

test('M1: a main-side deletion is not an author edit after the reported head', () => {
  const oldBase = 'e'.repeat(40)
  const newBase = 'f'.repeat(40)
  const foldedReport = { ...report, head_sha: implementation, base_sha: oldBase }
  assert.equal(verifyGitEvidence({ contract, report: foldedReport, prBaseSha: prBase, prHeadSha: prHead }, io({
    mergeBase: () => newBase,
    isAncestor: (a, b) => !(a === newBase && b === implementation),
    changedFiles: (from, to) => {
      if (from === base && to === implementation) return ['scripts/fix.mjs']
      if (from === implementation && to === prHead) return ['.agent/contract.json', '.agent/completion.json', 'gone.txt']
      return []
    },
    // gone.txt is absent at both mergeBase and tip (main deleted it) — not an author edit.
    blobEquals: (from, to, file) => file === 'gone.txt',
    isContentPreserving: () => ({ ok: true, reason: 'same head' }),
  })), true)
})

test('implementation edit after the reported head is refused even when main also moved (H3)', () => {
  const oldBase = 'e'.repeat(40)
  const newBase = 'f'.repeat(40)
  const foldedReport = { ...report, head_sha: implementation, base_sha: oldBase }
  assert.throws(() => verifyGitEvidence({ contract, report: foldedReport, prBaseSha: prBase, prHeadSha: prHead }, io({
    mergeBase: () => newBase,
    isAncestor: (a, b) => !(a === newBase && b === implementation),
    changedFiles: (from, to) => {
      if (from === base && to === implementation) return ['scripts/fix.mjs']
      if (from === implementation && to === prHead) return ['.agent/contract.json', '.agent/completion.json', 'base.txt', 'scripts/late.mjs']
      return []
    },
    // late.mjs is NOT from main (blob differs) — the old fromMain set would
    // have swallowed it because it appeared in the PR diff.
    blobEquals: (from, to, file) => file === 'base.txt',
    isContentPreserving: () => ({ ok: true, reason: 'same head' }),
  })), /implementation changed after the reported head|scripts\/late\.mjs/)
})

test('code changed after the reported head is refused', () => {
  assert.throws(() => verifyGitEvidence({ contract, report, prBaseSha: prBase, prHeadSha: prHead }, io({ changedFiles: (from) => from === base ? ['scripts/fix.mjs'] : ['.agent/contract.json', '.agent/completion.json', 'scripts/late.mjs'] })), /implementation changed after the reported head|only this pull request's own two evidence files/)
})

test('both ancestry links and full SHAs are required', () => {
  assert.throws(() => verifyGitEvidence({ contract, report, prBaseSha: prBase, prHeadSha: prHead }, io({ isAncestor: () => false })), /not an ancestor/)
  assert.throws(() => verifyGitEvidence({ contract: { ...contract, base_sha: 'abc1234' }, report, prBaseSha: prBase, prHeadSha: prHead }, io()), /40-character/)
})

test('the checked-in contract must match its exact immutable published ref', () => {
  assert.throws(() => verifyGitEvidence({ contract, report: { ...report, contract_ref: 'refs/db-contracts/42/2' }, prBaseSha: prBase, prHeadSha: prHead }, io()), /exact immutable ref/)
  // A content mutation of the committed record now reaches refuseCommittedMutation
  // (previously shadowed by an earlier identical hash throw) and is refused as an
  // immutable-record rewrite.
  assert.throws(() => verifyGitEvidence({ contract, report, prBaseSha: prBase, prHeadSha: prHead }, io({ readPublishedContract: () => ({ ...contract, goal: 'wider after the fact' }) })), /immutable|cannot be rewritten/)
})

test('completion digest must name the published contract bytes', () => {
  assert.throws(() => verifyGitEvidence({ contract, report: { ...report, contract_sha256: '0'.repeat(64) }, prBaseSha: prBase, prHeadSha: prHead }, io()), /contract_sha256 does not match/)
})

test('published contract read distinguishes absent ref from transport and fetch failures', () => {
  const ref = 'refs/db-contracts/42/1'
  const fail = (status) => { const error = new Error('network unavailable'); error.status = status; throw error }
  assert.throws(() => readPublishedContractFromGit(ref, () => fail(2)), /missing published contract/)
  assert.throws(() => readPublishedContractFromGit(ref, () => fail(128)), /could not read published contract ref/)
  assert.throws(() => readPublishedContractFromGit(ref, (_command, args) => args[0] === 'ls-remote' ? `${base}\t${ref}\n` : fail(128)), /could not fetch published contract/)
})

test('evidence pair classification distinguishes inherited, current, and half-written evidence', () => {
  assert.equal(classifyEvidencePair(['docs/change.md']), 'inherited')
  assert.equal(classifyEvidencePair(['.agent/contract.json', '.agent/completion.json', 'docs/change.md']), 'current')
  assert.equal(classifyEvidencePair(['.agent/contract.json', 'docs/change.md']), 'partial')
  assert.equal(classifyEvidencePair(['.agent/completion.json']), 'partial')
})

test('classification CLI compares the exact pull request base and head', () => {
  const output = []
  const calls = []
  const originalLog = console.log
  console.log = value => output.push(value)
  try {
    assert.equal(main(['--classify-evidence-pair', '--pr-base-sha', prBase, '--pr-head-sha', prHead], io({
      mergeBase: (actualBase, actualHead) => { calls.push(['merge-base', actualBase, actualHead]); return base },
      changedFiles: (actualBase, actualHead) => { calls.push(['diff', actualBase, actualHead]); return ['.agent/contract.json', '.agent/completion.json'] },
    })), 0)
  } finally {
    console.log = originalLog
  }
  assert.deepEqual(output, ['current'])
  assert.deepEqual(calls, [['merge-base', prBase, prHead], ['diff', base, prHead]])
})

test('a branch behind main is classified from its merge base, not as deleting evidence added later on main', () => {
  const files = prChangedFiles(prBase, prHead, {
    mergeBase: () => base,
    changedFiles: (from, to) => {
      assert.equal(from, base)
      assert.equal(to, prHead)
      return ['docs/old-branch-change.md']
    },
  })
  assert.equal(classifyEvidencePair(files), 'inherited')
})

test('a files_changed mismatch says which list is Git and exactly what to add or remove (#498)', () => {
  assert.throws(
    () => verifyGitEvidence({ contract, report, prBaseSha: prBase, prHeadSha: prHead }, io({ changedFiles: (from) => from === base ? [...report.files_changed, 'scripts/hidden.mjs'] : ['.agent/contract.json', '.agent/completion.json'] })),
    /Git changed \[.*scripts\/hidden\.mjs.*\] but \.agent\/completion\.json files_changed lists \[.*\]; add to the report \[scripts\/hidden\.mjs\], remove from the report \[\]/,
  )
})

// ISSUE #2998 item 2 — the two derivable completion fields come from git, not typing.
import { deriveGitFacts } from './agent-work-contract-git-evidence.mjs'
test('#2998-2 head_sha and files_changed are derived from git and nothing else is touched',()=>{
  const head='f'.repeat(40)
  const io={mergeBase:()=>'a'.repeat(40),revParse:()=>head.toUpperCase(),changedFiles:()=>['b.txt','a.txt']}
  const report={schema_version:1,work_issue:2998,outcome:'ready-for-merge',head_sha:'0'.repeat(40),files_changed:['typed-wrong.txt'],db_reads:[],checks:[{command:'x',exit_code:0}]}
  const derived=deriveGitFacts(report,{base:'origin/main',head:'HEAD'},io)
  // The two derivable fields are replaced with what git actually contains, normalised.
  assert.equal(derived.head_sha,head)
  assert.deepEqual(derived.files_changed,['a.txt','b.txt'])
  // Everything git cannot know is carried through untouched and still must be authored.
  assert.equal(derived.outcome,'ready-for-merge')
  assert.equal(derived.work_issue,2998)
  assert.deepEqual(derived.checks,[{command:'x',exit_code:0}])
  // The input is not mutated.
  assert.deepEqual(report.files_changed,['typed-wrong.txt'])
  // It fails closed rather than writing a plausible-looking wrong answer.
  assert.throws(()=>deriveGitFacts(report,{base:'origin/main',head:'HEAD'},{...io,mergeBase:()=>'not-a-sha'}),/could not resolve an exact merge base/)
  assert.throws(()=>deriveGitFacts(report,{base:'origin/main',head:'HEAD'},{...io,revParse:()=>'short'}),/could not resolve HEAD to an exact 40-character implementation commit/)
  assert.throws(()=>deriveGitFacts(report,{base:'origin/main',head:'HEAD'},{...io,changedFiles:()=>null}),/did not return a readable changed-file list/)
  assert.throws(()=>deriveGitFacts(null,{base:'origin/main',head:'HEAD'},io),/needs a readable completion report object/)
})

// --- #2708: disjoint, generation-keyed evidence paths -------------------------

test('#2708: a pull request may carry its own generation-keyed pair instead of the shared one', () => {
  assert.equal(verifyGitEvidence({ contract, report, prBaseSha: prBase, prHeadSha: prHead },
    io({ changedFiles: (from) => from === base ? ['scripts/fix.mjs'] : keyedPair })), true)
})

test('#2708: a pull request may not carry another pull request keyed evidence pair', () => {
  assert.throws(() => verifyGitEvidence({ contract, report, prBaseSha: prBase, prHeadSha: prHead },
    io({ changedFiles: (from) => from === base ? ['scripts/fix.mjs'] : ['.agent/work/99/1/completion.json', '.agent/work/99/1/contract.json'] })),
    /only this pull request's own two evidence files.*\.agent\/work\/42\/1\/completion\.json/s)
})

test('#2708: keyed pairs classify exactly as the legacy pair does, and two of them fail closed', () => {
  assert.equal(classifyEvidencePair([...keyedPair, 'scripts/fix.mjs']), 'current')
  assert.equal(classifyEvidencePair(['.agent/work/42/1/contract.json']), 'partial')
  assert.equal(classifyEvidencePair(['.agent/work/42/2/contract.json', '.agent/work/42/2/completion.json']), 'current')
  assert.equal(classifyEvidencePair([...keyedPair, '.agent/work/99/1/contract.json', '.agent/work/99/1/completion.json']), 'conflicted')
  // Two different pull requests' evidence never lands on the same path, which is
  // the whole point: these two lists are disjoint.
  assert.deepEqual(keyedPair.filter((path) => ['.agent/work/99/1/completion.json', '.agent/work/99/1/contract.json'].includes(path)), [])
})

// --- #2845: evidence rebound to the head under review -------------------------

test('#2845: a pair anchored to a superseded base is refused', () => {
  const movedBase = 'e'.repeat(40)
  assert.throws(() => verifyGitEvidence({ contract, report, prBaseSha: prBase, prHeadSha: prHead },
    io({ mergeBase: () => movedBase, changedFiles: (from) => from === movedBase ? ['scripts/fix.mjs'] : ['.agent/contract.json', '.agent/completion.json'] })),
    /anchored to a superseded base: it records a{40} but this pull request's merge base with main is e{40}/)
})

test('#2845: rebinding the completion report to the refreshed base and head passes', () => {
  const movedBase = 'e'.repeat(40)
  const rebound = { ...report, base_sha: movedBase }
  assert.equal(verifyGitEvidence({ contract, report: rebound, prBaseSha: prBase, prHeadSha: prHead },
    io({ mergeBase: () => movedBase, changedFiles: (from) => from === movedBase ? ['scripts/fix.mjs'] : ['.agent/contract.json', '.agent/completion.json'] })), true)
})

test('#2845: a rebound base is still held to the exact-SHA and ancestry rules', () => {
  assert.throws(() => verifyGitEvidence({ contract, report: { ...report, base_sha: 'e1e2e3' }, prBaseSha: prBase, prHeadSha: prHead }, io()), /40-character base SHA/)
  assert.throws(() => verifyGitEvidence({ contract, report, prBaseSha: prBase, prHeadSha: prHead }, io({ mergeBase: () => 'not-a-sha' })), /could not resolve an exact merge base/)
})

// --- #3380: gate-level enforcement of generation lineage -----------------------

const parentContract = { ...contract } // v1, generation 1
const parentDigest = contractHash(parentContract)
const childV2 = {
  ...contract,
  schema_version: 2,
  generation: 2,
  evidence_parent: { work_issue: 42, generation: 1, contract_sha256: parentDigest },
}
const keyedPair2 = ['.agent/work/42/2/completion.json', '.agent/work/42/2/contract.json']
const childReport = { ...report, contract_ref: 'refs/db-contracts/42/2', contract_sha256: contractHash(childV2) }
const childIo = (over = {}) => ({
  isAncestor: () => true,
  changedFiles: (from) => from === base ? ['scripts/fix.mjs'] : keyedPair2,
  mergeBase: () => base,
  readPublishedContract: (ref) => {
    if (ref === 'refs/db-contracts/42/2') return childV2
    if (ref === 'refs/db-contracts/42/1') return parentContract
    throw new Error(`unexpected ref ${ref}`)
  },
  ...over,
})

test('#3380: a v2 contract with a verified parent binding passes the gate', () => {
  assert.equal(verifyGitEvidence({ contract: childV2, report: childReport, prBaseSha: prBase, prHeadSha: prHead }, childIo()), true)
})

test('#3380: a forged evidence_parent digest is refused in the gate (Major 1)', () => {
  const forged = {
    ...childV2,
    evidence_parent: { work_issue: 42, generation: 1, contract_sha256: '0'.repeat(64) },
  }
  const forgedIo = childIo({
    readPublishedContract: (ref) => (ref === 'refs/db-contracts/42/2' ? forged : parentContract),
  })
  assert.throws(
    () => verifyGitEvidence({ contract: forged, report: { ...childReport, contract_sha256: contractHash(forged) }, prBaseSha: prBase, prHeadSha: prHead }, forgedIo),
    /forged parent|does not match the predecessor/,
  )
})

test('#3380: a v2 contract whose parent contract is unavailable is refused', () => {
  const missingParentIo = childIo({
    readPublishedContract: (ref) => (ref === 'refs/db-contracts/42/2' ? childV2 : null),
  })
  assert.throws(
    () => verifyGitEvidence({ contract: childV2, report: childReport, prBaseSha: prBase, prHeadSha: prHead }, missingParentIo),
    /predecessor contract is not available/,
  )
})

test('#3380: a missing predecessor ref fails closed with a structured error, not an unhandled throw', () => {
  const throwingIo = childIo({
    readPublishedContract: (ref) => {
      if (ref === 'refs/db-contracts/42/2') return childV2
      throw new GitEvidenceError(`missing predecessor contract: ${ref} does not exist`)
    },
  })
  assert.throws(
    () => verifyGitEvidence({ contract: childV2, report: childReport, prBaseSha: prBase, prHeadSha: prHead }, throwingIo),
    /missing predecessor contract/,
  )
})

test('#3380: a v2 contract may not fall back to the legacy pair (mismatched pair-vs-identity)', () => {
  const legacyIo = childIo({
    changedFiles: (from) => (from === base ? ['scripts/fix.mjs'] : ['.agent/contract.json', '.agent/completion.json']),
  })
  // The tail predicate and resolveCurrentPair now agree: a v2 contract's
  // acceptable pairs exclude the legacy paths, so the refusal fires at the
  // tail check rather than later in resolveCurrentPair.
  assert.throws(
    () => verifyGitEvidence({ contract: childV2, report: childReport, prBaseSha: prBase, prHeadSha: prHead }, legacyIo),
    /must use its keyed pair|only this pull request's own two evidence files/,
  )
})

test('#3380: an unknown .agent/ path in the implementation diff is refused', () => {
  const filesWithJunk = ['scripts/fix.mjs', '.agent/evil.sh']
  assert.throws(
    () => verifyGitEvidence({ contract, report: { ...report, files_changed: filesWithJunk }, prBaseSha: prBase, prHeadSha: prHead },
      io({ changedFiles: (from) => (from === base ? filesWithJunk : ['.agent/contract.json', '.agent/completion.json']) })),
    /not inert evidence/,
  )
})

test('#3380: a committed-record content mutation reaches refuseCommittedMutation in the gate', () => {
  assert.throws(
    () => verifyGitEvidence({ contract, report, prBaseSha: prBase, prHeadSha: prHead },
      io({ readPublishedContract: () => ({ ...contract, goal: 'mutated after publication' }) })),
    /immutable/,
  )
})

test('#3380: a committed-generation identity mutation is refused with successor guidance', () => {
  assert.throws(
    () => verifyGitEvidence({ contract, report, prBaseSha: prBase, prHeadSha: prHead },
      io({ readPublishedContract: () => ({ ...contract, generation: 2 }) })),
    /cannot be rewritten|publish a successor/,
  )
})
