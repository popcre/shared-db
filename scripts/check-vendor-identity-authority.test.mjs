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
import { mkdtempSync, writeFileSync, mkdirSync, rmSync, readFileSync } from 'node:fs';
import { tmpdir } from 'node:os';
import { join, dirname } from 'node:path';
import { fileURLToPath } from 'node:url';
import {
  check,
  registerEntryIsOpen,
  stripSql,
  lineCommentStarts,
  sourceAuthorityHeaders,
} from './check-vendor-identity-authority.mjs';

// Fixture people are roles, not names. This repository is public (AGENTS.md
// §6.14) and a test fixture is as public as anything else in it.
const REGISTER = [
  '| id | question | who | evidence | status |',
  '|---|---|---|---|---|',
  '| 2.34 | ANSWERED 2026-09-10 - mgCategory is part of the identity. | vendor contact | - | Answered. |',
  '| 2.36 | OPEN AND BLOCKING - what identifies a /proddetails row? | vendor contact | - | SENT, awaiting reply. |',
  '',
].join('\n');

const DEFAULT_CONFIG = {
  activation_migration: '20260920000000',
  schemas: { coldlion: { register: 'docs/coldlion-open-questions.md', vendor: 'ColdLion' } },
};

function repo(migrations, { register = REGISTER, config = DEFAULT_CONFIG, noMigrationsDir = false } = {}) {
  const dir = mkdtempSync(join(tmpdir(), 'vendor-authority-'));
  mkdirSync(join(dir, 'config'), { recursive: true });
  if (!noMigrationsDir) mkdirSync(join(dir, 'supabase/migrations'), { recursive: true });
  mkdirSync(join(dir, 'docs'), { recursive: true });
  if (config !== null) {
    writeFileSync(join(dir, 'config/vendor-landing-authority.json'), JSON.stringify(config));
  }
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

// ---------------------------------------------------------------------------
// The five evasions the governed review of PR #3389 found in the first version
// of IDENTITY. Each of these changes what rows the vendor is allowed to send,
// and each one got past a regex that enumerated constraint shapes.
// ---------------------------------------------------------------------------

test('refuses an UNNAMED add unique, which carries no constraint name to match on', () => {
  const f = run({
    '20260921000000_unnamed.sql':
      'alter table coldlion.prod_detail add unique nulls not distinct (prod_order_no, prod_line_seq);',
  });
  assert.equal(f.length, 1);
  assert.match(f[0], /no "-- source-authority:" line/);
});

test('refuses a column-level unique, which has no parenthesis after the keyword', () => {
  const f = run({
    '20260921000000_column.sql': 'alter table coldlion.prod_detail add column vendor_ref text unique;',
  });
  assert.equal(f.length, 1);
  assert.match(f[0], /no "-- source-authority:" line/);
});

test('refuses dropping a unique INDEX, which is not a drop constraint', () => {
  const f = run({
    '20260921000000_dropindex.sql': 'drop index coldlion.prod_detail_order_line_idx;',
  });
  assert.equal(f.length, 1);
  assert.match(f[0], /no "-- source-authority:" line/);
});

test('refuses CREATE TABLE ... LIKE INCLUDING CONSTRAINTS, which copies an identity claim', () => {
  const f = run({
    '20260921000000_like.sql':
      'create table coldlion.prod_detail_v2 (like coldlion.prod_detail including constraints including indexes);',
  });
  assert.equal(f.length, 1);
  assert.match(f[0], /no "-- source-authority:" line/);
});

test('refuses an EXCLUDE constraint, which enforces uniqueness under another keyword', () => {
  const f = run({
    '20260921000000_exclude.sql':
      'alter table coldlion.prod_detail add constraint pd_excl exclude using btree (prod_order_no with =, prod_line_seq with =);',
  });
  assert.equal(f.length, 1);
  assert.match(f[0], /no "-- source-authority:" line/);
});

test('refuses an identity change reached through SET search_path, with no schema-qualified name', () => {
  const f = run({
    '20260921000000_searchpath.sql':
      'set search_path = coldlion, public;\nalter table prod_detail add constraint pd_line unique (prod_order_no, prod_line_seq);',
  });
  assert.equal(f.length, 1);
  assert.match(f[0], /coldlion/);
  assert.match(f[0], /no "-- source-authority:" line/);
});

// ---------------------------------------------------------------------------
// A citation has to resolve to a document. The first version extracted entry
// ids and, finding none, checked nothing at all — so free prose passed.
// ---------------------------------------------------------------------------

test('refuses a citation that names nothing checkable', () => {
  const f = run({
    '20260921000000_prose_authority.sql':
      '-- source-authority: ColdLion told us on the phone, trust me\n' +
      'alter table coldlion.prod_detail add constraint pd_line unique (prod_order_no, prod_line_seq);',
  });
  assert.equal(f.length, 1);
  assert.match(f[0], /names nothing a reader can check/);
});

test('accepts a dated owner ruling as an authority', () => {
  const f = run({
    '20260921000000_ruling.sql':
      '-- source-authority: owner ruling 2026-09-29 - pkey is the row identity\n' +
      'alter table coldlion.prod_detail add constraint pd_pkey unique (company_code, pkey);',
  });
  assert.deepEqual(f, []);
});

test('refuses an undated owner ruling, which points at no locatable decision', () => {
  const f = run({
    '20260921000000_undated.sql':
      '-- source-authority: owner ruling\n' +
      'alter table coldlion.prod_detail add constraint pd_pkey unique (company_code, pkey);',
  });
  assert.equal(f.length, 1);
  assert.match(f[0], /names nothing a reader can check/);
});

// ---------------------------------------------------------------------------
// Register parsing. Ids repeat in the live register (2.25-2.32 each appear
// twice and the two rows disagree), so reading the first row found made the
// answer depend on document order.
// ---------------------------------------------------------------------------

const DUPLICATE_REGISTER = [
  '| id | status |',
  '|---|---|',
  '| 2.40 | Closed |',
  '',
  '| id | question |',
  '|---|---|',
  '| 2.40 | Still waiting on ColdLion - asked 2026-09-03, no reply. |',
  '',
].join('\n');

test('reads a repeated entry as OPEN when its two rows disagree', () => {
  const f = run(
    {
      '20260921000000_dup.sql':
        '-- source-authority: 2.40\n' +
        'alter table coldlion.prod_detail add constraint pd_line unique (prod_order_no, prod_line_seq);',
    },
    { register: DUPLICATE_REGISTER },
  );
  assert.equal(f.length, 1);
  assert.match(f[0], /still OPEN/);
});

test('accepts a settled marker written as the whole of a summary cell', () => {
  const f = run(
    {
      '20260921000000_cell.sql':
        '-- source-authority: 2.41\n' +
        'alter table coldlion.prod_detail add constraint pd_pkey unique (company_code, pkey);',
    },
    { register: ['| id | status |', '|---|---|', '| 2.41 | Closed |', ''].join('\n') },
  );
  assert.deepEqual(f, []);
});

test('does not read the word closed inside prose as a settled marker', () => {
  const f = run(
    {
      '20260921000000_softclose.sql':
        '-- source-authority: 2.42\n' +
        'alter table coldlion.prod_detail add constraint pd_pkey unique (company_code, pkey);',
    },
    {
      register: [
        '| id | question |',
        '|---|---|',
        '| 2.42 | The vendor ticket was closed with no answer; still waiting. |',
        '',
      ].join('\n'),
    },
  );
  assert.equal(f.length, 1);
  assert.match(f[0], /still OPEN/);
});

test('does not read DROPPED as settled - 2.19 drops one ask from an entry that stays open', () => {
  const f = run(
    {
      '20260921000000_dropped.sql':
        '-- source-authority: 2.43\n' +
        'alter table coldlion.prod_detail add constraint pd_pkey unique (company_code, pkey);',
    },
    { register: ['| id | question |', '|---|---|', '| 2.43 | DROPPED ask (a); (b) and (c) still open. |', ''].join('\n') },
  );
  assert.equal(f.length, 1);
  assert.match(f[0], /still OPEN/);
});

// ---------------------------------------------------------------------------
// Unreadable inputs. A governance guard that concludes "settled" from a file it
// could not read is the failure this repository names most often.
// ---------------------------------------------------------------------------

test('refuses when the cited register file does not exist', () => {
  const dir = repo({
    '20260921000000_noreg.sql':
      '-- source-authority: 2.34\n' +
      'alter table coldlion.prod_detail add constraint pd_pkey unique (company_code, pkey);',
  });
  rmSync(join(dir, 'docs/coldlion-open-questions.md'));
  try {
    const f = check(dir);
    assert.equal(f.length, 1);
    assert.match(f[0], /does not exist/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('throws when the config is missing, so an absent config is never a pass', () => {
  const dir = repo({});
  rmSync(join(dir, 'config/vendor-landing-authority.json'));
  try {
    assert.throws(() => check(dir), /no config at/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('throws when the config names no vendor landing schemas', () => {
  const dir = mkdtempSync(join(tmpdir(), 'vendor-authority-empty-'));
  mkdirSync(join(dir, 'config'), { recursive: true });
  writeFileSync(
    join(dir, 'config/vendor-landing-authority.json'),
    JSON.stringify({ activation_migration: '20260920000000', schemas: {} }),
  );
  try {
    assert.throws(() => check(dir), /names no vendor landing schemas/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

// ---------------------------------------------------------------------------
// Second governed review of PR #3389. Each case below is a shape that reached
// a clean "OK" from the previous version of the guard.
// ---------------------------------------------------------------------------

test('refuses a whitespace-separated schema qualifier, which no substring match sees', () => {
  const f = run({
    '20260921000000_spaced.sql':
      'alter table coldlion . prod_detail add constraint pd_line unique (prod_order_no, prod_line_seq);',
  });
  assert.equal(f.length, 1);
  assert.match(f[0], /no "-- source-authority:" line/);
});

test('refuses a newline-separated and quoted schema qualifier', () => {
  const f = run({
    '20260921000000_quoted.sql':
      'alter table "coldlion"\n.prod_detail add constraint pd_line unique (prod_order_no);',
  });
  assert.equal(f.length, 1);
  assert.match(f[0], /no "-- source-authority:" line/);
});

test('refuses set_config search_path, the spelling SET does not cover', () => {
  const f = run({
    '20260921000000_setcfg.sql':
      "select set_config('search_path', 'coldlion, public', false);\n" +
      'alter table prod_detail add constraint pd_line unique (prod_order_no);',
  });
  assert.equal(f.length, 1);
});

test('refuses DROP COLUMN, which removes an identity constraint without naming one', () => {
  const f = run({ '20260921000000_dropcol.sql': 'alter table coldlion.prod_detail drop column prod_line_seq;' });
  assert.equal(f.length, 1);
  assert.match(f[0], /no "-- source-authority:" line/);
});

test('refuses DROP TABLE and DROP SCHEMA on a vendor landing schema', () => {
  assert.equal(run({ '20260921000000_droptbl.sql': 'drop table coldlion.prod_detail;' }).length, 1);
  assert.equal(run({ '20260921000000_dropsch.sql': 'drop schema coldlion cascade;' }).length, 1);
});

test('a trailing comment is stripped, so its prose cannot refuse an unrelated migration', () => {
  // `stripSql` claimed to strip comments but only removed whole-line ones, so
  // this public-schema migration was refused by the words in its own comment.
  const f = run({
    '20260921000000_public.sql':
      'alter table public.thing add column note text; -- unrelated to coldlion.prod_detail uniqueness',
  });
  assert.deepEqual(f, []);
});

test('a -- that lives inside a string literal does not truncate the statement', () => {
  const f = run({
    '20260921000000_literal.sql':
      "insert into coldlion.note (t) values ('a--b'); alter table coldlion.prod_detail add constraint u unique (a);",
  });
  assert.equal(f.length, 1);
});

test('a source-authority header inside a block comment does not count as a header', () => {
  const f = run({
    '20260921000000_fakehdr.sql':
      '/*\n-- source-authority: 2.34\n*/\nalter table coldlion.prod_detail add constraint u unique (a);',
  });
  assert.equal(f.length, 1);
  assert.match(f[0], /no "-- source-authority:" line/);
});

test('a source-authority header inside a dollar-quoted body does not count as a header', () => {
  const f = run({
    '20260921000000_fakefn.sql':
      'create function coldlion.f() returns void language sql as $$\n' +
      '-- source-authority: 2.34\nselect 1 $$;\n' +
      'alter table coldlion.prod_detail add constraint u unique (a);',
  });
  assert.equal(f.length, 1);
  assert.match(f[0], /no "-- source-authority:" line/);
});

test('two disagreeing source-authority headers refuse, rather than the first one winning', () => {
  const f = run({
    '20260921000000_two.sql':
      '-- source-authority: 2.34\n-- source-authority: 2.36\n' +
      'alter table coldlion.prod_detail add constraint u unique (a);',
  });
  assert.equal(f.length, 1);
  assert.match(f[0], /do not agree/);
});

test('a missing migrations directory refuses; the guard could not look, so it cannot pass', () => {
  const dir = repo({}, { noMigrationsDir: true });
  try {
    assert.throws(() => check(dir), /could not examine anything/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('an absent activation_migration refuses instead of skipping every migration', () => {
  const dir = repo(
    { '20260921000000_assert.sql': 'alter table coldlion.prod_detail add constraint u unique (a);' },
    { config: { schemas: DEFAULT_CONFIG.schemas } },
  );
  try {
    assert.throws(() => check(dir), /activation_migration must be a 14-digit/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('a misspelled activation_migration refuses; string comparison would have skipped everything', () => {
  const dir = repo(
    { '20260921000000_assert.sql': 'alter table coldlion.prod_detail add constraint u unique (a);' },
    { config: { ...DEFAULT_CONFIG, activation_migration: '2026-09-20' } },
  );
  try {
    assert.throws(() => check(dir), /activation_migration must be a 14-digit/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('a register path that escapes the repository refuses', () => {
  const dir = repo(
    {},
    { config: { ...DEFAULT_CONFIG, schemas: { coldlion: { register: '../outside.md', vendor: 'ColdLion' } } } },
  );
  try {
    assert.throws(() => check(dir), /resolves outside the repository/);
  } finally {
    rmSync(dir, { recursive: true, force: true });
  }
});

test('an uppercase .SQL extension is still examined', () => {
  const f = run({ '20260921000000_upper.SQL': 'alter table coldlion.prod_detail add constraint u unique (a);' });
  assert.equal(f.length, 1);
});

test('a settled word elsewhere in the row cannot settle a row whose status is still open', () => {
  // The exact fail-open the review named: a question cell that shouts ANSWERED
  // beside a status cell saying the reply has only been SENT.
  const register = [
    '| id | question | status |',
    '|---|---|---|',
    '| 2.40 | ANSWERED for a different endpoint - does it apply here? | SENT, awaiting reply. |',
    '',
  ].join('\n');
  assert.equal(registerEntryIsOpen(register, '2.40').open, true);
});

test('a mixed-case marker with trailing punctuation in its own cell reads as settled', () => {
  const register = ['| id | q | status |', '|---|---|---|', '| 2.41 | anything | **Answered 2026-09-10.** |', ''].join('\n');
  assert.equal(registerEntryIsOpen(register, '2.41').open, false);
});

test('the parser reads the REAL register, not only synthetic fixtures', () => {
  // 24 inline fixtures proved the parser against a register shape the tests
  // themselves invented. This asserts the parser-to-document contract: that ids
  // sit in the first cell of a pipe table, and that the conventions the real
  // file uses classify the way the guard assumes.
  const root = join(dirname(fileURLToPath(import.meta.url)), '..');
  const register = readFileSync(join(root, 'docs/coldlion-open-questions.md'), 'utf8');

  const identity = registerEntryIsOpen(register, '2.36');
  assert.equal(identity.found, true, '2.36 must be findable in the real register');
  assert.equal(identity.open, false, '2.36 records the 2026-09-29 identity answer and must read settled');

  const reduced = registerEntryIsOpen(register, '2.19');
  assert.equal(reduced.found, true);
  assert.equal(reduced.open, true, '2.19 DROPPED one ask; the entry itself stayed open');

  const split = registerEntryIsOpen(register, '2.25');
  assert.equal(split.rows > 1, true, '2.25 appears more than once, which is what the every-row rule is for');
  assert.equal(split.open, true, 'its summary row says Closed and its detail row is still awaiting a reply');

  assert.equal(registerEntryIsOpen(register, '9.99').found, false);
});

// ---------------------------------------------------------------------------
// Round-3 findings. Each of these passed the guard before the fix, so each one
// is the negative case for a defect that actually shipped.
// ---------------------------------------------------------------------------

test('H1: refuses an identity constraint asserted inside a DO block', () => {
  // The file contains no `coldlion.` outside the dollar quote, so the pre-fix
  // guard never even tested it for an identity keyword and printed OK.
  const f = run({
    '20260921000000_do_assert.sql': [
      'do $$ begin',
      '  alter table coldlion.prod_detail add constraint pd_line unique (prod_order_no, prod_line_seq);',
      'end $$;',
    ].join('\n'),
  });
  assert.equal(f.length, 1, 'a DO-block identity claim must be refused');
  assert.match(f[0], /carries no "-- source-authority:" line/);
});

test('H1: refuses an identity constraint REMOVED inside a DO block', () => {
  // The removal direction is the direction of the real incident.
  const f = run({
    '20260921000000_do_drop.sql': [
      'do $$ begin',
      '  if exists (select 1 from pg_constraint where conname = %L) then',
      '    alter table coldlion.prod_detail drop constraint pd_line;',
      '  end if;',
      'end $$;',
    ].join('\n'),
  });
  assert.equal(f.length, 1, 'a DO-block identity removal must be refused');
});

test('H1: refuses an identity constraint hidden in a function body', () => {
  const f = run({
    '20260921000000_fn.sql': [
      'create function coldlion.reshape() returns void language sql as $body$',
      '  alter table coldlion.prod_detail add constraint pd_line unique (prod_order_no);',
      '$body$;',
      'select coldlion.reshape();',
    ].join('\n'),
  });
  assert.equal(f.length, 1, 'an identity claim inside a function body must be refused');
});

test('H2: a genuine header after a multi-line block comment is accepted', () => {
  // The line-indexed header reader validated this header against the WRONG
  // raw line and refused a correctly cited migration.
  const f = run({
    '20260921000000_after_comment.sql': [
      '/*',
      ' * Why this constraint is safe.',
      ' */',
      '-- source-authority: 2.34',
      'alter table coldlion.prod_detail add constraint pd_mg unique (mg_category);',
    ].join('\n'),
  });
  assert.deepEqual(f, [], 'a genuine header must survive a preceding block comment');
});

test('H2: a fake header inside a multi-line block comment is still refused', () => {
  // The same index drift accepted this one, because the line it landed on
  // happened to begin with two spaces.
  const f = run({
    '20260921000000_fake_in_comment.sql': [
      '/*',
      '-- source-authority: 2.34',
      '*/',
      '  alter table coldlion.prod_detail add constraint pd_mg unique (mg_category);',
    ].join('\n'),
  });
  assert.equal(f.length, 1, 'a citation inside a block comment is not a citation');
  assert.match(f[0], /carries no "-- source-authority:" line/);
});

test('H3: refuses dropping the schema when it is not the first name listed', () => {
  const f = run({
    '20260921000000_drop_schemas.sql': 'drop schema public, coldlion cascade;',
  });
  assert.equal(f.length, 1, 'the guarded schema must be found anywhere in the name list');
});

test('M1: an escape string with an escaped quote does not swallow the rest of the file', () => {
  const f = run({
    '20260921000000_estring.sql': [
      "insert into coldlion.prod_detail (note) values (E'it\\'s fine');",
      'alter table coldlion.prod_detail add constraint pd_line unique (prod_order_no);',
    ].join('\n'),
  });
  assert.equal(f.length, 1, 'the identity claim after an E-string must still be seen');
});

test('M4: a citation naming several ids is checked against EVERY id', () => {
  // 2.34 is settled and 2.36 is open in the fixture register. Citing both must
  // refuse: the settled one does not excuse the open one.
  const f = run({
    '20260921000000_multi.sql': [
      '-- source-authority: 2.34 and 2.36',
      'alter table coldlion.prod_detail add constraint pd_line unique (prod_order_no);',
    ].join('\n'),
  });
  assert.equal(f.length, 1);
  assert.match(f[0], /cites 2\.36, which is still OPEN/);
});

test('M4: the guard exits 0, 1 and 2 as branch protection observes them', async () => {
  const { spawnSync } = await import('node:child_process');
  const script = join(dirname(fileURLToPath(import.meta.url)), 'check-vendor-identity-authority.mjs');
  const spawn = (dir) =>
    spawnSync(process.execPath, [script], { env: { ...process.env, VENDOR_AUTHORITY_ROOT: dir }, encoding: 'utf8' });

  const clean = repo({ '20260921000000_ok.sql': 'alter table public.t add constraint u unique (a);' });
  const dirty = repo({
    '20260921000000_bad.sql': 'alter table coldlion.prod_detail add constraint pd unique (a);',
  });
  const broken = repo({}, { config: null });
  try {
    const ok = spawn(clean);
    assert.equal(ok.status, 0, 'a clean tree must exit 0');
    assert.match(ok.stdout, /vendor identity authority OK/);

    const bad = spawn(dirty);
    assert.equal(bad.status, 1, 'a refused migration must exit 1');
    assert.match(bad.stderr, /without a settled source authority/);

    const cannot = spawn(broken);
    assert.equal(cannot.status, 2, 'an unreadable input must exit 2, never 0');
    assert.match(cannot.stderr, /could not run/);
  } finally {
    for (const d of [clean, dirty, broken]) rmSync(d, { recursive: true, force: true });
  }
});

test('M4: the documented ENTRY_ID over-match is real and fails closed', () => {
  // `1.2` in prose is harvested as an entry id. That is intended: an id the
  // register does not carry is refused, so over-matching cannot pass anything.
  const f = run({
    '20260921000000_overmatch.sql': [
      '-- source-authority: see section 1.2 of the vendor note',
      'alter table coldlion.prod_detail add constraint pd unique (a);',
    ].join('\n'),
  });
  assert.equal(f.length, 1);
  assert.match(f[0], /cites 1\.2, which is not an entry/);
});

test('H4: a settled leading word in the QUESTION cell does not settle an open row', () => {
  const register = [
    '| id | question | who | evidence | status |',
    '|---|---|---|---|---|',
    '| 2.50 | Answered for the other endpoint - this one still needs a vendor reply | vendor contact | - | awaiting reply |',
    '',
  ].join('\n');
  assert.equal(registerEntryIsOpen(register, '2.50').open, true, 'only the status cell settles a row');
});

test('H4: a mixed-case open marker leading the status cell keeps the row open', () => {
  const register = [
    '| id | question | who | evidence | status |',
    '|---|---|---|---|---|',
    '| 2.51 | what identifies a row? | vendor contact | - | Waiting on the vendor. |',
    '',
  ].join('\n');
  assert.equal(registerEntryIsOpen(register, '2.51').open, true);
});

test('a status cell settles on its VERDICT, not on its typography', () => {
  // Both of these are real, recorded revisions of entry 2.36's status cell. The
  // first is how it read when this guard was written; the second is how `main`
  // reworded it a day later. Nothing about the entry changed — the identity
  // question was answered on 2026-09-29 either way — so both must read settled.
  //
  // This test exists because the shouted-only version of the test passed
  // locally and failed in CI, for exactly that reason: the branch carried the
  // older wording and CI tested against the newer one. The failure looked like
  // a platform difference and was not.
  const shouted =
    '**Identity and shape treatment ANSWERED 2026-09-29 — do not re-ask.** ' +
    'Q5 factory-cost still open (they asked us to elaborate). Q4 cancelled-qty use Unknown.';
  const sentenceCase =
    '**Fully answered 2026-09-29 (identity + cost). Do not re-ask.** ' +
    'Owner ruling recorded the same day. Q4 cancelled-qty use remains soft Unknown only.';
  for (const status of [shouted, sentenceCase]) {
    const register = ['| id | status |', '|---|---|', `| 2.60 | ${status} |`, ''].join('\n');
    assert.equal(
      registerEntryIsOpen(register, '2.60').open,
      false,
      `a verdict that answers the question must settle it: ${status.slice(0, 48)}…`,
    );
  }
});

test('a trailing caveat does not settle a cell whose verdict is open', () => {
  // The mirror image of the test above. Reading only the opening verdict must
  // not become a way to bury an open status behind a settled-sounding caveat.
  const register = [
    '| id | status |',
    '|---|---|',
    '| 2.61 | **Still waiting on the vendor.** The neighbouring question was answered 2026-09-29. |',
    '',
  ].join('\n');
  assert.equal(registerEntryIsOpen(register, '2.61').open, true);
});

test('H3: identity DDL built as a string and EXECUTEd is refused', () => {
  // The ordinary idiom for idempotent DDL. Round 3 opened up dollar-quoted
  // bodies but left their string literals blanked, so this file had no
  // `coldlion.` and no `unique` anywhere the guard looked and printed OK.
  const f = run({
    '20260921000000_execute.sql': [
      'do $$ begin',
      "  if not exists (select 1 from pg_constraint where conname = 'pd_line_key') then",
      "    execute 'alter table coldlion.prod_detail add constraint pd_line_key unique (prod_order_no)';",
      '  end if;',
      'end $$;',
    ].join('\n'),
  });
  assert.equal(f.length, 1, 'dynamic identity DDL must be refused');
  assert.match(f[0], /carries no "-- source-authority:" line/);
});

test('H3: scanning string literals is deliberately over-broad, and that is the safe direction', () => {
  // The cost of the fix above: a migration that merely MENTIONS a guarded table
  // and a uniqueness keyword inside DATA is now asked for a header it does not
  // strictly need. This test pins that as an accepted trade-off rather than
  // leaving it as a surprise. A false refusal costs one header line; the false
  // pass this replaces cost nine production orders.
  const f = run({
    '20260921000000_note.sql':
      "insert into coldlion.ingest_note (text) values ('we must not add a unique constraint here');",
  });
  assert.equal(f.length, 1, 'over-refusal is the documented, intended behaviour');
});

test('prose in a COMMENT still does not trip the identity test', () => {
  // Comments are stripped whether or not they sit inside a dollar-quoted body,
  // so the over-breadth above is bounded to string literals.
  const f = run({
    '20260921000000_notice.sql': [
      'do $$ begin',
      '  -- we will not add a unique constraint here',
      '  /* nor a primary key */',
      '  update coldlion.prod_detail set note = 1;',
      'end $$;',
    ].join('\n'),
  });
  assert.deepEqual(f, [], 'prose about uniqueness in a comment is not a uniqueness claim');
});

test('H2: refuses an EXCLUDE constraint written without USING', () => {
  // `using <method>` is optional and defaults to gist, so the covered spelling
  // and the uncovered one were one word apart.
  const f = run({
    '20260921000000_excl.sql':
      'alter table coldlion.prod_detail add constraint pd_excl exclude (prod_order_no with =);',
  });
  assert.equal(f.length, 1, 'EXCLUDE without USING enforces uniqueness just the same');
});

test('M2: a WITHDRAWN or SUPERSEDED entry is not a settled authority', () => {
  // A withdrawn question is one the vendor never answered.
  for (const status of ['Withdrawn.', 'Superseded by 2.90.']) {
    const register = ['| id | status |', '|---|---|', `| 2.70 | ${status} |`, ''].join('\n');
    assert.equal(registerEntryIsOpen(register, '2.70').open, true, `${status} is not an answer`);
  }
});

test('M3: a row written without a trailing pipe is read on its real status cell', () => {
  // `slice(1, -1)` dropped the last cell, handing the status test the cell
  // before it -- which said "Closed" while the real status said otherwise.
  const register = [
    '| id | question | status',
    '|---|---|---',
    '| 2.80 | Closed for the other endpoint | awaiting reply',
    '',
  ].join('\n');
  assert.equal(registerEntryIsOpen(register, '2.80').open, true);
});

test('M6: an empty migrations tree refuses rather than printing OK', () => {
  // An empty tree is the same claim as an absent one: the guard looked at
  // nothing. Reporting OK would be a pass earned by examining no files.
  assert.throws(() => run({}), /examined nothing/);
});

test('H1: a settled word plus a lower-case open marker in one cell reads OPEN', () => {
  // The settled test was case-insensitive and read the whole verdict while the
  // open test was case-sensitive or first-word-only, so these read SETTLED.
  // Both tests now read the same span.
  for (const status of [
    'Closed, awaiting reply.',
    'Still waiting on the vendor; the neighbouring question was answered 2026-09-29.',
    'Resolved for shape A only - pending the vendor on shape B.',
  ]) {
    const register = ['| id | status |', '|---|---|', `| 2.90 | ${status} |`, ''].join('\n');
    assert.equal(
      registerEntryIsOpen(register, '2.90').open,
      true,
      `an unanswered status must stay open: ${status}`,
    );
  }
});

test('H1: bolding the verdict does not change whether an open marker is seen', () => {
  // The typography dependence, in the direction that matters. The bolded and
  // unbolded forms of one status must classify alike.
  const sentence = 'Still waiting on the vendor.';
  const tail = ' The neighbouring question was answered 2026-09-29.';
  const bolded = registerEntryIsOpen(
    ['| id | status |', '|---|---|', `| 2.91 | **${sentence}**${tail} |`, ''].join('\n'),
    '2.91',
  ).open;
  const plain = registerEntryIsOpen(
    ['| id | status |', '|---|---|', `| 2.91 | ${sentence}${tail} |`, ''].join('\n'),
    '2.91',
  ).open;
  assert.equal(bolded, true, 'the bolded form must read open');
  assert.equal(plain, bolded, 'bolding must not change the verdict');
});

test('a negated settled word keeps the entry open even with no listed open marker', () => {
  // The enumerated open-marker veto only knows the words somebody listed. This
  // reads the negation itself, and it is load-bearing: an earlier edit dropped
  // it and left "Closed with no answer." reading SETTLED, which the fifth
  // review noticed as dead code rather than as a behaviour change.
  for (const status of ['Closed with no answer.', 'Resolved with no reply from the vendor.']) {
    const register = ['| id | status |', '|---|---|', `| 2.95 | ${status} |`, ''].join('\n');
    assert.equal(registerEntryIsOpen(register, '2.95').open, true, status);
  }
});

// ---------------------------------------------------------------------------
// Round 7. The scanners get DIRECT tests here, not only whole-migration ones.
// Every assertion in the suite used to go through `check`, which is exactly how
// a dead-but-load-bearing veto survived a green 67-test run.
// ---------------------------------------------------------------------------

test('H1: refuses an EXCLUDE constraint written across a line break', () => {
  // The EXCLUDE alternative ended in `(` and the shared trailing \b then
  // demanded a word character after the parenthesis. Both earlier tests put a
  // column name there, so the suite was green over a real fail-open.
  const f = run({
    '20260921000000_excl_multiline.sql': [
      'alter table coldlion.prod_detail',
      '  add constraint pd_excl exclude (',
      '    prod_order_no with =,',
      '    prod_line_seq with =',
      '  );',
    ].join('\n'),
  });
  assert.equal(f.length, 1, 'a line break must not hide an exclusion constraint');
});

test('H2: refuses identity DDL whose schema name is a separate format argument', () => {
  // `format('%I.%I', 'coldlion', 'prod_detail')` never writes `coldlion.`, so
  // requiring the dot skipped the file before the identity test.
  const f = run({
    '20260921000000_format.sql': [
      'do $$ begin',
      "  execute format('alter table %I.%I add constraint u unique (%I)',",
      "    'coldlion', 'prod_detail', 'prod_order_no');",
      'end $$;',
    ].join('\n'),
  });
  assert.equal(f.length, 1, 'a split qualified name is still the guarded schema');
});

test('H2: refuses identity DDL reached through a psql variable', () => {
  const f = run({
    '20260921000000_psqlvar.sql': ['\\set sch coldlion', 'alter table :sch.prod_detail add constraint u unique (a);'].join('\n'),
  });
  assert.equal(f.length, 1);
});

test('M2: a migration whose name has no 14-digit version refuses instead of being skipped', () => {
  // `2026-09-30_x.sql` yields stamp `2026-09-30`, and `-` sorts below `0`, so
  // the file was skipped in silence -- an unreadable input treated as a pass.
  assert.throws(
    () => run({ '2026-09-30_identity.sql': 'alter table coldlion.prod_detail add constraint u unique (a);' }),
    /does not begin with a 14-digit version/,
  );
});

test('M3: a U& literal with an escaped quote does not swallow the rest of the file', () => {
  const f = run({
    '20260921000000_ustring.sql': [
      "insert into coldlion.prod_detail (note) values (U&'don\\'t');",
      'alter table coldlion.prod_detail add constraint u unique (prod_order_no);',
    ].join('\n'),
  });
  assert.equal(f.length, 1, 'the identity claim after a U& literal must still be seen');
});

test('M4: unlisted open vocabulary that IS listed now keeps the entry open', () => {
  for (const status of ['Closed. On hold with the vendor.', 'Closed. Escalated, no word from the vendor.']) {
    const register = ['| id | status |', '|---|---|', `| 2.96 | ${status} |`, ''].join('\n');
    assert.equal(registerEntryIsOpen(register, '2.96').open, true, status);
  }
});

test('M5: stripSql is tested directly, not only through check', () => {
  // Line comments, nested block comments, dollar bodies and the three string
  // forms, asserted on the scanner itself.
  assert.match(stripSql('select 1; -- unique\n'), /^select 1;\s+$/m);
  assert.doesNotMatch(stripSql('/* a /* b */ unique */ select 1;'), /unique/i);
  assert.doesNotMatch(stripSql("do $$ unique $$;"), /unique/i, 'blanked by default');
  assert.match(stripSql('do $$ unique $$;', { keepDollar: true }), /unique/i, 'scanned under keepDollar');
  assert.doesNotMatch(stripSql("select 'unique';"), /unique/i, 'a string is data by default');
  assert.match(stripSql("select 'unique';", { keepStrings: true }), /unique/i);
  assert.match(stripSql('select "coldlion"."t";'), /coldlion/i, 'a quoted identifier is a name, not data');

  // Newlines survive every blanking path, so offsets stay comparable.
  for (const sql of ['/*\na\n*/x', "do $$\na\n$$;", "select '\na\n';"]) {
    assert.equal(
      stripSql(sql).split('\n').length,
      sql.split('\n').length,
      `line count must survive: ${JSON.stringify(sql)}`,
    );
  }
});

test('M5: lineCommentStarts reports only genuine line comments', () => {
  const sql = [
    '/* -- not a comment, it is inside a block */',
    "select 'x -- not a comment either';",
    'do $$ -- inside a body, not a header $$;',
    '-- a real one',
  ].join('\n');
  const starts = lineCommentStarts(sql);
  assert.equal(starts.length, 1, 'exactly one genuine line comment');
  assert.ok(sql.slice(starts[0]).startsWith('-- a real one'));

  // And it agrees with stripSql about where constructs end.
  assert.deepEqual(lineCommentStarts('-- one\n-- two'), [0, 7]);
});

test('M5: both scanners agree that a dollar tag inside a string is not a close', () => {
  const sql = "do $$ begin raise notice 'x $$ y'; end $$;\n-- source-authority: 2.34";
  assert.equal(lineCommentStarts(sql).length, 1, 'the header after the body is still found');
  assert.deepEqual(sourceAuthorityHeaders(sql), ['2.34']);
});

test('a distinctly tagged body may contain $$ without closing early', () => {
  // This is the VALID way to write a body containing `$$`, and the reason the
  // earlier version of this test was wrong. Dollar quoting has no escapes: a
  // bare `$$` inside a `$$`-tagged body really does close it, so such SQL is
  // invalid and asserting guard behaviour on it asserted nothing. With a
  // distinct tag the body is intact, and a header after it is a header.
  const f = run({
    '20260921000000_tagged.sql': [
      'create function coldlion.f() returns void language plpgsql as $body$',
      "begin raise notice 'cost $$ per unit'; end",
      '$body$;',
      '-- source-authority: 2.34',
      'alter table coldlion.prod_detail add constraint pd_mg unique (mg_category);',
    ].join('\n'),
  });
  assert.deepEqual(f, [], 'a genuine header after a distinctly tagged body must count');
});

test('an identity claim inside a distinctly tagged body is still refused', () => {
  const f = run({
    '20260921000000_tagged_claim.sql': [
      'create function coldlion.f() returns void language sql as $body$',
      "  -- $$ is just text in here",
      '  alter table coldlion.prod_detail add constraint pd unique (prod_order_no);',
      '$body$;',
    ].join('\n'),
  });
  assert.equal(f.length, 1);
});

test('an unterminated string literal is bounded to its own line, not to end of file', () => {
  // One stray quote used to blank the whole remaining migration, hiding every
  // later identity claim. Reachable from real SQL via an early-closed body.
  const f = run({
    '20260921000000_stray_quote.sql': [
      "insert into coldlion.note (t) values ('oops;",
      'alter table coldlion.prod_detail add constraint pd unique (prod_order_no);',
    ].join('\n'),
  });
  assert.equal(f.length, 1, 'the claim on the next line must still be seen');
});
