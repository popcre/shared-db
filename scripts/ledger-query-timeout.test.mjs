import test from 'node:test'
import assert from 'node:assert/strict'
import childProcess from 'node:child_process'
import { syncBuiltinESMExports } from 'node:module'
import { githubIo } from './manage-migration-author-lanes.mjs'

test('ledger query bounds its child and distinguishes timeouts, failing closed', (t) => {
  let failure = Object.assign(new Error('spawn timed out'), { code: 'ETIMEDOUT' })
  t.mock.method(childProcess, 'execFileSync', (_command, _args, options) => {
    assert.equal(options.timeout, 60000)
    assert.equal(options.killSignal, 'SIGKILL')
    if (failure) throw failure
    return '{"preview":["20260101000000"],"production":["20260101000000"]}'
  })
  syncBuiltinESMExports()
  try {
    assert.throws(() => githubIo.runLedgerQuery(''), /timed out after 60000 ms \(fail closed\)/)
    failure = Object.assign(new Error('child failed'), { stderr: 'ledger unavailable' })
    assert.throws(() => githubIo.runLedgerQuery(''), /ledger read failed: ledger unavailable/)
    failure = null
    assert.deepEqual(githubIo.appliedMigrationVersions(), {
      preview: new Set(['20260101000000']), production: new Set(['20260101000000']),
    })
  } finally {
    t.mock.restoreAll()
    syncBuiltinESMExports()
  }
})
