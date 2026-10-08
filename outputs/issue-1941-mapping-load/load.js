// Records Laura/Ilona's Creative->Submissions decisions (shared-db#1941) as superseding,
// append-only versions in plm.dcp_opa_property_resolution. Dry run unless COMMIT=1.
const {Client}=require('pg');const fs=require('fs');
const d=JSON.parse(fs.readFileSync('decisions.json'));const sha=fs.readFileSync('sha.txt','utf8').trim();
const EVIDENCE='popcre/shared-db#1941: returned licensing review workbook (Creative-to-Submissions property mapping 3.xlsx), 2026-10-08';
const BY='licensing review, shared-db#1941';
const EXPECT_BEFORE=+process.env.EXPECT_BEFORE, EXPECT_DECISIONS=+process.env.EXPECT_DECISIONS, EXPECT_MEMBERS=+process.env.EXPECT_MEMBERS;
if(!(EXPECT_BEFORE&&EXPECT_DECISIONS&&EXPECT_MEMBERS))throw new Error('EXPECT_* required');
const wbSha=require('crypto').createHash('sha256').update(fs.readFileSync(process.env.WORKBOOK)).digest('hex');
if(wbSha!==sha)throw new Error('workbook digest mismatch');
(async()=>{const c=new Client({host:'aws-1-us-east-1.pooler.supabase.com',port:6543,user:'postgres.qsllyeztdwjgirsysgai',database:'postgres',password:process.env.PW,ssl:{rejectUnauthorized:false}});
await c.connect();await c.query('begin');
// Target proof: the shared POP production project, by pooler tenant and a table only it has.
// Server-reported identity plus the exact ledger size observed in the reviewed dry run.
const t=(await c.query("select current_user u, current_database() db, to_regclass('plm.dcp_opa_property_resolution') is not null ok")).rows[0];
if(!t.ok||t.u!=='postgres'||t.db!=='postgres')throw new Error('target proof failed');
await c.query('lock table plm.dcp_opa_property_resolution in share row exclusive mode');
const before=+(await c.query('select count(*) from plm.dcp_opa_property_resolution')).rows[0].count;
if(before!==EXPECT_BEFORE)throw new Error('ledger size '+before+' != expected '+EXPECT_BEFORE+' (wrong target or changed since dry run)');
let ins=0,mem=0;const all=[...d.map.map(x=>({...x,state:'mapped'})),...d.excl.map(x=>({...x,state:'excluded'}))];
for(const x of all){
 const prev=(await c.query(`select * from plm.dcp_opa_property_resolution where source_system=$1 and source_table=$2 and source_property_id=$3 order by decision_version desc limit 1`,[x.sys,x.tbl,x.id])).rows[0];
 if(prev&&prev.approval_status==='approved'&&prev.creative_decision_state!=='unmapped'&&prev.creative_decision_state!==null)throw new Error('not unmapped any more: '+x.sys+' '+x.id);
 if(prev&&prev.approval_status==='rejected')throw new Error('rejected copy, skip by hand: '+x.id);
 const reason=x.state==='mapped'?'Mapped by licensing review to: '+x.targets.map(t=>t.l).join('; '):x.reason+(x.note?' - '+x.note:'');
 const r=(await c.query(`insert into plm.dcp_opa_property_resolution(source_system,source_table,source_property_id,decision_version,approval_status,supersedes_resolution_id,evidence_reference,evidence_sha256,decision_reason,contract_asserted_studio_code,contract_evidence_reference,contract_evidence_sha256,approved_at,approved_by,creative_decision_state)
  values($1,$2,$3,$4,'approved',$5,$6,$7,$8,$9,$10,$11,clock_timestamp(),$12,$13) returning resolution_id`,
  [x.sys,x.tbl,x.id,prev?+prev.decision_version+1:1,prev?prev.resolution_id:null,EVIDENCE,sha,reason,prev?.contract_asserted_studio_code??null,prev?.contract_evidence_reference??null,prev?.contract_evidence_sha256??null,BY,x.state])).rows[0];
 ins++;
 if(x.state==='mapped')for(const [i,m] of x.targets.entries()){await c.query(`insert into plm.dcp_opa_property_resolution_member(resolution_id,submission_source_system,submission_source_table,submission_source_id,licensed_property_id,member_ordinal) values($1,$2,$3,$4,$5,$6)`,
  [r.resolution_id,m.sys,m.tbl,m.id,m.tbl==='plm.opa_property'?m.id:null,i+1]);mem++}}
const after=+(await c.query('select count(*) from plm.dcp_opa_property_resolution')).rows[0].count;
if(after-before!==all.length||ins!==EXPECT_DECISIONS||mem!==EXPECT_MEMBERS)throw new Error('row count mismatch');
await c.query('set constraints all immediate');
console.log({before,decisions:ins,mapped:d.map.length,excluded:d.excl.length,members:mem});
await c.query(process.env.COMMIT==='1'?'commit':'rollback');console.log(process.env.COMMIT==='1'?'COMMITTED':'DRY RUN rolled back');await c.end()})().catch(async e=>{console.error('FAILED',e.message);process.exit(1)})
