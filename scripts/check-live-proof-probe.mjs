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
// structural migration pull request whose work issue returns to this repository (shared-db)
// when the probe is absent from both the pull request tree and main. An outcome
// returning to an application repository proves itself from that repository and
// is not judged here.
import { execFileSync } from 'node:child_process'
import { existsSync, readFileSync } from 'node:fs'
import { pathToFileURL } from 'node:url'
import { runGitHubCommand } from './lib/github-transport.mjs'
import { validateHistoricalRestorationFile } from './historical-migration-restorations.mjs'
import { currentRepository, isThisRepositoryOrHistorical } from './lib/repository-identity.mjs'

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

// A probe the live-proof workflow could accept must select a `passed` column.
// Its row count and value are proven only at live-proof time, on production.
export function probeLooksUsable(sql) {
  const text = String(sql ?? '')
  return /\bselect\b/i.test(text) && /\bpassed\b/i.test(text)
}

// Pure decision; inputs are gathered by the caller so the rule is testable offline.
// Fail closed: a migration pull request with no contract, a structural outcome with
// no return address, or a probe that cannot pass all refuse here.
export function evaluateProbe({ contract, changedFiles, readIssueBody, readProbe, isCodeTruthRestoration = () => false, repository }) {
  const migrations = changedFiles.filter((f) => f.startsWith('supabase/migrations/') && f.endsWith('.sql'))
  if (!migrations.length) return { relevant: false, reason: 'no migration file changed' }
  // Same exemption as the lease gate: a code-truth restoration re-records history
  // that is already applied and has no outcome of its own to prove.
  if (migrations.length === 1 && isCodeTruthRestoration(migrations[0])) return { relevant: false, reason: 'historical code-truth restoration' }
  if (!contract) throw new ProbeCheckError('migration pull request has no .agent/contract.json; cannot tell which outcome it proves')
  if (contract.work_type !== 'structural') return { relevant: false, reason: 'contract is not structural' }
  const issue = contract.work_issue
  if (!Number.isInteger(issue) || issue <= 0) throw new ProbeCheckError('structural contract has no valid work_issue')
  const returnTo = scopeField(readIssueBody(issue), 'application_return_to')
  if (!returnTo) throw new ProbeCheckError(`structural outcome #${issue} has no application_return_to in its db-work-scope`)
  // Resolved only here, so a pull request with no structural outcome never needs an identity (#2530).
  repository ??= currentRepository()
  if (!isThisRepositoryOrHistorical(returnTo, repository)) return { relevant: false, reason: `outcome #${issue} returns to ${returnTo}` }
  const path = probePath(issue)
  const sql = readProbe(path)
  if (sql === null || sql === undefined) {
    throw new ProbeCheckError(`#${issue} returns to ${repository} but ${path} is not in this pull request or on main. ` +
      'Commit the read-only live-proof probe (one row with a boolean "passed" column) in this migration pull request, ' +
      'so the live proof can run the moment production applies instead of waiting on a separate reviewed pull request.')
  }
  if (!probeLooksUsable(sql)) throw new ProbeCheckError(`${path} does not select a "passed" column; the live proof would refuse it`)
  return { relevant: true, issue, path }
}

function git(args) { return execFileSync('git', args, { encoding: 'utf8', stdio: ['ignore', 'pipe', 'ignore'] }) }

export function main() {
  try {
    const contract = existsSync('.agent/contract.json') ? JSON.parse(readFileSync('.agent/contract.json', 'utf8')) : null
    const changedFiles = git(['diff', '--name-only', '--diff-filter=AMR', 'origin/main...HEAD']).split(/\r?\n/).filter(Boolean)
    const result = evaluateProbe({
      contract,
      changedFiles,
      readIssueBody: (n) => runGitHubCommand(['api', `repos/${currentRepository()}/issues/${n}`, '--jq', '.body'],
        { wrapError: (d) => new ProbeCheckError(`GitHub read failed: ${d}`) }),
      // main may have moved past this branch under the --contains freshness rule.
      readProbe: (p) => {
        if (existsSync(p)) return readFileSync(p, 'utf8')
        try { return git(['show', `origin/main:${p}`]) } catch { return null }
      },
      isCodeTruthRestoration: (f) => {
        try { return validateHistoricalRestorationFile(f, readFileSync(f, 'utf8')).codeTruthOnly === true } catch { return false }
      },
    })
    console.log(result.relevant ? `Live-proof probe present: ${result.path}.` : `Live-proof probe check not applicable: ${result.reason}.`)
    return 0
  } catch (e) {
    console.error(`REFUSED: ${e.message}`)
    return 2
  }
}

if (import.meta.url === pathToFileURL(process.argv[1] ?? '').href) process.exitCode = main()
