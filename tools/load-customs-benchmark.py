#!/usr/bin/env python3
"""Lossless private customs archive loader. No DDL. Read-only unless --apply.
Uses the canonical Supabase Management API token from the process environment.
Source contents and API errors are never printed. Full source bytes stay private.
"""
import argparse
import hashlib
import json
import mimetypes
import os
from pathlib import Path
import sys
import urllib.request

SECTIONS = ('matches','suggestions','code_checks','unmatched','coverage','anomalies')
CONTEXT = ('Owner-directed authoritative historical customs evidence benchmark (#5447; '
           'designflow-backend#279). Preserve original extraction and matching context. '
           'Historical filings are not binding CBP rulings or verified current-law labels. '
           'Packet-level links and family leads are inferred, clocks may classify components, '
           'unmatched styles are limited-snapshot mismatches, and original anomalies remain unresolved. '
           'The source item master is an exported snapshot, not verified live. '
           'Keep evaluation answers isolated from model inputs and training memory.')

def canonical(value):
    return json.dumps(value,sort_keys=True,separators=(',',':'),ensure_ascii=False)

def sha(content):
    return hashlib.sha256(content).hexdigest()

def literal(value):
    return 'NULL' if value is None else "'" + str(value).replace("'","''") + "'"

def json_sql(value):
    return literal(canonical(value))+'::jsonb'

def inventory(root, master):
    root, master = Path(root).resolve(), Path(master).resolve()
    files=[]
    for p in sorted(root.rglob('*')):
        if p.is_symlink():
            raise ValueError('Source symlinks require explicit reconciliation')
        if p.is_file():
            b=p.read_bytes()
            files.append((str(p.relative_to(root)),p,sha(b),len(b)))
    b=master.read_bytes()
    files.append(('item_master_snapshot/'+master.name,master,sha(b),len(b)))
    manifest=[dict(relative_path=n,sha256=h,byte_count=s) for n,p,h,s in files]
    data=json.loads((root/'intelligence_20261101/intelligence.json').read_text())
    if data['summary']['master_sha256'] != sha(b):
        raise ValueError('The exported item-master bytes differ from the report source')
    rows=[]
    for section in SECTIONS:
        for i,row in enumerate(data[section]):
            if not isinstance(row,dict): raise ValueError('Unexpected non-object source row')
            status=row.get('status') or {'suggestions':'Family research lead','code_checks':'Code lookup evidence','unmatched':'Unmatched source style','coverage':'Packet coverage','anomalies':'Source anomaly'}[section]
            candidate=section=='matches' and status=='Historical link candidate'
            rows.append(dict(section=section,source_ordinal=i,style_number=row.get('style'),product_description=row.get('description'),product_family=row.get('group') or row.get('family'),historical_hts=row.get('hts'),packet_reference=row.get('packet'),evidence_status=status,exact_historical_candidate=candidate,current_law_verified=False,original_record=row))
    return sha(canonical(manifest).encode()),manifest,files,data,rows

class Database:
    def __init__(self,ref,ref_file):
        self.ref,self.ref_file=ref,Path(ref_file)
        self.token=os.environ['SUPABASE_ACCESS_TOKEN']
    def api(self,path,data=None):
        req=urllib.request.Request('https://api.supabase.com/v1/'+path,data=None if data is None else json.dumps(data).encode(),headers={'Authorization':'Bearer '+self.token,'Content-Type':'application/json'})
        with urllib.request.urlopen(req,timeout=120) as response:return json.load(response)
    def prove(self):
        if self.ref_file.read_text().strip()!=self.ref:raise ValueError('Local project-ref target mismatch')
        if self.api('projects/'+self.ref)['id']!=self.ref:raise ValueError('Management API target mismatch')
    def query(self,sql,write=False):
        self.prove() # fresh target proof immediately before each write/read
        return self.api('projects/'+self.ref+'/database/query',{'query':sql,'read_only':not write})

def run(args):
    ident,manifest,files,data,rows=inventory(args.root,args.master)
    db=Database(args.expected_ref,args.project_ref_file)
    if args.apply:
        db.query('insert into plm.customs_benchmark_dataset (dataset_id,benchmark_name,authority_scope,source_manifest,original_intelligence,authority_context,source_file_count,source_byte_count,observation_count) values ('+','.join([literal(ident),literal('customs_intelligence_20261101'),literal('historical_customs_evidence'),json_sql(manifest),json_sql(data),literal(CONTEXT),str(len(files)),str(sum(x[3] for x in files)),str(len(rows))])+') on conflict do nothing;',True)
        existing = {r['relative_path']:(r['content_sha256'],r['byte_count']) for r in db.query('select relative_path,content_sha256,byte_count from plm.customs_benchmark_artifact where dataset_id='+literal(ident))}
        for name,path,digest,size in files:
            if name in existing:
                if existing[name] != (digest,size):raise ValueError('Conflicting preserved artifact')
                continue
            content=path.read_bytes()
            if sha(content)!=digest:raise ValueError('Source changed during import')
            sql='insert into plm.customs_benchmark_artifact (dataset_id,relative_path,content_sha256,media_type,byte_count,content) values ('+','.join([literal(ident),literal(name),literal(digest),literal(mimetypes.guess_type(name)[0] or 'application/octet-stream'),str(size),"decode("+literal(content.hex())+",'hex')"])+') on conflict do nothing;'
            db.query(sql,True)
        for start in range(0,len(rows),100):
            values=[]
            for r in rows[start:start+100]:
                values.append('('+','.join([literal(ident),literal(r['section']),str(r['source_ordinal']),*[literal(r[k]) for k in ['style_number','product_description','product_family','historical_hts','packet_reference','evidence_status']],str(r['exact_historical_candidate']).lower(),'false',json_sql(r['original_record'])])+')')
            db.query('insert into plm.customs_benchmark_observation values '+','.join(values)+' on conflict do nothing;',True)
    stored=db.query('select source_manifest,original_intelligence,authority_context,source_file_count,source_byte_count,observation_count from plm.customs_benchmark_dataset where dataset_id='+literal(ident))
    assert len(stored)==1,'Dataset absent'
    d=stored[0]
    assert d['source_manifest']==manifest and d['original_intelligence']==data and d['authority_context']==CONTEXT,'Dataset context mismatch'
    assert (d['source_file_count'],d['source_byte_count'],d['observation_count'])==(len(files),sum(x[3] for x in files),len(rows)),'Dataset counts mismatch'
    artifacts=db.query("select relative_path,content_sha256,byte_count,encode(sha256(content),'hex') as actual_sha256 from plm.customs_benchmark_artifact where dataset_id="+literal(ident)+' order by relative_path')
    expected={n:(h,s) for n,p,h,s in files}
    assert len(artifacts)==len(expected),'Incomplete archive'
    for a in artifacts:assert expected[a['relative_path']]==(a['actual_sha256'],a['byte_count']) and a['content_sha256']==a['actual_sha256'],'Archive bytes mismatch'
    observed=db.query('select section,source_ordinal,style_number,product_description,product_family,historical_hts,packet_reference,evidence_status,exact_historical_candidate,current_law_verified,original_record from plm.customs_benchmark_observation where dataset_id='+literal(ident))
    assert sorted(observed,key=lambda r:(r['section'],r['source_ordinal']))==sorted(rows,key=lambda r:(r['section'],r['source_ordinal'])),'Observation or context mismatch'
    # Re-inventory after reads proves no original changed while being loaded.
    assert inventory(args.root,args.master)[0]==ident,'Source changed during verification'
    print(json.dumps(dict(target=args.expected_ref,dataset_id=ident,files=len(files),source_bytes=sum(x[3] for x in files),observations=len(rows),sections={s:len(data[s]) for s in SECTIONS},all_source_sha256_verified=True,all_row_context_verified=True)))

def main():
    p=argparse.ArgumentParser(description=__doc__)
    p.add_argument('--root',required=True);p.add_argument('--master',required=True)
    p.add_argument('--expected-ref',required=True);p.add_argument('--project-ref-file',required=True)
    p.add_argument('--apply',action='store_true')
    args=p.parse_args()
    try:run(args)
    except Exception as exc:
        # Error bodies can contain SQL, secrets or private source evidence.
        print('Customs benchmark operation failed ('+type(exc).__name__+', HTTP '+str(getattr(exc,'code','n/a'))+'); private error details withheld.',file=sys.stderr)
        return 1
    return 0
if __name__=='__main__':sys.exit(main())
