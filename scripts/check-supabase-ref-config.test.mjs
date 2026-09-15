// Offline tests for scripts/check-supabase-ref-config.mjs (issue #2429).
// Run: node --test scripts/check-supabase-ref-config.test.mjs
import test from 'node:test'
import assert from 'node:assert/strict'
import {extractRefEntries, buildInventory, classify, main} from './check-supabase-ref-config.mjs'

const PARENT = 'aaaaaaaaaaaaaaaaaaaa'
const LIVE_BRANCH = 'bbbbbbbbbbbbbbbbbbbb' // only visible through `branches list`
const DELETED = 'cccccccccccccccccccc' // the August-deleted ref still sitting in an overlay
const projects = [{ref: PARENT, name: 'prod', status: 'ACTIVE_HEALTHY'}]
const branchesFor = (ref) => (ref === PARENT ? [{project_ref: LIVE_BRANCH, name: 'shared-db-schema-rehearsal', status: 'FUNCTIONS_DEPLOYED'}] : [])

function run(argv, files, lists = {projects, branchesFor}) {
  const logs = []
  const code = main(argv, {
    readFile: (f) => files[f],
    env: {},
    log: (s) => logs.push(s),
    supabaseJson: (args) => (args[0] === 'projects' ? lists.projects : lists.branchesFor(args[3])),
  })
  return {code, out: logs.join('\n')}
}

test('extracts refs from KEY=VALUE, JSON and supabase URLs', () => {
  assert.deepEqual(extractRefEntries(`PREVIEW_PROJECT_REF=${LIVE_BRANCH}\n# X=${DELETED}\nNOTE=hello`, 'f').map((e) => e.ref), [LIVE_BRANCH])
  assert.deepEqual(extractRefEntries(JSON.stringify({preview: {url: `https://${DELETED}.supabase.co`}}), 'j'), [{source: 'j', key: 'preview.url', ref: DELETED}])
})

test('a live preview branch is LIVE even though projects list omits it (positive control)', () => {
  const r = run(['--config', 'o', '--control-ref', LIVE_BRANCH], {o: `PREVIEW_PROJECT_REF=${LIVE_BRANCH}`})
  assert.equal(r.code, 0, r.out)
  assert.match(r.out, /LIVE\s+bbbb/)
})

test('a stale ref FAILS and names its source and key instead of passing', () => {
  const r = run(['--config', 'overlay.env', '--control-ref', LIVE_BRANCH], {'overlay.env': `PREVIEW_PROJECT_REF=${DELETED}`})
  assert.equal(r.code, 1)
  assert.match(r.out, /FAIL UNKNOWN cccccccccccccccccccc {2}overlay\.env :: PREVIEW_PROJECT_REF/)
  assert.match(r.out, /authoritative values/)
})

test('stale ref recorded in a retired-ref key is RETIRED and still fails the active key', () => {
  const r = run(['--config', 'o', '--control-ref', LIVE_BRANCH], {o: `PREVIEW_PROJECT_REF=${DELETED}\nRETIRED_PREVIEW_REFS=${DELETED}`})
  assert.equal(r.code, 1)
  assert.match(r.out, /FAIL RETIRED cccc.* PREVIEW_PROJECT_REF/)
  assert.match(r.out, /ok {3}RETIRED cccc.* RETIRED_PREVIEW_REFS \(retired-ref key\)/)
})

test('projects-only inventory cannot call anything missing: control fails, verdicts downgrade, exit 2', () => {
  const r = run(['--config', 'o', '--control-ref', LIVE_BRANCH], {o: `PREVIEW_PROJECT_REF=${LIVE_BRANCH}`}, {projects, branchesFor: () => []})
  assert.equal(r.code, 2)
  assert.match(r.out, /UNKNOWN bbbb/)
  assert.match(r.out, /INVENTORY UNTRUSTED: control ref/)
})

test('a failed branch listing makes the inventory untrusted rather than declaring refs dead', () => {
  const inv = buildInventory(projects, () => { throw new Error('rate limited') })
  const report = classify([{source: 's', key: 'K', ref: LIVE_BRANCH}], inv)
  assert.equal(report.exitCode, 2)
  assert.equal(report.results[0].verdict, 'UNKNOWN')
})

test('the check can fail: swapping the live ref for the stale one flips exit 0 to 1', () => {
  const ok = run(['--config', 'o', '--control-ref', LIVE_BRANCH], {o: `K_REF=${LIVE_BRANCH}`})
  const bad = run(['--config', 'o', '--control-ref', LIVE_BRANCH], {o: `K_REF=${DELETED}`})
  assert.deepEqual([ok.code, bad.code], [0, 1])
})
