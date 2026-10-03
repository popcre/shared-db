#!/usr/bin/env node
// Guard: an identity constraint on a VENDOR LANDING table must cite a source
// authority, and that authority must not be an open question.
//
// Why this exists. On 2026-09-15 a session measured 166 rows of ColdLion's
// /proddetails feed, found (prodOrderNo, prodLineSeq) unique in that sample,
// and asserted it as a unique constraint. It is not true of the population:
// the 2026-09-17 backfill hit rows that share a line number, and nine
// production orders stopped landing. ColdLion had never been asked. The
// answer register (docs/coldlion-open-questions.md) was never opened — the
// only prodLineSeq answer on record is about a DIFFERENT endpoint, where the
// line number alone was never a row identity either.
//
// A landing table records what a vendor sent. Saying "these columns are
// unique" is a claim about the vendor's data, not about ours, so it needs the
// vendor's word. This guard refuses the migration unless it names where that
// word is written, and refuses a citation that points at a question still
// waiting for an answer.
//
//   node scripts/check-vendor-identity-authority.mjs
//
// Offline and deterministic: no network, no database, no secrets.
//
// EVERY unreadable input is a refusal, never a pass. Two governed reviews of
// PR #3389 found the opposite: a missing migrations directory returned "OK",
// and a missing or misspelled `activation_migration` compared every stamp
// against the string "undefined", skipped every file, and printed "OK" while
// checking nothing. A guard that switches itself off on a config typo and
// still reports green is worse than no guard, because the green is believed.

import { readFileSync, readdirSync, existsSync, statSync } from 'node:fs';
import { join, resolve, sep } from 'node:path';

const ROOT = process.env.VENDOR_AUTHORITY_ROOT ?? process.cwd();

// An identity claim: a uniqueness or primary-key assertion, or the removal of
// one. Comments and string literals are stripped first so prose about a
// constraint never trips it.
//
// The first version of this list enumerated shapes (`unique (`,
// `add constraint <name> unique`, …) and the governed review of PR #3389 named
// five ways straight past it: an UNNAMED `add unique nulls not distinct (c)`,
// a column-level `c text unique` with no parenthesis, a `drop index` on a
// unique index, a `create table … (like other including constraints)` that
// copies the constraints without naming one, and an `exclude using` that
// enforces the same property under a different keyword. A guard that has to be
// complete cannot be a list of the shapes somebody happened to think of, so
// `unique` is matched as a bare keyword — every spelling of it contains it.
// `\b` keeps it off `unique_key` and similar identifiers.
//
// The second review named the REMOVAL direction, which is the direction of the
// actual incident and which the job header claims to cover: `drop column`,
// `drop table` and `drop schema` each destroy an identity constraint without
// containing any of the words above. They are matched too.
//
// A false positive here costs one header line; a false negative cost nine
// production orders.
const IDENTITY = new RegExp(
  `\\b(${[
    'unique', // every UNIQUE form: constraint, column-level, index, NULLS NOT DISTINCT
    'primary\\s+key',
    'drop\\s+constraint',
    'drop\\s+index',
    'drop\\s+column', // takes its constraints with it
    'drop\\s+table',
    'drop\\s+schema',
    'including\\s+(?:constraints|indexes|all)', // CREATE TABLE … LIKE copies them
  ].join('|')})\\b`,
  'i',
);

// EXCLUDE gets its OWN pattern rather than an alternative inside the one above.
// As an alternative it ended in `(`, a non-word character, and the shared
// trailing `\b` then demanded a word character immediately AFTER the
// parenthesis -- so an exclusion constraint written across a line break matched
// nothing at all. Both shipped tests happened to put a column name right after
// `(`, which is exactly why a green suite proved nothing about it.
// `using <method>` is optional in PostgreSQL and defaults to gist.
const EXCLUDE_CONSTRAINT = /\bexclude\s*(?:using\s+[a-z_]+\s*)?\(/i;

function assertsIdentity(body) {
  return IDENTITY.test(body) || EXCLUDE_CONSTRAINT.test(body);
}

// A citation has to point at something a reader can go and check. Free prose
// ("trust me") satisfied the first version, because it found no entry ids and
// then checked nothing. These are the two forms that resolve to a document: a
// register entry id, or a dated owner ruling.
//
// The owner-ruling form is a SHAPE check and nothing more — nothing here can
// resolve "owner ruling 2026-09-29" to a document, so a false one passes. That
// limit is stated in the config under `_citation_forms` rather than left for a
// reader to discover. The entry-id form is the one that is actually verified.
const ENTRY_ID = /\b\d+\.\d+\b/g;
const OWNER_RULING = /\bowner\s+ruling\b[^,;]*\b\d{4}-\d{2}-\d{2}\b/i;

const HEADER_LINE = /^\s*--\s*source-authority:\s*(.+?)\s*$/i;

/**
 * Remove comments and string/identifier literals, so that only executable SQL
 * text reaches the identity and schema tests.
 *
 * A regex could not do this. The first version stripped WHOLE-LINE `--`
 * comments only, so a trailing comment after a statement survived into the body
 * and its prose was searched for `unique` and for `coldlion.` — the review
 * found a `public` migration that a trailing comment alone would have refused.
 * Stripping a trailing comment with a regex is worse: `insert into t values
 * ('a--b');` would lose the rest of its line, taking real SQL with it. So this
 * walks the text once, tracking the four quoting forms Postgres has.
 *
 * Everything removed is replaced by a space, never deleted, so token
 * boundaries — and therefore `\b` in IDENTITY — survive.
 *
 * Newlines are preserved, even inside a construct that is blanked wholesale,
 * so offsets and line numbers in the output still match the input.
 *
 * This WAS a load-bearing contract: `sourceAuthorityHeaders` used to compare the
 * raw and stripped texts line by line, and blanking a multi-line construct
 * shortened the stripped side, which both refused genuine headers and accepted
 * fake ones. That reader is gone -- header positions now come from
 * `lineCommentStarts`, which reports offsets -- so NOTHING CONSUMES line
 * alignment any more. It is kept because it costs nothing and keeps the output
 * comparable to the input, not because anything depends on it. Do not cite it as
 * a guarantee a future caller may rely on without checking.
 *
 * `keepDollar` scans a dollar-quoted body AS SQL instead of blanking it. The
 * same review found that blanking made
 * `do $$ begin alter table coldlion.prod_detail add constraint u unique (a); end $$;`
 * invisible: no `coldlion.` survived outside the quote, so the file was never
 * even tested for an identity keyword and the guard printed OK over exactly the
 * claim it exists to refuse. The identity and schema tests therefore read the
 * body; header detection still does not, because a `-- source-authority:` line
 * inside a function body is not a header on the migration.
 */
export function stripSql(sql, { keepStrings = false, keepDollar = false } = {}) {
  const text = String(sql);
  // Blank a span without changing how many lines it spans.
  const blank = (span) => span.replace(/[^\n]/g, ' ');
  const out = [];
  let i = 0;
  while (i < text.length) {
    const rest = text.slice(i);
    if (rest.startsWith('--')) {
      const end = text.indexOf('\n', i);
      const stop = end === -1 ? text.length : end;
      out.push(blank(text.slice(i, stop)));
      i = stop;
      continue;
    }
    if (rest.startsWith('/*')) {
      // Postgres block comments nest.
      let depth = 1;
      let j = i + 2;
      while (j < text.length && depth > 0) {
        if (text.startsWith('/*', j)) { depth += 1; j += 2; }
        else if (text.startsWith('*/', j)) { depth -= 1; j += 2; }
        else j += 1;
      }
      out.push(blank(text.slice(i, j)));
      i = j;
      continue;
    }
    const dollar = /^\$([A-Za-z_][A-Za-z0-9_]*)?\$/.exec(rest);
    if (dollar !== null) {
      const tag = dollar[0];
      const close = text.indexOf(tag, i + tag.length);
      const stop = close === -1 ? text.length : close + tag.length;
      if (keepDollar) {
        // The delimiters are not SQL; the body is. Recursing keeps the body's
        // own comments and string literals out of the scan, so prose such as
        // `raise notice 'add constraint u unique'` still cannot trip IDENTITY.
        const inner = close === -1 ? text.slice(i + tag.length) : text.slice(i + tag.length, close);
        out.push(blank(tag));
        out.push(stripSql(inner, { keepStrings, keepDollar }));
        if (close !== -1) out.push(blank(tag));
      } else {
        out.push(blank(text.slice(i, stop)));
      }
      i = stop;
      continue;
    }
    if (text[i] === "'" || text[i] === '"') {
      const quote = text[i];
      // Postgres escape strings (E'a\'b') treat a backslash as an escape;
      // escape; ordinary strings do not. Reading the escaped quote as a closing one
      // made the scanner run past the real end of the literal and swallow the
      // rest of the file as string content, taking any later `unique` or
      // `coldlion.` with it.
      const escapes = quote === "'" && /(^|[^A-Za-z0-9_$])(?:[eE]|[uU]&)$/.test(text.slice(0, i));
      let j = i + 1;
      let closed = false;
      while (j < text.length) {
        if (escapes && text[j] === '\\') { j += 2; continue; }
        if (text[j] === quote && text[j + 1] === quote) { j += 2; continue; }
        if (text[j] === quote) { j += 1; closed = true; break; }
        j += 1;
      }
      // An UNTERMINATED literal is bounded to its own line rather than run to
      // end of file. Running to EOF let one stray quote blank an entire
      // migration and hide every later identity claim -- reachable from valid
      // SQL, because a dollar tag written inside a literal really does close
      // the body (dollar quoting has no escapes), leaving the tail to be
      // scanned as loose text. Bounding it keeps a mis-scan from becoming a
      // silent pass.
      if (!closed) {
        const nl = text.indexOf('\n', i);
        j = nl === -1 ? text.length : nl;
      }
      // A double-quoted identifier is the object's NAME, and dropping it whole
      // would hide `"coldlion"."prod_detail"` from the schema test. Its content
      // is kept, its quotes become spaces; a single-quoted string is data and
      // goes entirely — except under `keepStrings`, which the search-path test
      // needs because `set_config('search_path', 'coldlion', …)` carries the
      // schema name inside a string literal.
      const keep = quote === '"' || keepStrings;
      out.push(keep ? ` ${text.slice(i + 1, Math.max(i + 1, j - 1))} ` : blank(text.slice(i, j)));
      i = j;
      continue;
    }
    out.push(text[i]);
    i += 1;
  }
  return out.join('');
}

/**
 * Every offset in `sql` at which a GENUINE `--` line comment begins.
 *
 * This exists because the two earlier attempts to answer "is this `--` real?"
 * both failed, in opposite directions. Round 2 ran one regex over the raw file
 * and accepted a header written inside a block comment or a function body.
 * Round 3 compared the raw and stripped texts line by line, which drifted the
 * moment any construct spanned a line, and so both refused genuine headers and
 * accepted fake ones. Neither guess is needed: the scanner already knows
 * exactly where it is, so it can simply say so.
 *
 * One scan, the same quoting rules as `stripSql`, returning offsets. A `--`
 * inside a block comment, a string, a quoted identifier or a dollar-quoted body
 * is never reported, because the scan is inside that construct when it passes
 * over it.
 */
export function lineCommentStarts(sql) {
  const text = String(sql);
  const starts = [];
  let i = 0;
  while (i < text.length) {
    if (text.startsWith('--', i)) {
      starts.push(i);
      const end = text.indexOf('\n', i);
      i = end === -1 ? text.length : end;
      continue;
    }
    if (text.startsWith('/*', i)) {
      let depth = 1;
      let j = i + 2;
      while (j < text.length && depth > 0) {
        if (text.startsWith('/*', j)) { depth += 1; j += 2; }
        else if (text.startsWith('*/', j)) { depth -= 1; j += 2; }
        else j += 1;
      }
      i = j;
      continue;
    }
    const dollar = /^\$([A-Za-z_][A-Za-z0-9_]*)?\$/.exec(text.slice(i));
    if (dollar !== null) {
      const tag = dollar[0];
      const close = text.indexOf(tag, i + tag.length);
      i = close === -1 ? text.length : close + tag.length;
      continue;
    }
    if (text[i] === "'" || text[i] === '"') {
      const quote = text[i];
      const escapes = quote === "'" && /(^|[^A-Za-z0-9_$])(?:[eE]|[uU]&)$/.test(text.slice(0, i));
      let j = i + 1;
      let closed = false;
      while (j < text.length) {
        if (escapes && text[j] === '\u005c') { j += 2; continue; }
        if (text[j] === quote && text[j + 1] === quote) { j += 2; continue; }
        if (text[j] === quote) { j += 1; closed = true; break; }
        j += 1;
      }
      // An UNTERMINATED literal is bounded to its own line rather than run to
      // end of file. Running to EOF let one stray quote blank an entire
      // migration and hide every later identity claim -- reachable from valid
      // SQL, because a dollar tag written inside a literal really does close
      // the body (dollar quoting has no escapes), leaving the tail to be
      // scanned as loose text. Bounding it keeps a mis-scan from becoming a
      // silent pass.
      if (!closed) {
        const nl = text.indexOf('\n', i);
        j = nl === -1 ? text.length : nl;
      }
      i = j;
      continue;
    }
    i += 1;
  }
  return starts;
}

/**
 * Collect every `-- source-authority:` header, reading only genuine line
 * comments.
 *
 * A file that states two DIFFERENT authorities states neither: taking the first
 * of several would hide a contradiction, which is the same defect as taking the
 * first of several register rows, and it is closed the same way.
 *
 * A header must also be the only thing on its line, or follow a completed
 * statement. `alter table t add constraint u unique (a); -- source-authority: 2.36`
 * is a citation; a `--` in the middle of an unterminated statement is a note on
 * that statement, not a header on the migration.
 */
export function sourceAuthorityHeaders(raw) {
  const text = String(raw);
  const found = [];
  for (const start of lineCommentStarts(text)) {
    const end = text.indexOf('\n', start);
    const comment = text.slice(start, end === -1 ? text.length : end);
    const match = HEADER_LINE.exec(comment);
    if (match === null) continue;
    const lineStart = text.lastIndexOf('\n', start - 1) + 1;
    const before = text.slice(lineStart, start).trim();
    if (before !== '' && !/;$/.test(before)) continue;
    found.push(match[1].trim());
  }
  return found;
}

/**
 * `set search_path = coldlion` followed by unqualified table names touches the
 * schema without the migration ever writing `coldlion.`, so the schema test
 * reads the search path too — in every spelling it has: `set`, `set local`,
 * `set session`, `=` or `to`, a comma list, and `set_config('search_path', …)`.
 */
export function setsSearchPathTo(body, schema) {
  const name = schema.toLowerCase().replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  const boundary = new RegExp(`(^|[\\s,'"])${name}($|[\\s,'"])`, 'i');
  const assignments = [
    ...body.matchAll(/\bset\s+(?:local\s+|session\s+)?"?search_path"?\s*(?:=|to)([^;]*)/gi),
    ...body.matchAll(/\bset_config\s*\(\s*'?"?\s*search_path\s*"?'?\s*,([^)]*)/gi),
  ];
  for (const match of assignments) if (boundary.test(match[1])) return true;
  return false;
}

// `drop schema coldlion cascade` and `create schema coldlion` name the schema
// with no dot after it, so neither the qualified-name test nor the search-path
// test sees them. Dropping the schema takes every identity constraint in it.
// The guarded schema name as a whole word, case-insensitive. Cached because
// `check` builds it once per migration per schema.
const schemaWordCache = new Map();
function schemaWord(schema) {
  const key = schema.toLowerCase();
  let re = schemaWordCache.get(key);
  if (re === undefined) {
    re = new RegExp(`\\b${key.replace(/[.*+?^${}()|[\]\\]/g, '\\$&')}\\b`, 'i');
    schemaWordCache.set(key, re);
  }
  return re;
}

export function namesSchemaBare(body, schema) {
  const name = schema.toLowerCase().replace(/[.*+?^${}()|[\]\\]/g, '\\$&');
  // The first version matched only the FIRST name after `schema`, so
  // `drop schema public, coldlion cascade;` named coldlion and was skipped —
  // the same enumeration-of-spellings defect the identity pattern had, one
  // layer up. Read the whole name list, the way the search-path test does.
  const boundary = new RegExp(`(^|[\\s,"])"?${name}"?($|[\\s,;"])`, 'i');
  const statements = body.matchAll(/\b(?:drop|create|alter)\s+schema\b(?:\s+if\s+(?:not\s+)?exists\b)?([^;]*)/gi);
  for (const match of statements) if (boundary.test(`${match[1]} `)) return true;
  return false;
}

/**
 * Normalise a qualified name so `coldlion.prod_detail` is recognisable however
 * it was written.
 *
 * The review found the schema test evaded by whitespace alone: SQL accepts
 * `coldlion . prod_detail` and `coldlion\n.prod_detail`, neither of which
 * contains the substring `coldlion.`. That is the same "only the spellings
 * somebody thought of" defect the identity pattern had, surviving one layer up.
 * Quotes are already removed by stripSql, so only the spacing is left to close.
 */
export function normalizeQualifiedNames(body) {
  return body.replace(/\s*\.\s*/g, '.');
}

// `DROPPED` is deliberately NOT a settled marker: entry 2.19 uses it for one
// ask that was withdrawn from an entry that stayed open, so reading it as
// settled would pass an open question.
// WITHDRAWN and SUPERSEDED are NOT here, and that is the point. A withdrawn
// question is one the vendor never answered, and a superseded one points at a
// decision that has moved; citing either as "where the vendor said it" is the
// failure this guard exists to prevent. The same reasoning already excluded
// DROPPED, and treating these three differently was an inconsistency the fifth
// review named.
const SETTLED = ['ANSWERED', 'CLOSED', 'RESOLVED', 'CLEARED'];
// Shouted in the same convention, and meaning the opposite. The list is longer
// than it was because the third review named markers it did not contain:
// WAITING, OUTSTANDING, NO REPLY, NOT YET.
//
// It stays SHOUTED (case-sensitive) on purpose. A case-insensitive row-wide
// veto was tried and it read the real register's entry 2.36 as open: that
// entry's status cell says the identity question is ANSWERED and, in the same
// breath, that a separate cost sub-question is "still open" and a cancelled-qty
// field is "Unknown". Vetoing on incidental lower-case prose would refuse every
// citation of a correctly answered entry, so the veto reads the register's own
// emphatic convention instead.
const OPEN_SHOUTED = new RegExp(
  '\\b(?:OPEN|BLOCKING|BLOCKED|SENT|AWAITING|AWAITS|PENDING|UNANSWERED|UNKNOWN|OUTSTANDING' +
    '|WAITING|TBD|UNDECIDED|UNRESOLVED|NO\\s+(?:REPLY|ANSWER|RESPONSE)' +
    '|NOT\\s+(?:ANSWERED|YET|CONFIRMED|RESOLVED))\\b',
);
// The same markers in ANY case, tested against the VERDICT span rather than
// only the cell's first word. The fifth review found the asymmetry that left:
// the settled test was case-insensitive and read the whole verdict, while the
// open test was case-sensitive or first-word-only, so
// `Closed, awaiting reply.` and
// `Still waiting on the vendor; the neighbouring question was answered 2026-09-29.`
// both read SETTLED. Both tests now read the same span, which also removes the
// typography dependence on the open side: bolding the verdict or not no longer
// changes whether an open marker is seen.
const OPEN_IN_VERDICT = new RegExp(
  '\\b(?:OPEN|BLOCKED|BLOCKING|SENT|AWAITING|AWAITS|PENDING|UNANSWERED|UNKNOWN' +
    '|OUTSTANDING|WAITING|WAIT|TBD|UNDECIDED|UNRESOLVED|ESCALATED|CHASING' +
    '|ON\\s+HOLD|IN\\s+PROGRESS|TO\\s+(?:ASK|SEND|CONFIRM)|FOLLOW(?:\\s|-)?UP' +
    '|WITH\\s+THE\\s+VENDOR|NO\\s+WORD)\\b',
  'i',
);

// A settled marker in ANY case. The shouted form alone was not enough: the real
// register wrote entry 2.36's verdict as `ANSWERED` when this guard was built
// and `Fully answered` a day later, and the shouted-only test flipped that
// citation from settled to open with no change to the guard at all. Reading the
// register's typography was the mistake; read its sentence instead.
const SETTLED_ANY = new RegExp(`\\b(?:${SETTLED.join('|')})\\b`, 'i');

// An explicitly NEGATED settled word, in any case. This is what keeps
// "the ticket was closed with no answer" open: `closed` is present, and so is
// the negation that makes it mean the opposite.
const SETTLED_NEGATED =
  /\b(?:not|never|no)\s+(?:yet\s+)?(?:been\s+)?(?:answer|answers|answered|repl(?:y|ied|ies)|response|resolved|closed|confirmed|decision)\b/i;

/**
 * The VERDICT span of a status cell: its opening statement.
 *
 * A real status cell states its verdict first and then qualifies it. Both
 * recorded revisions of entry 2.36 do exactly that — a bolded verdict, then a
 * note that one sub-question is still open and one field is Unknown. Judging
 * the whole cell therefore reads a correctly answered entry as open, because of
 * the caveats; judging only shouted words reads it as open as soon as somebody
 * rewrites the verdict in sentence case. Neither is a property of the entry.
 *
 * So: if the cell opens with a bolded run, that run is the verdict. Otherwise
 * the whole cell is. The open-marker vetoes below still read the WHOLE cell for
 * a shouted marker, so a status that shouts both still reads open.
 */
function verdictSpan(cell) {
  const text = cell.trim();
  const bold = /^\*\*([\s\S]*?)\*\*/.exec(text);
  return bold === null ? text : bold[1];
}

// A pipe-table row's cells. `slice(1, -1)` alone silently DROPPED the last real
// cell of a row written without a trailing pipe, which the fifth review found
// could hand the status test the wrong cell entirely: for
// `| 2.36 | Closed for the other endpoint | awaiting reply` it would read
// "Closed for the other endpoint" as the status. Only drop the trailing element
// when a trailing pipe actually produced it.
function cells(row) {
  const parts = row.trimEnd().split('|');
  const out = parts.slice(1);
  if (row.trimEnd().endsWith('|')) out.pop();
  return out;
}

/**
 * An open-questions register entry is OPEN unless its own row says it was
 * ANSWERED, CLOSED, RESOLVED or CLEARED. Conservative on purpose: an entry
 * this parser cannot classify counts as open, so an ambiguous citation fails
 * loudly rather than passing quietly.
 *
 * WITHDRAWN and SUPERSEDED are deliberately NOT settled -- see the SETTLED
 * list for why. This docstring said they were for one round after the code
 * stopped agreeing, which is the third time in this file that prose outlived
 * the decision it described. If you change the rule, change this paragraph in
 * the same edit.
 *
 * Ids REPEAT in this register — 2.25 through 2.32 each appear twice, once in a
 * summary table and once in the detail table below it, and the two rows do not
 * always agree (2.25's summary row says "Closed" while its detail row is still
 * waiting on ColdLion). The first version took the first row it found, which
 * made the answer depend on document order. EVERY row carrying the id must say
 * settled, so a disagreement reads as open.
 *
 * Within a single row the same discipline applies in two ways the second review
 * asked for:
 *
 *  - A shouted settled marker ANYWHERE in the row used to settle it on its own,
 *    so a row whose status cell read "SENT, awaiting reply" was settled by the
 *    word ANSWERED appearing in the question text beside it. A row that shouts
 *    a settled marker AND an open one now reads OPEN.
 *  - The VERDICT is the status cell's opening statement: its leading bolded
 *    run if it has one, otherwise the whole cell. Both the settled test and
 *    the open test read that same span, case-insensitively.
 *
 * KNOWN LIMIT, not yet closed: because the verdict span stops at the end of a
 * leading bolded run, a caveat written AFTER that run is outside it. So
 * `**Closed.** Pending the vendor on scope B.` reads settled while the same
 * sentence unbolded reads open. Bolding therefore still changes the answer.
 * Closing this properly means not parsing prose at all -- requiring the
 * register to carry an explicit machine-readable status token before an entry
 * is citable -- which is a change to the register, not only to this file.
 */
export function registerEntryIsOpen(registerText, id) {
  const rows = registerText.split('\n').filter((l) => l.trim().startsWith('|'));
  const matching = rows.filter((l) => {
    const first = l.split('|')[1];
    return first !== undefined && first.trim() === id;
  });
  if (matching.length === 0) return { found: false, open: true, rows: 0 };
  // Judge the STATUS cell, the last one in the row, and within it the opening
  // verdict rather than the whole cell. Letting ANY cell settle the row was the
  // round-2 finding reopened in round 3: a question or evidence cell that merely
  // began with "Answered…" settled an entry whose status cell did not. Scoping
  // to the status cell fixes both directions — a shouted OPEN marker in the
  // question text no longer vetoes a settled status, and a settled word in the
  // question text no longer settles an open one.
  const settled = matching.every((row) => {
    const rowCells = cells(row);
    const status = rowCells[rowCells.length - 1] ?? '';
    // A shouted open marker anywhere in the cell still vetoes: a status that
    // shouts both ANSWERED and OPEN is reporting a disagreement, not a verdict.
    if (OPEN_SHOUTED.test(status)) return false;
    const verdict = verdictSpan(status);
    if (OPEN_IN_VERDICT.test(verdict)) return false;
    // An explicitly NEGATED settled word. Without this, "Closed with no answer."
    // reads settled: `closed` is present and no enumerated open marker is. The
    // veto above only knows the words somebody listed; this one reads the
    // negation itself. Dropping it was an accident of an earlier edit that the
    // fifth review noticed as dead code.
    if (SETTLED_NEGATED.test(verdict)) return false;
    return SETTLED_ANY.test(verdict);
  });
  return { found: true, open: !settled, rows: matching.length };
}

/**
 * Read and validate the config. Every field the guard depends on is checked
 * here, because an unchecked field is a way to switch the guard off silently:
 * a missing `activation_migration` made every `stamp < "undefined"` comparison
 * true and skipped the whole tree.
 */
export function loadConfig(root) {
  const configPath = join(root, 'config/vendor-landing-authority.json');
  if (!existsSync(configPath)) throw new Error(`no config at ${configPath}`);
  let config;
  try {
    config = JSON.parse(readFileSync(configPath, 'utf8'));
  } catch (e) {
    throw new Error(`config at ${configPath} is not readable JSON: ${e.message}`);
  }
  const activation = config.activation_migration;
  if (typeof activation !== 'string' || !/^\d{14}$/.test(activation)) {
    throw new Error(
      'config activation_migration must be a 14-digit migration stamp; ' +
        `got ${JSON.stringify(activation)}. Stamps are compared as strings, so an absent or ` +
        'misspelled value would skip every migration and report a clean guard.',
    );
  }
  const schemas = Object.entries(config.schemas ?? {});
  if (schemas.length === 0) throw new Error('config names no vendor landing schemas');
  for (const [schema, entry] of schemas) {
    if (typeof entry?.register !== 'string' || entry.register.trim() === '') {
      throw new Error(`config schema ${schema} names no register`);
    }
    if (typeof entry?.vendor !== 'string' || entry.vendor.trim() === '') {
      throw new Error(`config schema ${schema} names no vendor`);
    }
    const registerPath = resolve(root, entry.register);
    if (registerPath !== resolve(root) && !registerPath.startsWith(resolve(root) + sep)) {
      throw new Error(`config schema ${schema} register ${entry.register} resolves outside the repository`);
    }
  }
  return config;
}

export function check(root = ROOT) {
  const config = loadConfig(root);
  const schemas = Object.keys(config.schemas);
  const migrationsDir = join(root, 'supabase/migrations');
  if (!existsSync(migrationsDir) || !statSync(migrationsDir).isDirectory()) {
    // Previously `return []`, which printed OK. An absent migration tree means
    // the guard could not look, and "could not look" is never "nothing wrong".
    throw new Error(`no migrations directory at ${migrationsDir}; the guard could not examine anything`);
  }
  // An EMPTY tree is the same claim as an absent one: the guard looked at
  // nothing. This repository has never had zero migrations, so an empty
  // directory means the guard is pointed somewhere wrong -- a wrong
  // VENDOR_AUTHORITY_ROOT, a partial checkout -- and reporting OK would be a
  // pass earned by examining no files at all.
  if (!readdirSync(migrationsDir).some((name) => /\.sql$/i.test(name))) {
    throw new Error(`no .sql migrations under ${migrationsDir}; the guard examined nothing`);
  }
  const failures = [];

  for (const name of readdirSync(migrationsDir).sort()) {
    if (!/\.sql$/i.test(name)) continue;
    const stamp = name.split('_')[0];
    // The config stamp is validated as 14 digits; this one was not, and the
    // same lexicographic comparison was fed whatever the file name began
    // with. `2026-09-30_x.sql` yields `2026-09-30`, and `-` sorts below `0`,
    // so the file was skipped IN SILENCE -- an unreadable input treated as a
    // pass, which this file's own header forbids.
    if (!/^\d{14}$/.test(stamp)) {
      throw new Error(
        `${name}: migration file name does not begin with a 14-digit version, so the guard cannot tell ` +
          `whether it predates the activation floor. Rename it or exclude it deliberately.`,
      );
    }
    // Migrations older than the guard cannot be edited to add a citation, and
    // rewriting applied history is itself forbidden here.
    if (stamp < config.activation_migration) continue;
    const raw = readFileSync(join(migrationsDir, name), 'utf8');
    // `keepDollar` is what makes a `do $$ ... $$` block visible here. Without it
    // the third review showed the guard printing OK over an identity constraint
    // asserted inside a PL/pgSQL body, in both directions, because nothing the
    // schema test looks for survived outside the quote.
    // EVERY test reads string literals. Dollar-quoted bodies were opened up in
    // round 3; round 5 showed that was not enough, because the ordinary idiom
    // for idempotent DDL puts the whole statement in a string:
    //
    //   do $$ begin
    //     if not exists (...) then
    //       execute 'alter table coldlion.prod_detail add constraint u unique (a)';
    //     end if;
    //   end $$;
    //
    // With strings blanked that file has no `coldlion.` and no `unique` anywhere
    // the guard looks, so it was skipped before the identity test ran and the
    // check printed OK. Scanning string content is deliberately over-broad: a
    // migration that merely MENTIONS a guarded table and a uniqueness keyword
    // inside data will now be asked for a header it may not need. That is the
    // safe direction — a false refusal costs one header line, a false pass cost
    // nine production orders — and comments are still stripped, so prose outside
    // a literal cannot trigger it.
    const body = normalizeQualifiedNames(stripSql(raw, { keepStrings: true, keepDollar: true }));
    const lowered = body.toLowerCase();
    const touched = schemas.filter(
      (s) =>
        // A bare WORD match, not `coldlion.`. Requiring the dot assumed the
        // qualified name is written in one piece, and the ordinary
        // `execute format('alter table %I.%I ...', 'coldlion', 'prod_detail')`
        // idiom never writes that two-character sequence at all -- the schema
        // name is its own string literal. Same for a psql `:sch.prod_detail`.
        // Matching the name anywhere is MUCH broader: any migration that so
        // much as mentions a guarded schema inside a literal is now examined
        // for an identity keyword. That is the accepted direction, and the
        // keyword test still has to fire before anything is refused.
        schemaWord(s).test(lowered) ||
        setsSearchPathTo(body, s) ||
        namesSchemaBare(body, s),
    );
    if (touched.length === 0) continue;
    if (!assertsIdentity(body)) continue;

    const headers = sourceAuthorityHeaders(raw);
    if (headers.length === 0) {
      failures.push(
        `${name}: changes an identity constraint on vendor landing schema(s) ` +
          `${touched.join(', ')} but carries no "-- source-authority:" line. ` +
          `A uniqueness or primary-key claim on a landing table is a claim about ` +
          `${touched.map((s) => config.schemas[s].vendor).join('/')} data. Name where the vendor said it — ` +
          `an answered entry id in the register, or an owner ruling.`,
      );
      continue;
    }
    if (new Set(headers).size > 1) {
      failures.push(
        `${name}: carries ${headers.length} "-- source-authority:" lines that do not agree ` +
          `(${headers.map((h) => `"${h}"`).join(', ')}). A file that states two authorities states neither.`,
      );
      continue;
    }
    const citation = headers[0];
    const ids = citation.match(ENTRY_ID) ?? [];
    if (ids.length === 0 && !OWNER_RULING.test(citation)) {
      // The first version checked nothing at all here, so any prose passed.
      failures.push(
        `${name}: source-authority says "${citation}", which names nothing a reader can check. ` +
          `Cite a register entry id (for example 2.36): that form is RESOLVED against the ` +
          `register and refused while the entry is still open. A dated owner ruling ` +
          `("owner ruling 2026-09-29") is accepted on its SHAPE ONLY — nothing here checks that ` +
          `the ruling exists — so prefer the entry id wherever one exists.`,
      );
      continue;
    }
    for (const schema of touched) {
      const registerPath = join(root, config.schemas[schema].register);
      if (!existsSync(registerPath)) {
        failures.push(`${name}: cites authority but ${config.schemas[schema].register} does not exist`);
        continue;
      }
      const register = readFileSync(registerPath, 'utf8');
      for (const id of ids) {
        const { found, open } = registerEntryIsOpen(register, id);
        if (!found) {
          failures.push(`${name}: source-authority cites ${id}, which is not an entry in ${config.schemas[schema].register}`);
        } else if (open) {
          failures.push(
            `${name}: source-authority cites ${id}, which is still OPEN in ` +
              `${config.schemas[schema].register}. Wait for ${config.schemas[schema].vendor} to answer before ` +
              `asserting or removing an identity constraint on their data.`,
          );
        }
      }
    }
  }
  return failures;
}

const invokedDirectly = process.argv[1] !== undefined &&
  import.meta.url.endsWith(process.argv[1].replace(/\\/g, '/').split('/').pop());
if (invokedDirectly) {
  let failures;
  try {
    failures = check();
  } catch (e) {
    console.error(`vendor identity authority guard could not run: ${e.message}`);
    process.exit(2);
  }
  if (failures.length > 0) {
    console.error('Vendor landing identity constraints without a settled source authority:\n');
    for (const f of failures) console.error(`  - ${f}\n`);
    process.exit(1);
  }
  console.log('vendor identity authority OK');
}
