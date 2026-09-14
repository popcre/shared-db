import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { checkProposalBody, findDestructiveSql, classifyStatement, REQUIRED_HEADINGS } from './lib/destructive-analysis-guard.mjs'
import { main } from './check-destructive-analysis.mjs'

const complete = REQUIRED_HEADINGS.map((h) => `## ${h}\n\nfilled in\n`).join('\n')

function run(argv, files = {}, diff = '') {
  const out = []; const err = []
  const code = main(argv, { readFile: (p) => files[p], diff: () => diff, log: (m) => out.push(m), error: (m) => err.push(m) })
  return { code, out: out.join('\n'), err: err.join('\n') }
}

test('complete checklist passes', () => assert.equal(checkProposalBody(complete).ok, true))

test('missing heading fails and is named', () => {
  const r = checkProposalBody(complete.replace('## Positive control', '## Something else'))
  assert.equal(r.ok, false)
  assert.deepEqual(r.missing, ['Positive control'])
})

test('heading left with only the template comment is empty', () => {
  const r = checkProposalBody(complete.replace('## Evidence class\n\nfilled in', '## Evidence class\n\n<!-- structural or usage -->'))
  assert.deepEqual(r.empty, ['Evidence class'])
})

test('the shipped issue template has every heading but fails until filled', () => {
  const template = readFileSync(new URL('../.github/ISSUE_TEMPLATE/destructive-proposal.md', import.meta.url), 'utf8')
  assert.match(template, /labels: destructive-proposal/)
  const r = checkProposalBody(template)
  assert.deepEqual(r.missing, [])
  assert.deepEqual(r.empty, REQUIRED_HEADINGS)
})

test('CLI: unlabeled issue is not checked; labeled incomplete issue fails', () => {
  assert.equal(run(['--issue-body-file', 'b', '--labels', 'db-work'], { b: '' }).code, 0)
  const r = run(['--issue-body-file', 'b', '--labels', 'db-work,destructive-proposal'], { b: '## Proposed action\ndrop x' })
  assert.equal(r.code, 1)
  assert.match(r.err, /missing heading\(s\): Observation window/)
  assert.equal(run(['--issue-body-file', 'b', '--labels', 'Destructive-Proposal'], { b: complete }).code, 0)
})

const diffFor = (path, lines) => `diff --git a/${path} b/${path}\n--- a/${path}\n+++ b/${path}\n@@ -0,0 +1 @@\n${lines.map((l) => `+${l}`).join('\n')}\n`

test('statement classification', () => {
  assert.deepEqual(classifyStatement('DROP INDEX CONCURRENTLY x'), ['DROP'])
  assert.deepEqual(classifyStatement('truncate plm.x'), ['TRUNCATE'])
  assert.deepEqual(classifyStatement('vacuum (full, analyze) t'), ['VACUUM FULL'])
  assert.deepEqual(classifyStatement('delete from t'), ['DELETE without WHERE'])
  assert.deepEqual(classifyStatement('delete from t where id = 1'), [])
  assert.deepEqual(classifyStatement('drop function f()'), [])
  assert.deepEqual(classifyStatement('vacuum analyze t'), [])
})

test('destructive SQL outside migrations fails; migrations, tests, comments and strings do not', () => {
  assert.deepEqual(findDestructiveSql(diffFor('docs/q/cleanup.sql', ['drop table plm.old;'])), [{ file: 'docs/q/cleanup.sql', kinds: ['DROP'] }])
  assert.deepEqual(findDestructiveSql(diffFor('supabase/migrations/20990101000000_x.sql', ['drop table plm.old;'])), [])
  assert.deepEqual(findDestructiveSql(diffFor('supabase/tests/x.sql', ['truncate t;'])), [])
  assert.deepEqual(findDestructiveSql(diffFor('scripts/x.sql', ['-- drop table t', "select 'truncate';"])), [])
  assert.deepEqual(findDestructiveSql(diffFor('scripts/x.sql', ['delete from t', '  where id = 1;'])), [])
})

test('marker naming an issue permits the statement', () => {
  assert.deepEqual(findDestructiveSql(diffFor('scripts/x.sql', ['-- destructive-proposal: #2427', 'drop index plm.i;'])), [])
  assert.equal(findDestructiveSql(diffFor('scripts/x.sql', ['-- destructive-proposal: soon', 'drop index plm.i;'])).length, 1)
})

test('CLI diff mode exit codes', () => {
  assert.equal(run(['--diff-base', 'origin/main'], {}, diffFor('a.sql', ['vacuum full t;'])).code, 1)
  assert.equal(run(['--diff-base', 'origin/main'], {}, '').code, 0)
  assert.equal(run([]).code, 2)
})
