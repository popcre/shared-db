// Offline regression guards for the bounded #6228 identity-link repair.
// Database execution is covered by preview CI, which requires Supabase.
import assert from 'node:assert/strict'
import { readFileSync } from 'node:fs'
import test from 'node:test'

const sql = readFileSync(new URL('../supabase/migrations/20261113041225_opa_contract_studio_placement_fix_forward.sql', import.meta.url), 'utf8')

test('preserves shared canonical properties and only repairs the two reviewed identities', () => {
  assert.doesNotMatch(sql, /update\s+core\.property/i)
  assert.match(sql, /\('372', 'Standard Characters', 'Mickey Mouse', 'disney', 'DY'\)/)
  assert.match(sql, /\('640', 'X-Men Classic', 'X-Men', 'marvel', 'MV'\)/)
  assert.match(sql, /p\.name in \(r\.previous_name, r\.canonical_name\)/)
})

test('validates studio ownership before creating or linking targets', () => {
  const guard = sql.indexOf('unexpected previous identity or outside studio licensor')
  assert.ok(guard > 0 && guard < sql.indexOf('insert into core.property'))
  assert.match(sql, /p\.licensor_id = v_lic/)
  assert.match(sql, /s\.studio_code = r\.studio/)
  assert.match(sql, /unexpected source resolution for OPA/)
})

test('rejects ambiguous case-insensitive targets before writes', () => {
  assert.match(sql, /lower\(name\) = lower\(r\.canonical_name\)/)
  const guard = sql.indexOf('if v_n > 1 then')
  assert.ok(guard > 0 && guard < sql.indexOf('insert into core.property'))
  assert.match(sql, /canonical target spelling differs/)
  assert.match(sql, /lock table core\.property, core\.taxonomy_source_ref, plm\.source_resolution/)
})

test('repairs missing references and updates the durable resolution through its supported entry point', () => {
  assert.match(sql, /insert into core\.taxonomy_source_ref/)
  assert.match(sql, /on conflict \(source_system,source_table,source_id\) do update\s+set entity_id = excluded\.entity_id/)
  assert.match(sql, /select updated_at into v_updated from plm\.source_resolution/)
  assert.match(sql, /perform plm\.set_source_resolution/)
  assert.match(sql, /repair OPA identity link'::text, v_updated/)
})

test('keeps repairs and whole-chain validation in one atomic block', () => {
  assert.equal((sql.match(/^do \$/gm) ?? []).length, 1)
  assert.doesNotMatch(sql, /\bcommit\s*;/i)
  assert.match(sql, /if v_n <> v_expected then\s+raise exception/)
  assert.match(sql, /sr\.core_property_id = p\.id/)
})
