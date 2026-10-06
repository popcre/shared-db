// Rotation plan v10 self-tests: one runnable file covering every helper's
// documented behavior, including failure cases. Committed to the reviewed
// branch; the plan's §7 records its verbatim output. No secrets touched.
import { spawnSync } from 'node:child_process';
import { mkdtempSync, writeFileSync, readFileSync, rmSync, mkdirSync } from 'node:fs';
import { join, sep } from 'node:path';
import { tmpdir, homedir } from 'node:os';
import { createHash } from 'node:crypto';

const here = new URL('.', import.meta.url).pathname.replace(/^\/([A-Za-z]:)/, '$1');
const results = [];
function check(name, pass, detail = '') {
  results.push(`${pass ? 'PASS' : 'FAIL'} ${name}${detail ? ' — ' + detail : ''}`);
}
function run(args, env = {}, opts = {}) {
  return spawnSync('node', [join(here, args[0]), ...args.slice(1)], {
    encoding: 'utf8', env: { ...process.env, ...env }, timeout: opts.timeout ?? 60000, ...opts,
  });
}

// probe.mjs
const base = { PGHOST: undefined, PGPORT: undefined, PGUSER: undefined, PGDATABASE: undefined, PGPASSWORD: undefined };
let r = run(['probe.mjs']);
check('probe no-env → ERR MISSING-ENV exit 4', r.stdout.includes('ERR MISSING-ENV') && r.status === 4);
const pg = { ...base, PGHOST: 'h', PGPORT: '1', PGUSER: 'u', PGDATABASE: 'd', PGPASSWORD: 'x' };
// MISSING-CA: hold the bundle aside for the duration of this one probe.
const caPath = join(homedir(), '.tmp-rotation', 'rds-global-bundle.pem');
const heldPath = caPath + '.held';
let held = false;
try { renameSync(caPath, heldPath); held = true; } catch { /* already absent */ }
try {
  r = run(['probe.mjs'], pg);
  check('probe PG*+no-CA → MISSING-CA exit 4', r.stdout.includes('ERR MISSING-CA') && r.status === 4);
} finally {
  if (held) renameSync(heldPath, caPath);
}
const t0 = Date.now();
r = run(['probe.mjs'], { ...pg, PGHOST: '10.255.255.1' }, { timeout: 40000 });
const secs = ((Date.now() - t0) / 1000).toFixed(1);
check(`probe hang-host → exit 4 within deadline (${secs}s)`, r.status === 4 && Date.now() - t0 < 25000, r.stdout.trim());

// gen.mjs: label required, overwrite refused, 40 bytes, fingerprint reproducible.
r = run(['gen.mjs']);
check('gen no-label → usage exit 2', r.status === 2);
r = run(['gen.mjs', 'selftest-a']);
const vf = join(homedir(), '.tmp-rotation', 'value-selftest-a.txt');
const bytes = readFileSync(vf);
check('gen writes exactly 40 bytes', bytes.length === 40);
const val = bytes.toString('utf8');
check('gen alphabet constrained', /^[A-Za-z0-9._~-]{40}$/.test(val));
const fp = r.stdout.match(/fingerprint ([0-9a-f]{16})/)[1];
const mine = createHash('sha256').update(val).digest('hex').slice(0, 16);
check('gen fingerprint reproducible', fp === mine);
r = run(['gen.mjs', 'selftest-a']);
check('gen overwrite refused exit 2', r.status === 2 && String(r.stderr).includes('refusing to overwrite'));
rmSync(vf, { force: true });

// closure.mjs: digest stable; unresolvable dependency fails closed (synthetic tree).
r = run(['closure.mjs']);
const d1 = r.stdout.match(/pg-closure-digest: ([0-9a-f]{64}) \((\d+) files, (\d+) packages\)/);
check('closure prints digest+counts', r.status === 0 && Boolean(d1), r.stdout.trim().slice(0, 80));
r = run(['closure.mjs']);
check('closure digest stable across runs', r.stdout.includes(d1[1]));
// synthetic: a package whose dependency cannot resolve → nonzero + named.
const t = mkdtempSync(join(tmpdir(), 'closure-neg-'));
const nm = join(t, 'node_modules');
mkdirSync(join(nm, 'pg'), { recursive: true });
writeFileSync(join(nm, 'pg', 'package.json'), JSON.stringify({ name: 'pg', dependencies: { ghost: '1.0.0' } }));
const negSrc = join(t, 'closure-copy.mjs');
writeFileSync(negSrc, readFileSync(join(here, 'closure.mjs'), 'utf8')
  .replace('C:/repos/dflow_plm/designflow-item-master/node_modules', nm.split(sep).join('/')));
const neg = spawnSync('node', [negSrc], { encoding: 'utf8', timeout: 30000 });
check('closure unresolvable dep → nonzero naming it', neg.status !== 0 && String(neg.stderr).includes('ghost'), String(neg.stderr).trim().slice(0, 90));
rmSync(t, { recursive: true, force: true });

// sanitize.mjs: none, credential, boundary-crossing credential.
const tmp = mkdtempSync(join(tmpdir(), 'san-'));
const p1 = join(tmp, 'a.json'); writeFileSync(p1, 'not json');
r = run(['sanitize.mjs', '200', p1]);
check('sanitize unreadable body → 200 (none)', r.stdout.trim() === '200 (none)');
const p2 = join(tmp, 'b.json'); writeFileSync(p2, JSON.stringify({ message: 'ok ' + 'CREDENTIALTOKEN0123456789abcdef' }));
r = run(['sanitize.mjs', '200', p2]);
check('sanitize credential → [redacted]', r.stdout.includes('[redacted]') && !r.stdout.includes('CREDENTIALTOKEN'));
const p3 = join(tmp, 'c.json'); writeFileSync(p3, JSON.stringify({ message: 'x'.repeat(290) + ' SECRETcredential0123456789abcdefghij' }));
r = run(['sanitize.mjs', '422', p3]);
check('sanitize boundary credential fully redacted', !r.stdout.includes('SECRETcredential') && r.stdout.includes('[redacted]'));
rmSync(tmp, { recursive: true, force: true });

console.log(results.join('\n'));
const failed = results.filter((x) => x.startsWith('FAIL')).length;
console.log(`\n${results.length - failed}/${results.length} passed`);
process.exit(failed === 0 ? 0 : 1);
