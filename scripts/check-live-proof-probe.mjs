#!/usr/bin/env node
// Issue #3127 (#3029 acceptance target 8): live proof within 30 minutes of
// production_applied.
//
// WHY THIS EXISTS
// The Shared DB Live Proof workflow runs the probe committed on main at
// `.github/live-proofs/<work_issue>.sql`. In the Step 10 trial, #3043's probe
// was written only AFTER production applied, as its own pull request (#3055).
// That pull request sat idle and then went through three governed review rounds
// before it could merge: production applied 13:40, live proof ran 15:52. The
// live check itself took 21 seconds.
//
// So the probe must ride in the implementation pull request, reviewed together
// with the migration. This guard, run by the guarded migration merge, refuses a
// structural migration pull request whose work issue returns to u2giants/shared-db
// when the probe is absent from the merged tree. An outcome returning to an
// application repository proves itself from that repository and is not judged here.
import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { pathToFileURL } from 'node:url'
import { runGitHubCommand } from './lib/github-transport.mjs'

export const SHARED_DB = 'u2giants/shared-db'
const SCOPE_FENCE = /```db-work-scope\s*\n([\s\S]*?)```/g

export class ProbeCheckError extends Error {}

export function scopeField(body, name) {
  const blocks = [...String(body ?? '').matchAll(SCOPE_FENCE)].map((m) => m[1])
  if (blocks.length !== 1) throw new ProbeCheckError('work issue must carry exactly one db-work-scope block')
  const values = blocks[0].split(/\r?\n/).filter((l) => l.startsWith(`${name}:`)).map((l) => l.slice(name.length + 1).trim())
  if (values.length > 1) throw new ProbeCheckError(`db-work-scope repeats ${name}`)
  return values[0] || null
}

export function probePath(workIssue) { return `.github/live-proofs/${workIssue}.sql` }

// Pure decision. Inputs are gathered by the caller so the rule is testable offline.
export function evaluateProbe({ contract, changedFiles, readIssueBody, probeExists }) {
  const migrations = changedFiles.filter((f) => f.startsWith('supabase/migrations/') && f.endsWith('.sql'))
  if (!migrations.length) return { relevant: false, reason: 'no migration file changed' }
  if (!contract || contract.work_type !== 'structural') return { relevant: false, reason: 'contract is not structural' }
  const issue = contract.work_issue
  if (!Number.isInteger(issue) || issue <= 0) throw new ProbeCheckError('structural contract has no valid work_issue')
  const returnTo = scopeField(readIssueBody(issue), 'application_return_to')
  if (returnTo !== SHARED_DB) return { relevant: false, reason: `outcome #${issue} returns to ${returnTo ?? 'no repository'}` }
  const path = probePath(issue)
  if (!probeExists(path)) {
    throw new ProbeCheckError(`#${issue} returns to ${SHARED_DB} but ${path} is not in this pull request or on main. ` +
      'Commit the read-only live-proof probe (one row with a boolean "passed" column) in this migration pull request, ' +
      'so the live proof can run the moment production applies instead of waiting on a separate reviewed pull request.')
  }
  return { relevant: true, issue, path }
}

function git(args) { return execFileSync('git', args, { encoding: 'utf8' }) }

export function main() {
  try {
    const contract = existsSync('.agent/contract.json') ? JSON.parse(readFileSync('.agent/contract.json', 'utf8')) : null
    const changedFiles = git(['diff', '--name-only', '--diff-filter=AMR', 'origin/main...HEAD']).split(/\r?\n/).filter(Boolean)
    const result = evaluateProbe({
      contract,
      changedFiles,
      readIssueBody: (n) => runGitHubCommand(['api', `repos/${SHARED_DB}/issues/${n}`, '--jq', '.body'],
        { wrapError: (d) => new ProbeCheckError(`GitHub read failed: ${d}`) }),
      probeExists: (p) => existsSync(p),
    })
    console.log(result.relevant ? `Live-proof probe present: ${result.path}.` : `Live-proof probe check not applicable: ${result.reason}.`)
    return 0
  } catch (e) {
    console.error(`REFUSED: ${e.message}`)
    return 2
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) process.exitCode = main()
