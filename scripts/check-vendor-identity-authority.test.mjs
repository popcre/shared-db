// Negative-path tests for the vendor identity authority guard.
//
// Repo standard: a test that only proves a guard EXISTS is worthless. Every
// case here proves the guard REFUSES something, including the exact shape of
// the 2026-09-15 defect it was written for — a uniqueness claim on a ColdLion
// landing table that no ColdLion answer supports.
//
//   node --test scripts/check-vendor-identity-authority.test.mjs

import { test } from 'node:test';
import assert from 'node:assert/strict';
import { mkdtempSync, writeFileSync, mkdirSync, rmSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join } from 'node:path';
import { check } from './check-vendor-identity-authority.mjs';

const REGISTER = [
  '| id | question | who | evidence | status |',
  '|---|---|---|---|---|',
  '| 2.34 | ANSWERED 2026-09-10 - mgCategory is part of the identity. | JamieLynn | - | Answered. |',
  '| 2.36 | OPEN AND BLOCKING - what identifies a /proddetails row? | JamieLynn | - | SENT, awaiting reply. |',
  '',
].join('\n');

function repo(migrations, { register = REGISTER } = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'vendor-authority-'));
  mkdirSync(join(dir, 'config'), { recursive: true });
  mkdirSync(join(dir, 'supabase/migrations'), { recursive: true });
  mkdirSync(join(dir, 'docs'), { recursive: true });
  writeFileSync(
    join(dir, 'config/vendor-landing-authority.json'),
    JSON.stringify({
      activation_migration: '20260920000000',
      schemas: { coldlion: { register: 'docs/coldlion-open-questions.md', vendor: 'ColdLion' } },
    }),
  );
  writeFileSync(join(dir, 'docs/coldlion-open-questions.md'), register);
  for (const [name, sql] of Object.entries(migrations)) {
    writeFileSync(join(dir, 'supabase/migrations', name), sql);
  }
  return dir;
}

function run(migrations, opts) {
  const dir = repo(migrations, opts);
  try {
    return check(dir);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
}

test('refuses a uniqueness claim on a vendor landing table with no cited authority', () => {
  const f = run({
    '20260921000000_assert.sql':
      'alter table coldlion.prod_detail add constraint pd_line unique (company_code, prod_order_no, prod_line_seq);',
  });
  assert.equal(f.length, 1);
  assert.match(f[0], /no "-- source-authority:" line/);
  assert.match(f[0], /ColdLion/);
});

test('refuses DROPPING an identity constraint with no cited authority - the 2026-09-17 case', () => {
  const f = run({
    '20260921000000_drop.sql': 'alter table coldlion.prod_detail drop constraint prod_detail_order_line_key;',
  });
  assert.equal(f.length, 1);
  assert.match(f[0], /no "-- source-authority:" line/);
});

test('refuses an authority that is still an OPEN question', () => {
  const f = run({
    '20260921000000_open.sql':
      '-- source-authority: open question 2.36\nalter table coldlion.prod_detail drop constraint prod_detail_order_line_key;',
  });
  assert.equal(f.length, 1);
  assert.match(f[0], /still OPEN/);
});

test('refuses a citation that names no entry in the register', () => {
  const f = run({
    '20260921000000_ghost.sql':
      '-- source-authority: 9.99\nalter table coldlion.prod_detail add constraint x unique (pkey);',
  });
  assert.equal(f.length, 1);
  assert.match(f[0], /not an entry/);
});

test('accepts an answered authority', () => {
  const f = run({
    '20260921000000_ok.sql':
      '-- source-authority: 2.34 - ColdLion confirmed the identity 2026-09-10\n' +
      'alter table coldlion.merch_group_detail add constraint mg_id unique (mg_category, mg_code);',
  });
  assert.deepEqual(f, []);
});

test('ignores migrations older than the guard, which cannot be edited', () => {
  const f = run({
    '20260916001944_historic.sql':
      'alter table coldlion.prod_detail add constraint pd_line unique (prod_order_no, prod_line_seq);',
  });
  assert.deepEqual(f, []);
});

test('ignores tables that are not vendor landing tables', () => {
  const f = run({
    '20260921000000_ours.sql': 'alter table public.style add constraint style_key unique (style_no);',
  });
  assert.deepEqual(f, []);
});

test('ignores the word unique when it only appears in a comment', () => {
  const f = run({
    '20260921000000_prose.sql':
      '-- coldlion.prod_detail keeps its unique (pkey) identity; this migration only grants select\n' +
      'grant select on coldlion.prod_detail to db_data_admin;',
  });
  assert.deepEqual(f, []);
});
