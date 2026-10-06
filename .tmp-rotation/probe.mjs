// Rotation plan v10 helper: one bounded connection probe using the SAME PG*
// env transport the hardening PR landed on main. Prints OK / ERR <code> and
// never the password, URL, or any server message that could embed them.
//
// Env: PGHOST PGPORT PGUSER PGDATABASE PGPASSWORD PGSSLMODE
// Exit 0 on connect+SELECT 1; exit 3 on a classified Postgres error (28P01 is
// the only code the plan accepts as an auth-rejection proof); exit 4 on any
// transport/classification failure (TLS, DNS, timeout — these do NOT count as
// proof of anything).
import { createRequire } from 'node:module';
import { readFileSync } from 'node:fs';
import { join } from 'node:path';
import { homedir } from 'node:os';

const PG_PATH = 'C:/repos/dflow_plm/designflow-item-master/node_modules/pg';
let Client;
try {
  ({ Client } = createRequire(import.meta.url)(PG_PATH));
} catch (error) {
  console.log('ERR LOAD-PG');
  process.exit(4);
}

const required = ['PGHOST', 'PGPORT', 'PGUSER', 'PGDATABASE', 'PGPASSWORD'];
for (const name of required) {
  if (!process.env[name]) {
    console.log('ERR MISSING-ENV');
    process.exit(4);
  }
}

// Full TLS verification with the Amazon RDS global CA bundle (v9 review lesson:
// rejectUnauthorized:false was rejected; the pooler chain is Amazon-issued).
// The bundle is downloaded once during preflight; a missing bundle fails CLOSED.
const CA_BUNDLE = join(homedir(), '.tmp-rotation', 'rds-global-bundle.pem');
let ca;
try {
  ca = readFileSync(CA_BUNDLE, 'utf8');
} catch {
  console.log('ERR MISSING-CA');
  process.exit(4);
}

const client = new Client({
  host: process.env.PGHOST,
  port: Number(process.env.PGPORT),
  user: process.env.PGUSER,
  database: process.env.PGDATABASE,
  password: process.env.PGPASSWORD,
  ssl: { ca, rejectUnauthorized: true, servername: process.env.PGHOST },
  connectionTimeoutMillis: 15000,
});

// ONE overall deadline across connect + query + shutdown: a hung query or a
// hung end() is a transport failure, never a verdict, never left running.
const DEADLINE_MS = 20000;
const deadline = new Promise((resolve) => {
  setTimeout(() => resolve('DEADLINE'), DEADLINE_MS).unref();
});

// The work promise NEVER rejects: the error is captured as a value so the
// race settles through the deadline branch cleanly (a rejecting raced promise
// would surface as an uncaught rejection before classification).
let workError = null;
const work = (async () => {
  try {
    await client.connect();
    await client.query('select 1');
    await client.end();
    return 'DONE';
  } catch (error) {
    workError = error;
    return 'FAILED';
  }
})();

const outcome = await Promise.race([work, deadline]);
if (outcome === 'DEADLINE') {
  try { client.destroy(); } catch { /* already gone */ }
  console.log('ERR TIMEOUT');
  process.exit(4);
}
if (workError === null) {
  console.log('OK');
  process.exit(0);
}
{
  const error = workError;
  const code = error && (error.code ?? error.errcode);
  if (code === '28P01') {
    console.log('ERR 28P01');
    process.exit(3);
  }
  // Never print error.message: server auth text can echo user/host material.
  console.log(`ERR ${typeof code === 'string' ? code : 'UNCLASSIFIED'}`);
  process.exit(4);
}
