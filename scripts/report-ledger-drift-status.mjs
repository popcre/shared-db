#!/usr/bin/env node
//
// LEDGER-DRIFT STATUS REPORT — what is pending, who merged it, who must promote it.
//
// WHY THIS EXISTS (issue #2508)
// ----------------------------
//   The migration-ledger drift check (check-migration-ledger-drift.mjs) correctly
//   reports WHAT is drift. It does not say WHERE each pending version came from or
//   WHO owns its promotion. Alarm issues like #2508 therefore accumulate hand-written
//   status comments that go stale, and every successor session re-researches the same
//   git history from scratch.
//
//   This tool turns a drift-check JSON result into an issue-comment-ready status
//   report: one row per actionable version, with the introducing commit and source
//   PR number recovered from git, plus a compact promotion-candidate list that names
//   the bounded workflow each genuinely-pending version must enter.
//
// READ-ONLY. It reads git history and a JSON file. It never writes to any database,
// never dispatches a workflow, and never touches production.
//
//   node scripts/report-ledger-drift-status.mjs --json drift.json
//   node scripts/check-migration-ledger-drift.mjs --target production --json \
//     | node scripts/report-ledger-drift-status.mjs --json -
//
// Exit 0 = report generated. Exit 2 = COULD NOT generate (missing input, bad JSON,
// or no actionable versions to attribute — which is a clean-drift answer, not this
// tool's failure mode; use the drift check itself for that verdict).

import { execFileSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'

const repoRoot = path.resolve(path.dirname(fileURLToPath(import.meta.url)), '..')

export class Unknown extends Error {}

// ---------------------------------------------------------------------------
// Pure logic — no network, no filesystem.
// ---------------------------------------------------------------------------

/**
 * Recover a GitHub PR number from a commit subject.
 *
 * Merge commits carry `Merge pull request #1234 from ...`. Squash and rebase
 * merges carry a trailing `(#1234)`. A bare `#1234` anywhere in the subject is
 * accepted as a last resort because several migrations reference their work
 * issue that way and the number is still the right pointer for a human.
 */
export function prNumberFromSubject(subject) {
  const text = String(subject ?? '')
  const merge = text.match(/Merge pull request #(\d+)/)
  if (merge) return Number(merge[1])
  const squash = text.match(/\(#(\d+)\)\s*$/)
  if (squash) return Number(squash[1])
  const any = text.match(/#(\d+)/)
  if (any) return Number(any[1])
  return null
}

/**
 * One status row per actionable version. `attribution` is a map of version ->
 * { commit, subject, pr } as recovered from git; missing entries are tolerated
 * and rendered as "unattributed" rather than failing the whole report.
 */
export function buildStatusRows(drift, attribution = {}) {
  const rows = []
  for (const version of drift.actionableMergedNotApplied ?? []) {
    const info = attribution[version] ?? {}
    rows.push({
      version,
      file: drift.fileByVersion?.[version] ?? '',
      kind: drift.pendingClassifications?.[version]?.kind ?? 'genuinely-pending',
      reason: drift.pendingClassifications?.[version]?.reason ?? '',
      commit: info.commit ?? '',
      subject: info.subject ?? '',
      pr: info.pr ?? null,
    })
  }
  return rows
}

/**
 * Render the issue-comment-ready markdown. Deliberately compact: the alarm issue
 * is a tracker, not a whitepaper. Every line must survive being read six weeks
 * later by a session that has none of this conversation.
 */
export function formatStatusReport({ target, projectRef, baseRef, drift, rows }) {
  const lines = []
  const actionable = rows.length
  const excluded = (drift.intentionallyExcluded ?? []).length
  const foreign = (drift.foreignTarget ?? []).length
  const orphans = (drift.appliedNotMerged ?? []).length

  lines.push(`## Ledger drift status — ${target} (\`${projectRef}\`)`)
  lines.push('')
  lines.push(`Merged on \`${baseRef}\`: **${drift.mergedCount}**. Applied in \`supabase_migrations.schema_migrations\`: **${drift.appliedCount}**.`)
  lines.push('')

  if (actionable === 0 && orphans === 0) {
    lines.push('**No actionable drift.** Every merged version has a ledger row (retired/held/foreign-target versions may still appear in the check output for visibility).')
    return lines.join('\n')
  }

  if (actionable > 0) {
    lines.push(`### Promotion candidates — ${actionable} genuinely-pending version(s)`)
    lines.push('')
    lines.push('| version | source PR | file |')
    lines.push('|---|---|---|')
    for (const row of rows) {
      const pr = row.pr ? `#${row.pr}` : 'unattributed'
      const file = row.file ? `\`${row.file.split('/').pop()}\`` : '—'
      lines.push(`| \`${row.version}\` | ${pr} | ${file} |`)
    }
    lines.push('')
    lines.push('These are reviewed, merged migrations that are **not** switched on in this database.')
    lines.push('⚠️ Any object they create is **absent from the live catalog**. Do not read that absence as "the work was never done" (issue #892).')
    lines.push('')
    lines.push('**Holders:** each version above needs a production apply through the bounded Shared Supabase Migrations workflow. That lane is the orchestrator\'s single production lane, not this session\'s. This report is detection only — no production action was taken.')
    lines.push('')
  }

  if (excluded > 0 || foreign > 0) {
    lines.push(`Non-actionable listings: **${excluded}** retired/deliberately-held, **${foreign}** foreign-target. Their absence is the intended end state; see the check output for reasons.`)
    lines.push('')
  }

  if (orphans > 0) {
    lines.push(`### Orphan ledger rows — ${orphans}`)
    lines.push('')
    for (const version of drift.appliedNotMerged ?? []) lines.push(`- \`${version}\``)
    lines.push('')
    lines.push('An orphan ledger row means DDL reached this database from outside reviewed, merged history. Supabase keys the ledger on the version alone, so a later migration that legitimately takes one of these versions will be silently skipped.')
    lines.push('')
  }

  lines.push(`*Generated by \`scripts/report-ledger-drift-status.mjs\` from a \`check-migration-ledger-drift --json\` result. Detection/recovery reporting only — no production apply.*`)
  return lines.join('\n')
}

// ---------------------------------------------------------------------------
// I/O — git log for PR attribution. Injected, so the logic above is unit-testable.
// ---------------------------------------------------------------------------

/**
 * The first-parent commit on the base branch that introduced each migration
 * file — for a PR merged with a merge commit, that is the merge commit itself,
 * whose subject carries `Merge pull request #NNNN`. A PR number is recovered
 * from that subject when one is present.
 *
 * `--first-parent` is the key: the raw `git log --diff-filter=A` finds the
 * commit inside the feature branch that created the file, whose subject has no
 * PR number. Walking only first-parent history finds the merge that landed the
 * file on main.
 */
export function attributeVersions(fileByVersion, run = execFileSync) {
  const attribution = {}
  for (const [version, file] of Object.entries(fileByVersion ?? {})) {
    if (!file) continue
    let out = ''
    try {
      out = run('git', ['-C', repoRoot, 'log', '--first-parent', '--format=%H%x09%s', '--reverse', 'origin/main', '--', file], {
        encoding: 'utf8',
        maxBuffer: 1024 * 1024,
      })
    } catch {
      // A file git cannot attribute is not a reason to refuse the whole report.
      continue
    }
    const line = String(out).trim().split(/\r?\n/)[0] ?? ''
    if (!line) continue
    const tab = line.indexOf('\t')
    const commit = tab === -1 ? line : line.slice(0, tab)
    const subject = tab === -1 ? '' : line.slice(tab + 1)
    attribution[version] = { commit, subject, pr: prNumberFromSubject(subject) }
  }
  return attribution
}

// ---------------------------------------------------------------------------
// CLI
// ---------------------------------------------------------------------------

function parseArgs(argv) {
  const options = { jsonPath: null, help: false }
  for (let i = 0; i < argv.length; i += 1) {
    const arg = argv[i]
    if (arg === '--json') {
      options.jsonPath = argv[(i += 1)]
      if (!options.jsonPath) throw new Unknown('--json requires a file path or - for stdin')
    } else if (arg === '--help' || arg === '-h') {
      options.help = true
    } else {
      throw new Unknown(`unknown argument: ${arg}`)
    }
  }
  return options
}

const USAGE = `
Turn a check-migration-ledger-drift --json result into an issue-comment-ready
status report with per-version PR attribution.

  node scripts/check-migration-ledger-drift.mjs --target production --json \\
    | node scripts/report-ledger-drift-status.mjs --json -

  node scripts/report-ledger-drift-status.mjs --json drift.json

Options:
  --json <path|->   Drift-check JSON output. Use - to read stdin.
  --help            Show this help.

Exit 0 = report generated. Exit 2 = COULD NOT generate.
`.trim()

export async function main(argv) {
  let options
  try {
    options = parseArgs(argv)
  } catch (error) {
    console.error(String(error.message))
    console.error(USAGE)
    return 2
  }
  if (options.help) {
    console.log(USAGE)
    return 0
  }
  if (!options.jsonPath) {
    console.error('UNKNOWN: --json is required (a file path, or - for stdin).')
    console.error(USAGE)
    return 2
  }

  let raw
  try {
    raw = options.jsonPath === '-' ? readFileSync(0, 'utf8') : readFileSync(options.jsonPath, 'utf8')
  } catch (error) {
    console.error(`UNKNOWN: could not read drift JSON: ${error.message}`)
    return 2
  }

  let result
  try {
    result = JSON.parse(raw)
  } catch {
    console.error('UNKNOWN: drift input is not valid JSON.')
    return 2
  }
  if (!result?.drift || typeof result.drift.mergedCount !== 'number') {
    console.error('UNKNOWN: drift JSON is missing the expected shape (drift.mergedCount).')
    return 2
  }

  const fileByVersion = result.fileByVersion ?? {}
  const attribution = attributeVersions(fileByVersion)
  const rows = buildStatusRows(
    { ...result.drift, fileByVersion, pendingClassifications: result.pendingClassifications ?? {} },
    attribution,
  )
  console.log(formatStatusReport({
    target: result.target ?? 'production',
    projectRef: result.projectRef ?? 'unknown',
    baseRef: result.baseRef ?? 'origin/main',
    drift: result.drift,
    rows,
  }))
  return 0
}

const invokedDirectly = process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)
if (invokedDirectly) process.exitCode = await main(process.argv.slice(2))
