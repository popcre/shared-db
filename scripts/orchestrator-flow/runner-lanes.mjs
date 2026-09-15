#!/usr/bin/env node
// Runner lanes for queue-sensitive required checks (issue #2729, programme ai-devops#401 Step 7).
//
// The registry (runner-lanes.json) declares five free, standard, GitHub-hosted runner labels
// that can each run the queue-sensitive jobs with the same assertions. start-reroute.mjs reads
// qualifiedLanesFor() as its qualified_lanes input, so a job that is never picked up is replaced
// by exactly one new run on a different lane (dispatched through the workflow's `lane` input).
//
// The aggregate verdict is the stable required context. It passes only when every required
// assertion has exactly one successful check run for the head, across the default and lane runs.
import fs from 'node:fs'
import path from 'node:path'
import { fileURLToPath } from 'node:url'
import { ghJson } from '../lib/github-transport.mjs'

export class RunnerLaneError extends Error {}
const HERE = path.dirname(fileURLToPath(import.meta.url))
export const REGISTRY_PATH = path.join(HERE, 'runner-lanes.json')
const LABEL = /^[a-z0-9][a-z0-9.-]*$/, TOKEN = /^[A-Za-z0-9._-]+$/, SHA = /^[0-9a-f]{40}$/i
const FAILED = new Set(['failure', 'timed_out', 'action_required', 'startup_failure', 'stale'])
const IGNORED = new Set(['cancelled', 'skipped', 'neutral'])

export function validateRegistry(registry) {
  if (registry?.schema_version !== 1) throw new RunnerLaneError('runner lane registry schema_version must be 1')
  if (typeof registry.aggregate_context !== 'string' || !registry.aggregate_context) throw new RunnerLaneError('aggregate_context is required')
  const lanes = registry.lanes
  if (!Array.isArray(lanes) || lanes.length < 5) throw new RunnerLaneError('at least five runner lanes are required')
  const names = new Set()
  for (const lane of lanes) {
    if (!LABEL.test(String(lane?.label ?? '')) || lane.name !== lane.label) throw new RunnerLaneError(`lane label is unsafe: ${lane?.label}`)
    if (lane.class !== 'standard') throw new RunnerLaneError(`lane ${lane.label} is not a free standard runner`)
    if (/large|cores|gpu|xl/i.test(lane.label)) throw new RunnerLaneError(`lane ${lane.label} looks like a larger paid runner`)
    if (names.has(lane.label)) throw new RunnerLaneError(`duplicate lane ${lane.label}`)
    names.add(lane.label)
  }
  const jobs = registry.queue_sensitive_jobs
  if (!Array.isArray(jobs) || !jobs.length) throw new RunnerLaneError('queue_sensitive_jobs must be nonempty')
  const contexts = new Set(), assertionNames = new Set()
  for (const job of jobs) {
    if (!job?.workflow || !job.job_id || !job.context) throw new RunnerLaneError('each queue-sensitive job needs workflow, job_id and context')
    if (contexts.has(job.context) || job.context === registry.aggregate_context) throw new RunnerLaneError(`duplicate context ${job.context}`)
    contexts.add(job.context)
    if (!Array.isArray(job.assertions) || !job.assertions.length) throw new RunnerLaneError(`${job.context} needs assertions`)
    for (const a of job.assertions) {
      if (!TOKEN.test(a) || assertionNames.has(a)) throw new RunnerLaneError(`assertion is unsafe or duplicated: ${a}`)
      assertionNames.add(a)
    }
  }
  return registry
}

export function loadRegistry(file = REGISTRY_PATH) {
  return validateRegistry(JSON.parse(fs.readFileSync(file, 'utf8')))
}

export function jobFor(registry, workflow) {
  const job = registry.queue_sensitive_jobs.find((x) => x.workflow === workflow)
  if (!job) throw new RunnerLaneError(`workflow ${workflow} is not a registered queue-sensitive job`)
  return job
}

// The qualified_lanes input for runnerStartDecision: every lane carries the job's full assertion set.
export function qualifiedLanesFor(registry, workflow) {
  const job = jobFor(registry, workflow)
  return registry.lanes.map((lane) => ({ name: lane.label, qualified: lane.qualified === true, assertions: [...job.assertions] }))
}

// Dispatch parameters for a replacement run; nothing here performs the dispatch.
export function replacementDispatchInputs(registry, decision) {
  if (decision?.action !== 'dispatch-new-run') throw new RunnerLaneError('replacement inputs require a dispatch-new-run decision')
  jobFor(registry, decision.workflow)
  if (!registry.lanes.some((lane) => lane.label === decision.lane && lane.qualified === true)) throw new RunnerLaneError(`lane ${decision.lane} is not qualified`)
  return { workflow: decision.workflow, inputs: { lane: decision.lane }, head_sha: decision.head_sha }
}

export function laneCheckName(context, lane) { return `${context} [lane ${lane}]` }

function parseCheckName(registry, name) {
  for (const job of registry.queue_sensitive_jobs) {
    if (name === job.context) return { job, lane: null }
    const prefix = `${job.context} [lane `
    if (name.startsWith(prefix) && name.endsWith(']')) return { job, lane: name.slice(prefix.length, -1) }
  }
  return null
}

// Pure verdict over the head's latest check runs. Returns {verdict:'pass'|'pending'|'refuse', ...}.
export function aggregateVerdict(registry, checkRuns) {
  validateRegistry(registry)
  if (!Array.isArray(checkRuns)) throw new RunnerLaneError('check runs must be an array')
  const byJob = new Map(registry.queue_sensitive_jobs.map((job) => [job.context, []]))
  const refusals = []
  for (const run of checkRuns) {
    const parsed = parseCheckName(registry, String(run?.name ?? ''))
    if (!parsed) continue
    if (parsed.lane !== null && !registry.lanes.some((lane) => lane.label === parsed.lane)) {
      refusals.push(`${run.name}: unregistered lane`)
      continue
    }
    byJob.get(parsed.job.context).push(run)
  }
  const passed = [], pending = []
  for (const job of registry.queue_sensitive_jobs) {
    const runs = byJob.get(job.context)
    const failed = runs.filter((r) => r.status === 'completed' && FAILED.has(r.conclusion))
    const succeeded = runs.filter((r) => r.status === 'completed' && r.conclusion === 'success')
    const open = runs.filter((r) => r.status !== 'completed')
    const unknown = runs.filter((r) => r.status === 'completed' && r.conclusion !== 'success' && !FAILED.has(r.conclusion) && !IGNORED.has(r.conclusion))
    if (failed.length) refusals.push(`${job.context}: failed assertion (${failed.map((r) => `${r.name}=${r.conclusion}`).join(', ')})`)
    else if (unknown.length) refusals.push(`${job.context}: unreadable conclusion (${unknown.map((r) => `${r.name}=${r.conclusion}`).join(', ')})`)
    else if (succeeded.length > 1) refusals.push(`${job.context}: duplicate assertion (${succeeded.map((r) => r.name).join(', ')})`)
    else if (open.length) pending.push(`${job.context}: ${open.map((r) => `${r.name}=${r.status}`).join(', ')}`)
    else if (succeeded.length === 1) passed.push(...job.assertions)
    else refusals.push(`${job.context}: assertion never ran successfully`)
  }
  if (refusals.length) return { verdict: 'refuse', refusals, pending }
  if (pending.length) return { verdict: 'pending', pending }
  const required = registry.queue_sensitive_jobs.flatMap((job) => job.assertions).sort()
  if (JSON.stringify([...passed].sort()) !== JSON.stringify(required)) return { verdict: 'refuse', refusals: ['accepted assertions do not equal the required set'] }
  return { verdict: 'pass', assertions: required }
}

// Workflow YAML must expose exactly the registry's lanes and keep the stable default context.
export function workflowLaneConformance(registry, rawWorkflowText, job) {
  const problems = [], workflowText = String(rawWorkflowText).replace(/\r\n/g, '\n')
  const options = [...workflowText.matchAll(/^\s+- (ubuntu-[a-z0-9.-]+)\s*$/gm)].map((m) => m[1])
  const labels = registry.lanes.map((lane) => lane.label)
  if (JSON.stringify(options) !== JSON.stringify(labels)) problems.push(`lane choice options ${JSON.stringify(options)} differ from registry ${JSON.stringify(labels)}`)
  const input = /^ {6}lane:\n((?: {8}.*\n| {10}.*\n)+)/m.exec(workflowText)?.[1] ?? ''
  if (!/^ {8}type: choice$/m.test(input)) problems.push('lane input type is not choice')
  if (!/^ {8}default: ''$/m.test(input)) problems.push("lane input default is not ''")
  if (!/^ {8}required: false$/m.test(input)) problems.push('lane input required flag is not false')
  const perms = [...workflowText.matchAll(/^([ \t]*)permissions:(.*)$/gm)]
  const topPerms = /^permissions:\n((?: {2}\S.*\n)+)/m.exec(workflowText)?.[1] ?? ''
  if (perms.length !== 1 || perms[0][1] !== '' || perms[0][2].trim() !== '' || topPerms !== '  contents: read\n') problems.push('permissions are not exactly contents: read')
  const guard = /case "\$LANE" in\n\s+(.*)\) ;;\n\s+\*\) echo "::error::Unregistered runner lane: \$LANE"; exit 1 ;;/.exec(workflowText)
  if (!guard || JSON.stringify(guard[1].split('|')) !== JSON.stringify(["''", ...labels])) problems.push('lane guard step does not refuse values outside the registry')
  if (!workflowText.includes(`LANE: \${{ inputs.lane }}`)) problems.push('lane guard step does not read the lane input')
  if (!workflowText.includes(`runs-on: \${{ inputs.lane || 'ubuntu-latest' }}`)) problems.push('runs-on does not select the lane input with ubuntu-latest default')
  if (!workflowText.includes(`name: \${{ inputs.lane && format('${job.context} [lane {0}]', inputs.lane) || '${job.context}' }}`)) problems.push('job name does not keep the stable default context and lane-suffixed replacement name')
  return problems
}

function argValue(argv, flag) { const i = argv.indexOf(flag); return i >= 0 ? argv[i + 1] : undefined }

export function runAggregate({ repo, headSha, registry = loadRegistry(), fetchRuns, sleep, now = Date.now, timeoutMs, intervalMs = 20000, log = console.log }) {
  if (!SHA.test(String(headSha ?? '')) || !/^[\w.-]+\/[\w.-]+$/.test(String(repo ?? ''))) throw new RunnerLaneError('aggregate requires --repo owner/name and a 40-hex --head-sha')
  const deadline = now() + timeoutMs
  for (;;) {
    const result = aggregateVerdict(registry, fetchRuns(repo, headSha))
    if (result.verdict !== 'pending') return result
    if (now() >= deadline) return { verdict: 'refuse', refusals: result.pending.map((p) => `still not finished at deadline: ${p}`) }
    log(`waiting: ${result.pending.join('; ')}`)
    sleep(intervalMs)
  }
}

function fetchCheckRuns(repo, sha) {
  const body = ghJson(['api', `repos/${repo}/commits/${sha}/check-runs?per_page=100&filter=latest`])
  if (!Array.isArray(body?.check_runs) || body.total_count > body.check_runs.length) throw new RunnerLaneError('check-run listing is incomplete; refusing rather than judging a partial page')
  return body.check_runs.map((r) => ({ name: r.name, status: r.status, conclusion: r.conclusion }))
}

if (process.argv[1] && path.resolve(process.argv[1]) === fileURLToPath(import.meta.url)) {
  const argv = process.argv.slice(2)
  try {
    if (!argv.includes('--aggregate')) throw new RunnerLaneError('usage: runner-lanes.mjs --aggregate --repo owner/name --head-sha SHA [--timeout-minutes N]')
    const result = runAggregate({
      repo: argValue(argv, '--repo'),
      headSha: argValue(argv, '--head-sha'),
      fetchRuns: fetchCheckRuns,
      sleep: (ms) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms),
      timeoutMs: Number(argValue(argv, '--timeout-minutes') ?? 45) * 60000,
    })
    if (result.verdict !== 'pass') { console.error(`AGGREGATE REFUSED:\n  ${result.refusals.join('\n  ')}`); process.exit(1) }
    console.log(`AGGREGATE PASSED: ${result.assertions.join(', ')} each ran exactly once`)
  } catch (error) { console.error(error.message); process.exit(1) }
}
