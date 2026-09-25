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

import { readFileSync, readdirSync, existsSync } from 'node:fs';
import { join } from 'node:path';

const ROOT = process.env.VENDOR_AUTHORITY_ROOT ?? process.cwd();
const CONFIG = join(ROOT, 'config/vendor-landing-authority.json');
const MIGRATIONS = join(ROOT, 'supabase/migrations');
const HEADER = /^\s*--\s*source-authority:\s*(.+?)\s*$/im;

// An identity claim: a uniqueness or primary-key assertion, or the removal of
// one. Comments are stripped first so prose about a constraint never trips it.
const IDENTITY = /\b(unique\s*\(|add\s+constraint\s+\S+\s+unique|primary\s+key|drop\s+constraint|create\s+unique\s+index)/i;

function stripSql(sql) {
  return sql.replace(/\/\*[\s\S]*?\*\//g, ' ').replace(/^\s*--.*$/gm, ' ');
}

/**
 * An open-questions register entry is OPEN unless its own row says it was
 * answered, closed, withdrawn, resolved or cleared. Conservative on purpose:
 * an entry this parser cannot classify counts as open, so an ambiguous
 * citation fails loudly rather than passing quietly.
 */
export function registerEntryIsOpen(registerText, id) {
  const rows = registerText.split('\n').filter((l) => l.trim().startsWith('|'));
  const row = rows.find((l) => {
    const first = l.split('|')[1];
    return first !== undefined && first.trim() === id;
  });
  if (row === undefined) return { found: false, open: true };
  const settled = /\b(ANSWERED|CLOSED|WITHDRAWN|RESOLVED|CLEARED|SUPERSEDED)\b/.test(row);
  return { found: true, open: !settled };
}

export function check(root = ROOT) {
  const configPath = join(root, 'config/vendor-landing-authority.json');
  if (!existsSync(configPath)) throw new Error(`no config at ${configPath}`);
  const config = JSON.parse(readFileSync(configPath, 'utf8'));
  const schemas = Object.keys(config.schemas ?? {});
  if (schemas.length === 0) throw new Error('config names no vendor landing schemas');
  const migrationsDir = join(root, 'supabase/migrations');
  if (!existsSync(migrationsDir)) return [];
  const failures = [];

  for (const name of readdirSync(migrationsDir).sort()) {
    if (!name.endsWith('.sql')) continue;
    const stamp = name.split('_')[0];
    // Migrations older than the guard cannot be edited to add a citation, and
    // rewriting applied history is itself forbidden here.
    if (stamp < String(config.activation_migration)) continue;
    const raw = readFileSync(join(migrationsDir, name), 'utf8');
    const body = stripSql(raw);
    const touched = schemas.filter((s) => body.toLowerCase().includes(`${s.toLowerCase()}.`));
    if (touched.length === 0) continue;
    if (!IDENTITY.test(body)) continue;

    const cited = HEADER.exec(raw);
    if (cited === null) {
      failures.push(
        `${name}: changes an identity constraint on vendor landing schema(s) ` +
          `${touched.join(', ')} but carries no "-- source-authority:" line. ` +
          `A uniqueness or primary-key claim on a landing table is a claim about ` +
          `${touched.map((s) => config.schemas[s].vendor).join('/')} data. Name where the vendor said it — ` +
          `an answered entry id in the register, or an owner ruling.`,
      );
      continue;
    }
    const citation = cited[1];
    for (const schema of touched) {
      const registerPath = join(root, config.schemas[schema].register);
      if (!existsSync(registerPath)) {
        failures.push(`${name}: cites authority but ${config.schemas[schema].register} does not exist`);
        continue;
      }
      const register = readFileSync(registerPath, 'utf8');
      for (const id of citation.match(/\b\d+\.\d+\b/g) ?? []) {
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
