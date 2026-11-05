"""Execute the real workflow/credential gate with mocked process/API boundaries.

All data is synthetic. No GitHub, secret service, network or database calls occur.
"""
import argparse
import hashlib
import base64
import io
from contextlib import redirect_stdout
import copy
import json
import os
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parent))
import nontransactional_index_maintenance as maintenance
import index_maintenance_source
import review_finding_hold
import automatic_index_maintenance as automatic
import automatic_promotion_candidates as promotion
from test_nontransactional_index_maintenance import entry,FakeDB,MemoryReceipts

PREVIEW='a'*20
HEAD='b'*40
MERGE='c'*40
OP='sg-hnsw-rebuild-5616-v1'


class WorkflowGateTests(unittest.TestCase):
    def setUp(self):
        self.directory=tempfile.TemporaryDirectory()
        self.root=Path(self.directory.name)
        temp=self.root/'supabase/.temp';temp.mkdir(parents=True)
        (temp/'project-ref').write_text(PREVIEW)
        (temp/'pooler-url').write_text(f'postgresql://postgres.{PREVIEW}@fixture.invalid:5432/postgres?sslmode=require')
        self.entry=entry()
        self.options=argparse.Namespace(operation=OP,target='preview',expected_project_ref=PREVIEW,
            source_sha=HEAD,dispatch_ref=f'refs/db-index-maintenance-operations/{OP}/preview/{HEAD}',linked_dir=self.root)
        self.env=dict(GITHUB_ACTIONS='true',GITHUB_REPOSITORY=maintenance.REPO,GITHUB_EVENT_NAME='workflow_dispatch',
            GITHUB_RUN_ATTEMPT='1',GITHUB_ACTOR='github-actions[bot]',GITHUB_WORKFLOW_REF=maintenance.REPO+'/.github/workflows/'+maintenance.WORKFLOW+'@refs/heads/main',
            GITHUB_RUN_ID='123',PREVIEW_PROJECT_REF=PREVIEW,EXPECTED_PROJECT_REF=PREVIEW,SUPABASE_DB_PASSWORD='synthetic-not-a-secret')
        self.run=dict(id=123,path='.github/workflows/'+maintenance.WORKFLOW,head_sha=HEAD,head_branch='main',
            event='workflow_dispatch',status='in_progress',conclusion=None,run_attempt=1,
            actor={'login':'github-actions[bot]'},triggering_actor={'login':'github-actions[bot]'},
            display_title=f'INDEX preview {self.options.dispatch_ref} {HEAD}')
        self.pr=dict(merged_at='synthetic-merged',base={'ref':'main'},merge_commit_sha=MERGE)
        self.policy={'schema_version':1,'operations':{OP:self.entry}}
        self.dispatch=dict(operation_id=OP,target='preview',source_sha=HEAD,policy_digest=maintenance.digest(self.entry))
        self.admitted=True;self.findings=[];self.calls=[]
        self.main=HEAD;self.ancestry=True;self.truncated=False
        self.source_files={'.github/workflows/shared-supabase-migrations.yml':'# trusted workflow',
            'scripts/safety.py':'# trusted safety helper',
            'tools/unrelated-hts.mjs':'// HTS original'}
        self.current_files=None
        self.blobs={}

    def fixture_tree(self,ref):
        files=dict(self.source_files if ref==HEAD else self.current_files or self.source_files)
        files.setdefault('config/nontransactional-index-maintenance.json',json.dumps({'schema_version':1,'operations':{OP:self.entry}}))
        entries=[]
        for path,body in files.items():
            raw=body.encode();sha=hashlib.sha1(b'blob '+str(len(raw)).encode()+b'\0'+raw).hexdigest()
            self.blobs[sha]=raw;entries.append({'path':path,'type':'blob','mode':'100644','sha':sha})
        return {'tree':entries,'truncated':self.truncated}

    def tearDown(self):self.directory.cleanup()

    def process(self,args,**kwargs):
        self.calls.append(args)
        if args[:3]==['git','cat-file','blob']:return subprocess.CompletedProcess(args,0,self.blobs[args[3]],b'')
        if args==['git','rev-parse','HEAD']:out=HEAD
        elif args[:3]==['git','merge-base','--is-ancestor']:out=''
        elif args[:2]==['git','show']:out=json.dumps(self.policy)
        elif args[0]=='node':out=json.dumps({'admitted':self.admitted})
        else:raise AssertionError('unexpected process boundary')
        return subprocess.CompletedProcess(args,0,out,'')

    def api(self,endpoint):
        if endpoint=='actions/runs/123':return self.run
        if endpoint=='commits/main':return {'sha':self.main}
        if endpoint.startswith('compare/'):return {'status':'identical' if self.main==HEAD else 'ahead' if self.ancestry else 'diverged','behind_by':0 if self.ancestry else 1}
        if endpoint.startswith('git/trees/'):return self.fixture_tree(endpoint.split('/')[2].split('?')[0])
        if endpoint.startswith('git/blobs/'):
            sha=endpoint.rsplit('/',1)[1];return {'sha':sha,'encoding':'base64','content':base64.b64encode(self.blobs[sha]).decode()}
        if endpoint=='pulls/1':return self.pr
        raise AssertionError('unexpected API boundary '+endpoint)

    def execute_gate(self):
        with patch.dict(os.environ,self.env,clear=True),patch.object(maintenance,'gh',side_effect=self.api),patch.object(maintenance.subprocess,'run',side_effect=self.process),patch.object(maintenance.Receipts,'read',return_value=self.dispatch),patch.object(review_finding_hold,'gh_issues',return_value=[]),patch.object(review_finding_hold,'blocking_findings',return_value=self.findings):
            return maintenance.workflow_gate(self.options,self.entry)

    def test_real_gate_accepts_exact_automatic_preview_and_canonical_protected_credentials(self):
        result=self.execute_gate()
        self.assertEqual(result['PGHOST'],'fixture.invalid')
        self.assertEqual(result['PGUSER'],'postgres.'+PREVIEW)
        self.assertEqual(result['PGPORT'],'5432')
        self.assertEqual(result['_SOURCE_MERGE_SHA'],MERGE)
        self.assertTrue(any(args[0]=='node' and args[-1]=='admit' for args in self.calls))

    def test_enabled_automatic_selector_dispatch_is_consumed_by_real_preview_gate(self):
        policy_path=self.root/'synthetic-policy.json';policy_path.write_text(json.dumps(self.policy))
        records={};dispatches=[]
        def read(ref):return records.get(ref)
        def create(ref,value):records[ref]=value;return value
        def dispatch_process(args,**kwargs):
            self.assertEqual(args[:3],['gh','workflow','run'])
            fields=dict(args[i+1].split('=',1) for i,value in enumerate(args) if value=='-f')
            dispatches.append(fields)
            return subprocess.CompletedProcess(args,0,'','')
        with patch.dict(os.environ,self.env,clear=True),patch.object(maintenance,'POLICY',policy_path),patch.object(maintenance,'gh',side_effect=self.api),patch.object(promotion,'workflow_runs',return_value=[]),patch.object(promotion,'is_held',return_value=False),patch.object(maintenance.Receipts,'read',side_effect=read),patch.object(maintenance.Receipts,'create',side_effect=create),patch.object(automatic.subprocess,'run',side_effect=dispatch_process),patch.object(sys,'argv',['automatic_index_maintenance.py']),redirect_stdout(io.StringIO()):
            self.assertEqual(automatic.main(),0)
        self.assertEqual(len(dispatches),1)
        fields=dispatches[0]
        self.assertEqual(fields['target'],'preview')
        self.assertEqual(fields['mode'],'apply')
        self.assertNotIn('preview_allowlist',fields)
        self.options.dispatch_ref=fields['migration_train_ref']
        self.options.source_sha=fields['commit_sha']
        self.dispatch=records[self.options.dispatch_ref]
        self.assertEqual(self.execute_gate()['_SOURCE_MERGE_SHA'],MERGE)

    def test_actual_gate_accepts_ancestor_with_only_unexecuted_hts_tool_change(self):
        self.main='d'*40;self.current_files={**self.source_files,'tools/unrelated-hts.mjs':'// HTS changed'}
        result=self.execute_gate()
        self.assertEqual(result['_CURRENT_MAIN_SHA'],self.main)
        self.assertEqual(result['_SOURCE_MERGE_SHA'],MERGE)

    def test_actual_gate_refuses_all_relevant_guard_policy_data_and_dependency_mutations(self):
        self.main='d'*40
        cases=[{**self.source_files,'scripts/safety.py':'# retired safety'},
            {**self.source_files,'config/nontransactional-index-maintenance.json':'{"schema_version":1,"operations":{}}'},
            {**self.source_files,'.github/workflows/shared-supabase-migrations.yml':'# unsafe workflow'},
            {**self.source_files,'config/health-initial-index-definitions.json':'{}'},
            {**self.source_files,'scripts/new_guard.py':'# new dependency'},
            {k:v for k,v in self.source_files.items() if k!='scripts/safety.py'}]
        for current in cases:
            self.current_files=current
            with self.subTest(paths=list(current)),self.assertRaisesRegex(maintenance.Refusal,'trusted-source parity'):self.execute_gate()

    def test_actual_gate_follows_nested_relative_tool_dependency_and_refuses_changed_tool(self):
        self.source_files['scripts/safety.py']='from sibling import helper'
        self.source_files['scripts/sibling.py']='# retained sibling guard'
        self.source_files['scripts/bridge.mjs']="export {x} from '../tools/real-worker.mjs'"
        self.source_files['tools/real-worker.mjs']='export const x=1'
        self.main='d'*40;self.current_files={**self.source_files,'tools/real-worker.mjs':'export const x=2'}
        with self.assertRaisesRegex(maintenance.Refusal,'producer/current policy changed'):self.execute_gate()

    def test_point_of_mutation_rechecks_current_producer_and_never_runs_sql_after_relevant_drift(self):
        self.execute_gate()
        db=FakeDB();runner=maintenance.Maintenance(db,MemoryReceipts(),self.entry,{},OP,self.execute_gate)
        self.main='d'*40;self.current_files={**self.source_files,'scripts/safety.py':'# changed after initial admission'}
        with self.assertRaisesRegex(maintenance.Refusal,'trusted-source parity'):runner.execute('CREATE INDEX CONCURRENTLY must_not_run')
        self.assertEqual(db.sql,[])

    def test_actual_gate_refuses_nonancestor_truncated_and_advance_during_proof(self):
        self.main='d'*40;self.ancestry=False
        with self.assertRaisesRegex(maintenance.Refusal,'trusted main ancestor'):self.execute_gate()
        self.ancestry=True;self.truncated=True
        with self.assertRaisesRegex(maintenance.Refusal,'truncated'):self.execute_gate()
        self.truncated=False
        original=self.api;calls=0
        def moving(endpoint):
            nonlocal calls
            if endpoint=='commits/main':
                calls+=1
                if calls>1:return {'sha':'e'*40}
            return original(endpoint)
        with patch.object(self,'api',side_effect=moving),self.assertRaisesRegex(maintenance.Refusal,'advanced during'):self.execute_gate()

    def test_each_wrong_live_run_binding_refuses_before_native_admission_or_credentials(self):
        cases=[('id',999),('path','.github/workflows/other.yml'),('head_sha','d'*40),('head_branch','other'),
            ('event','push'),('status','completed'),('conclusion','failure'),('run_attempt',2),
            ('actor',{'login':'u2giants'}),('triggering_actor',{'login':'u2giants'}),('display_title','unrelated')]
        for key,value in cases:
            before=copy.deepcopy(self.run);self.run[key]=value;self.calls=[]
            with self.subTest(key=key),self.assertRaisesRegex(maintenance.Refusal,'live automatic workflow run proof'):self.execute_gate()
            self.assertFalse(any(args[0]=='node' for args in self.calls));self.run=before

    def test_manual_context_and_replay_refuse_even_when_api_proof_would_pass(self):
        for key,value in [('GITHUB_ACTOR','u2giants'),('GITHUB_RUN_ATTEMPT','2'),('GITHUB_EVENT_NAME','push')]:
            before=self.env[key];self.env[key]=value
            with self.subTest(key=key),self.assertRaises(maintenance.Refusal):self.execute_gate()
            self.env[key]=before

    def test_changed_protected_preview_ref_refuses_old_link(self):
        self.env['PREVIEW_PROJECT_REF']='e'*20
        with self.assertRaisesRegex(maintenance.Refusal,'currently configured preview'):self.execute_gate()

    def test_production_never_substitutes_for_preview(self):
        self.env['PREVIEW_PROJECT_REF']=maintenance.PROD
        with self.assertRaisesRegex(maintenance.Refusal,'preview reference'):self.execute_gate()

    def test_missing_link_wrong_link_and_transaction_pooler_refuse(self):
        temp=self.root/'supabase/.temp'
        for change in ['ref','missing','port']:
            (temp/'project-ref').write_text(PREVIEW)
            (temp/'pooler-url').write_text(f'postgresql://postgres.{PREVIEW}@fixture.invalid:5432/postgres?sslmode=require')
            if change=='ref':(temp/'project-ref').write_text('e'*20)
            elif change=='missing':(temp/'pooler-url').unlink()
            else:(temp/'pooler-url').write_text(f'postgresql://postgres.{PREVIEW}@fixture.invalid:6543/postgres?sslmode=require')
            with self.subTest(change=change),self.assertRaises(maintenance.Refusal):self.execute_gate()

    def test_policy_cannot_borrow_an_unrelated_historical_merged_pr(self):
        self.policy['operations'][OP]={**self.entry,'work_issue':9999}
        with self.assertRaisesRegex(maintenance.Refusal,'authored'):self.execute_gate()

    def test_missing_dispatch_claim_and_finding_each_refuse(self):
        self.dispatch['policy_digest']='0'*64
        with self.assertRaisesRegex(maintenance.Refusal,'dispatch receipt'):self.execute_gate()
        self.dispatch['policy_digest']=maintenance.digest(self.entry);self.admitted=False
        with self.assertRaisesRegex(maintenance.Refusal,'claim admission'):self.execute_gate()
        self.admitted=True;self.findings=[{'number':9999}]
        with self.assertRaisesRegex(maintenance.Refusal,'review finding'):self.execute_gate()


class PreviewReceiptBindingTests(unittest.TestCase):
    def runner(self,project_ref):
        db=FakeDB();receipts=MemoryReceipts();identity=dict(target='production',project_ref=maintenance.PROD,
            preview_project_ref=PREVIEW,source_sha=HEAD,execution_sha=HEAD,executor_digest='d'*64,source_pr=1,run_id=123)
        runner=maintenance.Maintenance(db,receipts,entry(),identity,'synthetic-operation',lambda:None)
        receipts.records[runner.receipt_ref('complete','preview')]={**identity,'target':'preview','project_ref':project_ref,
            'phase':'complete','operation_id':'synthetic-operation','policy_digest':maintenance.digest(entry())}
        return runner

    def test_only_current_configured_preview_receipt_is_accepted(self):
        runner=self.runner(PREVIEW)
        self.assertEqual(runner.read('complete','preview')['project_ref'],PREVIEW)

    def test_stale_preview_or_production_ref_cannot_supply_preview_proof(self):
        for wrong in ['e'*20,maintenance.PROD,None]:
            with self.subTest(wrong=wrong),self.assertRaisesRegex(maintenance.Refusal,'currently configured preview'):
                self.runner(wrong).read('complete','preview')


def native_fixture(request):
    """Only the isolated TEST harness, never a production authority input."""
    import prove_index_maintenance_source as native
    test=WorkflowGateTests();test.setUp()
    if request.get('target')=='production':
        test.dispatch['target']='production'
        test.env['EXPECTED_PROJECT_REF']=maintenance.PROD
        (test.root/'supabase/.temp/project-ref').write_text(maintenance.PROD)
        (test.root/'supabase/.temp/pooler-url').write_text(f'postgresql://postgres.{maintenance.PROD}@fixture.invalid:5432/postgres?sslmode=require')
        test.run['display_title']=f'INDEX production {request["dispatch_ref"]} {HEAD}'
    try:
        test.main='d'*40
        test.current_files={**test.source_files,'tools/unrelated-hts.mjs':'// unrelated changed HTS'}
        case=request.pop('_test_case','unrelated')
        if case=='guard':test.current_files['scripts/safety.py']='# replaced vulnerable guard'
        if case=='policy':test.current_files['config/nontransactional-index-maintenance.json']='{"schema_version":1,"operations":{}}'
        if case=='forcepush':test.ancestry=False
        if case=='dependency':test.current_files['scripts/new_guard.py']='# new safety input'
        if case=='atomic':test.current_files['scripts/atomic_migration_apply.py']='# new credential guard'
        (test.root/'policy.json').write_text(json.dumps(test.policy))
        with patch.dict(os.environ,test.env,clear=True),patch.object(maintenance,'ROOT',test.root),patch.object(maintenance,'POLICY',test.root/'policy.json'),patch.object(maintenance,'gh',side_effect=test.api),patch.object(maintenance.subprocess,'run',side_effect=test.process),patch.object(maintenance.Receipts,'read',return_value=test.dispatch),patch.object(review_finding_hold,'gh_issues',return_value=[]),patch.object(review_finding_hold,'blocking_findings',return_value=[]):
            return native.verify(request)
    finally:test.tearDown()


if __name__=='__main__':
    if '--native-fixture' in sys.argv:
        try:print(json.dumps(native_fixture(json.load(sys.stdin))))
        except Exception as exc:
            print('isolated actual native-entry fixture refused: '+str(exc),file=sys.stderr);sys.exit(2)
    else:unittest.main()
