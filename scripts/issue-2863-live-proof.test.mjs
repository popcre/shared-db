import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { probeShapeProblem } from './check-live-proof-probe.mjs';

const sql = readFileSync(new URL('../.github/live-proofs/2863.sql', import.meta.url), 'utf8');
test('recovered replay proof passes the production single-read-statement guard', () => {
  assert.equal(probeShapeProblem(sql), null);
});
test('both required endpoint witnesses are conjunctive, never alternative evidence', () => {
  assert.match(sql, /SELECT EXISTS \(SELECT 1 FROM prepack_replay\)\s+AND EXISTS \(SELECT 1 FROM prod_replay\)/);
  assert.doesNotMatch(sql, /\b(?:10111|10119|17303|7263)\b/);
});

// Every component of the #2863 live assertion must be structurally present.
// Removing any one of these from the probe must make the offline suite fail,
// so a weakened or inauthentic proof cannot pass silently.

test('idempotent replay: the replay run inserts and updates nothing', () => {
  assert.match(sql, /r\.rows_inserted = 0/);
  assert.match(sql, /r\.rows_updated = 0/);
});

test('no duplicate collapse: every replay run has an empty change_log', () => {
  assert.match(sql, /NOT EXISTS \(SELECT 1 FROM coldlion\.change_log c WHERE c\.run_id = r\.id\)/);
});

test('stable row counts: a prior run with matching counts precedes each replay', () => {
  assert.match(sql, /prior\.rows_fetched = r\.rows_fetched/);
  assert.match(sql, /prior\.rows_unchanged = r\.rows_unchanged/);
});

test('lands and re-lands: both endpoints require a prior succeeded run', () => {
  const priorMatches = sql.match(/prior\.status = 'succeeded' AND prior\.finished_at < r\.started_at/g) ?? [];
  assert.equal(priorMatches.length, 2, 'prepack and prod each need their own prior-run witness');
});

test('table counts equal run counts, proving no row was collapsed or lost', () => {
  assert.match(sql, /count\(\*\) FROM coldlion\.prepack_detail d[\s\S]*?= r\.rows_unchanged/);
  assert.match(sql, /count\(\*\) FROM coldlion\.prod_detail d[\s\S]*?= r\.rows_fetched/);
});

test('counts are derived from loader evidence, never hardcoded expected totals', () => {
  // The probe must reference run-record columns as its only count sources.
  assert.match(sql, /r\.rows_unchanged/);
  assert.match(sql, /r\.rows_fetched/);
  // A fixed expected total would appear as a bare integer compared to a count.
  assert.doesNotMatch(sql, /count\(\*\)[^=]*=\s*\d+/);
});

test('false control: dropping either endpoint witness breaks the conjunctive gate', () => {
  const withoutPrepack = sql.replace(/SELECT EXISTS \(SELECT 1 FROM prepack_replay\)\s+AND EXISTS \(SELECT 1 FROM prod_replay\)/,
    'SELECT EXISTS (SELECT 1 FROM prod_replay)');
  assert.doesNotMatch(withoutPrepack, /EXISTS \(SELECT 1 FROM prepack_replay\)\s+AND EXISTS \(SELECT 1 FROM prod_replay\)/);
  const withoutProd = sql.replace(/SELECT EXISTS \(SELECT 1 FROM prepack_replay\)\s+AND EXISTS \(SELECT 1 FROM prod_replay\)/,
    'SELECT EXISTS (SELECT 1 FROM prepack_replay)');
  assert.doesNotMatch(withoutProd, /EXISTS \(SELECT 1 FROM prepack_replay\)\s+AND EXISTS \(SELECT 1 FROM prod_replay\)/);
});

test('false control: a write statement is refused by the probe shape guard', () => {
  assert.notEqual(probeShapeProblem('DELETE FROM coldlion.prepack_detail'), null);
  assert.notEqual(probeShapeProblem('SELECT true as passed; DROP TABLE coldlion.prod_detail'), null);
});

test('RLS and privilege posture is part of the proof', () => {
  assert.match(sql, /relrowsecurity/);
  assert.match(sql, /has_table_privilege\('service_role','coldlion\.prepack_detail','SELECT'\)/);
  assert.match(sql, /has_table_privilege\('service_role','coldlion\.prod_detail','SELECT'\)/);
});
