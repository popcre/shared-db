// Derives pg's runtime dependency closure using Node's OWN module resolution
// from inside the pg package directory (createRequire.resolve with paths), so
// NESTED node_modules layouts resolve exactly as require() would at runtime —
// a hoisted-only walk can miss nested copies and let runtime code escape the
// digest (2026-10-06 plan-review round 15, High). Walks transitively with a
// visited set, fails closed (exit nonzero, naming it) when a dependency
// cannot be RESOLVED, and prints one deterministic digest over every file
// under pg + the resolved closure (paths relative to node_modules, forward
// slashes; nested packages hash under their nested relative path, so the
// digest follows the code that actually loads).
import { createHash } from 'node:crypto';
import { readdirSync, readFileSync, existsSync } from 'node:fs';
import { dirname, join, relative, sep, resolve } from 'node:path';
import { createRequire } from 'node:module';
import { pathToFileURL, fileURLToPath } from 'node:url';

const root = resolve('C:/repos/dflow_plm/designflow-item-master/node_modules');
const pgDir = join(root, 'pg');

function fail(msg) {
  console.error(msg);
  process.exit(1);
}

// Resolve one dependency to its package directory the way require() would
// from inside the requesting package — this is what makes nested
// node_modules/layouts resolve identically to runtime.
function resolveDep(name, fromDir) {
  const req = createRequire(pathToFileURL(join(fromDir, 'package.json')));
  let entry;
  try {
    // Resolve the package MAIN entry (always exported); '<name>/package.json'
    // fails on modern exports-mapped packages.
    entry = req.resolve(name);
  } catch (err) {
    throw new Error(`unresolvable dependency: ${name} (required from ${relative(root, fromDir) || 'pg'}): ${err.message}`);
  }
  // Walk up from the entry to the package root: the nearest package.json
  // whose `name` matches (falls back to the nearest one), staying inside
  // node_modules boundaries.
  let dir = dirname(entry);
  for (;;) {
    const pj = join(dir, 'package.json');
    if (existsSync(pj)) {
      try {
        if (JSON.parse(readFileSync(pj, 'utf8')).name === name) return resolve(dir);
      } catch { /* keep walking */ }
    }
    const parent = dirname(dir);
    if (parent === dir || dir === root) {
      return fail(`could not locate package root for ${name} from ${entry}`);
    }
    dir = parent;
  }
}

const dirs = new Set([pgDir]);
// Visit key is the RESOLVED DIRECTORY, not the dependency name: two packages
// may depend on different versions of X resolved to different directories,
// and both copies are runtime-loadable — a name-keyed set would hash only
// the first (round 16, High). optionalDependencies are hashed when
// installed (an installed optional dep loads on matching platforms) and
// skipped silently only when absent, which is the one fail-open direction
// npm itself defines.
const visitedDirs = new Set([pgDir]);
const queue = [pgDir];
while (queue.length > 0) {
  const dir = queue.shift();
  let pkg;
  try {
    pkg = JSON.parse(readFileSync(join(dir, 'package.json'), 'utf8'));
  } catch {
    fail(`unreadable package.json in ${relative(root, dir)}`);
  }
  const required = Object.keys(pkg.dependencies ?? {});
  const optional = Object.keys(pkg.optionalDependencies ?? {});
  for (const dep of required) {
    let depDir;
    try { depDir = resolveDep(dep, dir); } catch (e) { fail(e.message); }
    if (visitedDirs.has(depDir)) continue;
    visitedDirs.add(depDir);
    dirs.add(depDir);
    queue.push(depDir);
  }
  for (const dep of optional) {
    let depDir;
    try {
      depDir = resolveDep(dep, dir);
    } catch {
      continue; // absent optional dependency: not installed, not loadable
    }
    if (visitedDirs.has(depDir)) continue;
    visitedDirs.add(depDir);
    dirs.add(depDir);
    queue.push(depDir);
  }
}

const files = [];
function walk(d) {
  for (const e of readdirSync(d, { withFileTypes: true })) {
    const p = join(d, e.name);
    if (e.isDirectory()) walk(p);
    else files.push(p);
  }
}
for (const dir of dirs) walk(dir);
files.sort();
if (files.length === 0) fail('empty closure — nothing hashed');
const lines = files.map((f) => relative(root, f).split(sep).join('/') + ':' + createHash('sha256').update(readFileSync(f)).digest('hex'));
const digest = createHash('sha256').update(lines.join('\n')).digest('hex');
console.log('pg-closure-digest:', digest, `(${files.length} files, ${dirs.size} packages)`);
