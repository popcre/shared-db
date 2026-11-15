import { test } from 'node:test'
import assert from 'node:assert/strict'
import fs from 'node:fs'
import os from 'node:os'
import path from 'node:path'

const writer = new URL('./write-production-ledger.mjs', import.meta.url)

async function runWriter(t, fetchImpl) {
  const directory = fs.mkdtempSync(path.join(os.tmpdir(), 'production-ledger-test-'))
  const output = path.join(directory, 'ledger.json')
  const originalArgv = process.argv
  const originalToken = process.env.SUPABASE_ACCESS_TOKEN
  t.after(() => {
    process.argv = originalArgv
    if (originalToken === undefined) delete process.env.SUPABASE_ACCESS_TOKEN
    else process.env.SUPABASE_ACCESS_TOKEN = originalToken
    fs.rmSync(directory, { recursive: true, force: true })
  })
  process.argv = [process.execPath, writer.pathname, output]
  process.env.SUPABASE_ACCESS_TOKEN = 'offline-test-token'
  t.mock.method(globalThis, 'fetch', fetchImpl)
  const messages = []
  t.mock.method(console, 'log', (message) => messages.push(message))
  // Each case executes the real CLI body with a fresh module instance.
  await import(`${writer.href}?case=${encodeURIComponent(directory)}`)
  return { output, stdout: messages.join('\n') }
}

test('writes the versions returned by the production ledger', async (t) => {
  const { output, stdout } = await runWriter(t, async () => ({
    ok: true,
    text: async () => JSON.stringify([
      { version: '20260101000000' }, { version: '20260102000000' },
    ]),
  }))
  assert.deepEqual(JSON.parse(fs.readFileSync(output, 'utf8')), ['20260101000000', '20260102000000'])
  assert.match(stdout, /production ledger: 2 applied versions/)
})

test('read failure warns and finishes without writing a file', async (t) => {
  const { output, stdout } = await runWriter(t, async () => { throw new Error('offline read failure') })
  assert.equal(fs.existsSync(output), false)
  assert.match(stdout, /::warning::production ledger unreadable/)
  assert.match(stdout, /offline read failure.*selector uses run evidence only/)
})

test('an empty ledger warns and finishes without writing a file', async (t) => {
  const { output, stdout } = await runWriter(t, async () => ({ ok: true, text: async () => '[]' }))
  assert.equal(fs.existsSync(output), false)
  assert.match(stdout, /::warning::production ledger unreadable \(empty ledger\)/)
})
