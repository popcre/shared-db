import test from 'node:test'
import assert from 'node:assert/strict'
import { evaluate, renderReading, parseLedger, renderLedger, READING_SQL, WRITER_READING_SQL, fetchReading, main } from './db-bloat-weekly.mjs'

const MB = 1048576
const tbl = (o) => ({ tbl: 'x.t', heap_bytes: 200 * MB, index_bytes: 50 * MB, est_rows: 1000, live_bytes: 150 * MB,
  n_tup_ins: 0, n_tup_upd: 0, n_tup_hot_upd: 0, n_tup_del: 0, top_writer: 'update x.t set a=1', ...o })
const rd = (at, tables, reset = null) => ({ read_at: at, stats_reset: reset, tables })

test('SQL is a single read-only SELECT', () => {
  assert.match(READING_SQL, /^with t as/)
  assert.doesNotMatch(READING_SQL, /\b(alter|drop|vacuum|truncate|create)\b/i)
})

test('heap/live over 2 on an update-churned table is flagged with its writer', () => {
  const [r] = evaluate(rd('2026-11-09T11:00:00Z', [tbl({ heap_bytes: 500 * MB, n_tup_upd: 10, n_tup_del: 1 })]), null)
  assert.equal(r.flags.length, 1)
  assert.match(renderReading(rd('2026-11-09T11:00:00Z', []), [r], null, { target: 'production', runUrl: 'u' }), /Likely writer: `update x.t/)
})

test('coldlion.change_log update-driven bloat is flagged', () => {
  const [r] = evaluate(rd('2026-11-09T11:00:00Z', [tbl({ tbl: 'coldlion.change_log', heap_bytes: 900 * MB, n_tup_upd: 50, n_tup_del: 0 })]), null)
  assert.equal(r.flags.length, 1)
  assert.deepEqual(r.notes, [])
})

test('delete-dominated space on any table is reclaimable, not flagged', () => {
  const prev = rd('2026-11-02T11:00:00Z', [tbl({ heap_bytes: 500 * MB, n_tup_upd: 100, n_tup_del: 0 })])
  const [r] = evaluate(rd('2026-11-09T11:00:00Z', [tbl({ heap_bytes: 500 * MB, n_tup_upd: 110, n_tup_del: 5000 })]), prev)
  assert.deepEqual(r.flags, [])
})

test('index/heap growth > 50% and low HOT with churn are flagged week-over-week', () => {
  const prev = rd('2026-11-02T11:00:00Z', [tbl({ index_bytes: 40 * MB, n_tup_upd: 0, n_tup_hot_upd: 0 })])
  const [r] = evaluate(rd('2026-11-09T11:00:00Z', [tbl({ index_bytes: 100 * MB, n_tup_upd: 7000, n_tup_hot_upd: 1000 })]), prev)
  assert.equal(r.flags.length, 2)
})

test('a stats reset between readings disables deltas', () => {
  const prev = rd('2026-11-02T11:00:00Z', [tbl({ n_tup_upd: 0 })], '2026-10-01T00:00:00Z')
  const [r] = evaluate(rd('2026-11-09T11:00:00Z', [tbl({ n_tup_upd: 7000, n_tup_hot_upd: 0 })], '2026-11-05T00:00:00Z'), prev)
  assert.equal(r.updPerRowDay, null)
  assert.deepEqual(r.flags, [])
})

test('ledger round-trips without writer text', () => {
  const reading = rd('2026-11-09T11:00:00Z', [tbl({})])
  const back = parseLedger(renderLedger(reading))
  assert.equal(back.tables[0].tbl, 'x.t')
  assert.equal(back.tables[0].top_writer, undefined)
  assert.equal(parseLedger('nothing'), null)
})

const response = (rows, ok = true) => ({ ok, status: ok ? 200 : 400, text: async () => JSON.stringify(rows) })

test('empty table reading is healthy', async () => {
  const reading = await fetchReading('test', 'token', { fetchImpl: async () => response([]) })
  assert.deepEqual(reading.tables, [])
  assert.ok(Number.isFinite(Date.parse(reading.read_at)))
  assert.deepEqual(evaluate(reading, null), [])
})

test('large heaps with no live estimate are flagged or explained by delete evidence', () => {
  for (const name of ['x.t', 'coldlion.change_log']) {
    const [unexplained, deleted] = evaluate(rd('2026-11-09T11:00:00Z', [
      tbl({ tbl: name, live_bytes: 0, est_rows: 0 }),
      tbl({ tbl: name, live_bytes: 0, est_rows: 0, n_tup_del: 100 }),
    ]), null)
    assert.equal(unexplained.flags.length, 1)
    assert.deepEqual(unexplained.notes, [])
    assert.deepEqual(deleted.flags, [])
    assert.match(deleted.notes[0], /reclaimable/)
  }
})

test('rotation requires delete evidence and weekly deltas override historical deletes', () => {
  const table = tbl({ tbl: 'coldlion.change_log', heap_bytes: 900 * MB, n_tup_del: 1000 })
  assert.match(evaluate(rd('2026-11-09T11:00:00Z', [table]), null)[0].notes[0], /deleted rows/)
  const prev = rd('2026-11-02T11:00:00Z', [table])
  const [r] = evaluate(rd('2026-11-09T11:00:00Z', [{ ...table, n_tup_upd: 50 }]), prev)
  assert.equal(r.flags.length, 1)
  assert.deepEqual(r.notes, [])
})

test('unavailable writer extension falls back to core stats', async () => {
  const queries = []
  const reading = await fetchReading('test', 'token', { fetchImpl: async (url, options) => {
    queries.push(JSON.parse(options.body).query)
    return queries.length === 1 ? response({ message: 'relation does not exist' }, false)
      : response([{ ...tbl({ top_writer: null }), read_at: '2026-11-09T11:00:00Z' }])
  } })
  assert.deepEqual(queries, [WRITER_READING_SQL, READING_SQL])
  assert.doesNotMatch(READING_SQL, /extensions.pg_stat_statements/)
  assert.equal(reading.tables.length, 1)
  assert.equal(reading.tables[0].top_writer, null)
})

test('failed core stats still reject the reading', async () => {
  await assert.rejects(fetchReading('test', 'token', { fetchImpl: async () => response('unavailable', false) }), /Management API returned 400/)
})

test('dry run reads baseline but never changes ledger or posts reading', async () => {
  const oldFetch = globalThis.fetch
  const oldArgv = process.argv
  const oldEnv = { ...process.env }
  const oldLog = console.log
  const calls = []
  try {
    process.argv = ['node', 'script', '--post=false']
    process.env.GH_TOKEN = 'test'
    process.env.SUPABASE_ACCESS_TOKEN = 'test'
    console.log = () => {}
    globalThis.fetch = async (url, options = {}) => {
      calls.push({ url, method: options.method ?? 'GET' })
      if (url.startsWith('https://api.supabase.com/')) return response([])
      assert.equal(options.method ?? 'GET', 'GET')
      return { ok: true, json: async () => [{ id: 1, body: renderLedger(rd('2026-11-02T11:00:00Z', [])) }] }
    }
    assert.equal(await main(), 0)
    assert.equal(calls.length, 2)
    assert.ok(calls[1].url.includes('/comments?'))
  } finally {
    globalThis.fetch = oldFetch
    process.argv = oldArgv
    process.env = oldEnv
    console.log = oldLog
  }
})
