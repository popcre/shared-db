import test from 'node:test';
import assert from 'node:assert/strict';
import { readFileSync } from 'node:fs';

const sql = readFileSync(new URL('../supabase/migrations/20261103142609_pdf_indra_rescan.sql', import.meta.url), 'utf8');
const commit = sql.split('CREATE OR REPLACE FUNCTION public.commit_pdf_rescan_batch')[1];

test('rescan preserves omitted required metadata and empty page count', () => {
  assert.match(commit, /filename = COALESCE\(r\.e->>'filename', p\.filename\)/);
  assert.match(commit, /relative_path = COALESCE\(r\.e->>'relative_path', p\.relative_path\)/);
  assert.match(commit, /v_page_count := NULLIF\(r\.e->>'page_count', ''\)::integer/);
  assert.match(commit, /page_count = COALESCE\(v_page_count, p\.page_count\)/);
});

test('bad casts are caught before any backup or mutation', () => {
  assert.match(commit, /SELECT e FROM jsonb_array_elements\(p_rows\) e\s+LOOP/);
  assert.match(commit, /BEGIN\s+v_asset_id := NULLIF\(r\.e->>'asset_id', ''\)::uuid;\s+v_page_count :=[^;]+;\s+EXCEPTION WHEN invalid_text_representation OR numeric_value_out_of_range THEN\s+v_failed := v_failed \+ 1;\s+CONTINUE;\s+END;/);
  assert.ok(commit.indexOf('EXCEPTION WHEN') < commit.indexOf('INSERT INTO'));
  assert.match(commit, /IF v_asset_id IS NULL THEN\s+v_failed := v_failed \+ 1;\s+CONTINUE;/);
  assert.doesNotMatch(commit, /\(r\.e->>'page_count'\)::int/);
});

test('rescan protects both near-empty and proportionally shorter text', () => {
  assert.match(commit, /v_replace := v_len > 0 AND NOT \(\s+COALESCE\(length\(v_old\.extracted_text\), 0\) >= 100\s+AND \(v_len < 100 OR v_len < length\(v_old\.extracted_text\) \* 0\.5\)\)/);
});

test('behavioral SQL contracts cover backups, queue, metadata, malformed rows and designers', () => {
  const contracts = readFileSync(new URL('../supabase/tests/pdf_indra_rescan_contracts.sql', import.meta.url), 'utf8');
  for (const check of ['count_pdf_rescan_remaining()', 'claim_pdf_rescan_batch(10)',
    'commit_pdf_rescan_batch(', 'pdf_text_samples_backup', 'kept_existing',
    'not-an-integer', 'bad-uuid', 'Original creative', 'Original technical',
    'page_count <> 4', 'sku_files_used']) {
    assert.ok(contracts.includes(check), `Missing contract: ${check}`);
  }
  assert.match(contracts, /ROLLBACK;\s*$/);
});
