#!/usr/bin/env node
// Issue #2437 CLI. Two modes, both offline and read-only:
//   --issue-body-file <path> [--labels <comma list>]
//       Fails when the labels include `destructive-proposal` and the body lacks a
//       required checklist heading or leaves one empty.
//   --diff-base <git ref>
//       Fails when SQL added since the base introduces DROP / TRUNCATE /
//       VACUUM FULL / DELETE without WHERE outside migrations and test fixtures,
//       without a `-- destructive-proposal: #<issue>` marker in the same file.
import { readFileSync } from 'node:fs'
import { execFileSync } from 'node:child_process'
import { pathToFileURL } from 'node:url'
import { PROPOSAL_LABEL, REQUIRED_HEADINGS, checkProposalBody, findDestructiveSql } from './lib/destructive-analysis-guard.mjs'

export function main(argv, io = { readFile: (p) => readFileSync(p, 'utf8'), diff: (base) => execFileSync('git', ['diff', '--unified=0', '--no-ext-diff', `${base}...HEAD`, '--', '*.sql'], { encoding: 'utf8', maxBuffer: 256 * 1024 * 1024 }), log: console.log, error: console.error }) {
  const arg = (name) => { const i = argv.indexOf(name); return i >= 0 ? argv[i + 1] : undefined }
  const bodyFile = arg('--issue-body-file')
  const base = arg('--diff-base')
  if (bodyFile !== undefined) {
    const labels = String(arg('--labels') ?? '').split(',').map((l) => l.trim().toLowerCase()).filter(Boolean)
    if (!labels.includes(PROPOSAL_LABEL)) { io.log(`Issue is not labeled ${PROPOSAL_LABEL}; checklist not required.`); return 0 }
    const result = checkProposalBody(io.readFile(bodyFile))
    if (result.ok) { io.log(`Destructive-proposal checklist complete: ${REQUIRED_HEADINGS.join(', ')}.`); return 0 }
    if (result.missing.length) io.error(`ERROR: destructive-proposal issue body is missing heading(s): ${result.missing.join(', ')}`)
    if (result.empty.length) io.error(`ERROR: destructive-proposal issue body leaves heading(s) empty: ${result.empty.join(', ')}`)
    io.error('Absence is not proof (#2437). Use .github/ISSUE_TEMPLATE/destructive-proposal.md and fill every section in the BODY, not a comment.')
    return 1
  }
  if (base !== undefined) {
    const findings = findDestructiveSql(io.diff(base))
    if (!findings.length) { io.log('No unmarked destructive SQL added outside migrations.'); return 0 }
    io.error('ERROR: destructive SQL added outside the migration path (#2437):')
    for (const f of findings) io.error(`  ${f.file}: ${f.kinds.join(', ')}`)
    io.error('Add `-- destructive-proposal: #<issue>` naming a destructive-proposal issue whose checklist is complete, or remove the statement.')
    return 1
  }
  io.error('usage: check-destructive-analysis.mjs --issue-body-file <path> [--labels <list>] | --diff-base <ref>')
  return 2
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) process.exitCode = main(process.argv.slice(2))
