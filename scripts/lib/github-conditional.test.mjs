// Issue #2773: request-count fixtures for shared conditional reads, the
// host-wide single-flight snapshot, the change broadcast, and the host-wide
// rate-limit latch. Every count here is a count of executor invocations, i.e.
// real `gh` wire requests.
import test from 'node:test'
import assert from 'node:assert/strict'
import { spawn } from 'node:child_process'
import { mkdtempSync, readdirSync, readFileSync, rmSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import path from 'node:path'
import { fileURLToPath, pathToFileURL } from 'node:url'
import {
  FAILURE_BACKOFF_SECONDS, nextPageEndpoint, parseHttpResponse, pollDelayMs, sharedConditionalGet, singleFlight, waitForGeneration,
} from './github-conditional.mjs'
import { hostQuotaLatch, runGitHubCommand } from './github-transport.mjs'
import { fetchCheckRuns } from '../orchestrator-flow/runner-lanes.mjs'

const here = path.dirname(fileURLToPath(import.meta.url))
const scratch = () => mkdtempSync(path.join(tmpdir(), 'gh-2773-'))
const env = { GH_TOKEN: 'fixture-token' }

function fakeGitHub({ etag = 'W/"v1"', body = '{"n":1}', pollInterval } = {}) {
  const state = { etag, body, calls: [], counted: 0 }
  state.executor = (_bin, args) => {
    state.calls.push(args)
    const at = args.indexOf('-H')
    const sent = at >= 0 ? String(args[at + 1]).replace(/^If-None-Match:\s*/, '') : null
    const extra = pollInterval ? `X-Poll-Interval: ${pollInterval}\n` : ''
    if (sent && sent === state.etag) {
      const error = new Error('gh: HTTP 304')
      error.stdout = `HTTP/2.0 304 Not Modified\nEtag: ${state.etag}\n${extra}\n`
      throw error
    }
    state.counted += 1 // only a 200 is billed to the primary quota
    return `HTTP/2.0 200 OK\nEtag: ${state.etag}\n${extra}\n${state.body}`
  }
  return state
}

test('parseHttpResponse reads status, headers and body', () => {
  const r = parseHttpResponse('HTTP/2.0 200 OK\r\nEtag: W/"x"\r\nX-Poll-Interval: 60\r\n\r\n{"a":1}')
  assert.equal(r.status, 200); assert.equal(r.headers.get('etag'), 'W/"x"'); assert.equal(r.headers.get('x-poll-interval'), '60'); assert.equal(r.body, '{"a":1}')
})

test('unchanged polling consumes no primary quota: every repeat poll is a 304', () => {
  const dir = scratch(); const gh = fakeGitHub(); let clock = 0
  const read = () => sharedConditionalGet('repos/o/r/commits/abc/check-runs', { env, dir, executor: gh.executor, now: () => clock })
  const first = read()
  assert.equal(first.changed, true); assert.equal(first.body, '{"n":1}')
  for (let i = 1; i <= 20; i += 1) {
    clock += 30000
    const again = read()
    assert.equal(again.changed, false); assert.equal(again.status, 304); assert.equal(again.body, '{"n":1}')
  }
  assert.equal(gh.calls.length, 21, 'each poll generation makes exactly one conditional request')
  assert.equal(gh.counted, 1, 'twenty unchanged polls cost zero primary-quota requests')
  gh.etag = 'W/"v2"'; gh.body = '{"n":2}'; clock += 30000
  const changed = read()
  assert.equal(changed.changed, true); assert.equal(changed.body, '{"n":2}'); assert.equal(changed.generation, 2)
  assert.equal(gh.counted, 2)
  rmSync(dir, { recursive: true, force: true })
})

test('x-poll-interval is surfaced and is a floor, never a ceiling', () => {
  const dir = scratch(); const gh = fakeGitHub({ pollInterval: 60 })
  const r = sharedConditionalGet('repos/o/r/events', { env, dir, executor: gh.executor, now: () => 0 })
  assert.equal(r.pollIntervalMs, 60000)
  assert.equal(pollDelayMs({ baseMs: 20000, pollIntervalHeaderMs: r.pollIntervalMs }), 60000)
  assert.equal(pollDelayMs({ baseMs: 90000, pollIntervalHeaderMs: r.pollIntervalMs }), 90000)
  rmSync(dir, { recursive: true, force: true })
})

test('healthy polls keep their interval; failures back off 30/60/120/300s with bounded jitter', () => {
  assert.deepEqual(FAILURE_BACKOFF_SECONDS, [30, 60, 120, 300])
  assert.equal(pollDelayMs({ baseMs: 20000, failures: 0, random: () => 0.99 }), 20000, 'no backoff while healthy: work must not wait longer')
  const low = [1, 2, 3, 4, 9].map((failures) => pollDelayMs({ baseMs: 20000, failures, random: () => 0 }))
  assert.deepEqual(low, [30000, 60000, 120000, 300000, 300000])
  const high = pollDelayMs({ baseMs: 20000, failures: 4, random: () => 0.999 })
  assert.ok(high > 300000 && high < 360000, `jitter stays within 20%: ${high}`)
})

test('ten simultaneous identical readers in separate processes make one upstream read per generation', async () => {
  const dir = scratch(); const counter = path.join(dir, 'upstream-count.txt'); writeFileSync(counter, '')
  const lib = pathToFileURL(path.join(here, 'github-conditional.mjs')).href
  const script = `
    import { singleFlight } from ${JSON.stringify(lib)}
    import { appendFileSync } from 'node:fs'
    const [dir, counter, startAt] = process.argv.slice(1)
    while (Date.now() < Number(startAt)) {}
    const r = singleFlight({ dir, key: 'k', generation: 7, read: () => {
      appendFileSync(counter, 'x')
      Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, 400)
      return { snapshot: 'one' }
    } })
    process.stdout.write(JSON.stringify(r.value))`
  const startAt = Date.now() + 1500
  const runs = Array.from({ length: 10 }, () => new Promise((resolve, reject) => {
    const child = spawn(process.execPath, ['--input-type=module', '-e', script, dir, counter, String(startAt)], { stdio: ['ignore', 'pipe', 'pipe'] })
    let out = ''; let err = ''
    child.stdout.on('data', (d) => { out += d }); child.stderr.on('data', (d) => { err += d })
    child.on('close', (code) => (code === 0 ? resolve(out) : reject(new Error(err))))
  }))
  const outputs = await Promise.all(runs)
  assert.equal(readFileSync(counter, 'utf8').length, 1, 'exactly one upstream read for ten concurrent readers')
  for (const out of outputs) assert.deepEqual(JSON.parse(out), { snapshot: 'one' })
  rmSync(dir, { recursive: true, force: true })
})

test('a new generation makes a fresh read; a failed read is never served to other callers', () => {
  const dir = scratch(); let reads = 0
  assert.throws(() => singleFlight({ dir, key: 'k', generation: 1, read: () => { reads += 1; throw new Error('HTTP 502') } }), /502/)
  assert.deepEqual(singleFlight({ dir, key: 'k', generation: 1, read: () => { reads += 1; return 'ok' } }), { value: 'ok', shared: false })
  assert.deepEqual(singleFlight({ dir, key: 'k', generation: 1, read: () => { reads += 1; return 'other' } }), { value: 'ok', shared: true })
  assert.deepEqual(singleFlight({ dir, key: 'k', generation: 2, read: () => { reads += 1; return 'next' } }), { value: 'next', shared: false })
  assert.equal(reads, 3)
  rmSync(dir, { recursive: true, force: true })
})

test('a crashed lock holder is taken over instead of wedging every reader', () => {
  const dir = scratch(); let clock = Date.now()
  writeFileSync(path.join(dir, 'k.flight-3.lock'), '')
  const r = singleFlight({ dir, key: 'k', generation: 3, now: () => (clock += 30000), wait: () => {}, staleLockMs: 60000, read: () => 'recovered' })
  assert.equal(r.value, 'recovered')
  rmSync(dir, { recursive: true, force: true })
})

test('one observed change wakes every waiter exactly once; a missed wake times out without a busy loop', () => {
  const dir = scratch(); const gh = fakeGitHub(); const endpoint = 'repos/o/r/commits/abc/check-runs'
  sharedConditionalGet(endpoint, { env, dir, executor: gh.executor, now: () => 0 })
  let clock = 0; const sleeps = []
  const idle = waitForGeneration(endpoint, 1, { env, dir, timeoutMs: 30000, now: () => clock, wait: (ms) => { sleeps.push(ms); clock += ms } })
  assert.equal(idle.woken, false); assert.equal(sleeps.length, 30, 'one local file check per second, never a spin'); assert.equal(gh.calls.length, 1, 'waiting makes no request')
  gh.etag = 'W/"v2"'
  sharedConditionalGet(endpoint, { env, dir, executor: gh.executor, now: () => 60000 })
  const woken = Array.from({ length: 10 }, () => waitForGeneration(endpoint, 1, { env, dir, timeoutMs: 30000, wait: () => { throw new Error('must not sleep once changed') } }))
  assert.ok(woken.every((w) => w.woken && w.generation === 2))
  assert.equal(gh.calls.length, 2, 'ten woken waiters were told by one read')
  rmSync(dir, { recursive: true, force: true })
})

test('conditional check-run pages follow Link and are validated exactly as before', () => {
  const h = 'a'.repeat(40); const served = []
  const pages = {
    [`repos/o/r/commits/${h}/check-runs?per_page=100&filter=all`]: { body: JSON.stringify({ total_count: 2, check_runs: [{ id: 1, name: 'a', status: 'completed', conclusion: 'success' }] }), link: `<https://api.github.com/repositories/9/commits/${h}/check-runs?per_page=100&filter=all&page=2>; rel="next"` },
    [`repositories/9/commits/${h}/check-runs?per_page=100&filter=all&page=2`]: { body: JSON.stringify({ total_count: 2, check_runs: [{ id: 2, name: 'b', status: 'in_progress', conclusion: null }] }), link: null },
  }
  const rows = fetchCheckRuns('o/r', h, { readPage: (endpoint) => { served.push(endpoint); return pages[endpoint] } })
  assert.deepEqual(rows.map((r) => r.name), ['a', 'b']); assert.equal(served.length, 2)
  assert.equal(nextPageEndpoint(null), null)
  assert.throws(() => fetchCheckRuns('o/r', h, { readPage: () => ({ body: JSON.stringify({ total_count: 3, check_runs: [] }), link: null }) }), /incomplete/)
})

test('rate-limit exhaustion seen by one caller stops every other caller until reset, with no wire request', () => {
  const dir = scratch(); const latchEnv = { GH_TOKEN: 'fixture-token', GITHUB_QUOTA_LATCH_DIR: dir }
  let clock = 1_000_000; const now = () => clock; const resetSeconds = Math.floor((clock + 600000) / 1000)
  const exhaustedExecutor = (_bin, args) => {
    if (args[1] === '-i' && args[2] === 'rate_limit') return `HTTP/2.0 200 OK\n\n${JSON.stringify({ resources: { core: { remaining: 0, reset: resetSeconds }, graphql: { remaining: 10, reset: resetSeconds } } })}`
    const error = new Error('HTTP 403: API rate limit exceeded'); error.stderr = 'gh: API rate limit exceeded for user (HTTP 403)'; throw error
  }
  let first = 0
  assert.throws(() => runGitHubCommand(['api', 'repos/o/r/pulls/1'], { executor: (b, a, o) => { first += 1; return exhaustedExecutor(b, a, o) }, quotaLatch: hostQuotaLatch(latchEnv), maxRateLimitWaitMs: 1000, wait: () => {}, reportStderr: () => {}, now }), /rate limit exceeded/i)
  assert.equal(first, 2, 'the discovering caller spends its failing request plus the free rate_limit probe')
  // Every other caller -- other sessions, reads and writes alike -- is stopped locally.
  for (const args of [['api', 'repos/o/r/pulls/2'], ['api', '-X', 'POST', 'repos/o/r/git/refs', '-f', 'ref=x'], ['pr', 'view', '1']]) {
    let wire = 0
    const bucketArgs = args[0] === 'pr' ? ['api', 'repos/o/r'] : args
    assert.throws(() => runGitHubCommand(bucketArgs, { executor: () => { wire += 1; return '{}' }, quotaLatch: hostQuotaLatch(latchEnv), reportStderr: () => {}, now }), (e) => e.rateLimitExhausted && e.quotaLatched)
    assert.equal(wire, 0, `latched caller made a wire request: ${args.join(' ')}`)
  }
  // The graphql bucket is separate and is not stopped by a core exhaustion.
  let graph = 0
  runGitHubCommand(['api', 'graphql', '-f', 'query=x'], { executor: () => { graph += 1; return '{}' }, quotaLatch: hostQuotaLatch(latchEnv), now })
  assert.equal(graph, 1)
  // An opted-in reader waits for the reset instead of refusing.
  let waited = 0; let after = 0
  assert.equal(runGitHubCommand(['api', 'repos/o/r/pulls/3'], { executor: () => { after += 1; return 'ok' }, quotaLatch: hostQuotaLatch(latchEnv), maxRateLimitWaitMs: 900000, wait: (ms) => { waited = ms; clock += ms }, reportStderr: () => {}, now }), 'ok')
  assert.ok(waited >= 600000); assert.equal(after, 1)
  // After the reset every caller proceeds.
  let resumed = 0
  runGitHubCommand(['api', 'repos/o/r/pulls/4'], { executor: () => { resumed += 1; return '{}' }, quotaLatch: hostQuotaLatch(latchEnv), now })
  assert.equal(resumed, 1)
  rmSync(dir, { recursive: true, force: true })
})

test('a fail-fast caller that cannot probe still brakes others for a bounded window; a corrupt latch is ignored', () => {
  const dir = scratch(); const latchEnv = { GH_TOKEN: 't2', GITHUB_QUOTA_LATCH_DIR: dir }; let clock = 5_000_000; const now = () => clock
  assert.throws(() => runGitHubCommand(['api', 'x'], { attempts: 1, executor: () => { const e = new Error('HTTP 429'); e.stderr = 'API rate limit exceeded (HTTP 429)'; throw e }, quotaLatch: hostQuotaLatch(latchEnv), reportStderr: () => {}, now }))
  let wire = 0
  assert.throws(() => runGitHubCommand(['api', 'y'], { executor: () => { wire += 1; return '{}' }, quotaLatch: hostQuotaLatch(latchEnv), now }), (e) => e.quotaLatched)
  clock += 61000
  runGitHubCommand(['api', 'y'], { executor: () => { wire += 1; return '{}' }, quotaLatch: hostQuotaLatch(latchEnv), now })
  assert.equal(wire, 1)
  const latch = hostQuotaLatch(latchEnv); latch.write(['api', 'z'], clock + 1e9)
  const file = readdirLatch(dir); writeFileSync(file, 'not json')
  runGitHubCommand(['api', 'z'], { executor: () => { wire += 1; return '{}' }, quotaLatch: hostQuotaLatch(latchEnv), now })
  assert.equal(wire, 2)
  assert.equal(hostQuotaLatch({ GITHUB_QUOTA_LATCH: 'off' }), null)
  rmSync(dir, { recursive: true, force: true })
})

function readdirLatch(dir) {
  return path.join(dir, readdirSync(dir).find((n) => n.endsWith('-core.json')))
}
