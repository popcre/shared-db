// Issue #3187 (Refs #2773): wire-level proof that normal reviewer assignment and
// replacement stay within 10 GitHub API requests. The real CLI runs in a child
// process with every gh/git call answered by scripts/test-fixtures/github-wire-fake.mjs,
// which logs one row per call. A `gh api --paginate` invocation is logged once; a
// listing longer than 100 rows costs one more request per extra page in real life.
import test from 'node:test'
import assert from 'node:assert/strict'
import { spawnSync } from 'node:child_process'
import { mkdtempSync, readFileSync, writeFileSync, rmSync, existsSync, mkdirSync } from 'node:fs'
import { tmpdir } from 'node:os'
import path from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import { canonicalJson, sha256 } from './orchestrator-flow/evidence-bundle.mjs'
import { DELIVERY_CHECKS, runDeliveryPreflight } from './orchestrator-flow/delivery-preflight.mjs'

const here = path.dirname(fileURLToPath(import.meta.url))
const cli = path.join(here, 'manage-migration-author-lanes.mjs')
const fake = pathToFileURL(path.join(here, 'test-fixtures', 'github-wire-fake.mjs')).href
const HEAD = 'a'.repeat(40), MAIN = 'b'.repeat(40), TREE = 'c'.repeat(40)
const LIMIT = 10

function seed(file) {
  const scope = 'work\n\n```db-work-scope\nstatus: ready\nwork_type: repo-maintenance\nroute: repo-maintenance\nchange_type: workflow\npriority: 550\ndepends_on:\nwrites:\n```\n'
  writeFileSync(file, JSON.stringify({
    refs: { 'refs/heads/main': MAIN, 'refs/db-coordination/reviewer-index-cutover': MAIN },
    commits: { [MAIN]: { message: 'main', tree: TREE, parents: [] }, [HEAD]: { message: 'head', tree: TREE, parents: [MAIN] } },
    prs: { 9002: { state: 'open', head: HEAD, files: [{ filename: 'scripts/example.mjs', status: 'modified' }], closing: [9001], body: 'Closes #9001' } },
    issues: { 9001: { state: 'open', title: 'tooling', body: scope, labels: [] } },
  }))
  // Assignment now requires a registered, exact-head delivery preflight. Keep
  // this wire-budget fixture on the real governed path, with no network calls.
  const dir=path.dirname(file),registry=path.join(dir,'registry')
  mkdirSync(registry)
  const checks=Object.fromEntries(DELIVERY_CHECKS.map((name)=>[name,{status:'PASS',evidence_id:`${name}:9001:9002:${HEAD}`}]))
  const registrations=new Map()
  for(const kind of ['sidecars','producers']){
    const registration={evidence_id:checks[kind].evidence_id,kind,issue:9001,pr:9002,head_sha:HEAD,producer_id:`${kind}-producer`,artifact_digest:'d'.repeat(64)}
    registrations.set(registration.evidence_id,registration)
    Object.assign(checks[kind],{producer_id:registration.producer_id,artifact_digest:registration.artifact_digest,registry_digest:sha256(canonicalJson(registration))})
    writeFileSync(path.join(registry,`registration-${sha256(registration.evidence_id)}.json`),JSON.stringify(registration))
  }
  const record=runDeliveryPreflight({issue:9001,pr:9002,head_sha:HEAD,checks},{readEvidenceRegistration:(id)=>registrations.get(id)})
  const identity={policy_version:1,migrations:[],focused_files:[{path:'scripts/example.mjs',sha256:'d'.repeat(64)}],verification_files:[],claims:{writes:[],reads:[]},global_invalidators:[],migration_order_digest:sha256('[]'),work_type:'repo-maintenance'}
  const bundle={schema_version:1,bundle_id:sha256(canonicalJson(identity)),identity,metadata:{issue:9001,pr:9002,claim:null,base_main_sha:MAIN,integration_sha:HEAD,review:null,ci:null,delivery_preflight:{preflight_id:record.preflight_id,input_digest:record.input_digest}}}
  writeFileSync(path.join(dir,'record.json'),JSON.stringify(record))
  writeFileSync(path.join(dir,'bundle.json'),JSON.stringify(bundle))
  writeFileSync(path.join(dir,'changed.json'),'[]')
}

function run(dir, args) {
  const state = path.join(dir, 'state.json'), log = path.join(dir, 'log.txt')
  rmSync(log, { force: true })
  const reviewArgs=args.includes('--assign-reviewer')||args.includes('--replace-failed-reviewer')
    ? [...args,'--delivery-preflight-record',path.join(dir,'record.json'),'--evidence-bundle',path.join(dir,'bundle.json'),'--changed-files-file',path.join(dir,'changed.json')]
    : args
  const result = spawnSync(process.execPath, [cli, ...reviewArgs], {
    encoding: 'utf8', timeout: 180000,
    env: { ...process.env, WIRE_STATE: state, WIRE_LOG: log, NODE_OPTIONS: `--import ${fake}`, GH_TOKEN: 'wire-fixture-no-network', GIT_TERMINAL_PROMPT: '0', SHARED_DB_AUTHOR_ENGINE: 'claude', DELIVERY_EVIDENCE_REGISTRY_ROOT:path.join(dir,'registry') },
  })
  const rows = existsSync(log) ? readFileSync(log, 'utf8').trim().split('\n').filter(Boolean).map((line) => JSON.parse(line)) : []
  const api = rows.filter((row) => row.kind === 'rest' || row.kind === 'graphql')
  return { status: result.status, output: `${result.stdout}\n${result.stderr}`, api }
}

const common = ['--issue', '9001', '--pr', '9002', '--head-sha', HEAD]
const failure = [...common, '--failed-sequence', '1', '--failure-code', 'provider_unavailable', '--confirm-no-verdict', '--confirm-no-artifact']

test('#3187 reviewer assignment, release and replacement each stay within 10 API requests on the wire', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'reviewer-wire-'))
  try {
    seed(path.join(dir, 'state.json'))
    const steps = [
      ['slot 1 assignment', ['--assign-reviewer', ...common]],
      ['slot 2 assignment with a live slot 1 lease', ['--assign-reviewer', ...common, '--review-slot', '2']],
      ['failed reviewer release', ['--release-failed-reviewer', ...failure]],
      ['failed reviewer replacement', ['--replace-failed-reviewer', ...failure]],
    ]
    for (const [name, args] of steps) {
      const { status, output, api } = run(dir, args)
      assert.equal(status, 0, `${name} failed:\n${output.slice(-1500)}`)
      assert.ok(api.length <= LIMIT, `${name} used ${api.length} API requests:\n${api.map((row) => `${row.kind} ${row.label}`).join('\n')}`)
      assert.ok(!api.some((row) => /rate_limit/.test(row.label)), `${name} made an explicit quota request`)
    }
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
})

// Issue #3206 (Refs #2773): the idempotent retry of an assignment and both silent-reclaim
// routes are proved on the same wire. Commit dates and the probe's observed-at are moved
// back in the fake's model so the real age guards pass without weakening them.
function backdate(dir, probeObservedAt) {
  const file = path.join(dir, 'state.json'), state = JSON.parse(readFileSync(file, 'utf8'))
  for (const commit of Object.values(state.commits)) {
    commit.date = '2026-09-16T00:00:00Z'
    if (probeObservedAt && /silence-probe/.test(commit.message)) commit.message = commit.message.replace(/observed-at=\S+/, `observed-at=${probeObservedAt}`)
  }
  writeFileSync(file, JSON.stringify(state))
}

function within(name, { status, output, api }) {
  assert.equal(status, 0, `${name} failed:\n${output.slice(-1500)}`)
  assert.ok(api.length <= LIMIT, `${name} used ${api.length} API requests:\n${api.map((row) => `${row.kind} ${row.label}`).join('\n')}`)
  assert.ok(!api.some((row) => /rate_limit/.test(row.label)), `${name} made an explicit quota request`)
  return api.length
}

test('#3206 an idempotent assignment retry stays within 10 API requests on the wire', () => {
  const dir = mkdtempSync(path.join(tmpdir(), 'reviewer-wire-'))
  try {
    seed(path.join(dir, 'state.json'))
    within('first assignment', run(dir, ['--assign-reviewer', ...common]))
    within('idempotent assignment retry', run(dir, ['--assign-reviewer', ...common]))
  } finally {
    rmSync(dir, { recursive: true, force: true })
  }
})

for (const [name, extra, observedAt] of [
  ['unstarted silent reclaim', ['--unstarted'], null],
  ['silent reclaim after the confirmation window', [], '2026-09-16T01:00:00.000Z'],
]) {
  test(`#3206 ${name} stays within 10 API requests on the wire with no quota request`, () => {
    const dir = mkdtempSync(path.join(tmpdir(), 'reviewer-wire-'))
    try {
      seed(path.join(dir, 'state.json'))
      within('assignment', run(dir, ['--assign-reviewer', ...common]))
      backdate(dir, null)
      within('silence probe', run(dir, ['--probe-silent-reviewer', ...common, '--failed-sequence', '1', ...extra]))
      if (observedAt) backdate(dir, observedAt)
      const reclaim = run(dir, ['--reclaim-silent-reviewer', ...common, '--failed-sequence', '1', ...extra, '--confirm-no-verdict', '--confirm-no-artifact'])
      within(name, reclaim)
      assert.match(reclaim.output, /"releasedLeaseSha"/)
    } finally {
      rmSync(dir, { recursive: true, force: true })
    }
  })
}
