import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
import { probeShapeProblem, stripSqlNoise } from './check-live-proof-probe.mjs';

const sql = readFileSync(new URL('../.github/live-proofs/2863.sql', import.meta.url), 'utf8');
// Strip only comments so predicates hidden in comments cannot satisfy assertions.
// String literals are kept — they are real SQL content (endpoints, roles, keys).
function stripComments(s) {
  return String(s)
    .replace(/\/\*[\s\S]*?\*\//g, ' ')
    .replace(/--[^\n]*/g, ' ');
}
const code = stripComments(sql);

// Split CTEs so each endpoint can be pinned alone.
function cteBody(name) {
  const re = new RegExp(`${name} AS \\(([\\s\\S]*?)\\)\\s*,?\\s*(?:prod_replay|SELECT)`, 'i');
  const m = code.match(re);
  assert.ok(m, `CTE ${name} must exist in the probe`);
  return m[1];
}
const prepack = cteBody('prepack_replay');
const prod = cteBody('prod_replay');

test('recovered replay proof passes the production single-read-statement guard', () => {
  assert.equal(probeShapeProblem(sql), null);
});

test('both required endpoint witnesses are conjunctive, never alternative evidence', () => {
  assert.match(code, /SELECT EXISTS \(SELECT 1 FROM prepack_replay\)\s+AND EXISTS \(SELECT 1 FROM prod_replay\)/);
  assert.doesNotMatch(code, /\b(?:10111|10119|17303|7263)\b/);
});

test('each CTE names its own endpoint and succeeded status', () => {
  assert.match(prepack, /r\.endpoint = '\/prepackDetail'/);
  assert.match(prod, /r\.endpoint = '\/proddetails'/);
  assert.match(prepack, /r\.status = 'succeeded'/);
  assert.match(prod, /r\.status = 'succeeded'/);
});

test('idempotent replay: the replay run (r., not prior.) inserts and updates nothing', () => {
  // (?<![a-z]) ensures r is a table alias, not the trailing r of prior.
  for (const cte of [prepack, prod]) {
    assert.match(cte, /(?<![a-z])r\.rows_inserted = 0/);
    assert.match(cte, /(?<![a-z])r\.rows_updated = 0/);
  }
});

test('no duplicate collapse: every replay run has an empty change_log', () => {
  for (const cte of [prepack, prod]) {
    assert.match(cte, /NOT EXISTS \(SELECT 1 FROM coldlion\.change_log c WHERE c\.run_id = r\.id\)/);
  }
});

test('stable row counts: prior run counts match or conserve the replay', () => {
  // Prepack: prior unchanged equals replay unchanged (byte-identical coalesced response).
  assert.match(prepack, /prior\.rows_fetched = r\.rows_fetched/);
  assert.match(prepack, /prior\.rows_unchanged = r\.rows_unchanged/);
  // Prod: prior fetched equals replay fetched, and prior rows conserve.
  assert.match(prod, /prior\.rows_fetched = r\.rows_fetched/);
  assert.match(prod, /prior\.rows_fetched = prior\.rows_inserted \+ prior\.rows_updated \+ prior\.rows_unchanged/);
});

test('lands and re-lands: each CTE requires its own prior succeeded run', () => {
  for (const cte of [prepack, prod]) {
    assert.match(cte, /prior\.status = 'succeeded' AND prior\.finished_at < r\.started_at/);
  }
});

test('table counts equal run counts on both the run-scoped and population-scoped sides', () => {
  assert.match(prepack, /count\(\*\) FROM coldlion\.prepack_detail d[\s\S]*?d\.run_id = r\.id\)\s*= r\.rows_unchanged/);
  assert.match(prepack, /count\(\*\) FROM coldlion\.prepack_detail d[\s\S]*?d\.company_code = r\.company_code\)\s*= r\.rows_unchanged/);
  assert.match(prod, /count\(\*\) FROM coldlion\.prod_detail d[\s\S]*?d\.run_id = r\.id\)\s*= r\.rows_fetched/);
  assert.match(prod, /count\(\*\) FROM coldlion\.prod_detail d[\s\S]*?d\.prod_order_no::text = r\.request_params/);
});

test('sample identity keys are pinned for both endpoints', () => {
  assert.match(prepack, /fullSnapshot/);
  assert.match(prepack, /coveredKeys/);
  assert.match(prod, /prodOrderNo/);
});

// A landing-table count compared to a bare integer is a hardcoded total.
// Scope to a single (SELECT count(*) …) subquery so the RLS census (= 2) and
// other count(*) calls cannot bleed into the match.
const LANDING_COUNT = /\(SELECT count\(\*\) FROM coldlion\.(?:prepack_detail|prod_detail)(?:(?!\(SELECT)[\s\S])*?\)\s*=\s*\d+/;
test('counts are derived from loader evidence, never hardcoded expected totals', () => {
  assert.doesNotMatch(stripSqlNoise(sql), LANDING_COUNT);
});

// ---- false controls: mutate a real copy of the probe, then assert the SAME
// structural checks against the weakened copy. Each one must fail.

function assertStructuralComplete(text) {
  const noise = stripComments(text);
  assert.match(noise, /SELECT EXISTS \(SELECT 1 FROM prepack_replay\)\s+AND EXISTS \(SELECT 1 FROM prod_replay\)/);
  assert.match(noise, /(?<![a-z])r\.rows_inserted = 0/);
  assert.match(noise, /NOT EXISTS \(SELECT 1 FROM coldlion\.change_log c WHERE c\.run_id = r\.id\)/);
  assert.match(noise, /prior\.rows_fetched = r\.rows_fetched/);
  assert.doesNotMatch(stripSqlNoise(text), LANDING_COUNT);
}

test('false control: dropping the prepack witness breaks the structural gate', () => {
  const weakened = sql.replace(/SELECT EXISTS \(SELECT 1 FROM prepack_replay\)\s+AND EXISTS \(SELECT 1 FROM prod_replay\)/,
    'SELECT EXISTS (SELECT 1 FROM prod_replay)');
  assert.throws(() => assertStructuralComplete(weakened));
});

test('false control: dropping the prod witness breaks the structural gate', () => {
  const weakened = sql.replace(/SELECT EXISTS \(SELECT 1 FROM prepack_replay\)\s+AND EXISTS \(SELECT 1 FROM prod_replay\)/,
    'SELECT EXISTS (SELECT 1 FROM prepack_replay)');
  assert.throws(() => assertStructuralComplete(weakened));
});

test('false control: commenting out a predicate hides it from stripped SQL', () => {
  // Comment out every replay-run insert check (not the prior ones).
  const weakened = sql.replaceAll('AND r.rows_inserted = 0 AND r.rows_updated = 0',
    '-- AND r.rows_inserted = 0 AND r.rows_updated = 0');
  assert.throws(() => assertStructuralComplete(weakened));
});

test('false control: a hardcoded count trips the landing-count shape', () => {
  // Replace a real count comparison (not >= r.rows_unchanged) with a literal.
  const weakened = sql.replace(') = r.rows_unchanged', ') = 42');
  assert.match(stripSqlNoise(weakened), LANDING_COUNT);
  // ...and the authentic probe must NOT trip that pattern.
  assert.doesNotMatch(stripSqlNoise(sql), LANDING_COUNT);
});

test('false control: a write statement is refused by the probe shape guard', () => {
  assert.notEqual(probeShapeProblem('DELETE FROM coldlion.prepack_detail'), null);
  assert.notEqual(probeShapeProblem('SELECT true as passed; DROP TABLE coldlion.prod_detail'), null);
});

test('RLS and privilege posture is part of the proof', () => {
  assert.match(code, /relrowsecurity/);
  assert.match(code, /has_table_privilege\('service_role','coldlion\.prepack_detail','SELECT'\)/);
  assert.match(code, /has_table_privilege\('service_role','coldlion\.prod_detail','SELECT'\)/);
  assert.match(code, /anon/);
  assert.match(code, /authenticated/);
});
