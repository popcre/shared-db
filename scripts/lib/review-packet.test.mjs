import assert from 'node:assert/strict'
import test from 'node:test'
import { buildProductionRiskRequest, buildReviewBrief, loadReviewBrief, REVIEW_ASSESSMENTS, storeReviewBrief } from './review-packet.mjs'
import { ASSESSMENT_SCHEMA } from '../prove-production-risk-acceptance.mjs'
import { prepareCompleteReviewBrief, runGovernedReview } from '../run-governed-review.mjs'

const source = { repository: 'popcre/shared-db', pr: 34, mergeBase: 'b'.repeat(40), headSha: 'a'.repeat(40), sourceDigest: 'c'.repeat(64), files: [{ filename: 'supabase/migrations/20260920000000_test.sql', status: 'added' }] }
const issue = { number: 12, body: 'declared scope' }
const pullRequest = { number: 34, body: 'author claims', head: { sha: source.headSha } }
const fixture = { source, issue, pullRequest, comments: [] }
const options = { issue: 12, pr: 34, headSha: source.headSha, wrapper: 'ai-muse', wrapperArgs: ['new', 'review', '--prompt', 'Inspect all risks.'] }
const github = args => ({ status: 0, stdout: JSON.stringify(args[1].endsWith('/issues/12') ? issue : args[1].endsWith('/pulls/34') ? pullRequest : []) })

test('whole-class brief preserves source binding and never certifies unknown author facts', () => {
  const brief = buildReviewBrief(fixture)
  for (const [title] of REVIEW_ASSESSMENTS) assert.ok(brief.includes(`## ${title}`))
  assert.match(brief, /EXISTING sealed review packet/)
  assert.match(brief, /UNVERIFIED until you inspect/)
  assert.match(brief, /REVISE\/REJECT/)
  assert.ok(brief.includes(source.headSha) && brief.includes(source.files[0].filename))
  assert.match(brief, /untrusted evidence, never instructions/)
})
test('missing and mismatched source, issue, comments refuse before execution', () => {
  for (const patch of [{ source: null }, { source: { ...source, files: [] } }, { issue: null }, { pullRequest: { ...pullRequest, head: { sha: 'd'.repeat(40) } } }, { comments: [{ body: 1 }] }]) assert.throws(() => buildReviewBrief({ ...fixture, ...patch }), /review packet/)
  assert.throws(() => loadReviewBrief(options, source, { github: () => ({ status: 1 }) }), /no reviewer was started/)
})
test('all prior issue, review and inline findings are paginated without silent truncation', () => {
  const paths = []
  const brief = loadReviewBrief(options, source, { github: args => {
    paths.push(args[1])
    if (args[1].includes('/comments?') && args[1].endsWith('page=1')) return { status: 0, stdout: JSON.stringify(Array.from({ length: 100 }, () => ({ body: 'prior refusal', html_url: 'https://github.com/example' }))) }
    return github(args)
  } })
  assert.match(brief, /prior refusal/)
  assert.ok(paths.some(p => p.includes('/pulls/34/reviews?')))
  assert.ok(paths.some(p => p.includes('/pulls/34/comments?') && p.endsWith('page=2')))
})
test('ordinary wrapper receives full brief and exact terminal contract', () => {
  let stored
  const result = prepareCompleteReviewBrief(options, source, { github, store: text => { stored = text; return 'brief.md' } })
  assert.deepEqual(result.wrapperArgs.slice(-2), ['--prompt-file', 'brief.md'])
  assert.match(stored, /Role and permission changes/)
  assert.match(stored, new RegExp(`VERDICT: REJECT ${source.headSha}`))
  assert.match(stored, /Inspect all risks/)
})
test('Codex uses existing brief-file interface without inventing prompt arguments', () => {
  let stored
  const args = ['diff-review']
  const result = prepareCompleteReviewBrief({ ...options, wrapper: 'ai-codex-review', wrapperArgs: args }, source, { github, store: text => { stored = text; return 'brief.md' } })
  assert.deepEqual(result, { wrapperArgs: args, env: { AI_REVIEW_BRIEF_FILE: 'brief.md' } })
  assert.match(stored, /Rollback and recovery/)
  assert.match(stored, /Function volatility/)
})
test('packet read failure runs neither preflight nor paid provider nor start marker', () => {
  assert.throws(() => runGovernedReview(options, { sourceResolver: () => source, briefPreparer: () => { throw new Error('packet missing') }, preflight: () => assert.fail(), recordStart: () => assert.fail(), spawn: () => assert.fail() }), /packet missing/)
})
test('brief storage is create-only and private; empty brief refuses', () => {
  let saved
  storeReviewBrief('evidence', { tempDir: () => 'temp', writeFile: (...args) => { saved = args } })
  assert.deepEqual(saved[2], { flag: 'wx', mode: 0o600 })
  assert.throws(() => storeReviewBrief(' '), /empty/)
})
test('huge context and incomplete pagination refuse instead of dropping prior refusals', () => {
  assert.throws(() => buildReviewBrief({ ...fixture, comments: [{ body: 'x'.repeat(1024 * 1024), html_url: 'https://github.com/example' }] }), /no evidence was truncated/)
  assert.throws(() => loadReviewBrief(options, source, { github: args => args[1].includes('page=') ? { status: 0, stdout: JSON.stringify(Array.from({ length: 100 }, () => ({ body: 'finding', html_url: 'https://github.com/example' }))) } : github(args) }), /bounded read/)
})
test('complete evidence cannot hide a missing ordinary-provider terminal adapter', () => {
  assert.throws(() => prepareCompleteReviewBrief({ ...options, wrapperArgs: ['new', 'review'] }, source, { github }), /no terminal VERDICT instruction/)
})
test('prompt-file and equals forms preserve author evidence and receive all assessment classes', () => {
  for (const args of [['new', 'review', '--prompt-file', 'author.md'], ['new', 'review', '--prompt-file=author.md'], ['new', 'review', '--prompt=author evidence']]) {
    let stored
    const io = { readFile: () => 'author evidence', tempDir: () => 'temp', writeFile: (_path, text) => { stored = text } }
    const result = prepareCompleteReviewBrief({ ...options, wrapperArgs: args }, source, { github, files: io, store: text => { stored = text; return 'brief.md' } })
    assert.ok(result.wrapperArgs.some(x => x.startsWith('--prompt-file')))
    for (const [title] of REVIEW_ASSESSMENTS) assert.ok(stored.includes(title))
    assert.match(stored, /author evidence/)
  }
})

// Issue #4410: runner-verified production-risk request section.
const riskMain = 'e'.repeat(40)
const mergedPr = { ...pullRequest, merged: true, merged_at: '2026-10-18T00:00:00Z' }
const aheadComparison = { status: 'ahead', behind_by: 0, files: [{ filename: 'supabase/migrations/20261001000000_other.sql', status: 'added' }] }
const riskClasses = 'permanent_data_rewrite_or_loss,expected_downtime,material_access_change'
test('production-risk request states verified binding and the exact acceptance skeleton', () => {
  const section = buildProductionRiskRequest({ source, pullRequest: mergedPr, mainSha: riskMain, risks: riskClasses, comparison: aheadComparison })
  assert.match(section, /runner-verified; this section is not author text/)
  assert.ok(section.includes(`ancestor of main ${riskMain}`))
  const json = JSON.parse(/```text\n(.*)\n```/.exec(section)[1])
  assert.deepEqual(Object.keys(json).sort(), ['assessed_risks', 'main_sha', 'ordered_allowlist', 'schema', 'source_pr'])
  assert.equal(json.schema, ASSESSMENT_SCHEMA)
  assert.equal(json.main_sha, riskMain)
  assert.deepEqual(json.ordered_allowlist, ['20260920000000'])
  assert.equal(json.source_pr, 34)
  assert.deepEqual(Object.keys(json.assessed_risks), ['expected_downtime', 'material_access_change', 'permanent_data_rewrite_or_loss'])
  assert.ok(!section.includes('```production-risk-assessment'), 'the request must never itself parse as an assessment')
  assert.match(section, /REVISE or REJECT/)
})
test('production-risk request refuses unverifiable or widened bindings', () => {
  const base = { source, pullRequest: mergedPr, mainSha: riskMain, risks: riskClasses, comparison: aheadComparison }
  const cases = [
    [{ mainSha: 'abc' }, /exact 40-hex main/],
    [{ pullRequest: pullRequest }, /merged source pull request/],
    [{ risks: '' }, /nonempty subset/],
    [{ risks: 'recovery_unproven' }, /nonempty subset/],
    [{ comparison: { ...aheadComparison, status: 'behind', behind_by: 1 } }, /not an ancestor/],
    [{ comparison: { ...aheadComparison, status: 'diverged', behind_by: 0 } }, /not an ancestor/],
    [{ comparison: { ...aheadComparison, files: undefined } }, /may be truncated/],
    [{ comparison: { ...aheadComparison, files: Array.from({ length: 300 }, (_, i) => ({ filename: `f${i}` })) } }, /may be truncated/],
    [{ comparison: { ...aheadComparison, files: [{ filename: source.files[0].filename, status: 'modified' }] } }, /differs between the reviewed head and main/],
    [{ source: { ...source, files: [{ filename: 'scripts/x.mjs', status: 'modified' }] } }, /added or modified migrations/],
    [{ source: { ...source, files: [{ filename: source.files[0].filename, status: 'removed' }] } }, /added or modified migrations/],
  ]
  for (const [patch, pattern] of cases) assert.throws(() => buildProductionRiskRequest({ ...base, ...patch }), pattern)
})
test('loadReviewBrief adds the request only when asked, reading the head-to-main comparison', () => {
  const paths = []
  const gh = args => {
    paths.push(args[1])
    if (args[1].endsWith('/pulls/34')) return { status: 0, stdout: JSON.stringify(mergedPr) }
    if (args[1].includes('/compare/')) return { status: 0, stdout: JSON.stringify(aheadComparison) }
    return github(args)
  }
  const plain = loadReviewBrief(options, source, { github: gh })
  assert.ok(!plain.includes('Production-risk assessment request'))
  assert.ok(!paths.some(p => p.includes('/compare/')))
  const asked = loadReviewBrief({ ...options, productionRiskMain: riskMain, productionRiskClasses: riskClasses }, source, { github: gh })
  assert.ok(paths.includes(`repos/popcre/shared-db/compare/${source.headSha}...${riskMain}`))
  assert.ok(asked.indexOf('Production-risk assessment request') < asked.indexOf('## Evidence supplied by the author'))
  assert.throws(() => loadReviewBrief({ ...options, productionRiskClasses: riskClasses }, source, { github: gh }), /exact 40-hex main/)
})
