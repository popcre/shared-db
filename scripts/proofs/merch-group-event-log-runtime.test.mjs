import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';
const read = p => readFileSync(new URL(p, import.meta.url), 'utf8');
const migration = read('../../supabase/migrations/20261112190611_merch_group_event_log_runtime_grant.sql');

test('runtime privileges fail closed and preserve journal evidence', () => {
  assert.match(migration, /if not exists[\s\S]*raise exception '#6171: backend runtime or safe grants role missing'/);
  assert.match(migration, /pg_has_role\('designflow_prod_backend_runtime', 'designflow_prod_backend_grants', 'USAGE'\)/);
  assert.match(migration, /grant usage on schema coldlion to designflow_prod_backend_grants/);
  assert.match(migration, /grant select, insert on table coldlion\.merch_group_event_log\s+to designflow_prod_backend_grants/);
  assert.match(migration, /grant update \(status, reason, rows_touched, processed_at\)/);
  assert.doesNotMatch(migration, /\bto designflow_prod_backend_runtime\b/i);
  assert.doesNotMatch(migration, /^\s*grant[^;]*\bdelete\b/im);
  assert.equal((migration.match(/for (select|insert|update) to designflow_prod_backend_grants/g) || []).length, 3);
  assert.match(migration, /has_schema_privilege\(/);
  assert.match(migration, /has_column_privilege[\s\S]*is distinct from \(attname in/);
});

test('catalog proofs enumerate table and column rights and schema audience', () => {
  for (const file of ['./2873-catalog.sql', './2873-role-contract.sql']) {
    const sql = read(file);
    for (const column of ['status', 'reason', 'rows_touched', 'processed_at']) {
      assert.ok(sql.includes(`'column','coldlion.merch_group_event_log.${column}','UPDATE'`));
    }
    assert.match(sql, /aclexplode\(at.attacl\)/);
    assert.match(sql, /'table','coldlion.merch_group_event_log','SELECT'/);
    assert.match(sql, /'table','coldlion.merch_group_event_log','INSERT'/);
  }
  const catalog = read('./2873-catalog.sql');
  assert.match(catalog, /n.nspname='coldlion' AND r.rolname IN \('designflow_prod_tracking_grants','designflow_prod_backend_grants'\)/);
  assert.match(catalog, /WHERE n.nspname='coldlion'\)=2/);
});

test('SQL regression exercises RLS as runtime, evidence refusal and delete refusal', () => {
  const sql = read('../../supabase/tests/merch_group_event_log_runtime_contracts.sql');
  for (const expression of [/set local role designflow_prod_backend_runtime/, /row_security_active/, /insert into coldlion/, /select count\(\*\)/, /update coldlion/, /delete from coldlion/, /exception when insufficient_privilege/, /rollback;/]) assert.match(sql, expression);
  assert.doesNotMatch(sql, /raise warning|return;/i);
});
