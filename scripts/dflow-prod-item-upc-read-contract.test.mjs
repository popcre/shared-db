import test from 'node:test';
import assert from 'node:assert/strict';
import {readFileSync} from 'node:fs';
import {spawnSync} from 'node:child_process';
const container=process.env.DFLOW_UPC_TEST_CONTAINER;
const migration=readFileSync(new URL('../supabase/migrations/20261022232130_dflow_prod_item_upc_read_contract.sql',import.meta.url),'utf8');
const db=`upc_${process.pid}_${Date.now()}`;
function q(sql,database=db){return spawnSync('docker',['exec','-i',container,'psql','-U','postgres','-d',database,'-X','-At','-v','ON_ERROR_STOP=1'],{input:sql,encoding:'utf8'});}
function ok(sql){const r=q(sql);assert.equal(r.status,0,r.stderr);return r.stdout.trim();}
const fixture=`CREATE SCHEMA dflow_prod; CREATE SCHEMA dflow;
CREATE TABLE dflow_prod."itemDetail"(item_pk integer PRIMARY KEY,item_num_id varchar(50),compan_code_fk integer,div_code_fk integer,"UPC" varchar,"EAN" varchar,"GTIN" varchar,color_code_fk varchar,size_code_fk varchar,size_seq integer,whse_sku_id varchar,item_active_status varchar,coldlion_synced_at timestamptz,private_cost numeric);
CREATE TABLE dflow.secret(value text); CREATE VIEW dflow.item_detail_upc AS SELECT value FROM dflow.secret;
GRANT USAGE ON SCHEMA dflow_prod TO designflow_prod_item_master_grants;
INSERT INTO dflow_prod."itemDetail"(item_pk,item_num_id,compan_code_fk,div_code_fk,"UPC",whse_sku_id) VALUES (1,'SAME',1,1,'111','Z'),(2,'SAME',1,1,'222','A'),(3,'SAME',2,1,'333','B'),(4,'SAME',1,2,'444','C'),(5,NULL,1,1,'555','D'),(6,'SAME',1,1,NULL,'E'),(7,'SAME',1,1,'','F');`;
function denied(role,sql){const r=q(`SET ROLE ${role}; ${sql}`);assert.notEqual(r.status,0,`${role} unexpectedly allowed: ${sql}`);assert.match(r.stderr,/permission denied/);}
test('synthetic PG17 production UPC contract',{skip:!container},async t=>{
 const created=q(`CREATE DATABASE ${db};`,'postgres');assert.equal(created.status,0,created.stderr);
 try{
  ok(fixture);ok(migration);
  await t.test('full triple, unresolved/empty UPC exclusion and stable row ordering',()=>{
   for(const role of ['designflow_prod_item_master_runtime','designflow_prod_backend_runtime']) assert.equal(ok(`SET ROLE ${role}; SELECT string_agg(upc,',' ORDER BY whse_sku_id,item_pk) FROM dflow_prod.item_detail_upc WHERE item_num_id='SAME' AND compan_code_fk=1 AND div_code_fk=1;`),'SET\n222,111');
   assert.equal(ok('SELECT count(*) FROM dflow_prod.item_detail_upc;'),'4');
   assert.equal(ok("SELECT string_agg(attname,',' ORDER BY attnum) FROM pg_attribute WHERE attrelid='dflow_prod.item_detail_upc'::regclass AND attnum>0 AND NOT attisdropped;"),'item_pk,item_num_id,compan_code_fk,div_code_fk,upc,ean,gtin,color_code_fk,size_code_fk,size_seq,whse_sku_id,item_active_status,coldlion_synced_at');
  });
  await t.test('minimum access and legacy/browser/unrelated/write denials',()=>{
   denied('designflow_prod_item_master_runtime','SELECT private_cost FROM dflow_prod."itemDetail";');
   for(const verb of ['INSERT INTO dflow_prod."itemDetail"(item_pk) VALUES(99)','UPDATE dflow_prod."itemDetail" SET "UPC"=\'x\'','DELETE FROM dflow_prod."itemDetail"']) denied('designflow_prod_item_master_runtime',verb);
   denied('designflow_prod_item_master_runtime','SELECT * FROM dflow.item_detail_upc;');
   for(const role of ['anon','authenticated','service_role','designflow_prod_tracking_runtime','designflow_prod_data_sync_runtime']) denied(role,'SELECT * FROM dflow_prod.item_detail_upc;');
  });
  await t.test('invoker checks underlying privileges and RLS',()=>{
   ok('REVOKE SELECT ("UPC") ON dflow_prod."itemDetail" FROM designflow_prod_item_master_grants;');
   denied('designflow_prod_item_master_runtime','SELECT upc FROM dflow_prod.item_detail_upc;');
   ok('GRANT SELECT ("UPC") ON dflow_prod."itemDetail" TO designflow_prod_item_master_grants; ALTER TABLE dflow_prod."itemDetail" ENABLE ROW LEVEL SECURITY;');
   assert.equal(ok('SET ROLE designflow_prod_item_master_runtime; SELECT count(*) FROM dflow_prod.item_detail_upc;'),'SET\n0');
   ok('ALTER TABLE dflow_prod."itemDetail" DISABLE ROW LEVEL SECURITY;');
  });
  for(const [name,change] of [['missing column','ALTER TABLE dflow_prod."itemDetail" DROP COLUMN "GTIN"'],['RLS enabled','ALTER TABLE dflow_prod."itemDetail" ENABLE ROW LEVEL SECURITY'],['schema access missing','REVOKE USAGE ON SCHEMA dflow_prod FROM designflow_prod_item_master_grants']]) await t.test(`precondition ${name} rolls back without partial view or grants`,()=>{
   ok('DROP VIEW dflow_prod.item_detail_upc; REVOKE ALL ON dflow_prod."itemDetail" FROM designflow_prod_item_master_grants;');ok(change);
   const result=q(migration);assert.notEqual(result.status,0);assert.match(result.stderr,/#4659/);
   assert.equal(ok("SELECT to_regclass('dflow_prod.item_detail_upc') IS NULL;"),'t');
   assert.equal(ok("SELECT has_column_privilege('designflow_prod_item_master_grants','dflow_prod.\"itemDetail\"','UPC','SELECT');"),'f');
   if(name==='missing column')ok('ALTER TABLE dflow_prod."itemDetail" ADD COLUMN "GTIN" varchar;');
   if(name==='RLS enabled')ok('ALTER TABLE dflow_prod."itemDetail" DISABLE ROW LEVEL SECURITY;');
   if(name==='schema access missing')ok('GRANT USAGE ON SCHEMA dflow_prod TO designflow_prod_item_master_grants;');
   ok(migration);
  });
 } finally{const r=q(`DROP DATABASE ${db} WITH (FORCE);`,'postgres');assert.equal(r.status,0,r.stderr);}
});
