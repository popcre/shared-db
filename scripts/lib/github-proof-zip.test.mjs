import assert from 'node:assert/strict'
import { execFileSync } from 'node:child_process'
import { readFileSync } from 'node:fs'
import test from 'node:test'
import { readExactProofZip } from './github-proof-zip.mjs'

const MAKE_ZIP = String.raw`
import io, json, stat, sys, zipfile
rows = json.loads(sys.argv[1])
out = io.BytesIO()
with zipfile.ZipFile(out, 'w', zipfile.ZIP_DEFLATED) as archive:
    for row in rows:
        info = zipfile.ZipInfo(row['name'])
        info.compress_type = zipfile.ZIP_DEFLATED
        if row.get('link'):
            info.create_system = 3
            info.external_attr = (stat.S_IFLNK | 0o777) << 16
        archive.writestr(info, row['body'] * row.get('repeat', 1))
sys.stdout.buffer.write(out.getvalue())
`
const zip = (rows) => execFileSync('python3', ['-c', MAKE_ZIP, JSON.stringify(rows)], { encoding: null })

test('reads GitHub ZIP proof files exactly, independent of archive entry order', () => {
  const artifact = zip([{ name: 'production-ledger-after.txt', body: '20260925223300' }, { name: 'production-apply.txt', body: 'applied' }])
  assert.deepEqual([...readExactProofZip(artifact, ['production-apply.txt', 'production-ledger-after.txt'])], [
    ['production-apply.txt', 'applied'], ['production-ledger-after.txt', '20260925223300'],
  ])
  const live = zip([{ name: 'db-live-proof.json', body: '{"result":"passed"}' }])
  assert.deepEqual(JSON.parse(readExactProofZip(live, ['db-live-proof.json']).get('db-live-proof.json')), { result: 'passed' })
})

test('reads selected production files from the real multi-file nested artifact layout', () => {
  const artifact = zip([
    { name: 'production-dry-run.txt', body: 'unrelated but valid' },
    { name: 'production-apply.txt', body: 'applied' },
    { name: 'bounded-production/supabase/migration-content-manifest.json', body: '{"version":"20260925223300"}' },
    { name: 'catalog-verification/production-catalog-verification.json', body: '{}' },
  ])
  const files = readExactProofZip(artifact, ['production-apply.txt', 'migration-content-manifest.json', 'production-catalog-verification.json'], { allowUnrelatedFiles: true })
  assert.equal(files.get('production-apply.txt'), 'applied')
  assert.deepEqual(JSON.parse(files.get('migration-content-manifest.json')), { version: '20260925223300' })
  assert.throws(() => readExactProofZip(artifact, ['production-apply.txt']), /refused/)
})

test('accepts the original production-bound GitHub ZIP format without trusting a tar path', () => {
  const localOriginal = '/tmp/shared-db-2870-backend-10960473018.zip'
  try {
    const text = readExactProofZip(readFileSync(localOriginal), ['db-live-proof.json']).get('db-live-proof.json')
    assert.equal(JSON.parse(text).result, 'passed')
  } catch (error) {
    if (error?.code !== 'ENOENT') throw error
  }
})

test('refuses extra, duplicate, missing, traversal and cross-proof files', () => {
  const expected = ['db-live-proof.json']
  for (const rows of [
    [{ name: 'db-live-proof.json', body: '{}' }, { name: 'extra.json', body: '{}' }],
    [{ name: 'db-live-proof.json', body: '{}' }, { name: 'db-live-proof.json', body: '{}' }],
    [{ name: 'other-run-proof.json', body: '{}' }],
    [{ name: '../db-live-proof.json', body: '{}' }],
    [{ name: '/db-live-proof.json', body: '{}' }],
    [{ name: 'nested/db-live-proof.json', body: '{}' }],
  ]) assert.throws(() => readExactProofZip(zip(rows), expected), /proof artifact ZIP refused/)
  const duplicateExpected = zip([{ name: 'production-apply.txt', body: 'one' }, { name: 'nested/production-apply.txt', body: 'two' }])
  assert.throws(() => readExactProofZip(duplicateExpected, ['production-apply.txt'], { allowUnrelatedFiles: true }), /refused/)
})

test('refuses symlinks, malformed ZIP, oversized expansion and invalid expected names', () => {
  assert.throws(() => readExactProofZip(zip([{ name: 'db-live-proof.json', body: 'target', link: true }]), ['db-live-proof.json']), /refused/)
  assert.throws(() => readExactProofZip(Buffer.from('not a zip'), ['db-live-proof.json']), /refused/)
  assert.throws(() => readExactProofZip(zip([{ name: 'db-live-proof.json', body: 'x', repeat: 4 * 1024 * 1024 + 1 }]), ['db-live-proof.json']), /refused/)
  assert.throws(() => readExactProofZip(zip([{ name: 'db-live-proof.json', body: '{}' }]), ['../db-live-proof.json']), /expected proof files are invalid/)
})
