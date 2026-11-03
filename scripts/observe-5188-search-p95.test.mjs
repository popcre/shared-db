import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync, mkdtempSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { runInNewContext } from 'node:vm';
import { createRequire } from 'node:module';

const source = readFileSync(new URL('./observe-5188-search-p95.sh', import.meta.url), 'utf8');
const writer = source.match(/\nnode -e '\n([\s\S]*?)\n' "\$OUT_DIR"/)[1];

for (const [p95, expected] of [[299.99, 'passed'], [300, 'observed-over-budget'], [695, 'observed-over-budget']]) {
  test(`artifact records scoped p95 ${p95} against the 300 ms budget`, () => {
    const directory = mkdtempSync(join(tmpdir(), 'observe-5188-test-'));
    try {
      runInNewContext(writer, { require: createRequire(import.meta.url), console: { log() {} },
        process: { argv: ['node', directory, '5188', '2026-11-02T18:00:00Z',
        '135', String(p95), '500', '900', '20', '300', 'popcre/shared-db', '1', 'a'.repeat(40)] } });
      const artifact = JSON.parse(readFileSync(join(directory, 'observation.json'), 'utf8'));
      assert.equal(artifact.result, expected);
      assert.equal(artifact.budget_met, p95 < 300);
      assert.equal(artifact.p95_ms, p95);
      assert.equal(artifact.budget_ms, 300);
      assert.match(artifact.owner_direction, /2026-11-02: proceed with the proof and the close/);
    } finally {
      rmSync(directory, { recursive: true, force: true });
    }
  });
}
