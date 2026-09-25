// Tests for the ledger-drift status reporter (issue #2508).
//
// Backlog B7 standard: prove the reporter REFUSES bad input and that the
// attribution extraction is correct — not merely that the happy path exists.
//
//   node --test scripts/report-ledger-drift-status.test.mjs

import { test } from 'node:test'
import assert from 'node:assert/strict'

import {
  Unknown,
  attributeVersions,
  buildStatusRows,
  formatStatusReport,
  prNumberFromSubject,
} from './report-ledger-drift-status.mjs'

// --- PR number extraction ---------------------------------------------------

test('extracts PR from a merge commit subject', () => {
  assert.equal(prNumberFromSubject('Merge pull request #3301 from popcre/codex/issue-3282-pdf-claim-analysis'), 3301)
})

test('extracts PR from a squash-merge trailing reference', () => {
  assert.equal(prNumberFromSubject('fix(#2478): static anon/authenticated revokes on SKU helper (#2846)'), 2846)
})

test('falls back to any #N in the subject', () => {
  assert.equal(prNumberFromSubject('migration: re-reserve 20260911204023 as 20260911212849 (#2746)'), 2746)
  assert.equal(prNumberFromSubject('feat: add leased HTS classification jobs (#3382)'), 3382)
})

test('returns null when no PR number is present', () => {
  assert.equal(prNumberFromSubject('migration: re-reserve 20260911204023 as 20260911212849'), null)
  assert.equal(prNumberFromSubject(''), null)
  assert.equal(prNumberFromSubject(undefined), null)
})

// --- status rows ------------------------------------------------------------

const sampleDrift = {
  mergedCount: 706,
  appliedCount: 676,
  mergedNotApplied: ['20260911212849', '20260817150944', '20260909121403'],
  appliedNotMerged: [],
  intentionallyExcluded: ['20260817150944'],
  foreignTarget: ['20260909121403'],
  actionableMergedNotApplied: ['20260911212849'],
  driftFound: true,
  fileByVersion: {
    '20260911212849': 'supabase/migrations/20260911212849_shared_style_group_sku_key.sql',
    '20260817150944': 'supabase/migrations/20260817150944_sync_dflow_columns_onto_plm_designflow_copies.sql',
    '20260909121403': 'supabase/migrations/20260909121403_hts_rag_split_isolated_schema.sql',
  },
  pendingClassifications: {
    '20260911212849': { kind: 'genuinely-pending', reason: 'No retirement names this version.' },
    '20260817150944': { kind: 'deliberately-held', reason: 'Preview-only historical restoration.' },
    '20260909121403': { kind: 'foreign-target', reason: 'Targets a different database.' },
  },
}

test('buildStatusRows lists only actionable versions with attribution', () => {
  const rows = buildStatusRows(sampleDrift, {
    '20260911212849': { commit: 'e056475dd', subject: 'migration: re-reserve (#2746)', pr: 2746 },
  })
  assert.equal(rows.length, 1)
  assert.equal(rows[0].version, '20260911212849')
  assert.equal(rows[0].pr, 2746)
  assert.match(rows[0].file, /20260911212849_shared_style_group_sku_key\.sql$/)
})

test('buildStatusRows tolerates missing attribution without dropping the row', () => {
  const rows = buildStatusRows(sampleDrift, {})
  assert.equal(rows.length, 1)
  assert.equal(rows[0].pr, null)
  assert.equal(rows[0].commit, '')
})

test('buildStatusRows produces an empty list when nothing is actionable', () => {
  const rows = buildStatusRows({ ...sampleDrift, actionableMergedNotApplied: [] }, {})
  assert.deepEqual(rows, [])
})

// --- report rendering -------------------------------------------------------

const sampleRows = buildStatusRows(sampleDrift, {
  '20260911212849': { commit: 'e056475dd', subject: 'migration: re-reserve (#2746)', pr: 2746 },
})

test('formatStatusReport names the project, counts, and promotion holders', () => {
  const report = formatStatusReport({
    target: 'production',
    projectRef: 'qsllyeztdwjgirsysgai',
    baseRef: 'origin/main',
    drift: sampleDrift,
    rows: sampleRows,
  })
  assert.match(report, /qsllyeztdwjgirsysgai/)
  assert.match(report, /Promotion candidates — 1 genuinely-pending/)
  assert.match(report, /#2746/)
  assert.match(report, /20260911212849/)
  assert.match(report, /bounded Shared Supabase Migrations workflow/)
  assert.match(report, /no production apply/i)
})

test('formatStatusReport reports clean state when nothing is actionable', () => {
  const report = formatStatusReport({
    target: 'production',
    projectRef: 'x',
    baseRef: 'origin/main',
    drift: { ...sampleDrift, actionableMergedNotApplied: [], driftFound: false },
    rows: [],
  })
  assert.match(report, /No actionable drift/)
  assert.doesNotMatch(report, /Promotion candidates/)
})

test('formatStatusReport lists orphan ledger rows when present', () => {
  const report = formatStatusReport({
    target: 'production',
    projectRef: 'x',
    baseRef: 'origin/main',
    drift: { ...sampleDrift, appliedNotMerged: ['20260101000000'], actionableMergedNotApplied: [], driftFound: true },
    rows: [],
  })
  assert.match(report, /Orphan ledger rows — 1/)
  assert.match(report, /20260101000000/)
})

test('formatStatusReport renders unattributed rows honestly', () => {
  const rows = buildStatusRows({ ...sampleDrift, actionableMergedNotApplied: ['20260911212849'] }, {})
  const report = formatStatusReport({
    target: 'production',
    projectRef: 'x',
    baseRef: 'origin/main',
    drift: sampleDrift,
    rows,
  })
  assert.match(report, /unattributed/)
})

// --- attribution I/O --------------------------------------------------------

test('attributeVersions recovers commit and PR from a git runner', () => {
  const run = (_cmd, args) => {
    assert.ok(args.includes('--first-parent'))
    assert.ok(args.includes('--reverse'))
    assert.ok(args.includes('origin/main'))
    return '26d9345b3a0ee015d8d02c0705002dd10b7f3f4e\tMerge pull request #2746 from u2giants/codex/issue-2478-shared-sku-key\n'
  }
  const attribution = attributeVersions(
    { '20260911212849': 'supabase/migrations/20260911212849_shared_style_group_sku_key.sql' },
    run,
  )
  assert.equal(attribution['20260911212849'].commit, '26d9345b3a0ee015d8d02c0705002dd10b7f3f4e')
  assert.equal(attribution['20260911212849'].pr, 2746)
})

test('attributeVersions uses the supplied base ref', () => {
  const run = (_cmd, args) => {
    assert.ok(args.includes('refs/heads/feature'))
    return 'abc123\tMerge pull request #99 from x/y\n'
  }
  const attribution = attributeVersions({ '20260101000000': 'a.sql' }, run, 'refs/heads/feature')
  assert.equal(attribution['20260101000000'].pr, 99)
})

test('attributeVersions prefers the entry that carries a PR number', () => {
  const run = () => 'aaa\tmigration: re-reserve something\nbbb\tMerge pull request #42 from x/y\n'
  const attribution = attributeVersions({ '20260101000000': 'a.sql' }, run)
  assert.equal(attribution['20260101000000'].commit, 'bbb')
  assert.equal(attribution['20260101000000'].pr, 42)
})

test('attributeVersions skips files git cannot attribute rather than failing', () => {
  const run = () => { throw new Error('bad path') }
  const attribution = attributeVersions({ '20260911212849': 'supabase/migrations/missing.sql' }, run)
  assert.deepEqual(attribution, {})
})

// --- CLI refusal paths (the "no silent failures" rule) -----------------------

test('CLI refuses without --json', async () => {
  const { main } = await import('./report-ledger-drift-status.mjs')
  // Capture stderr noise from the refusal path.
  const originalError = console.error
  console.error = () => {}
  try {
    assert.equal(await main([]), 2)
  } finally {
    console.error = originalError
  }
})

test('CLI refuses invalid JSON', async () => {
  const { main } = await import('./report-ledger-drift-status.mjs')
  const originalError = console.error
  console.error = () => {}
  try {
    assert.equal(await main(['--json', 'nonexistent-file.json']), 2)
  } finally {
    console.error = originalError
  }
})

test('Unknown is the typed refusal used across the tool', () => {
  assert.throws(() => { throw new Unknown('x') }, Unknown)
})
