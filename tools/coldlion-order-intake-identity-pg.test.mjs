// Behavioural test of the ColdLion canonical writer's component identity
// against an isolated PostgreSQL 17 (the tools-offline-tests docker step sets
// COLDLION_WRITER_TEST_CONTAINER). It replays the SO 7128092 incident
// (2026-10-26): a component line already moved onto an Import PO, the
// component set renumbered, and a new component appearing mid-set. The old
// positional ordinal silently dropped AA0631P1P01 and minted a duplicate of
// AA063PFPF02; the identity-keyed writer must do neither.

import test from "node:test";
import assert from "node:assert/strict";
import { spawnSync } from "node:child_process";

import { buildWriteSql, buildIdentityGuardSql } from "./coldlion-landing/lib/order-intake-write.mjs";

const container = process.env.COLDLION_WRITER_TEST_CONTAINER;
const DB = "coldlion_identity_test";

function psql(sql, db = DB) {
  const r = spawnSync("docker", ["exec", "-i", container, "psql", "-U", "postgres", "-d", db,
    "-v", "ON_ERROR_STOP=1", "-qAt", "-F", "|"], { input: sql, encoding: "utf8" });
  if (r.status !== 0) throw new Error(`psql failed: ${r.stderr}`);
  return r.stdout.trim();
}

const SCHEMA = `
create schema coldlion; create schema plm; create schema core; create schema app;
create function app.set_updated_at() returns trigger language plpgsql as $$begin new.updated_at = now(); return new; end$$;
create table coldlion.sync_run (id uuid primary key, endpoint text, company_code text, request_params jsonb,
  status text, requested_by text, started_at timestamptz, finished_at timestamptz, error_message text, notes text,
  rows_inserted int, rows_updated int, rows_unchanged int);
create table coldlion.routing_code_map (code text primary key, order_type text, ship_to text);
create table coldlion.intake_new_order (id uuid primary key default gen_random_uuid(), sales_order_no bigint unique check (sales_order_no <> 0),
  warehouse_code text, state text not null, state_changed_at timestamptz, claim_evidence jsonb not null default '{}');
create table coldlion.intake_quarantine (id uuid primary key default gen_random_uuid(), reason text not null,
  sales_order_no bigint, detail jsonb not null default '{}', first_seen_run uuid);
create table coldlion.intake_order_line (id uuid primary key default gen_random_uuid(), sales_order_no bigint,
  sales_order_line_no int, master_item_no text, last_seen_run uuid, company_code text, division_code text,
  customer_code text, po_number text, sales_person_code1 text, start_date date, cancel_date date,
  line_qty numeric, warehouse_code text, line_source_hash text);
create table coldlion.intake_order_component (id uuid primary key default gen_random_uuid(), line_id uuid,
  sub_item_no text, sub_label_code text, order_qty numeric, component_source_hash text, last_seen_run uuid);
create table coldlion.item_detail (company_code text, division_code text, item_no text, item_pkey text, carton_qty numeric);
create table core.company_source_ref (company_id uuid, source_system text, source_table text, source_id text);
create table plm.erp_customer (customer_code text primary key, customer_id uuid, active boolean);
create table plm.production_order (id uuid primary key default gen_random_uuid(), production_order_number text,
  company_id uuid, metadata jsonb not null default '{}', source_system text, source_id text,
  updated_at timestamptz default now(), unique (source_system, source_id));
create table plm.production_order_source_ref (production_order_id uuid, source_system text, source_id text,
  is_primary boolean, metadata jsonb, unique (source_system, source_id));
create table plm.production_order_line (id uuid primary key default gen_random_uuid(), production_order_id uuid,
  line_number text, sku text, quantity_ordered numeric, order_person text, order_type text,
  customer_po_number text, assortment_id text, assortment_component_ordinal integer, case_pack numeric,
  ship_to text, start_ship_date date, cancel_date date, metadata jsonb, source_system text, source_id text,
  updated_at timestamptz default now(), unique (source_system, source_id));
create table plm.production_order_line_source_ref (production_order_line_id uuid, source_system text,
  source_id text, is_primary boolean, metadata jsonb, unique (source_system, source_id));
insert into coldlion.routing_code_map values ('W1', 'Import', 'Ross DC');
insert into plm.erp_customer values ('ROSS', '00000000-0000-0000-0000-0000000000aa', true);
`;

const SO = 7128092;
const COMPONENTS = ["AA0631P1P01", "AA0631P1P02", "AA063PFPF01", "AA063PFPF02"];

/** Stage one observation of SO 7128092 line 1 with the given components. */
function stage(run, components) {
  return `
insert into coldlion.sync_run (id, started_at) values ('${run}', now());
with l as (
  insert into coldlion.intake_order_line (sales_order_no, sales_order_line_no, master_item_no, last_seen_run,
    company_code, division_code, customer_code, po_number, line_qty, warehouse_code, line_source_hash)
  values (${SO}, 1, 'AA06301', '${run}', 'POP', 'D1', 'ROSS', '62004433', 96, 'W1', 'h-${run}')
  returning id)
insert into coldlion.intake_order_component (line_id, sub_item_no, sub_label_code, order_qty, component_source_hash, last_seen_run)
select l.id, c, null, 24, 'hash-' || c, '${run}' from l, unnest(array[${components.map((c) => `'${c}'`).join(",")}]) c;
insert into coldlion.intake_new_order (sales_order_no, warehouse_code, state) values (${SO}, 'W1', 'pending')
  on conflict (sales_order_no) do update set state = 'pending';`;
}

const linesBySku = () => psql(`
select pl.sku || '@' || p.production_order_number || '#' || r.source_id
from plm.production_order_line_source_ref r
join plm.production_order_line pl on pl.id = r.production_order_line_id
join plm.production_order p on p.id = pl.production_order_id
where r.source_system = 'coldlion' order by pl.sku, r.source_id;`).split("\n").filter(Boolean);

let n = 0;
const run = () => `00000000-0000-0000-0000-${String(++n).padStart(12, "0")}`;
const write = () => psql(buildWriteSql({ runId: run(), write: true }));

test("SO 7128092: renumbering, a moved line and a new mid-set component never drop or duplicate a component", { skip: !container }, () => {
  psql(`drop database if exists ${DB}`, "postgres");
  psql(`create database ${DB}`, "postgres");
  psql(SCHEMA);

  // 2026-10-08: ColdLion first sent only AA063PFPF02 (handle component:1).
  psql(stage(run(), ["AA063PFPF02"]));
  write();
  // 2026-10-13: the OrderList consolidation moved that line onto Import PO D3691.
  psql(`insert into plm.production_order (production_order_number) values ('D3691');
update plm.production_order_line set production_order_id = (select id from plm.production_order where production_order_number = 'D3691')
 where sku = 'AA063PFPF02';`);
  // 2026-10-26: the full set arrives; AA0631P1P01 now sorts first (mid-set
  // insertion before the existing component).
  psql(stage(run(), COMPONENTS));
  write();

  const lines = linesBySku();
  assert.deepEqual(lines.map((l) => l.split("@")[0]), COMPONENTS, `each component exactly once: ${lines}`);
  assert.ok(lines.includes(`AA063PFPF02@D3691#coldlion:so:${SO}:line:1:component:1`), "the moved line keeps its handle and stays on D3691");
  assert.equal(psql(`select count(*) from coldlion.intake_quarantine`), "0");

  // A second identical run is a no-op: nothing renumbers.
  psql(`update coldlion.intake_new_order set state = 'pending'`);
  write();
  assert.deepEqual(linesBySku(), lines);
});

test("a ref whose line SKU disagrees with its identity quarantines the order loudly and writes nothing", { skip: !container }, () => {
  psql(`update plm.production_order_line set sku = 'WRONG' where sku = 'AA0631P1P02';
update coldlion.intake_new_order set state = 'pending';`);
  const before = linesBySku();
  write();
  assert.deepEqual(linesBySku(), before);
  assert.equal(psql(`select state from coldlion.intake_new_order where sales_order_no = ${SO}`), "quarantined");
  assert.match(psql(`select detail::text from coldlion.intake_quarantine where reason = 'component-identity-conflict'`), /line=WRONG staged=AA0631P1P02.*sku-mismatch/);
});

test("a legacy ref with no recorded identity quarantines instead of minting a duplicate", { skip: !container }, () => {
  psql(`update plm.production_order_line set sku = 'AA0631P1P02' where sku = 'WRONG';
delete from coldlion.intake_quarantine;
update plm.production_order_line_source_ref set metadata = '{"origin":"coldlion_intake"}' where source_id like '%:component:1';
update coldlion.intake_new_order set state = 'pending';`);
  const before = linesBySku();
  write();
  assert.deepEqual(linesBySku(), before);
  assert.match(psql(`select detail::text from coldlion.intake_quarantine`), /ref-without-identity/);
});

test("the recurring guard passes on a correct order and names a dropped component", { skip: !container }, () => {
  psql(`delete from coldlion.intake_quarantine;
update plm.production_order_line_source_ref r set metadata = '{"origin":"coldlion_intake"}'::jsonb
  || jsonb_build_object('master_item_no', 'AA06301', 'sub_item_no', pl.sku)
  from plm.production_order_line pl where pl.id = r.production_order_line_id;
update coldlion.intake_new_order set state = 'created', claim_evidence = '{}';`);
  const ok = psql(buildIdentityGuardSql()).split("|");
  assert.deepEqual(ok.slice(0, 6), ["0", "0", "0", "0", "4", "0"]);
  psql(`delete from plm.production_order_line where sku = 'AA0631P1P01'`);
  const bad = psql(buildIdentityGuardSql()).split("|");
  assert.equal(bad[0], "1");
  assert.match(bad[6], /7128092\/1\/AA0631P1P01:missing/);
});
