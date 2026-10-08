const {Client}=require('pg');const fs=require('fs');
(async()=>{const c=new Client({host:'aws-1-us-east-1.pooler.supabase.com',port:6543,user:'postgres.qsllyeztdwjgirsysgai',database:'postgres',password:process.env.PW,ssl:{rejectUnauthorized:false}});
await c.connect();await c.query('begin read only');
const src=(await c.query("select prosrc from pg_proc p join pg_namespace n on n.oid=pronamespace where nspname='api' and proname='db_data_admin_scraped_source_inventory'")).rows[0].prosrc;
const L=src.split('\n');const a=L.findIndex(x=>x.includes("if v_entity_kind = 'property'"))+1;
const k=L.findIndex((x,i)=>i>a&&x.includes('), filtered as ('));const p=L.findIndex((x,i)=>i>a&&x.includes('page_creative_decision as materialized'));const q=L.findIndex((x,i)=>i>p&&x.includes('), current_copy as materialized'));
const sql=L.slice(a,k).join('\n')+"\n    ), ordered as materialized (select * from keyed\n"+L.slice(p,q).join('\n')+`
    )
    select jsonb_agg(jsonb_build_object('g',o.licensor_group_name,'p',o.source_purpose,'l',o.display_label,'sys',o.source_system,'tbl',o.source_table,'id',o.source_id,'st',coalesce(d.decision_state, case when o.source_purpose='Creative' then 'unmapped' end))) j
    from ordered o left join page_creative_decision d on d.row_key=o.row_key`;
fs.writeFileSync('q.sql',sql);const rows=(await c.query(sql)).rows[0].j;await c.query('rollback');await c.end();
fs.writeFileSync('rows.json',JSON.stringify(rows));const t={};for(const x of rows){if(x.p==='Creative'){const kk=x.g+'|'+x.st;t[kk]=(t[kk]||0)+1}}console.log(rows.length,t)})().catch(e=>{console.error(e.message);process.exit(1)})
