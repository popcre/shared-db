import test from 'node:test'
import assert from 'node:assert/strict'
import { createHash } from 'node:crypto'
import { gunzipSync } from 'node:zlib'
import { readFileSync } from 'node:fs'
import { inspectPrStructuralChange, structuralWritesMatch } from './db-flow/admission.mjs'
import { validateClaimObjects } from './lib/lanes/claims.mjs'

const migration = 'supabase/migrations/20261018172640_public_admin_rls_initplans.sql'
const sql = readFileSync(new URL('../' + migration, import.meta.url), 'utf8')
const manifest = JSON.parse(readFileSync(new URL('../docs/verification/rls-initplan/4427/manifest.json', import.meta.url)))
const contract = JSON.parse(readFileSync(new URL('../.agent/work/4427/5/contract.json', import.meta.url)))
const quote = value => '"' + value.replaceAll('"', '""') + '"'

test('the canonical DDL inspector recognizes exactly the admitted policy and table writes', () => {
  const inspected = inspectPrStructuralChange([{ filename: migration, status: 'added', content: sql }])
  assert.equal(structuralWritesMatch(inspected, validateClaimObjects(contract.db_writes)), true)
})

test('each of 44 qualified policies wraps the entire helper and retains absent clauses', () => {
  assert.equal(manifest.target_policies.length, 46)
  assert.equal(new Set(manifest.tables).size, 39)
  assert.equal(manifest.all_overlapping_policies.length, 72)
  assert.equal(manifest.rewrite_tables.length, 37)
  assert.equal(manifest.false_positives.length, 2)
  assert.doesNotMatch(sql, /^ALTER POLICY .* ON "archive"\./m)
  const alters = [...sql.matchAll(/^ALTER POLICY ([\s\S]*?);$/gm)].map(match => match[0])
  assert.equal(alters.length, 44)
  for (const policy of manifest.rewritten_policies) {
    const prefix = `ALTER POLICY ${quote(policy.policyname)} ON ${quote(policy.schemaname)}.${quote(policy.tablename)}\n  `
    const clauses = []
    for (const [field, keyword] of [['qual', 'USING'], ['with_check', 'WITH CHECK']]) {
      if (policy[field] !== null) {
        assert.equal(policy[field], "has_role(auth.uid(), 'admin'::app_role)")
        clauses.push(`${keyword} ((SELECT public.has_role(auth.uid(), 'admin'::public.app_role)))`)
      }
    }
    assert.ok(alters.includes(prefix + clauses.join('\n  ') + ';'), policy.policyname)
  }
})

test('drift checks cover complete original predicates and preserve metadata and policy unions', () => {
  const targetLiterals = [...sql.matchAll(/\$targets\$([\s\S]*?)\$targets\$::jsonb/g)]
  assert.equal(targetLiterals.length, 2)
  for (const match of targetLiterals) assert.deepEqual(JSON.parse(match[1]), manifest.rewritten_policies)
  assert.match(sql, /actual IS DISTINCT FROM expected/)
  assert.match(sql, /snapshot IS DISTINCT FROM current_setting\('shared_db\.rls4427_before'\)::jsonb/)
  for (const field of ['relowner', 'relacl', 'relrowsecurity', 'relforcerowsecurity', 'attacl', 'pg_get_functiondef', 'proowner', 'proacl', 'proconfig', 'provolatile', 'prosecdef', 'p.roles', 'p.cmd', 'p.permissive', 'p.qual', 'p.with_check']) assert.ok(sql.includes(field), field)
  assert.match(sql, /regexp_replace\(actual\.qual/)
  assert.match(sql, /regexp_replace\(actual\.with_check/)
  assert.doesNotMatch(sql, /\b(?:CREATE|DROP|GRANT|REVOKE|TRUNCATE|INSERT|UPDATE|DELETE)\s+(?:TABLE|FUNCTION|ROLE|POLICY|INTO|FROM)\b/i)
})

// Retained evidence must remain tied to the exact executable SQL, not a stale green run.
test('retained isolated runtime evidence matches current SQL and complete measured results', () => {
  const base = new URL('../docs/verification/rls-initplan/4427/', import.meta.url)
  const summary = JSON.parse(readFileSync(new URL('source-runtime-summary.json', base)))
  const packed = readFileSync(new URL('source-runtime-evidence.json.gz', base))
  const raw = gunzipSync(packed)
  const hash = value => createHash('sha256').update(value).digest('hex')
  assert.equal(hash(packed), summary.compressed_sha256)
  assert.equal(hash(raw), summary.uncompressed_sha256)
  const evidence = JSON.parse(raw)
  assert.equal(evidence.ci_run_id, 39154055887)
  assert.equal(evidence.tested_head, '2fbc889e50ccc59090742531e049a1c3232b1778')
  for (const [file, digest] of Object.entries(evidence.source_sha256)) {
    assert.equal(hash(readFileSync(new URL('../' + file, import.meta.url))), digest, file)
  }
  assert.equal(evidence.access.length, 2124)
  const outcomes = new Map(evidence.access.map(row => [row.phase + ':' + row.context + ':' + row.probe, row.result]))
  assert.equal(outcomes.size, 2124)
  for (const row of evidence.access.filter(row => row.phase === 'original')) {
    assert.deepEqual(outcomes.get('candidate:' + row.context + ':' + row.probe), row.result)
  }
  assert.equal(evidence.performance.samples.length, 198)
  assert.equal(evidence.performance.summary.length, 9)
  assert.equal(evidence.performance.any_regression_requires_investigation, false)
  for (const measured of evidence.performance.summary) assert.equal(measured.requires_regression_investigation, false)
  for (const [name, stats] of Object.entries(summary.initplan_execution_counts)) {
    assert.equal(stats.samples, 33)
    assert.equal(stats.loops_above_1, 0)
    if (name.startsWith('candidate ')) assert.equal(stats.initplans, stats.loops_equal_1)
  }
})
