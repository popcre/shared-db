// Offline contract tests for the /proddetails loader (issue #3180).
//
// Synthetic fixtures only — no real ColdLion values, no secrets, no database. The
// workflows are tested statically: the only dynamic test of a production writer is a
// production write.

import test from "node:test";
import assert from "node:assert/strict";
import { readFileSync } from "node:fs";
import { fileURLToPath } from "node:url";
import {
  PROD_DETAIL_SPEC,
  assertRequestedOrder,
  buildProdDetailLoadSql,
  doneKeysSql,
  harvestSql,
  makeProdDetailRun,
  parseDoneKeys,
  parseHarvest,
  parseReconciliation,
  reconcileSql,
  selectKeys,
  projectProdDetailRows,
} from "./coldlion-landing/lib/prod-details.mjs";
import { masterUrl } from "./coldlion-landing/lib/master-http.mjs";
import { loadOneKey, main, parseArgs } from "./coldlion-landing/sync-prod-details.mjs";

const RUN = "11111111-1111-4111-8111-111111111111";
const NOW = "2026-09-17T00:00:00.000Z";

/** A synthetic /proddetails row carrying every approved field, blanks where the vendor sends them. */
function sourceRow(overrides = {}) {
  return {
    pkey: 900001,
    prodOrderNo: 20000,
    prodLineSeq: 1,
    divisionCode: "SYN001",
    itemPkey: 800001,
    itemNo: "SYN-ITEM",
    itemDesc: "Synthetic item",
    colorCode: "SYN-C",
    sizeCode: "SYN-S",
    dimCode: "",
    labelCode: "",
    prepackCode: "",
    prodQty: 12,
    wipQty: 0,
    prodCost: 3.5,
    custPONumber: "",
    merchGroup05Desc: "Synthetic group",
    createdTime: "2026-01-02T03:04:05Z",
    createdUser: "SYN-USER",
    modTime: "2026-01-03T03:04:05Z",
    modUser: "SYN-USER2",
    ...overrides,
  };
}

function projected(rows, overrides = {}) {
  return projectProdDetailRows(rows, { runId: RUN, fetchedAt: NOW, companyCode: "SYNCO", prodOrderNo: 20000, ...overrides });
}

// -------------------------------------------------------------------------------------
// The spec is the live-rederived shape: exactly the 21 fields of the 2026-09-15 grain
// proof and the 2026-09-17 re-derivation, no more and no fewer.
// -------------------------------------------------------------------------------------

test("the spec carries exactly the 21 live /proddetails fields", () => {
  assert.deepEqual(
    PROD_DETAIL_SPEC.fields.map((field) => field.api).sort(),
    ["colorCode", "createdTime", "createdUser", "custPONumber", "dimCode", "divisionCode", "itemDesc", "itemNo", "itemPkey", "labelCode", "merchGroup05Desc", "modTime", "modUser", "pkey", "prepackCode", "prodCost", "prodLineSeq", "prodOrderNo", "prodQty", "sizeCode", "wipQty"],
  );
  assert.deepEqual(PROD_DETAIL_SPEC.key, ["company_code", "pkey"]);
  assert.deepEqual(PROD_DETAIL_SPEC.uniqueIdentity, ["company_code", "prod_order_no", "prod_line_seq"]);
});

test("projection normalises sentinels, stamps the company, and hashes the complete record", () => {
  const { rows } = projected([
    sourceRow({ createdTime: "1900-01-01T00:00:00Z", prodCost: 3.5 }),
    sourceRow({ pkey: 900002, prodLineSeq: 2, itemNo: "" }),
  ]);
  assert.equal(rows.length, 2);
  assert.equal(rows[0].company_code, "SYNCO");
  assert.equal(rows[0].created_time, null, "the 1900 empty-date marker never lands as a fact");
  assert.equal(rows[0].prod_cost, 3.5);
  assert.equal(rows[1].item_no, null, "blank text lands as null");
  assert.match(rows[0].source_hash, /^[0-9a-f]{64}$/);
  assert.deepEqual(rows[0].source_raw, sourceRow({ createdTime: "1900-01-01T00:00:00Z", prodCost: 3.5 }), "the hash input is the complete fetched record");
  assert.equal(rows[0].run_id, RUN);
});

test("unknown and omitted fields fail loudly and fatally", () => {
  assert.throws(() => projected([sourceRow({ newPrivateField: "x" })]), /unreviewed field/);
  const missing = sourceRow(); delete missing.wipQty;
  assert.throws(() => projected([missing]), /omitted approved field/);
  for (const bad of [sourceRow({ newPrivateField: "x" })]) {
    try { projected([bad]); assert.fail("must throw"); }
    catch (error) { assert.equal(error.fatal, true, "a shape failure is fatal for the whole run"); }
  }
});

test("a row for another production order is refused", () => {
  assert.throws(() => projected([sourceRow({ prodOrderNo: 20001 })]), /under a request for/);
  assert.throws(() => assertRequestedOrder([sourceRow({ prodOrderNo: 20001 })], 20000), /under a request for/);
  assert.doesNotThrow(() => assertRequestedOrder([sourceRow({ prodOrderNo: "20000" })], 20000), "the vendor may send the order as a JSON string");
});

test("either identity appearing twice in one response is refused", () => {
  assert.throws(() => projected([sourceRow(), sourceRow({ itemNo: "SYN-OTHER" })]), /duplicate rows for one pkey/);
  assert.throws(() => projected([sourceRow(), sourceRow({ pkey: 900002, itemNo: "SYN-OTHER" })]), /duplicate rows for one prodOrderNo \+ prodLineSeq/);
});

test("a blank identity field is refused", () => {
  assert.throws(() => projected([sourceRow({ pkey: "" })]), /blank identity/);
  assert.throws(() => projected([sourceRow({ prodLineSeq: null })]), /blank identity/);
});

test("an empty response is a legitimate zero-row key, not a failure", () => {
  const result = projected([]);
  assert.deepEqual(result.rows, []);
  assert.equal(result.zeroRow, true);
  const sql = buildProdDetailLoadSql({ run: runFor({ rowsFetched: 0, zeroRow: true }), rows: [] });
  assert.match(sql, /,\s*200,\s*null,\s*0\);/, "the run still records zero rows fetched");
  assert.match(sql, /zeroRow=1/);
});

// -------------------------------------------------------------------------------------
// The generated transaction: replay determinism, and the two identities.
// -------------------------------------------------------------------------------------

function runFor(overrides = {}) {
  return makeProdDetailRun({
    id: RUN,
    companyCode: "SYNCO",
    prodOrderNo: 20000,
    requestedBy: "test",
    startedAt: "2026-09-17T00:00:00.000Z",
    finishedAt: "2026-09-17T00:00:01.000Z",
    httpStatus: 200,
    bodyStatus: null,
    rowsFetched: 2,
    ...overrides,
  });
}

test("replaying the same input generates the identical transaction", () => {
  const { rows } = projected([sourceRow(), sourceRow({ pkey: 900002, prodLineSeq: 2 })]);
  const a = buildProdDetailLoadSql({ run: runFor(), rows });
  const b = buildProdDetailLoadSql({ run: runFor(), rows });
  assert.equal(a, b, "a replay is byte-identical, so an idempotent re-run changes nothing but bookkeeping");
});

test("the upsert targets only the primary key and never collapses the second identity", () => {
  const sql = buildProdDetailLoadSql({ run: runFor(), rows: projected([sourceRow()]).rows });
  assert.match(sql, /on conflict \(company_code, pkey\) do update set/);
  assert.doesNotMatch(sql, /on conflict \(company_code, prod_order_no, prod_line_seq\)/,
    "a re-keyed vendor row must fail the table's unique constraint, not merge");
  assert.doesNotMatch(sql, /first_seen_at = excluded/, "first landing is forever");
  assert.match(sql, /last_seen_at = excluded\.last_seen_at/);
  assert.match(sql, /where t\.company_code is null or t\.source_hash <> s\.source_hash/, "the change trail records only real changes");
});

test("the transaction carries the spine bookkeeping", () => {
  const sql = buildProdDetailLoadSql({ run: runFor(), rows: projected([sourceRow()]).rows });
  assert.match(sql, /insert into coldlion\.sync_run/);
  assert.match(sql, /'\/proddetails'/);
  assert.match(sql, /update coldlion\.sync_run set status='succeeded'/);
  assert.match(sql, /insert into coldlion\.change_log[^;]*'prod_detail'/s);
  assert.match(sql, /jsonb_build_object\('company_code', s\.company_code, 'pkey', s\.pkey\)/);
});

// -------------------------------------------------------------------------------------
// Resumability and selection.
// -------------------------------------------------------------------------------------

const HARVEST = [
  { prodOrderNo: 30003, firstObserved: "2026-09-16T00:00:00", lastObserved: "2026-09-16T00:00:00" },
  { prodOrderNo: 30001, firstObserved: "2026-01-01T00:00:00", lastObserved: "2026-09-17T06:00:00" },
  { prodOrderNo: 30002, firstObserved: "2026-06-01T00:00:00", lastObserved: "2026-06-01T00:00:00" },
  { prodOrderNo: 30004, firstObserved: "2026-09-01T00:00:00", lastObserved: "2026-09-17T05:00:00" },
];

test("harvest and resume parsing tolerate Windows psql line endings", () => {
  const harvested = parseHarvest([["30001\r", "2026-01-01T00:00:00\r", "2026-09-17T06:00:00\r"], [" 30002 ", "2026-06-01T00:00:00", "2026-06-01T00:00:00"]]);
  assert.deepEqual(harvested.map((entry) => entry.prodOrderNo), [30001, 30002]);
  const done = parseDoneKeys([["30001\r"]]);
  assert.deepEqual([...done], [30001]);
  assert.throws(() => parseHarvest([["\r", "x", "y"]]), /blank key/);
});

test("backfill selects never-fetched keys oldest first and honours the bounds", () => {
  const done = new Set([30001]);
  const selection = selectKeys({ harvested: HARVEST, done, mode: "backfill", from: null, recentDays: 21, limit: null });
  assert.deepEqual(selection.map((entry) => entry.prodOrderNo), [30002, 30004, 30003], "oldest observation first, done keys skipped");
  const bounded = selectKeys({ harvested: HARVEST, done, mode: "backfill", from: null, recentDays: 21, limit: 2 });
  assert.deepEqual(bounded.map((entry) => entry.prodOrderNo), [30002, 30004]);
  const scoped = selectKeys({ harvested: HARVEST, done, mode: "backfill", from: "2026-08-31", recentDays: 21, limit: null });
  assert.deepEqual(scoped.map((entry) => entry.prodOrderNo), [30004, 30003], "only orders first observed on/after --from");
});

test("refresh catches never-fetched keys first, then recently-observed ones newest first", () => {
  const done = new Set([30001, 30004]);
  const selection = selectKeys({ harvested: HARVEST, done, mode: "refresh", from: null, recentDays: 21, limit: null });
  assert.deepEqual(selection.map((entry) => entry.prodOrderNo), [30002, 30003, 30001, 30004],
    "30002/30003 never fetched (oldest first); 30001/30004 re-read newest-observed first");
  const staleOnly = selectKeys({ harvested: HARVEST, done: new Set([30002]), mode: "refresh", from: null, recentDays: 1, limit: null });
  assert.deepEqual(staleOnly.map((entry) => entry.prodOrderNo).includes(30002), false, "a fetched key observed long ago is not re-read");
});

test("the harvest reads the landed history and the resume set reads the run evidence", () => {
  assert.match(harvestSql("SYNCO"), /from coldlion\.prod_history_line/);
  assert.match(harvestSql("SYNCO"), /where company_code = 'SYNCO'/);
  assert.match(harvestSql("SYNCO"), /group by prod_order_no/);
  assert.doesNotMatch(harvestSql("SYNCO"), /EP001/, "no exclusion here: history already excluded it before landing, and landing records what arrived");
  assert.match(doneKeysSql("SYNCO"), /endpoint = '\/proddetails'/);
  assert.match(doneKeysSql("SYNCO"), /status = 'succeeded'/);
  assert.match(doneKeysSql("SYNCO"), /request_params \? 'prodOrderNo'/);
});

test("reconciliation agrees only when the API side and the table tell one story", () => {
  const agrees = parseReconciliation(["3", "1", "10", "2", "10", "10", "10"]);
  assert.equal(agrees.agrees, true);
  assert.equal(agrees.zeroRowKeys, 1);
  assert.equal(agrees.exclusions, 0);
  const collapsed = parseReconciliation(["3", "1", "10", "2", "10", "9", "9"]);
  assert.equal(collapsed.agrees, false, "a missing table row disagrees");
  const duplicateCollapse = parseReconciliation(["3", "1", "10", "2", "10", "10", "9"]);
  assert.equal(duplicateCollapse.agrees, false, "distinct pkey below table rows is a collapse");
  const droppedZeroRow = parseReconciliation(["3", "1", "10", "3", "10", "10", "10"]);
  assert.equal(droppedZeroRow.agrees, false, "a zero-row key must never be counted as landed");
  assert.match(reconcileSql("SYNCO"), /count\(distinct pkey\)/);
  assert.match(reconcileSql("SYNCO"), /rows_fetched = 0/);
});

// -------------------------------------------------------------------------------------
// The fetch: a keyed bare-array request, and loadOneKey end to end.
// -------------------------------------------------------------------------------------

test("the request URL names the company and the order and nothing else", () => {
  assert.equal(
    masterUrl("/proddetails", { companyCode: "SYNCO", prodOrderNo: 20000 }).search,
    "?companyCode=SYNCO&prodOrderNo=20000",
  );
});

function fetchWith(payload) {
  return async () => ({ ok: true, status: 200, text: async () => JSON.stringify(payload) });
}

test("loadOneKey fetches, projects and lands one order in one transaction", async () => {
  const executed = [];
  const summary = await loadOneKey({
    prodOrderNo: 20000, apiKey: "hidden", companyCode: "SYNCO", requestedBy: "test",
    pauseMs: 0, fetchImpl: fetchWith([sourceRow(), sourceRow({ pkey: 900002, prodLineSeq: 2 })]),
    execute: (sql) => executed.push(sql),
  });
  assert.equal(summary.rowsFetched, 2);
  assert.equal(summary.zeroRow, false);
  assert.equal(executed.length, 1);
  assert.match(executed[0], /begin/);
  assert.match(executed[0], /commit/);
});

test("loadOneKey lands an empty array as a zero-row key", async () => {
  const executed = [];
  const summary = await loadOneKey({
    prodOrderNo: 20000, apiKey: "hidden", companyCode: "SYNCO", requestedBy: "test",
    pauseMs: 0, fetchImpl: fetchWith([]), execute: (sql) => executed.push(sql),
  });
  assert.equal(summary.zeroRow, true);
  assert.equal(summary.rowsFetched, 0);
  assert.match(executed[0], /insert into coldlion\.sync_run/);
});

test("loadOneKey refuses a paged envelope on a bare-array feed", async () => {
  await assert.rejects(
    loadOneKey({
      prodOrderNo: 20000, apiKey: "hidden", companyCode: "SYNCO", requestedBy: "test",
      pauseMs: 0, fetchImpl: fetchWith({ content: [], totalElements: 0 }), execute: () => assert.fail("must not write"),
    }),
    /plain array/,
  );
});

// -------------------------------------------------------------------------------------
// The CLI.
// -------------------------------------------------------------------------------------

test("parseArgs validates its own inputs", () => {
  assert.throws(() => parseArgs([]), /--mode is required/);
  assert.throws(() => parseArgs(["--mode", "everything"]), /unknown mode/);
  assert.throws(() => parseArgs(["--mode", "keys"]), /--mode keys requires/);
  assert.throws(() => parseArgs(["--mode", "keys", "--keys", "abc"]), /non-integer/);
  assert.throws(() => parseArgs(["--mode", "backfill", "--limit", "0"]), /positive integer/);
  assert.throws(() => parseArgs(["--mode", "backfill", "--from", "17-09-2026"]), /YYYY-MM-DD/);
  assert.deepEqual(parseArgs(["--mode", "keys", "--keys", "20000, 24332"]), { mode: "keys", keys: [20000, 24332], limit: null, from: null, recentDays: 21, company: "EDGEHOME", pauseMs: 3000, dryRun: false });
});

function cliDependencies({ harvest = HARVEST, done = [], loadKey, reconcile = ["0", "0", "0", "0", "0", "0", "0"] } = {}) {
  return {
    proveTarget: () => ({ database: "postgres", host: "syn-host", coldlionTables: 25 }),
    queryRows: (sql) => {
      if (sql.includes("count(distinct pkey)")) return [reconcile];
      if (sql.includes("prod_history_line")) return harvest.map((entry) => [String(entry.prodOrderNo), entry.firstObserved, entry.lastObserved]);
      if (sql.includes("sync_run")) return done.map((key) => [String(key)]);
      throw new Error(`unexpected read: ${sql.slice(0, 60)}`);
    },
    runSql: () => {},
    readApiKey: () => "hidden",
    recordMasterFailure: () => true,
    loadOneKey: loadKey ?? (async ({ prodOrderNo }) => ({ prodOrderNo, rowsFetched: 1, zeroRow: false })),
  };
}

test("a dry run reads evidence, fetches nothing and writes nothing", async () => {
  const deps = cliDependencies({ done: [30001] });
  const io = capture(() => main(["--mode", "backfill", "--dry-run"], deps));
  assert.match(io.output, /population 4, already succeeded 1, outstanding 3, selected 3/);
  assert.equal(deps.readApiKeyCalled, undefined);
});

test("a shape failure aborts the run instead of hammering a changed feed", async () => {
  let calls = 0;
  const deps = cliDependencies({
    loadKey: async () => { calls += 1; const error = new Error("/proddetails returned unreviewed field(s): surprise"); error.fatal = true; throw error; },
  });
  const io = capture(() => assert.rejects(main(["--mode", "backfill"], deps), /unreviewed field/));
  await io.promise;
  assert.equal(calls, 1, "the very next key is never fetched after a fatal shape refusal");
});

test("a per-key transport failure is recorded, skipped and fails the run loudly", async () => {
  const loaded = [];
  const deps = cliDependencies({
    done: [30001],
    loadKey: async ({ prodOrderNo }) => {
      if (prodOrderNo === 30002) { const error = new Error("/proddetails returned wire HTTP 500"); error.httpStatus = 500; throw error; }
      loaded.push(prodOrderNo);
      return { prodOrderNo, rowsFetched: 1, zeroRow: false };
    },
  });
  const io = capture(() => assert.rejects(main(["--mode", "backfill"], deps), /1 production order\(s\) failed/));
  await io.promise;
  assert.deepEqual(loaded.sort(), [30003, 30004], "the other keys still load; the failed one stays outstanding for the next run");
  assert.match(io.output, /prodOrderNo 30002 failed/);
});

test("a successful run ends with a reconciling report", async () => {
  const deps = cliDependencies({ reconcile: ["2", "0", "2", "2", "2", "2", "2"] });
  const io = capture(() => main(["--mode", "backfill"], deps));
  const result = await io.promise;
  assert.equal(result.reconciliation.agrees, true);
  assert.match(io.output, /reconcile: keysDone=2 zeroRowKeys=0 rowsFetchedTotal=2/);
});

test("a disagreement fails the run even though every key loaded", async () => {
  const deps = cliDependencies({ reconcile: ["2", "0", "2", "2", "2", "1", "1"] });
  const io = capture(() => assert.rejects(main(["--mode", "backfill"], deps), /reconciliation disagrees/));
  await io.promise;
});

function capture(action) {
  let text = "";
  const promise = (async () => {
    const original = { log: console.log, error: console.error };
    console.log = (chunk) => { text += chunk; }; console.error = (chunk) => { text += chunk; };
    try { return await action(); } finally { console.log = original.log; console.error = original.error; }
  })();
  return { get output() { return text; }, promise };
}

// -------------------------------------------------------------------------------------
// The two workflows this feed rides on.
// -------------------------------------------------------------------------------------

const PRODUCTION_REF = "qsllyeztdwjgirsysgai";
const readWorkflow = (name) => readFileSync(fileURLToPath(new URL(`../.github/workflows/${name}`, import.meta.url)), "utf8");
const sync = readWorkflow("coldlion-landing-sync.yml");
const backfill = readWorkflow("coldlion-prod-detail-backfill.yml");

test("the backfill workflow cannot be reached by a push, a pull request or a fork", () => {
  const on = backfill.slice(backfill.indexOf("\non:"), backfill.indexOf("\njobs:"));
  assert.doesNotMatch(on, /pull_request|push:/);
  assert.match(on, /workflow_dispatch/);
});

test("the scheduled sync still runs on schedule and dispatch only", () => {
  const on = sync.slice(sync.indexOf("\non:"), sync.indexOf("\njobs:"));
  assert.match(on, /schedule:/);
  assert.doesNotMatch(on, /pull_request|push:/);
});

test("every step that can write names the database it expects before it writes", () => {
  for (const [name, workflow] of [["the scheduled sync", sync], ["the prod-detail backfill", backfill]]) {
    const declarations = workflow.match(/COLDLION_EXPECTED_PROJECT_REF: (\S+)/g) ?? [];
    assert.ok(declarations.length >= 2, `${name} must declare its target beside every DATABASE_URL`);
    for (const declaration of declarations) {
      assert.equal(declaration, `COLDLION_EXPECTED_PROJECT_REF: ${PRODUCTION_REF}`);
    }
    assert.equal(
      (workflow.match(/DATABASE_URL: \$\{\{/g) ?? []).length,
      declarations.length,
      `${name} would otherwise carry a credential with no declared target`,
    );
  }
});

test("the backfill workflow cannot start without the secrets it needs", () => {
  assert.match(backfill, /SUPABASE_DB_URL_PRODUCTION is not set/);
  assert.match(backfill, /COLDLION_API_KEY is not set/);
});

test("the offline contract tests run before anything touches the database", () => {
  for (const [name, workflow] of [["the scheduled sync", sync], ["the prod-detail backfill", backfill]]) {
    const tests = workflow.indexOf("coldlion-landing-prod-details.test.mjs");
    const write = workflow.search(/DATABASE_URL: \$\{\{/);
    assert.ok(tests > 0, `${name} must prove the loader still holds its contracts`);
    assert.ok(tests < write, `${name} must prove it before it is trusted with a credential`);
  }
});

test("the prod-detail loader serialises against the history and master loaders", () => {
  for (const [name, workflow] of [["the scheduled sync", sync], ["the prod-detail backfill", backfill]]) {
    assert.match(workflow, /concurrency:/, `${name} must serialise itself`);
    assert.match(workflow, /group: coldlion-landing-sync/, `${name} must share the landing loader lane`);
    assert.match(workflow, /cancel-in-progress: false/, `${name} must never cut a transaction short`);
    assert.match(workflow, /timeout-minutes:/, `${name} must fail on its own budget`);
  }
});

test("the scheduled refresh runs the prod-detail step after history and masters", () => {
  const history = sync.indexOf("sync-history.mjs");
  const masters = sync.indexOf("sync-masters.mjs");
  const prodDetail = sync.indexOf("sync-prod-details.mjs");
  assert.ok(history > 0 && masters > history && prodDetail > masters,
    "the refresh must see the orders the history step landed moments ago");
  assert.match(sync, /--mode refresh/);
});
