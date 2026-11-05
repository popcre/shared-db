"""Real Git object/ancestry fixtures exercise canonical tree/blob parity."""
import json
from pathlib import Path
import subprocess
import sys
import tempfile
import unittest
from unittest.mock import patch
sys.path.insert(0,str(Path(__file__).resolve().parent))
import index_maintenance_source as source

class ActualGitProducerTests(unittest.TestCase):
    def setUp(self):
        self.temp=tempfile.TemporaryDirectory();self.root=Path(self.temp.name)
        self.git('init','-q');self.git('config','user.email','fixture@example.invalid');self.git('config','user.name','Fixture')
        self.entry={'source_pr':1}
        self.write('config/nontransactional-index-maintenance.json',json.dumps({'schema_version':1,'operations':{'fixed-op':self.entry}}))
        self.write('.github/workflows/shared-supabase-migrations.yml','# exact setup/driver/actions')
        self.write('scripts/main.py','from sibling import guard\n');self.write('scripts/sibling.py','# actual credential helper')
        self.write('scripts/bridge.mjs',"export {x} from '../tools/worker.mjs'\n")
        self.write('tools/worker.mjs','export const x=1\n');self.write('tools/hts/qualify.mjs','// unrelated HTS')
        self.base=self.commit();self.main=self.base;self.truncated=False;self.corrupt=False;self.count=0
    def tearDown(self):self.temp.cleanup()
    def git(self,*args):return subprocess.check_output(['git','-C',str(self.root),*args],stderr=subprocess.DEVNULL).decode().strip()
    def write(self,path,body):
        p=self.root/path;p.parent.mkdir(parents=True,exist_ok=True);p.write_text(body)
    def commit(self):self.git('add','.');self.git('commit','-qm','isolated fixture');return self.git('rev-parse','HEAD')
    def api(self,url):
        endpoint=url.removeprefix('repos/popcre/shared-db/')
        if endpoint=='commits/main':return {'sha':self.main}
        if endpoint.startswith('compare/'):
            left,right=endpoint.removeprefix('compare/').split('...')
            yes=subprocess.run(['git','-C',str(self.root),'merge-base','--is-ancestor',left,right]).returncode==0
            return {'status':'identical' if left==right else 'ahead' if yes else 'diverged','behind_by':0 if yes else 1}
        if endpoint.startswith('git/trees/'):
            ref=endpoint.split('/')[2].split('?')[0];rows=[]
            for line in self.git('ls-tree','-r',ref).splitlines():
                metadata,path=line.split('\t');mode,kind,sha=metadata.split();rows.append({'path':path,'mode':mode,'type':kind,'sha':sha})
            return {'tree':rows,'truncated':self.truncated}
        raise AssertionError('unexpected authority read '+endpoint)
    def prove(self):
        original=source.subprocess.run
        def local(args,**kw):return original(args,cwd=self.root,**kw)
        with patch.object(source.subprocess,'run',side_effect=local):return source.prove(self.base,self.entry,'fixed-op',self.api)
    def test_real_git_unrelated_hts_advance_preserves_all_guards_and_nested_tool_closure(self):
        self.write('tools/hts/qualify.mjs','// HTS changed');self.main=self.commit()
        result=self.prove();self.assertEqual(result['current_main_sha'],self.main);self.assertGreater(result['compared'],4)
    def test_actual_tracked_nested_tool_change_refuses_even_when_three_old_producers_unchanged(self):
        self.write('tools/worker.mjs','export const x=2');self.main=self.commit()
        with self.assertRaisesRegex(source.RiskGateError,'producer/current policy changed'):self.prove()
    def test_segmented_pathlib_runtime_tool_read_is_pinned_and_unbounded_tool_read_refuses(self):
        self.write('scripts/runtime.py',"from pathlib import Path\np=Path(__file__)/'tools'/'worker.mjs'\n")
        self.base=self.commit();self.main=self.base
        self.write('tools/worker.mjs','export const x=9');self.main=self.commit()
        with self.assertRaisesRegex(source.RiskGateError,'producer/current policy changed'):self.prove()
        with self.assertRaisesRegex(source.RiskGateError,'unbounded dynamic'):
            source.pin_paths({'.github/workflows/shared-supabase-migrations.yml':{'type':'blob'},'scripts/run.mjs':{'type':'blob'}},lambda p:'const p=`tools/${name}`')

    def test_unchanged_dynamic_pathlib_code_and_changed_actual_tool_refuse(self):
        self.write('scripts/runtime.py',"from pathlib import Path\nname='runtime-guard.mjs'\np=Path(__file__).resolve().parents[1]/'tools'/name\n")
        self.write('tools/runtime-guard.mjs','export const guard=1')
        self.base=self.commit();self.main=self.base
        self.write('tools/runtime-guard.mjs','export const guard=0');self.main=self.commit()
        with self.assertRaisesRegex(source.RiskGateError,'unresolved maintenance tools-directory prefix'):self.prove()

    def test_unchanged_tools_directory_alias_and_changed_executed_tool_refuse(self):
        self.write('scripts/runtime.py',"from pathlib import Path\nname='runtime-guard.mjs'\ntools_dir=Path(__file__).resolve().parents[1]/'tools'\ntool=tools_dir/name\n")
        self.write('tools/runtime-guard.mjs','export const guard=1')
        self.base=self.commit();self.main=self.base
        self.write('tools/runtime-guard.mjs','export const guard=0');self.main=self.commit()
        with self.assertRaisesRegex(source.RiskGateError,'tools-directory prefix'):self.prove()

    def test_unchanged_javascript_tools_directory_alias_and_changed_tool_refuse(self):
        self.write('scripts/runtime.mjs',"import path from 'node:path';const name='runtime-guard.mjs';const dir=path.join(ROOT,'tools');const tool=path.join(dir,name)")
        self.write('tools/runtime-guard.mjs','export const guard=1')
        self.base=self.commit();self.main=self.base
        self.write('tools/runtime-guard.mjs','export const guard=0');self.main=self.commit()
        with self.assertRaisesRegex(source.RiskGateError,'tools-directory prefix'):self.prove()

    def test_wrapped_and_plain_namespace_aliases_refuse_without_invented_tool_allowance(self):
        cases=[('scripts/runtime.py',"from pathlib import Path\nname='runtime-guard.mjs'\np=Path(ROOT)/str('tools')/name"),
            ('scripts/runtime.mjs',"const toolsDir='tools';const tool=path.join(toolsDir,name)")]
        for path,body in cases:
            self.write(path,body);self.write('tools/runtime-guard.mjs','export const guard=1')
            self.base=self.commit();self.main=self.base
            self.write('tools/runtime-guard.mjs','export const guard=0');self.main=self.commit()
            with self.subTest(path=path),self.assertRaisesRegex(source.RiskGateError,'tools-directory'):self.prove()
            (self.root/path).unlink()

    def test_formatted_terminal_namespace_direct_and_alias_refuse(self):
        cases=["p=Path(f'{ROOT}/tools')/name", "directory=f'{ROOT}/tools';p=Path(directory)/name", "directory=ROOT+'/tools';p=Path(directory)/name", "p=Path('/root/tools')/name"]
        for body in cases:
            self.write('scripts/runtime.py',"from pathlib import Path\n"+body)
            self.write('tools/runtime-guard.mjs','export const guard=1')
            self.base=self.commit();self.main=self.base
            self.write('tools/runtime-guard.mjs','export const guard=0');self.main=self.commit()
            with self.subTest(body=body),self.assertRaisesRegex(source.RiskGateError,'tools-directory'):self.prove()

    def test_js_shell_terminal_namespaces_refuse_before_alias_reuse(self):
        cases=[('scripts/runtime.mjs',"const dir=`${ROOT}/tools`;const tool=path.join(dir,name);spawnSync('node',[tool])"),
               ('scripts/runtime.sh','dir="$ROOT/tools";exec node "$dir/$name"'),
               ('scripts/runtime.sh','dir=$ROOT/tools;exec node "$dir/$name"'),
               ('scripts/runtime.mjs',"const dir=ROOT+'/tools';spawnSync('node',[dir+'/'+name])")]
        for path,body in cases:
            self.write(path,body);self.write('tools/runtime-guard.mjs','export const guard=1')
            self.base=self.commit();self.main=self.base
            self.write('tools/runtime-guard.mjs','export const guard=0');self.main=self.commit()
            with self.subTest(path=path,body=body),self.assertRaisesRegex(source.RiskGateError,'tools-directory terminal component'):self.prove()
            (self.root/path).unlink()

    def test_unchanged_relative_tool_importer_and_changed_nested_tool_refuse(self):
        self.write('tools/worker.mjs',"export {guard} from './nested/guard.mjs'\n")
        self.write('tools/nested/guard.mjs','export const guard=1')
        self.base=self.commit();self.main=self.base
        self.write('tools/nested/guard.mjs','export const guard=0');self.main=self.commit()
        with self.assertRaisesRegex(source.RiskGateError,'producer/current policy changed'):self.prove()

    def test_unchanged_static_pathlib_code_and_changed_actual_tool_refuse(self):
        self.write('scripts/runtime.py',"from pathlib import Path\np=Path(__file__).resolve().parents[1]/'tools'/'runtime-guard.mjs'\n")
        self.write('tools/runtime-guard.mjs','export const guard=1')
        self.base=self.commit();self.main=self.base
        self.write('tools/runtime-guard.mjs','export const guard=0');self.main=self.commit()
        with self.assertRaisesRegex(source.RiskGateError,'producer/current policy changed'):self.prove()

    def test_eval_source_read_cannot_hide_nested_dynamic_tool(self):
        self.write('scripts/source_reader.mjs',"eval(readFileSync(path.join(ROOT,'tools','source-data.mjs'),'utf8'))")
        self.write('tools/source-data.mjs',"const dir=path.join(ROOT,'tools');const file=path.join(dir,'runtime-guard.mjs');spawnSync('node',[file])")
        self.write('tools/runtime-guard.mjs','export const guard=1')
        self.base=self.commit();self.main=self.base
        self.write('tools/runtime-guard.mjs','export const guard=0');self.main=self.commit()
        with self.assertRaisesRegex(source.RiskGateError,'tools-directory prefix'):self.prove()

    def test_joined_executed_tool_is_walked_and_unknown_namespace_refuses(self):
        self.write('scripts/source_reader.mjs',"spawnSync('node',[path.join(ROOT,'tools','executed.mjs')])")
        self.write('tools/executed.mjs',"const dir=path.join(ROOT,'tools');const file=path.join(dir,name)")
        self.base=self.commit();self.main=self.base
        with self.assertRaisesRegex(source.RiskGateError,'tools-directory prefix'):self.prove()

    def test_current_disabled_policy_and_credential_sibling_change_refuse(self):
        self.write('scripts/sibling.py','# retired credential protection');self.main=self.commit()
        with self.assertRaisesRegex(source.RiskGateError,'producer/current policy changed'):self.prove()
    def test_new_tool_dependency_and_removed_existing_dependency_refuse(self):
        self.write('tools/worker.mjs','export {y} from "./new.mjs"');self.write('tools/new.mjs','export const y=1');self.main=self.commit()
        with self.assertRaises(source.RiskGateError):self.prove()
    def test_current_repository_execution_and_test_fixtures_have_complete_self_coverage(self):
        repository=Path(__file__).resolve().parents[1]
        rows=subprocess.check_output(['git','ls-tree','-r','HEAD'],cwd=repository,text=True)
        tree={}
        for line in rows.splitlines():
            meta,path=line.split('\t');mode,kind,sha=meta.split();tree[path]={'mode':mode,'type':kind,'sha':sha}
        pinned=source.pin_paths(tree,lambda p:subprocess.check_output(['git','show','HEAD:'+p],cwd=repository,text=True))
        self.assertIn('scripts/atomic_migration_apply.py',pinned)
        self.assertIn('scripts/lib/lanes/exclusive-policy.mjs',pinned)
        self.assertIn('tools/load-customs-benchmark.py',pinned)
        self.assertFalse(any(p.endswith('qualify-hts-prepacks.mjs') for p in pinned))

    def test_helper_only_changes_invalidate_actual_executor_receipt_with_same_source_merge(self):
        import nontransactional_index_maintenance as maintenance
        from test_nontransactional_index_maintenance import FakeDB,MemoryReceipts,entry
        legacy=['scripts/nontransactional_index_maintenance.py','scripts/index-maintenance-receipt.mjs']
        producers=['scripts/index_maintenance_source.py','scripts/prove_index_maintenance_source.py','scripts/lib/lanes/exclusive-locks.mjs']
        for p in legacy+producers:self.write(p,'# original safety input' if p.endswith('.py') else '// original safety input')
        self.commit()
        with patch.object(maintenance,'ROOT',self.root):before=maintenance.executor_digest()
        identity=dict(target='production',project_ref=maintenance.PROD,preview_project_ref='a'*20,source_sha='b'*40,execution_sha='d'*40,executor_digest=before,source_pr=1,run_id=123)
        for changed in producers:
            original=(self.root/changed).read_text()
            self.write(changed,'# changed producer' if changed.endswith('.py') else '// changed producer')
            with patch.object(maintenance,'ROOT',self.root):after=maintenance.executor_digest()
            self.assertNotEqual(after,before)
            receipts=MemoryReceipts();runner=maintenance.Maintenance(FakeDB(),receipts,entry(),{**identity,'executor_digest':after},'fixed-op',lambda:None)
            old={**identity,'target':'preview','project_ref':'a'*20,'execution_sha':'c'*40,'phase':'complete','operation_id':'fixed-op','policy_digest':maintenance.digest(entry())}
            receipts.records[runner.receipt_ref('complete','preview')]=old.copy()
            with self.assertRaisesRegex(maintenance.Refusal,'receipt binding'):runner.read('complete','preview')
            self.assertEqual(receipts.records[runner.receipt_ref('complete','preview')],old)
            self.write(changed,original)

    def test_truncated_tree_and_no_comparisons_fail_closed(self):
        self.truncated=True
        with self.assertRaisesRegex(source.RiskGateError,'truncated'):self.prove()
        with self.assertRaisesRegex(source.RiskGateError,'dependency absent'):source.pin_paths({},lambda p:'')

if __name__=='__main__':unittest.main()
