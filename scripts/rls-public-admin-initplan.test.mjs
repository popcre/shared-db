import test from 'node:test'
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import { inspectPrStructuralChange, structuralWritesMatch } from './db-flow/admission.mjs'
import { validateClaimObjects } from './lib/lanes/claims.mjs'

const migration = 'supabase/migrations/20261018172640_public_admin_rls_initplans.sql'
const sql = readFileSync(new URL('../' + migration, import.meta.url), 'utf8')
const manifest = JSON.parse(readFileSync(new URL('../docs/verification/rls-initplan/4427/manifest.json', import.meta.url)))
const contract = JSON.parse(readFileSync(new URL('../.agent/work/4427/1/contract.json', import.meta.url)))
const quote = value => '"' + value.replaceAll('"', '""') + '"'

test('the canonical DDL inspector recognizes exactly the admitted policy and table writes', () => {
  const inspected = inspectPrStructuralChange([{ filename: migration, status: 'added', content: sql }])
  assert.equal(structuralWritesMatch(inspected, validateClaimObjects(contract.db_writes)), true)
})

test('each of 46 exact policies wraps the entire helper and retains absent clauses', () => {
  assert.equal(manifest.target_policies.length, 46)
  assert.equal(new Set(manifest.tables).size, 39)
  assert.equal(manifest.all_overlapping_policies.length, 72)
  const alters = [...sql.matchAll(/^ALTER POLICY ([\s\S]*?);$/gm)].map(match => match[0])
  assert.equal(alters.length, 46)
  for (const policy of manifest.target_policies) {
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
  for (const match of targetLiterals) assert.deepEqual(JSON.parse(match[1]), manifest.target_policies)
  assert.match(sql, /actual IS DISTINCT FROM expected/)
  assert.match(sql, /snapshot IS DISTINCT FROM current_setting\('shared_db\.rls4427_before'\)::jsonb/)
  for (const field of ['relowner', 'relacl', 'relrowsecurity', 'relforcerowsecurity', 'attacl', 'pg_get_functiondef', 'proowner', 'proacl', 'proconfig', 'provolatile', 'prosecdef', 'p.roles', 'p.cmd', 'p.permissive', 'p.qual', 'p.with_check']) assert.ok(sql.includes(field), field)
  assert.match(sql, /regexp_replace\(actual\.qual/)
  assert.match(sql, /regexp_replace\(actual\.with_check/)
  assert.doesNotMatch(sql, /\b(?:CREATE|DROP|GRANT|REVOKE|TRUNCATE|INSERT|UPDATE|DELETE)\s+(?:TABLE|FUNCTION|ROLE|POLICY|INTO|FROM)\b/i)
})
