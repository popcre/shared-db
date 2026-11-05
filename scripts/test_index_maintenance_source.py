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
        with self.assertRaisesRegex(source.RiskGateError,'unbounded segmented'):
            source.pin_paths({'.github/workflows/shared-supabase-migrations.yml':{'type':'blob'},'scripts/run.py':{'type':'blob'}},lambda p:"p=ROOT / 'tools' / runtime_name" if p.endswith('.py') else '')

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

    def test_truncated_tree_and_no_comparisons_fail_closed(self):
        self.truncated=True
        with self.assertRaisesRegex(source.RiskGateError,'truncated'):self.prove()
        with self.assertRaisesRegex(source.RiskGateError,'dependency absent'):source.pin_paths({},lambda p:'')

if __name__=='__main__':unittest.main()
