// Shared conditional reads for polling callers (issue #2773).
//
// WHY THIS EXISTS
// ---------------
// Every session that waited on GitHub polled on its own timer and paid a full
// primary-quota request per poll, even when nothing had changed. Ten sessions
// watching the same head made ten identical reads every interval against one
// shared 5,000-request hourly bucket.
//
// Three rules remove that waste without making any wait longer:
//
//   1. CONDITIONAL. Every poll sends the stored ETag. GitHub answers an
//      unchanged resource with HTTP 304, which does NOT count against the
//      primary quota (verified live on 2026-09-17: x-ratelimit-used stayed
//      flat across three consecutive 304s while each 200 raised it by one).
//      The cached body is returned byte-for-byte.
//   2. SINGLE-FLIGHT, HOST-WIDE. Identical reads from any process on this
//      machine within one snapshot generation share ONE upstream request. The
//      first caller takes an exclusive lock file; every other caller waits
//      locally (no network) for the result that caller writes.
//   3. BROADCAST. A read that observes a change bumps the resource generation.
//      Waiters block on the local state file, so one observed change wakes
//      every waiter once; a missed wake falls back to the caller's normal
//      interval, never to a busy loop.
//
// The poll interval is never lengthened while a resource is healthy: an
// unchanged poll is free, so waiting longer would only make work slower. The
// exponential 30/60/120/300-second schedule with jitter applies to consecutive
// FAILED polls only, and GitHub's own x-poll-interval is honoured as a floor.
// Quota exhaustion is handled by the host-wide latch in github-transport.mjs,
// which stops every caller until the reset.
//
// Nothing here judges a response. A cached body is exactly the bytes GitHub
// last returned for that ETag, and every caller still validates it as before.
// A failed read is never shared: each caller fails on its own bounded path.

import { execFileSync } from 'node:child_process'
import { createHash } from 'node:crypto'
import { closeSync, mkdirSync, openSync, readdirSync, readFileSync, renameSync, rmSync, statSync, writeFileSync } from 'node:fs'
import { tmpdir } from 'node:os'
import path from 'node:path'
import { hostQuotaLatch, runGitHubCommand } from './github-transport.mjs'

const sleepSync = (ms) => Atomics.wait(new Int32Array(new SharedArrayBuffer(4)), 0, 0, ms)

export const FAILURE_BACKOFF_SECONDS = [30, 60, 120, 300]

/** Delay before the next poll after `failures` consecutive failed polls. */
export function pollDelayMs({ baseMs, failures = 0, pollIntervalHeaderMs = 0, random = Math.random }) {
  let delay = Math.max(Number(baseMs) || 0, Number(pollIntervalHeaderMs) || 0)
  if (failures > 0) {
    const step = FAILURE_BACKOFF_SECONDS[Math.min(failures, FAILURE_BACKOFF_SECONDS.length) - 1] * 1000
    delay = Math.max(delay, step) + Math.floor(random() * step * 0.2)
  }
  return delay
}

/** Split a `gh api -i` response into status, lower-cased headers, and body. */
export function parseHttpResponse(raw) {
  const text = String(raw ?? '').replace(/\r\n/g, '\n')
  const boundary = text.indexOf('\n\n')
  const head = boundary < 0 ? text : text.slice(0, boundary)
  const body = boundary < 0 ? '' : text.slice(boundary + 2)
  const lines = head.split('\n')
  const status = Number(/^HTTP\/\S+\s+(\d{3})/.exec(lines[0] ?? '')?.[1])
  const headers = new Map()
  for (const line of lines.slice(1)) {
    const at = line.indexOf(':')
    if (at > 0) headers.set(line.slice(0, at).trim().toLowerCase(), line.slice(at + 1).trim())
  }
  return { status: Number.isFinite(status) ? status : null, headers, body }
}

export function defaultSharedDir(env = process.env) {
  return env.GITHUB_SHARED_READ_DIR || path.join(tmpdir(), 'shared-db-github-reads')
}

export function sharedReadKey(endpoint, env = process.env) {
  const identity = String(env.GH_TOKEN || env.GITHUB_TOKEN || 'gh-cli-login')
  return createHash('sha256').update(`${identity}\n${endpoint}`).digest('hex').slice(0, 32)
}

function readJsonFile(file) {
  try { return JSON.parse(readFileSync(file, 'utf8')) } catch { return null }
}

function writeJsonAtomic(file, value) {
  const staging = `${file}.${process.pid}.${Date.now()}.${Math.random().toString(16).slice(2)}.tmp`
  writeFileSync(staging, JSON.stringify(value))
  renameSync(staging, file)
}

/**
 * Run `read` at most once per (key, generation) across every process on the
 * host. Callers that lose the race wait locally for the winner's result. A lock
 * older than `staleLockMs` (a crashed holder) is taken over.
 */
export function singleFlight({ dir, key, generation, read, wait = sleepSync, now = Date.now, staleLockMs = 60000, maxWaitMs = 120000 }) {
  mkdirSync(dir, { recursive: true })
  const resultFile = path.join(dir, `${key}.flight-${generation}.json`)
  const lockFile = path.join(dir, `${key}.flight-${generation}.lock`)
  const started = now()
  for (;;) {
    const done = readJsonFile(resultFile)
    if (done) return { value: done.value, shared: true }
    let fd
    try {
      fd = openSync(lockFile, 'wx')
    } catch (error) {
      if (error?.code !== 'EEXIST' && error?.code !== 'EPERM') throw error
      let age
      try { age = now() - statSync(lockFile).mtimeMs } catch { continue }
      if (age > staleLockMs) { rmSync(lockFile, { force: true }); continue }
      if (now() - started > maxWaitMs) throw new Error(`shared GitHub read did not finish within ${maxWaitMs}ms (lock ${lockFile})`)
      wait(25)
      continue
    }
    closeSync(fd)
    try {
      const again = readJsonFile(resultFile)
      if (again) return { value: again.value, shared: true }
      const value = read()
      writeJsonAtomic(resultFile, { value })
      pruneOldFlights(dir, key, generation)
      return { value, shared: false }
    } finally {
      rmSync(lockFile, { force: true })
    }
  }
}

// Finished generations older than the previous one can never be joined again.
function pruneOldFlights(dir, key, generation) {
  try {
    for (const name of readdirSync(dir)) {
      const match = /^(.+)\.flight-(\d+)\.json$/.exec(name)
      if (match && match[1] === key && Number(match[2]) < generation - 1) rmSync(path.join(dir, name), { force: true })
    }
  } catch { /* housekeeping only */ }
}

// `gh api -i` exits non-zero on 304 but prints the response on stdout. The
// transport wraps errors and drops stdout, so the 304 is turned back into a
// normal result at the executor, before the transport's classifier sees it.
function acceptNotModified(executor) {
  return (bin, args, options) => {
    try {
      return executor(bin, args, options)
    } catch (error) {
      const stdout = String(error?.stdout ?? '')
      if (/^HTTP\/\S+\s+304\b/.test(stdout)) return stdout
      throw error
    }
  }
}

/**
 * One conditional GET of a single REST page, shared host-wide.
 * Returns { body, changed, status, pollIntervalMs, generation, link, requested }.
 * `requested` is false when this caller joined another caller's read.
 */
export function sharedConditionalGet(endpoint, {
  env = process.env,
  dir = defaultSharedDir(env),
  executor = execFileSync,
  now = Date.now,
  wait = sleepSync,
  windowMs = 5000,
} = {}) {
  mkdirSync(dir, { recursive: true })
  const key = sharedReadKey(endpoint, env)
  const stateFile = path.join(dir, `${key}.state.json`)
  const generation = Math.floor(now() / windowMs)
  const flight = singleFlight({
    dir, key, generation, wait, now,
    read: () => {
      const state = readJsonFile(stateFile)
      const args = ['api', '-i']
      if (state?.etag && typeof state.body === 'string') args.push('-H', `If-None-Match: ${state.etag}`)
      args.push(endpoint)
      const response = parseHttpResponse(runGitHubCommand(args, { executor: acceptNotModified(executor), quotaLatch: executor === execFileSync ? hostQuotaLatch(env) : null }))
      const header = response.headers.get('x-poll-interval') ?? ''
      const pollIntervalMs = /^\d+$/.test(header) ? Number(header) * 1000 : 0
      if (response.status === 304) {
        if (!state || typeof state.body !== 'string') throw new Error(`GitHub answered 304 for ${endpoint} but no cached body exists; refusing to invent one`)
        return { body: state.body, changed: false, status: 304, pollIntervalMs, generation: Number(state.generation ?? 0), link: state.link ?? null }
      }
      if (response.status !== 200) throw new Error(`GitHub answered HTTP ${response.status} for ${endpoint}`)
      const next = { etag: response.headers.get('etag') ?? null, body: response.body, generation: Number(state?.generation ?? 0) + 1, link: response.headers.get('link') ?? null }
      writeJsonAtomic(stateFile, next)
      return { body: next.body, changed: true, status: 200, pollIntervalMs, generation: next.generation, link: next.link }
    },
  })
  return { ...flight.value, requested: !flight.shared }
}

/** Next-page URL from a Link header, or null. */
export function nextPageEndpoint(link) {
  const match = /<https:\/\/api\.github\.com\/([^>]+)>;\s*rel="next"/.exec(String(link ?? ''))
  return match ? match[1] : null
}

/**
 * Block until the shared generation for `endpoint` moves past `seenGeneration`
 * or `timeoutMs` passes. Reads only a local file; makes no request.
 */
export function waitForGeneration(endpoint, seenGeneration, { env = process.env, dir = defaultSharedDir(env), timeoutMs, now = Date.now, wait = sleepSync, checkEveryMs = 1000 } = {}) {
  const stateFile = path.join(dir, `${sharedReadKey(endpoint, env)}.state.json`)
  const deadline = now() + Math.max(0, Number(timeoutMs) || 0)
  for (;;) {
    const generation = Number(readJsonFile(stateFile)?.generation ?? 0)
    if (generation > Number(seenGeneration ?? 0)) return { woken: true, generation }
    const left = deadline - now()
    if (left <= 0) return { woken: false, generation }
    wait(Math.min(checkEveryMs, left))
  }
}
